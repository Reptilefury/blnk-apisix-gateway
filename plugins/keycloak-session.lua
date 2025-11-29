local core = require("apisix.core")
local http = require("resty.http")
local json = require("cjson")
local resty_sha256 = require("resty.sha256")
local str = require("resty.string")
local redis = require("resty.redis")

local plugin_name = "keycloak-session"

local schema = {
    type = "object",
    properties = {
        keycloak_url = {type = "string"},
        keycloak_realm = {type = "string", default = "master"},
        keycloak_client_id = {type = "string", default = "admin-cli"},
        redis_host = {type = "string", default = "127.0.0.1"},
        redis_port = {type = "integer", default = 6379},
        redis_password = {type = "string"},
    },
    required = {"keycloak_url"}
}

local _M = {
    version = 0.1,
    priority = 2400,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local function get_redis_connection(conf)
    local red = redis:new()
    red:set_timeout(1000)
    
    local ok, err = red:connect(conf.redis_host, conf.redis_port)
    if not ok then
        return nil, "Failed to connect to Redis: " .. err
    end
    
    if conf.redis_password then
        local res, err = red:auth(conf.redis_password)
        if not res then
            return nil, "Failed to authenticate with Redis: " .. err
        end
    end
    
    return red, nil
end

local function hash_token(token)
    local sha256 = resty_sha256:new()
    sha256:update(token)
    local digest = sha256:final()
    return str.to_hex(digest)
end

local function get_cached_token(conf, user_id)
    local red, err = get_redis_connection(conf)
    if not red then
        core.log.error("Redis connection failed: ", err)
        return nil
    end
    
    local cache_key = "keycloak_token:" .. user_id
    local cached_data, err = red:get(cache_key)
    red:close()
    
    if not cached_data or cached_data == ngx.null then
        return nil
    end
    
    local ok, data = pcall(json.decode, cached_data)
    if not ok then
        return nil
    end
    
    return data
end

local function cache_token(conf, user_id, token_data, ttl)
    local red, err = get_redis_connection(conf)
    if not red then
        core.log.error("Redis connection failed: ", err)
        return false
    end
    
    local cache_key = "keycloak_token:" .. user_id
    local cached_json = json.encode(token_data)
    
    local ok, err = red:setex(cache_key, ttl, cached_json)
    red:close()
    
    return ok ~= nil
end

local function reset_keycloak_password(conf, username, password)
    local httpc = http.new()
    httpc:set_timeout(5000)
    
    -- Get admin token first
    local admin_token_url = conf.keycloak_url .. "/realms/" .. conf.keycloak_realm .. "/protocol/openid-connect/token"
    local admin_res, err = httpc:request_uri(admin_token_url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
        },
        body = "grant_type=client_credentials&client_id=" .. conf.keycloak_client_id
    })
    
    if not admin_res or admin_res.status ~= 200 then
        return nil, "Failed to get admin token"
    end
    
    local admin_token_data = json.decode(admin_res.body)
    local admin_token = admin_token_data.access_token
    
    -- Reset user password
    local reset_url = conf.keycloak_url .. "/admin/realms/" .. conf.keycloak_realm .. "/users/" .. username .. "/reset-password"
    local reset_res, err = httpc:request_uri(reset_url, {
        method = "PUT",
        headers = {
            ["Authorization"] = "Bearer " .. admin_token,
            ["Content-Type"] = "application/json"
        },
        body = json.encode({
            type = "password",
            value = password,
            temporary = false
        })
    })
    
    return reset_res and reset_res.status < 300, err
end

local function get_keycloak_token(conf, username, password)
    local httpc = http.new()
    httpc:set_timeout(5000)
    
    local token_url = conf.keycloak_url .. "/realms/" .. conf.keycloak_realm .. "/protocol/openid-connect/token"
    local res, err = httpc:request_uri(token_url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
        },
        body = "grant_type=password&client_id=" .. conf.keycloak_client_id .. 
               "&username=" .. username .. "&password=" .. password
    })
    
    if not res or res.status ~= 200 then
        return nil, "Failed to get Keycloak token"
    end
    
    return json.decode(res.body), nil
end

function _M.access(conf, ctx)
    local uri = ngx.var.uri
    
    -- Skip for registration endpoint
    if uri == "/api/auth/register" then
        return
    end
    
    -- Skip for non-API paths
    if not string.match(uri, "^/api/") then
        return
    end
    
    -- Get Magic context from previous plugin
    local magic_user_id = ctx.magic_user_id
    local magic_token = ctx.magic_token
    local magic_expiry = ctx.magic_expiry
    
    if not magic_user_id or not magic_token then
        core.log.error("Keycloak Session: Missing Magic context")
        return 500, {error = "Internal authentication error"}
    end
    
    core.log.info("Keycloak Session: Processing for user ", magic_user_id)
    
    -- Calculate current token hash
    local current_token_hash = hash_token(magic_token)
    
    -- Check cache
    local cached_data = get_cached_token(conf, magic_user_id)
    
    local keycloak_token
    
    if cached_data and cached_data.current_magic_token_hash == current_token_hash then
        -- Same Magic token, use cached Keycloak token
        core.log.info("Keycloak Session: Using cached token for user ", magic_user_id)
        keycloak_token = cached_data.access_token
        
    else
        -- Different Magic token or no cache, need new Keycloak token
        core.log.info("Keycloak Session: Getting new Keycloak token for user ", magic_user_id)
        
        -- Reset Keycloak password to new Magic token
        local reset_ok, reset_err = reset_keycloak_password(conf, magic_user_id, magic_token)
        if not reset_ok then
            core.log.error("Keycloak Session: Password reset failed: ", reset_err)
            return 500, {error = "Authentication service error"}
        end
        
        -- Get new Keycloak token
        local token_data, token_err = get_keycloak_token(conf, magic_user_id, magic_token)
        if not token_data then
            core.log.error("Keycloak Session: Token request failed: ", token_err)
            return 401, {error = "Authentication failed"}
        end
        
        keycloak_token = token_data.access_token
        
        -- Cache the new token
        local cache_data = {
            access_token = token_data.access_token,
            refresh_token = token_data.refresh_token,
            expires_at = magic_expiry,
            current_magic_token_hash = current_token_hash
        }
        
        local ttl = magic_expiry - os.time()
        cache_token(conf, magic_user_id, cache_data, ttl)
    end
    
    -- Store Keycloak token in context
    ctx.keycloak_token = keycloak_token
    
    core.log.info("Keycloak Session: Token ready for user ", magic_user_id)
end

return _M

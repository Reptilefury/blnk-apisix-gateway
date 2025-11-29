local core = require("apisix.core")
local json = require("cjson")
local ngx = ngx
local string = string
local tonumber = tonumber
local os = os

local plugin_name = "magic-did-auth"

local schema = {
    type = "object",
    properties = {},
}

local _M = {
    version = 0.1,
    priority = 2500,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local function base64_decode(data)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b64chars..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b64chars:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

local function extract_token(headers)
    local auth_header = headers["authorization"]
    if not auth_header or not string.match(auth_header, "^Bearer ") then
        return nil
    end
    return string.sub(auth_header, 8)
end

local function sanitize_username(username)
    return string.gsub(username, "=", "")
end

local function validate_magic_token(token)
    -- Base64 decode the token
    local decoded = base64_decode(token)
    if not decoded then
        return nil, "Invalid token format"
    end
    
    -- Parse JSON array [proof, claim]
    local ok, token_array = pcall(json.decode, decoded)
    if not ok or type(token_array) ~= "table" or #token_array ~= 2 then
        return nil, "Invalid token structure"
    end
    
    local proof = token_array[1]
    local claim_str = token_array[2]
    
    -- Parse claim JSON
    local ok, claim = pcall(json.decode, claim_str)
    if not ok or type(claim) ~= "table" then
        return nil, "Invalid claim structure"
    end
    
    -- Validate required fields
    if not claim.iss or not claim.sub or not claim.ext or not claim.nbf then
        return nil, "Missing required claim fields"
    end
    
    -- Validate timestamps
    local now = os.time()
    if tonumber(claim.ext) <= now then
        return nil, "Token has expired"
    end
    
    if tonumber(claim.nbf) > now then
        return nil, "Token not yet valid"
    end
    
    -- Validate issuer format
    if not string.match(claim.iss, "^did:ethr:0x[0-9a-fA-F]+$") then
        return nil, "Invalid issuer format"
    end
    
    -- Extract and sanitize username
    local sanitized_username = sanitize_username(claim.sub)
    
    return {
        magic_user_id = sanitized_username,
        issuer = claim.iss,
        expiry = tonumber(claim.ext),
        token = token
    }, nil
end

function _M.access(conf, ctx)
    local headers = ngx.req.get_headers()
    local uri = ngx.var.uri
    
    -- Skip validation for non-API paths
    if not string.match(uri, "^/api/") then
        return
    end
    
    core.log.info("Magic DID Auth: Processing request for ", uri)
    
    -- Extract Magic DID token
    local token = extract_token(headers)
    if not token then
        core.log.error("Magic DID Auth: Missing Authorization header")
        return 401, {
            error = "MAGIC_AUTH_FAILED",
            error_description = "Missing or invalid Authorization header"
        }
    end
    
    -- Validate Magic DID token
    local magic_info, err = validate_magic_token(token)
    if not magic_info then
        core.log.error("Magic DID Auth: Token validation failed: ", err)
        return 401, {
            error = "MAGIC_AUTH_FAILED", 
            error_description = "Invalid Magic DID token"
        }
    end
    
    -- Store in context for next plugin
    ctx.magic_user_id = magic_info.magic_user_id
    ctx.magic_token = magic_info.token
    ctx.magic_issuer = magic_info.issuer
    ctx.magic_expiry = magic_info.expiry
    
    core.log.info("Magic DID Auth: Token validated for user ", magic_info.magic_user_id)
end

return _M

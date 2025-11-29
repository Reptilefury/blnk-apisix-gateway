local core = require("apisix.core")

local plugin_name = "request-enrichment"

local schema = {
    type = "object",
    properties = {},
}

local _M = {
    version = 0.1,
    priority = 2300,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    local uri = ngx.var.uri
    
    -- Skip for non-API paths
    if not string.match(uri, "^/api/") then
        return
    end
    
    -- Get context from previous plugins
    local magic_user_id = ctx.magic_user_id
    local magic_token = ctx.magic_token
    local magic_issuer = ctx.magic_issuer
    local keycloak_token = ctx.keycloak_token
    
    if not magic_user_id or not magic_token then
        core.log.error("Request Enrichment: Missing Magic context")
        return
    end
    
    core.log.info("Request Enrichment: Adding headers for user ", magic_user_id)
    
    -- Keep original Authorization header for Magic validation at service
    -- Add X-Keycloak-Token header for Keycloak validation at service (if not registration)
    if uri ~= "/api/auth/register" and keycloak_token then
        ngx.req.set_header("X-Keycloak-Token", keycloak_token)
        core.log.info("Request Enrichment: Added X-Keycloak-Token header")
    end
    
    -- Add additional context headers for debugging/audit
    ngx.req.set_header("X-Magic-User-ID", magic_user_id)
    ngx.req.set_header("X-Magic-Issuer", magic_issuer)
    ngx.req.set_header("X-Auth-Gateway-Processed", "true")
    
    core.log.info("Request Enrichment: Headers added for ", uri)
end

return _M

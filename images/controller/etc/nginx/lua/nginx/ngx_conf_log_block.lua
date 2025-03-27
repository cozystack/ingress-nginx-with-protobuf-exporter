local balancer = require("balancer")
local pbmetrics = require("pbmetrics")

local luaconfig = ngx.shared.luaconfig
local enablemetrics = luaconfig:get("enablemetrics")

balancer.log()

if enablemetrics then
    pbmetrics.call()
end

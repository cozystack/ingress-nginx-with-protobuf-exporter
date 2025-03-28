local cjson = require("cjson.safe")

local f = io.open("/etc/nginx/lua/cfg.json", "r")
local content = f:read("*a")
f:close()
local configfile = cjson.decode(content)

local lua_ingress = require("lua_ingress")
local balancer = require("balancer")
local pbmetrics = require("pbmetrics")
lua_ingress.init_worker()
balancer.init_worker()
if configfile.enable_metrics then
  pbmetrics.init_worker()
end

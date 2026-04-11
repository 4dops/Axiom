if getgenv().executed then return end
getgenv().executed = true

local executor = string.lower(identifyexecutor and identifyexecutor() or "")
local sourceUrl = "https://raw.githubusercontent.com/4dops/Axiom/refs/heads/main/games/phantomforces/Axiom.lua"

local threadTemplate = [[
    for _, func in getgc(false) do
        if type(func) == "function" and islclosure(func) and debug.getinfo(func).name == "require" and string.find(debug.getinfo(func).source, "ClientLoader") then
            %s
            break
        end
    end
]]

local function fetchSource()
    local success, result = pcall(game.HttpGet, game, sourceUrl, true)
    return success and result or nil
end

local function executeActorMethod(sourceCode, runnerName, getterName)
    local runner = _G[runnerName] or getfenv()[runnerName]
    local getter = _G[getterName] or getfenv()[getterName]
    
    if type(runner) ~= "function" or type(getter) ~= "function" then return false end
    
    local threadSource = string.format(threadTemplate, sourceCode)
    for _, actor in getter() do
        runner(actor, threadSource)
    end
    return true
end

local handlers = {
    { match = "volt", runner = "run_on_actor", getter = "getactors" },
    { match = "potassium", runner = "run_on_thread", getter = "getactorthreads" },
    { match = "wave", runner = "run_on_thread", getter = "getactorthreads" },
    { match = "synapse z", runner = "run_on_actor", getter = "getdeletedactors" },
    { match = "volcano", runner = "run_on_actor", getter = "get_actors" }
}

local sourceCode = fetchSource()
if not sourceCode then
    warn("Failed to fetch source from: " .. sourceUrl)
    return
end

local success = false

for _, handler in ipairs(handlers) do
    if string.find(executor, handler.match) then
        success = executeActorMethod(sourceCode, handler.runner, handler.getter)
        break
    end
end

if not success and getfflag then
    if string.lower(tostring(getfflag("DebugRunParallelLuaOnMainThread"))) == "true" then
        loadstring(sourceCode)()
        success = true
    elseif setfflag then
        setfflag("DebugRunParallelLuaOnMainThread", true)
        if queue_on_teleport then queue_on_teleport(sourceCode) end
        game:GetService("TeleportService"):Teleport(game.PlaceId)
        success = true
    end
end

getgenv().executed = success

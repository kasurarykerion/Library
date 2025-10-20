local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local NetworkManager = {}
NetworkManager.__index = NetworkManager

function NetworkManager.new()
	local self = setmetatable({}, NetworkManager)
	
	self.remotes = {}
	self.listeners = {}
	self.middleware = {}
	self.rateLimits = {}
	self.playerData = {}
	
	return self
end

function NetworkManager:createRemoteEvent(name)
	if self.remotes[name] then
		return self.remotes[name]
	end
	
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = game.ReplicatedStorage
	
	self.remotes[name] = remote
	self.listeners[name] = {}
	
	remote.OnServerEvent:Connect(function(player, ...)
		self:handleEvent(name, player, ...)
	end)
	
	return remote
end

function NetworkManager:createRemoteFunction(name)
	if self.remotes[name] then
		return self.remotes[name]
	end
	
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = game.ReplicatedStorage
	
	self.remotes[name] = remote
	self.listeners[name] = {}
	
	remote.OnServerInvoke = function(player, ...)
		return self:handleInvoke(name, player, ...)
	end
	
	return remote
end

function NetworkManager:on(eventName, callback)
	if not self.listeners[eventName] then
		self.listeners[eventName] = {}
	end
	
	table.insert(self.listeners[eventName], callback)
end

function NetworkManager:handleEvent(eventName, player, ...)
	if not self:checkRateLimit(player, eventName) then
		return
	end
	
	local args = {...}
	
	for _, mw in ipairs(self.middleware) do
		local success, result = pcall(mw, player, eventName, args)
		if not success or result == false then
			return
		end
	end
	
	if self.listeners[eventName] then
		for _, callback in ipairs(self.listeners[eventName]) do
			task.spawn(callback, player, ...)
		end
	end
end

function NetworkManager:handleInvoke(functionName, player, ...)
	if not self:checkRateLimit(player, functionName) then
		return nil
	end
	
	local args = {...}
	
	for _, mw in ipairs(self.middleware) do
		local success, result = pcall(mw, player, functionName, args)
		if not success or result == false then
			return nil
		end
	end
	
	if self.listeners[functionName] and #self.listeners[functionName] > 0 then
		return self.listeners[functionName][1](player, ...)
	end
	
	return nil
end

function NetworkManager:fire(eventName, player, ...)
	local remote = self.remotes[eventName]
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, ...)
	end
end

function NetworkManager:fireAll(eventName, ...)
	local remote = self.remotes[eventName]
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients(...)
	end
end

function NetworkManager:fireExcept(eventName, excludePlayer, ...)
	local remote = self.remotes[eventName]
	if remote and remote:IsA("RemoteEvent") then
		for _, player in ipairs(game.Players:GetPlayers()) do
			if player ~= excludePlayer then
				remote:FireClient(player, ...)
			end
		end
	end
end

function NetworkManager:fireMultiple(eventName, players, ...)
	local remote = self.remotes[eventName]
	if remote and remote:IsA("RemoteEvent") then
		for _, player in ipairs(players) do
			remote:FireClient(player, ...)
		end
	end
end

function NetworkManager:setRateLimit(eventName, maxCalls, timeWindow)
	self.rateLimits[eventName] = {
		maxCalls = maxCalls,
		timeWindow = timeWindow,
		calls = {}
	}
end

function NetworkManager:checkRateLimit(player, eventName)
	local limit = self.rateLimits[eventName]
	if not limit then
		return true
	end
	
	local userId = player.UserId
	if not limit.calls[userId] then
		limit.calls[userId] = {}
	end
	
	local now = tick()
	local calls = limit.calls[userId]
	
	for i = #calls, 1, -1 do
		if now - calls[i] > limit.timeWindow then
			table.remove(calls, i)
		end
	end
	
	if #calls >= limit.maxCalls then
		return false
	end
	
	table.insert(calls, now)
	return true
end

function NetworkManager:addMiddleware(callback)
	table.insert(self.middleware, callback)
end

function NetworkManager:setPlayerData(player, key, value)
	local userId = player.UserId
	if not self.playerData[userId] then
		self.playerData[userId] = {}
	end
	self.playerData[userId][key] = value
end

function NetworkManager:getPlayerData(player, key)
	local userId = player.UserId
	if self.playerData[userId] then
		return self.playerData[userId][key]
	end
	return nil
end

function NetworkManager:clearPlayerData(player)
	local userId = player.UserId
	self.playerData[userId] = nil
	
	for _, limit in pairs(self.rateLimits) do
		limit.calls[userId] = nil
	end
end

function NetworkManager:encodeJSON(data)
	return HttpService:JSONEncode(data)
end

function NetworkManager:decodeJSON(json)
	local success, result = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	
	if success then
		return result
	end
	return nil
end

function NetworkManager:destroy()
	for _, remote in pairs(self.remotes) do
		remote:Destroy()
	end
	
	self.remotes = {}
	self.listeners = {}
	self.middleware = {}
	self.rateLimits = {}
	self.playerData = {}
end

return NetworkManager

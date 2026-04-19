local CONFIG = {
	channelProtocol = "xray_scan_v1",
	receiveTimeout = 10,
	boxColor = 0x40FF40AA,
	-- Calibration knobs: tweak these until rendered boxes match real blocks.
	offset = { x = -0.6, y = -1.5, z = -0.65 },
}

local modules = peripheral.find("neuralInterface")
if not modules then
	error("Must have a neural interface", 0)
end

local function openWirelessModem()
	for _, name in ipairs(peripheral.getNames()) do
		if peripheral.getType(name) == "modem" then
			local modem = peripheral.wrap(name)
			if modem and modem.isWireless and modem.isWireless() then
				if not rednet.isOpen(name) then
					rednet.open(name)
				end
				return name
			end
		end
	end
	return nil
end

local modemName = openWirelessModem()
if not modemName then
	error("No wireless modem found for rednet.", 0)
end

local function tryMethod(obj, methodName, ...)
	if type(obj) ~= "table" then
		return false
	end

	local fn = obj[methodName]
	if type(fn) ~= "function" then
		return false
	end

	local ok = pcall(fn, obj, ...)
	if ok then
		return true
	end

	ok = pcall(fn, ...)
	return ok
end

local function clearPersisted3d(canvas3d)
	local cleared = false

	cleared = tryMethod(canvas3d, "clear") or cleared

	local tempRoot = nil
	if type(canvas3d.create) == "function" then
		local ok, result = pcall(canvas3d.create, { 0, 0, 0 })
		if not ok then
			ok, result = pcall(canvas3d.create, canvas3d, { 0, 0, 0 })
		end
		if ok then
			tempRoot = result
		end
	end

	if tempRoot then
		cleared = tryMethod(tempRoot, "clear") or cleared
		cleared = tryMethod(tempRoot, "remove") or cleared
	end

	return cleared
end

local canvas3d = modules.canvas3d()
local cleared = clearPersisted3d(canvas3d)

print("xray head receiver ready")
print("modem: " .. modemName)
print("offset: " .. CONFIG.offset.x .. ", " .. CONFIG.offset.y .. ", " .. CONFIG.offset.z)
print("startup clear: " .. (cleared and "ok" or "not supported"))
print("waiting for one packet: " .. CONFIG.channelProtocol)

local senderId, message = rednet.receive(CONFIG.channelProtocol, CONFIG.receiveTimeout)
if not senderId then
	error("Timed out waiting for xray packet", 0)
end

if type(message) ~= "table" or type(message.blocks) ~= "table" then
	error("Invalid packet format", 0)
end

if #message.blocks == 0 then
	error("Packet had no blocks to draw", 0)
end

local root3d = canvas3d.create({ 0, 0, 0 })
local drawn = 0

for _, block in ipairs(message.blocks) do
	local drawX = block.x + CONFIG.offset.x
	local drawY = block.y + CONFIG.offset.y
	local drawZ = block.z + CONFIG.offset.z

	root3d.addBox(drawX, drawY, drawZ, 1, 1, 1, CONFIG.boxColor)
	drawn = drawn + 1
end

print(string.format("drawn %d blocks from sender %d", drawn, senderId))
print("done")

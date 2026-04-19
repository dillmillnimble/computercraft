local CONFIG = {
	channelProtocol = "xray_scan_v1",
	receiveTimeout = 10,
	boxColor = 0x40FF40AA,
	-- Calibration knobs: tweak these until rendered boxes match real blocks.
	offset = { x = -0.6, y = -1.5, z = -0.65 },
	-- If scanner coordinates are player-facing relative, rotate into world-facing.
	useYawAlignment = true,
	-- Extra manual horizontal rotation: 0, 1, 2, or 3 quarter-turns.
	yawQuarterTurns = 0,
	-- Reduces drift caused by standing at different sub-block positions.
	useSubBlockCompensation = true,
	-- Try to draw through terrain by disabling depth test on overlays.
	renderThroughWalls = true,
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

local function normalizeYaw(yaw)
	local y = yaw % 360
	if y < 0 then
		y = y + 360
	end
	return y
end

local function facingFromYaw(yaw)
	local y = normalizeYaw(yaw)
	if y >= 315 or y < 45 then
		return "south"
	elseif y < 135 then
		return "west"
	elseif y < 225 then
		return "north"
	end
	return "east"
end

local function getOwnerMeta()
	local ok, meta = pcall(modules.getMetaOwner)
	if not ok or type(meta) ~= "table" then
		return nil
	end
	return meta
end

local function rotateFromEastBaseline(x, z, facing)
	if facing == "east" then
		return x, z
	elseif facing == "south" then
		return -z, x
	elseif facing == "west" then
		return -x, -z
	elseif facing == "north" then
		return z, -x
	end
	return x, z
end

local function rotateQuarterTurns(x, z, turns)
	local t = turns % 4
	if t < 0 then
		t = t + 4
	end

	for _ = 1, t do
		x, z = -z, x
	end

	return x, z
end

local function getSubBlockComp(meta)
	if not CONFIG.useSubBlockCompensation or not meta then
		return 0, 0, 0
	end

	local px = tonumber(meta.x) or 0
	local py = tonumber(meta.y) or 0
	local pz = tonumber(meta.z) or 0

	local dx = (math.floor(px) + 0.5) - px
	local dy = math.floor(py) - py
	local dz = (math.floor(pz) + 0.5) - pz
	return dx, dy, dz
end

local function setBoxDepthMode(box)
	if not CONFIG.renderThroughWalls then
		return false
	end

	-- Plethora variants expose depth toggles under different method names.
	if tryMethod(box, "setDepthTested", false) then
		return true
	end
	if tryMethod(box, "setDepthTest", false) then
		return true
	end
	if tryMethod(box, "setDepth", false) then
		return true
	end
	if tryMethod(box, "setDepthWrite", false) then
		return true
	end

	return false
end

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

local ownerMeta = getOwnerMeta()
local ownerYaw = ownerMeta and tonumber(ownerMeta.yaw) or 0
local ownerFacing = facingFromYaw(ownerYaw)
local snapX, snapY, snapZ = getSubBlockComp(ownerMeta)

local root3d = canvas3d.create({ 0, 0, 0 })
local drawn = 0
local depthConfigured = 0
local rootDepthConfigured = setBoxDepthMode(root3d)

for _, block in ipairs(message.blocks) do
	local bx = block.x
	local by = block.y
	local bz = block.z

	if CONFIG.useYawAlignment then
		bx, bz = rotateFromEastBaseline(bx, bz, ownerFacing)
	end
	bx, bz = rotateQuarterTurns(bx, bz, CONFIG.yawQuarterTurns)

	local drawX = bx + CONFIG.offset.x + snapX
	local drawY = by + CONFIG.offset.y + snapY
	local drawZ = bz + CONFIG.offset.z + snapZ

	local box = root3d.addBox(drawX, drawY, drawZ, 1, 1, 1, CONFIG.boxColor)
	if setBoxDepthMode(box) then
		depthConfigured = depthConfigured + 1
	end
	drawn = drawn + 1
end

print(string.format("yaw %.1f -> facing %s", ownerYaw, ownerFacing))
print("manual quarter-turns: " .. CONFIG.yawQuarterTurns)
print(string.format("sub-block compensation %.2f, %.2f, %.2f", snapX, snapY, snapZ))
print(string.format("drawn %d blocks from sender %d", drawn, senderId))
if CONFIG.renderThroughWalls then
	print(string.format("depth test disabled on %d/%d boxes", depthConfigured, drawn))
	if rootDepthConfigured then
		print("depth test disabled on root group")
	end
end
print("done")

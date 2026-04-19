local CONFIG = {
	channelProtocol = "xray_scan_v1",
	scanRadius = 12,
	scanInterval = 1.25,
	maxBlocksPerPacket = 256,
	-- Keep this whitelist short for lower network+render load.
	blockWhitelist = {
		["minecraft:diamond_ore"] = true,
		["minecraft:deepslate_diamond_ore"] = true,
		["minecraft:ancient_debris"] = true,
		["minecraft:emerald_ore"] = true,
		["minecraft:deepslate_emerald_ore"] = true,
		["minecraft:gold_ore"] = true,
		["minecraft:deepslate_gold_ore"] = true,
		["minecraft:redstone_ore"] = true,
		["minecraft:deepslate_redstone_ore"] = true,
		["minecraft:lapis_ore"] = true,
		["minecraft:deepslate_lapis_ore"] = true,
	}
}

local function nowMillis()
	if os.epoch then
		return os.epoch("utc")
	end
	return math.floor(os.clock() * 1000)
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

local scanner = peripheral.find("universal_scanner") or peripheral.find("scanner")
if not scanner then
	error("No scanner found (expected universal_scanner/scanner).", 0)
end

local modemName = openWirelessModem()
if not modemName then
	error("No wireless modem found for rednet.", 0)
end

print("xray pocket sender online")
print("modem: " .. modemName)
print("radius: " .. CONFIG.scanRadius .. " | interval: " .. CONFIG.scanInterval .. "s")

local function scanBlocks(radius)
	-- Peripherals++ scanner style: scan("block", radius)
	if scanner.scan then
		local ok, data = pcall(scanner.scan, "block", radius)
		if ok and type(data) == "table" then
			return data
		end

		-- Plethora style scanner fallback: scan()
		ok, data = pcall(scanner.scan)
		if ok and type(data) == "table" then
			return data
		end
	end
	return {}
end

local function tryLocate()
	local x, y, z = gps.locate(0.15)
	if not x then
		return nil
	end
	return { x = x, y = y, z = z }
end

while true do
	local raw = scanBlocks(CONFIG.scanRadius)
	local filtered = {}

	for _, block in ipairs(raw) do
		if CONFIG.blockWhitelist[block.name] then
			filtered[#filtered + 1] = {
				x = block.x,
				y = block.y,
				z = block.z,
				n = block.name,
			}

			if #filtered >= CONFIG.maxBlocksPerPacket then
				break
			end
		end
	end

	local packet = {
		v = 1,
		t = nowMillis(),
		sender = os.getComputerID(),
		pos = tryLocate(),
		radius = CONFIG.scanRadius,
		blocks = filtered,
	}

	rednet.broadcast(packet, CONFIG.channelProtocol)
	print(string.format("sent %d target blocks", #filtered))

	sleep(CONFIG.scanInterval)
end

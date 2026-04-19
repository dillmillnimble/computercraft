local CONFIG = {
    protocol = "xray_scan_v1",
    statusInterval = 0.20,
    markerSize = 0.25,
    markerAlpha = 180,
    centerX = 0.5,
    centerY = 0.5,
    centerZ = 0.5,
    yOffset = 0.0,
    facingMode = "auto", -- auto|xp|xn|zp|zn
}

local modules = peripheral.find("neuralInterface")
if not modules then
    error("Must have a neural interface.", 0)
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

local canvas2d = modules.canvas()
local canvas3dOrigin = modules.canvas3d()
canvas2d.clear()

local root3d = canvas3dOrigin.create({ 0, 0, 0 })
local hud = canvas2d.addGroup({ 5, 5 })
hud.addRectangle(0, 0, 380, 72, 0x00000099)
local statusText = hud.addText({ 6, 6 }, "xray booting", 0xFFFFFFFF, 1)
statusText.setShadow(true)

local palette = {
    ["minecraft:diamond_ore"] = 0x00E5FFFF,
    ["minecraft:deepslate_diamond_ore"] = 0x00BBD4FF,
    ["minecraft:ancient_debris"] = 0xB4552DFF,
    ["minecraft:emerald_ore"] = 0x00FF66FF,
    ["minecraft:deepslate_emerald_ore"] = 0x00C454FF,
    ["minecraft:gold_ore"] = 0xFFD54AFF,
    ["minecraft:deepslate_gold_ore"] = 0xC9A53BFF,
    ["minecraft:redstone_ore"] = 0xFF3B30FF,
    ["minecraft:deepslate_redstone_ore"] = 0xC92C25FF,
    ["minecraft:lapis_ore"] = 0x4361EEFF,
    ["minecraft:deepslate_lapis_ore"] = 0x334AB4FF,
}

local latestPacket = nil
local lastPacketMs = 0
local lastDrawMs = 0
local drawnCount = 0
local drawnObjects = {}

local function nowMillis()
    if os.epoch then
        return os.epoch("utc")
    end
    return math.floor(os.clock() * 1000)
end

local function roundBlockCoord(n)
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

local function toNumber(v)
    return tonumber(v)
end

local function splitWords(line)
    local out = {}
    for token in string.gmatch(line or "", "%S+") do
        out[#out + 1] = token
    end
    return out
end

local function yawToFacing(yaw)
    local y = yaw % 360
    if y < 0 then y = y + 360 end

    if y >= 45 and y < 135 then
        return "xn" -- west
    elseif y >= 135 and y < 225 then
        return "zn" -- north
    elseif y >= 225 and y < 315 then
        return "xp" -- east
    else
        return "zp" -- south
    end
end

local function facingBasis(facing)
    if facing == "xp" then
        return 1, 0, 0, 1
    elseif facing == "xn" then
        return -1, 0, 0, -1
    elseif facing == "zn" then
        return 0, -1, 1, 0
    else -- zp
        return 0, 1, -1, 0
    end
end

local function clearDrawn()
    for i = 1, #drawnObjects do
        drawnObjects[i].remove()
    end
    drawnObjects = {}
    drawnCount = 0
end

local function redrawFromLatest()
    if type(latestPacket) ~= "table" or type(latestPacket.blocks) ~= "table" then
        print("No packet yet. Wait for sender, then run redraw.")
        return
    end

    clearDrawn()

    local meta = modules.getMetaOwner()
    local facing = CONFIG.facingMode
    if facing == "auto" then
        facing = yawToFacing(meta.yaw or 0)
    end

    local fx, fz, rx, rz = facingBasis(facing)

    local origin = latestPacket.pos
    if not origin then
        origin = { x = meta.x or 0, y = meta.y or 0, z = meta.z or 0 }
    end

    local ox = roundBlockCoord(origin.x)
    local oy = roundBlockCoord(origin.y)
    local oz = roundBlockCoord(origin.z)

    local seen = {}

    for _, b in ipairs(latestPacket.blocks) do
        local lx = b.x or 0
        local ly = b.y or 0
        local lz = b.z or 0

        local wx = roundBlockCoord(ox + (fx * lx) + (rx * lz))
        local wy = roundBlockCoord(oy + ly)
        local wz = roundBlockCoord(oz + (fz * lx) + (rz * lz))

        local key = tostring(wx) .. ":" .. tostring(wy) .. ":" .. tostring(wz)
        if not seen[key] then
            seen[key] = true
            local color = palette[b.n] or 0xFFFFFFFF
            local box = root3d.addBox(
                wx + CONFIG.centerX,
                wy + CONFIG.centerY + CONFIG.yOffset,
                wz + CONFIG.centerZ,
                CONFIG.markerSize,
                CONFIG.markerSize,
                CONFIG.markerSize,
                color
            )
            if box.setAlpha then
                box.setAlpha(CONFIG.markerAlpha)
            end
            if box.setDepthTested then
                box.setDepthTested(false)
            end
            drawnObjects[#drawnObjects + 1] = box
            drawnCount = drawnCount + 1
        end
    end

    lastDrawMs = nowMillis()
    print(string.format("Redrew %d cubes (facing=%s, sender=%s)", drawnCount, facing, tostring(latestPacket.sender)))
end

local function receiverLoop()
    while true do
        local _, message = rednet.receive(CONFIG.protocol, 0.2)
        if type(message) == "table" and type(message.blocks) == "table" then
            latestPacket = message
            lastPacketMs = nowMillis()
        end
    end
end

local function hudLoop()
    while true do
        local age = nowMillis() - lastPacketMs
        local drawAge = nowMillis() - lastDrawMs
        local lines = {
            "XRAY MVP | modem " .. modemName,
            "drawn: " .. drawnCount .. " | packet age ms: " .. age .. " | draw age ms: " .. drawAge,
            string.format("size=%.2f alpha=%d center=(%.2f,%.2f,%.2f)", CONFIG.markerSize, CONFIG.markerAlpha, CONFIG.centerX, CONFIG.centerY, CONFIG.centerZ),
            "CLI: help | redraw | clear",
        }
        statusText.setText(table.concat(lines, "\n"))
        sleep(CONFIG.statusInterval)
    end
end

local function cliLoop()
    print("CLI ready. Type 'help' for commands.")
    while true do
        write("xray> ")
        local line = read()
        local args = splitWords(line)
        local cmd = string.lower(args[1] or "")

        if cmd == "" then
            -- ignore
        elseif cmd == "help" then
            print("status")
            print("redraw")
            print("clear")
            print("size <value>")
            print("alpha <0..255>")
            print("center <x> <y> <z>")
            print("yoffset <value>")
            print("facing auto|xp|xn|zp|zn")
        elseif cmd == "status" then
            print("have packet: " .. tostring(latestPacket ~= nil))
            print("drawn: " .. drawnCount)
            print("facing mode: " .. CONFIG.facingMode)
            if latestPacket then
                print("packet sender: " .. tostring(latestPacket.sender))
                print("packet blocks: " .. tostring(#latestPacket.blocks))
            end
        elseif cmd == "redraw" then
            redrawFromLatest()
        elseif cmd == "clear" then
            clearDrawn()
            print("cleared")
        elseif cmd == "size" then
            local n = toNumber(args[2])
            if not n then
                print("usage: size <value>")
            else
                CONFIG.markerSize = math.max(0.05, math.min(2.0, n))
                print(string.format("size=%.2f", CONFIG.markerSize))
            end
        elseif cmd == "alpha" then
            local n = toNumber(args[2])
            if not n then
                print("usage: alpha <0..255>")
            else
                CONFIG.markerAlpha = math.max(0, math.min(255, math.floor(n)))
                print("alpha=" .. CONFIG.markerAlpha)
            end
        elseif cmd == "center" then
            local cx = toNumber(args[2])
            local cy = toNumber(args[3])
            local cz = toNumber(args[4])
            if not cx or not cy or not cz then
                print("usage: center <x> <y> <z>")
            else
                CONFIG.centerX, CONFIG.centerY, CONFIG.centerZ = cx, cy, cz
                print(string.format("center=(%.2f, %.2f, %.2f)", CONFIG.centerX, CONFIG.centerY, CONFIG.centerZ))
            end
        elseif cmd == "yoffset" then
            local n = toNumber(args[2])
            if not n then
                print("usage: yoffset <value>")
            else
                CONFIG.yOffset = n
                print(string.format("yOffset=%.2f", CONFIG.yOffset))
            end
        elseif cmd == "facing" then
            local mode = string.lower(args[2] or "")
            if mode ~= "auto" and mode ~= "xp" and mode ~= "xn" and mode ~= "zp" and mode ~= "zn" then
                print("usage: facing auto|xp|xn|zp|zn")
            else
                CONFIG.facingMode = mode
                print("facing mode=" .. mode)
            end
        else
            print("unknown command. type 'help'.")
        end
    end
end

print("xray mvp renderer online")
print("protocol: " .. CONFIG.protocol)
print("manual mode: use 'redraw' to draw latest packet")

parallel.waitForAll(receiverLoop, hudLoop, cliLoop)

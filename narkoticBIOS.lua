local component, unicode = component, unicode
local pullSignal, proxy, list, huge = computer.pullSignal, component.proxy, component.list, math.huge
local function getComponent(type)
    return proxy(list(type)() or "")
end

local gpu
local screen
local keyboard
local isControl
local rx, ry
do
    gpu = getComponent("gpu")
    screen = list("screen")()
    if gpu and screen then
        rx, ry = gpu.getResolution()
        keyboard = proxy(screen).getKeyboards()[1]
        gpu.bind(screen)
        if keyboard then
            isControl = true
        end
    end
end

---------------------------------------------

local function setColorMode(state)
    if state then
        gpu.setBackground(0xFFFFFF)
        gpu.setForeground(0)
    else
        gpu.setBackground(0)
        gpu.setForeground(0xFFFFFF)
    end
end

local function clear()
    gpu.fill(1, 1, rx, ry, " ")
end

local function setText(text, posY)
    gpu.set((rx / 2) - (unicode.len(text) / 2), posY, text)
end

local function menu(label, strs)
    if not isControl then error("control is not found") end
    local select = 1
    while true do
        setColorMode(false)
        clear()
        setColorMode(true)
        setText(label, 1)
        for i = 1, #strs do
            setColorMode(select == i)
            setText(strs[i], i + 1)
        end
        local eventName, uuid, _, code = pullSignal()
        if eventName == "key_down" and uuid == keyboard then
            if code == 200 and select > 1 then
                select = select - 1
            end
            if code == 208 and select < #strs then
                select = select + 1
            end
            if code == 28 then
                return select
            end
        end
    end
end

local function yesno(label)
    return menu(label, {"no", "no", "yes", "no"}) == 3
end

local function input(posX, posY)
    local u, gpu = unicode, gpu
    local usub, ulen, uchar = u.sub, u.len, u.char
    local buffer = ""
    while true do
        gpu.set(posX, posY, "_")
        local eventName, uuid, char, code = pullSignal()
        if eventName == "key_down" and uuid == keyboard then
            if code == 28 then
                return buffer
            elseif code == 14 then
                if ulen(buffer) > 0 then
                    buffer = usub(buffer, 1, ulen(buffer) - 1)
                    gpu.set(posX, posY, " ")
                    posX = posX - 1
                    gpu.set(posX, posY, " ")
                end
            elseif char ~= 0 then
                buffer = buffer .. uchar(char)
                gpu.set(posX, posY, uchar(char))
                posX = posX + 1
            end
        elseif eventName == "clipboard" and uuid == keyboard then
            buffer = buffer .. char
            gpu.set(posX, posY, char)
            posX = posX + ulen(char)
            if usub(char, ulen(char), ulen(char)) == "\n" then
                return usub(buffer, 1, ulen(buffer) - 1)
            end
        end
    end
end

local function splash(str)
    clear()
    gpu.set(1, 1, str)
    gpu.set(1, 2, "press enter to continue...")
    while true do
        local eventName, uuid, _, code = pullSignal()
        if eventName == "key_down" and uuid == keyboard then
            if code == 28 then
                break
            end
        end
    end
end

---------------------------------------------

local function getBootAddress()
    return getComponent("eeprom").getData()
end

local function setBootAddress(address)
    local eeprom = getComponent("eeprom")
    eeprom.setData(address)
end

local function bootTo(address)
    computer.getBootAddress = function() return address end
    computer.setBootAddress = setBootAddress
    local fs = proxy(address)
    local file = assert(fs.open("/init.lua"))
    local buffer = ""
    while true do
        local read = fs.read(file, huge)
        if not read then break end
        buffer = buffer .. read
    end
    fs.close(file)
    assert(xpcall(assert(load(buffer, "=init")), debug.traceback))
    computer.shutdown()
end

local function selectfs(label)
    local data = {names = {}, addresses = {}}
    for address in list("filesystem") do
        data.names[#data.names + 1] = table.concat({address:sub(1, 6), proxy(address).getLabel()}, ":")
        data.addresses[#data.addresses + 1] = address
    end
    data.names[#data.names + 1] = "back"
    local select = menu(label, data.names)
    local address = data.addresses[select]
    return proxy(address or "") and address
end

local function selectbootdevice()
    local address = selectfs("fastboot")
    if address then
        getComponent("eeprom").setData(address)
    end
end

local function fastboot()
    local address = selectfs("fastboot")
    if address then
        bootTo(address)
    end
end

local function diskMenager()
    local function readonlySplash(address) 
        if proxy(address).isReadOnly() then
            splash("drive is read only") 
            return true
        end
    end
    while true do
        local select = menu("disk menager", {"rename", "format", "back"})
        if select == 1 then
            local address = selectfs("renamer")
            if address then
                if readonlySplash(address) then break end
                clear()
                gpu.set(1, 1, "new name: ")
                local read = input(11, 1)
                if read ~= "" then
                    proxy(address).setLabel(read)
                end
            end
        elseif select == 2 then
            local address = selectfs("formater")
            if address then
                if readonlySplash(address) then break end
                if yesno("format? "..address:sub(1, 6)) then
                    proxy(address).remove("/")
                end
            end
        elseif select == 3 then
            return
        end
    end
end

local function lua()
    while true do
        clear()
        gpu.set(1, 1, "lua: ")
        local read = input(6, 1)
        if read == "" then return end
        local code, err = load(read, nil, "=lua")
        if not code then
            splash(err or "unkown")
        else
            local ok, err = pcall(code)
            if not ok then
                splash(err or "unkown")
            end
        end
    end
end

local function mainmenu()
    while true do
        local select = menu("menu", {"select", "fastboot", "disk menager", "lua", "halt", "back"})
        if select == 1 then
            selectbootdevice()
        elseif select == 2 then
            fastboot()
        elseif select == 3 then
            diskMenager()
        elseif select == 4 then
            lua()
        elseif select == 5 then
            computer.shutdown()
        elseif select == 6 then
            return
        end
    end
end

---------------------------------------------

if isControl then
    for i = 1, 25 do
        local eventName, uuid, _, code = pullSignal(0.1)
        if eventName == "key_down" and uuid == keyboard then
            if code == 56 then
                mainmenu()
                break
            elseif code == 28 then
                break
            end
        end
    end
end

while not proxy(getBootAddress()) do
    mainmenu()
end
bootTo(getBootAddress())
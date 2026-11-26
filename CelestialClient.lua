local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/blebMaster/CelestialClientLua/refs/heads/main/CelestialLibrary"))()



local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local PlayerScripts = Players.LocalPlayer.PlayerScripts.MC
local World = require(PlayerScripts.World)
local Controller = require(Players.LocalPlayer.PlayerScripts.MC.Controller)
local Hands = require(PlayerScripts.Hands)
local Net = require(PlayerScripts.Net)
local Input = require(PlayerScripts.Input)
local Config = require(ReplicatedStorage.MC.Config)

local triggerBot = false
local nextTriggerBotAtack = 0
local TriggerBotAttackCooldown = 0.5
local OnlyCritsForTriggerBot = false    
local MaceAutoSwapTriggerBot = false
local weapons = {"netherite_sword","mace","netherite_spear","diamond_spear","netherite_axe","trident_in_hand","diamond_sword","iron_sword"}
local HitBoxExpansion = 1
local ReachDist = 0
local AutoTotem = false
local lastSwap = 0


local HttpService = game:GetService("HttpService")
local CONFIG_FILE = "CelestialConfig.json"

local Registry = {} 
local ConfigData = {}
local IsLoading = false


local Window = Library:CreateWindow({
    Name = "Celestial",
    ToggleKey = Enum.KeyCode.Z, 
    Strings = {
        Search = "Поиск функции...",
        Enabled = "Включено",
        Disabled = "Выключено",
        NoResults = "Ничего не найдено",
        NoSettings = "Нет настроек",
        Exit = "Выйти",
        BindNone = "НЕТ",  
    },
    Logo = "rbxassetid://132565077273663",
})


local Utils = Window:AddSection({ Name = "Utils", Category = "Main" })
local Combat = Window:AddSection({ Name = "Combat" })
local Visual = Window:AddSection({ Name = "Visual" })

for i, upval in ipairs(getupvalues(Net.send)) do
    if typeof(upval) == "function" then
        hookfunction(upval, newcclosure(function()
            return false
        end))
        print("foreignCaller пропатчен")
        break
    end
end

function SaveConfig()
    if IsLoading then return end
    if writefile then
        writefile(CONFIG_FILE, HttpService:JSONEncode(ConfigData))
    end
end

function Register(id, obj, defaultVal)
    Registry[id] = obj
    ConfigData[id] = defaultVal
    
    if type(obj) == "table" and obj.SetKeybind then
        local currentBind = obj:GetKeybind()
        Registry[id .. "_Bind"] = obj
        ConfigData[id .. "_Bind"] = currentBind and currentBind.Name or "NONE"
    end
    
    return obj
end

local function LoadConfig()
    if not (isfile and readfile and isfile(CONFIG_FILE)) then return end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)
    if not ok or type(decoded) ~= "table" then return end

    IsLoading = true
    for key, value in pairs(decoded) do
        local obj = Registry[key]
        if obj then
            if key:match("_Bind$") then
                local bindKey = (value ~= "NONE") and Enum.KeyCode[value] or nil
                obj:SetKeybind(bindKey, true)
            elseif obj.Kind == "Keybind" then
                local bindKey = (value ~= "NONE") and Enum.KeyCode[value] or nil
                obj:Set(bindKey) 
            else
                obj:Set(value) 
            end
            ConfigData[key] = value
        end
    end
    IsLoading = false
end


local TriggerBotFunc,OnlyCritsTriggerBotToggle,MaceAutoSwapToggle,MinALVSpeedSlider
TriggerBotFunc = Register("TriggerBotFunc",Combat:AddFunction({
    Name = "Trigger Bot",
    Description = "Автоматически бьет цель при наведении",
    Callback = function(state)
        ConfigData["TriggerBotFunc"] = state
        SaveConfig()
        triggerBot = state
    end,
}))

OnlyCritsTriggerBotToggle = Register("OnlyCritsTriggerBotToggle",TriggerBotFunc:AddToggle({
    Name = "Only Crits",    
    Default = OnlyCritsForTriggerBot,
    Callback = function(value)
        ConfigData["OnlyCritsTriggerBotToggle"] = value
        SaveConfig()
        OnlyCritsForTriggerBot = value
    end,
}))



MaceAutoSwapToggle = Register("MaceAutoSwapToggle",TriggerBotFunc:AddToggle({
    Name = "Auto swaps to mace",
    Default = MaceAutoSwapTriggerBot,
    Callback = function(value)
        ConfigData["MaceAutoSwapToggle"] = value
        SaveConfig()
        MaceAutoSwapTriggerBot = value
    end,
}))

HitBoxExpansionFunc = Register("HitBoxExpansionFunc",Combat:AddFunction({
    Name = "Hitbox Size",
    Description = "меняет размер хитбоксов у сущностей",
    Callback = function(state)
        ConfigData["HitBoxExpansionFunc"] = state
        SaveConfig()
        if state then HitBoxExpansion = HitBoxExpansionSlider:Get() else HitBoxExpansion = 1 end
    end,
    OnBind = function(key)
        ConfigData["HitBoxExpansionFunc_Bind"] = key and key.Name or "NONE"
        SaveConfig()
    end
}))


HitBoxExpansionSlider = Register("HitBoxExpansionSlider",HitBoxExpansionFunc:AddSlider({
    Name = "Size",
    Min = 1, Max = 5, Default = HitBoxExpansion, Increment = 1,
    Callback = function(value)
        ConfigData["HitBoxExpansionSlider"] = value
        SaveConfig()
        if HitBoxExpansionFunc:Get() then HitBoxExpansion = value end
    end,
}))


ReachFunc = Register("ReachFunc",Combat:AddFunction({
    Name = "Reach",
    Description = "меняет размер хитбоксов у сущностей",
    Callback = function(state)
        ConfigData["ReachFunc"] = state
        SaveConfig()
        if state then ReachDist = ReachSlider:Get() else ReachDist = 0 end
    end,
    OnBind = function(key)
        ConfigData["ReachFunc_Bind"] = key and key.Name or "NONE"
        SaveConfig()
    end
}))

ReachSlider = Register("ReachSlider",ReachFunc:AddSlider({
    Name = "Distance",
    Min = 0, Max = 1.5, Default = ReachDist, Increment = 0.25,
    Callback = function(value)
        ConfigData["ReachSlider"] = value
        SaveConfig()
        if ReachFunc:Get() then ReachDist = value end
    end,
}))



local oldPick = World.pick
World.pick = function(origin, dir, reach, padding)
    local newReach = reach + ReachDist
    return oldPick(origin, dir, newReach, padding)
end



local oldRayBox = World.rayBox
World.rayBox = function(origin, dir, feet, height, padding, width)
    local newHeight = height * HitBoxExpansion
    local newWidth = (width or 0.6) * HitBoxExpansion
    return oldRayBox(origin, dir, feet, newHeight, padding, newWidth)
end




RunService.RenderStepped:Connect(function()
    if not triggerBot then return end
    local time = os.clock()
    if time < nextTriggerBotAtack then return end
    local char = plr.Character
    if not char or not char:GetAttribute("Alive") then return end
    if not Controller.state or Input.mouseFree or Hands.using then return end
    local eye = Controller.eye()
    local look = Controller.look()
    if not eye or not look then return end
    local target, dist = World.pick(eye, look, Config.REACH+ReachDist)
    local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
    if target then
        local webHit = World.blockRay(eye, look, 4.5, { "Webs" })
        if webHit and webHit.dist <= dist then
            return
        end
        local sprint =  Controller.state.sprinting
        if MaceAutoSwapTriggerBot then
            local Falling = Controller.state and Controller.state.fallDistance >= 2.5
            if Falling then 
                local MaceSlot = getSlotByName("mace")
                local SlotNow = Hands.inv.selected
                if not MaceSlot then return end
                if MaceSlot ~= SlotNow then 
                    Hands.select(MaceSlot)
                    task.delay(0.1,function() Hands.select(SlotNow) end)
                end
                mouse1click()
                nextTriggerBotAtack = time + TriggerBotAttackCooldown
                return
            else
                if not CharHaveWeapon() then return end
                if not (Hands.strength() > 0.92) then return end
                if OnlyCritsForTriggerBot then
                    if hrp and hrp.AssemblyLinearVelocity.Y < -1 then
                        Controller.state.sprinting = false
                        mouse1click()
                        nextTriggerBotAtack = time + TriggerBotAttackCooldown
                        task.delay(0.1 ,function() Controller.state.sprinting = sprint end)
                        return
                    end
                else
                    if not (Hands.strength() > 0.92) then return end
                    mouse1click()
                    nextTriggerBotAtack = time + TriggerBotAttackCooldown
                    return
                end
            end
        else    
            if not CharHaveWeapon() then return end
            if not (Hands.strength() > 0.92) then return end
            if OnlyCritsForTriggerBot then
                if hrp and hrp.AssemblyLinearVelocity.Y < -1 then
                    Controller.state.sprinting = false
                    mouse1click()
                    nextTriggerBotAtack = time + TriggerBotAttackCooldown
                    task.delay(0.1 ,function() Controller.state.sprinting = sprint end)
                    return
                end    
            else
                mouse1click()
                nextTriggerBotAtack = time + TriggerBotAttackCooldown
                return
            end
        end
    end    
end)


SpeedMultiplierFunc = Register("SpeedMultiplierFunc",Utils:AddFunction({
    Name = "Speed Multiplier",
    Description = "изменяет скорость",
    Callback = function(state)
        ConfigData["SpeedMultiplierFunc"] = state
        SaveConfig()
         if state then 
            if plr.Character and plr.Character:GetAttribute("SpeedMult") then
                plr.Character:SetAttribute("SpeedMult",SpeedMultiplierSlider:Get())
            end
        end
    end,
    OnBind = function(key)
        ConfigData["SpeedMultiplierFunc_Bind"] = key and key.Name or "NONE"
        SaveConfig()
    end
}))

SpeedMultiplierSlider = Register("SpeedMultiplierSlider",SpeedMultiplierFunc:AddSlider({
    Name = "Size",
    Min = 1, Max = 3, Default = 1, Increment = 0.5,
    Callback = function(value)
        ConfigData["SpeedMultiplierSlider"] = value
        SaveConfig()
        if SpeedMultiplierFunc:Get() then 
            if plr.Character and plr.Character:GetAttribute("SpeedMult") then
                plr.Character:SetAttribute("SpeedMult",value)
            end
         end
    end,
}))



AutoTotemFunc = Register("AutoTotemFunc",Utils:AddFunction({
    Name = "Auto Totem",
    Description = "берёт тотем в правую руку если есть в хотбаре",
    Callback = function(state)
        ConfigData["AutoTotemFunc"] = state
        SaveConfig()
        AutoTotem = state
    end,
    OnBind = function(key) 
        ConfigData["AutoTotemFunc_Bind"] = key and key.Name or "NONE"
        SaveConfig()
    end
}))

RunService.Heartbeat:Connect(function()
    if not AutoTotem then return end
    local char = plr.Character
    if not char or not char:GetAttribute("Alive") then return end
    local offhand = Hands.inv.offhand
    if offhand and offhand.id:find("totem") then
        return
    end
    if os.clock() - lastSwap < 0.2 then return end
    for slot = 1, 9 do
        local item = Hands.inv.hotbar[slot]
        if item and item.id:find("totem") then
            lastSwap = os.clock()
            local prevSlot = Hands.inv.selected
            if slot ~= prevSlot then
                Hands.select(slot)
            end
            task.wait(0.1)
            Net.send({ a = "swap" })
            local temp = Hands.inv.hotbar[slot]
            Hands.inv.hotbar[slot] = Hands.inv.offhand
            Hands.inv.offhand = temp
            if slot ~= prevSlot then
                Hands.select(prevSlot)
            end
            break
        end
    end
end)

ElytraSwapFunc = Register("ElytraSwapFunc",Utils:AddFunction({
    Name = "Elytra Swap",
    Description = "При нажатии на горячую клавишу меняет броню на нагрудник/элитру",
    Callback = function(state) 
        ConfigData["PearlCatchFunc"] = state
        SaveConfig()
    end,
    OnBind = function(key)
        ConfigData["ElytraSwapFunc_Bind"] = key and key.Name or "NONE"
        SaveConfig()
    end
}))

local ElytraSwapBind =  Register("ElytraSwapBind",ElytraSwapFunc:AddKeybind({
    Name = "Кнопка свапа",
    Pressed = function() 
        if ElytraSwapFunc:Get() then ElytraSwap() end
    end,
    Callback = function(key) 
        ConfigData["ElytraSwapBind"] = key and key.Name or "NONE"
        SaveConfig()
    end,
}))


function ElytraSwap()
    local prevSlot = Hands.inv.selected
    local wearingElytra = Hands.inv.armor and Hands.inv.armor.chest and Hands.inv.armor.chest.id == "elytra"
    local targetName = wearingElytra and "chestplate" or "elytra"
    for slot = 1, 9 do
        local item = Hands.inv.hotbar[slot]
        if item and item.id:find(targetName) then
            if slot ~= prevSlot then
                Hands.select(slot)
            end

            Net.send({
                a = "use",
                hand = "main",
                look = Controller.look(),
                item = item.id,
                pressMs = math.floor(os.clock() * 1000 + 0.5)
            })
            if item.id == "elytra" then
                Controller.elytraPutOn()
            else
                Controller.elytraTakenOff()
            end

            if slot ~= prevSlot then
                Hands.select(prevSlot)
            end
            return
        end
    end
    Window:Notify({
    "Elytra Swap",
    "Elytra Swap doesnt find"..targetName .."in your hotbar",
    3
})
end

FireworkBindFunc = Register("FireworkBindFunc",Utils:AddFunction({
    Name = "Firework Key Bind",
    Description = "При нажатии на горячую клавишу использует фейерверк",
    Callback = function(state) 
        ConfigData["PearlCatchFunc"] = state
        SaveConfig()
    end,
    OnBind = function(key) 
        ConfigData["FireworkBindFunc_Bind"] = key and key.Name or "NONE"
        SaveConfig()
    end
}))

FireworkBind = Register("FireworkBind",FireworkBindFunc:AddKeybind({
    Name = "Кнопка активации",
    Callback = function(key) 
        ConfigData["FireworkBind"] = key and key.Name or "NONE"
        SaveConfig()
    end,
    Pressed = function() 
        if FireworkBindFunc:Get() then UseFirework() end
    end,
}))


function UseFirework()
    local wearingElytra = Hands.inv.armor and Hands.inv.armor.chest and Hands.inv.armor.chest.id == "elytra"
    if not wearingElytra then
        Window:Notify({
        "firework Bind",
        "Equip Elytra before using this bind",
        5,
        })
        return
    end
    local prevSlot = Hands.inv.selected
    for slot = 1, 9 do
        local item = Hands.inv.hotbar[slot]
        if item and item.id:find("firework") then
            if slot ~= prevSlot then
                Hands.select(slot)
            end

            Net.send({
                a = "use",
                hand = "main",
                look = Controller.look(),
                item = item.id,
                pressMs = math.floor(os.clock() * 1000 + 0.5),
                item = "firework_rocket",
                gliiding = true
            })
            if slot ~= prevSlot then
                Hands.select(prevSlot)
            end
            return
        end
    end
    Window:Notify({
    "Firework Bind",
    "Firework Bind doesnt find Fireworks in your hotbar",
    3,
})
end



PearlCatchFunc = Register("PearlCatchFunc",Utils:AddFunction({
    Name = "PearlCatch Key Bind",
    Description = "При нажатии на горячую клавишу делает pearl catch по направлению взгяда",
    Callback = function(state) 
        ConfigData["PearlCatchFunc"] = state
        SaveConfig()
    end,
    OnBind = function(key)
        ConfigData["PearlCatchFunc_Bind"] = key and key.Name or "NONE"
        SaveConfig()
    end
}))

PearlCatchBind = Register("PearlCatchBind",PearlCatchFunc:AddKeybind({
    Name = "Кнопка активации",
    Callback = function(key) 
        ConfigData["PearlCatchBind"] = key and key.Name or "NONE"
        SaveConfig()
    end,
    Pressed = function() 
        if PearlCatchFunc:Get() then AutoPearlCatch() end
    end,
}))


function AutoPearlCatch()
    local prevSlot = Hands.inv.selected
    local EnderPearlSlot = getSlotByName("pearl")
    local windChargeSlot = getSlotByName("wind_charge")
    if not EnderPearlSlot then 
        Window:Notify({
            title = "Pearl Catch Bind",
            content = "You dont have Ender Pearls in hotbar",
            duration = 5,
        })
        return
    end
    if not windChargeSlot then 
        Window:Notify({
            title = "Pearl Catch Bind",
            content = "You dont have Wind Charges in hotbar",
            duration = 5,
        })
        return
    end
    local Controllerlook = Controller.look()
    if EnderPearlSlot ~= prevSlot then  Hands.select(EnderPearlSlot) end
    Net.send({
        a = "use",
        hand = "main",
        look = Controllerlook,
        item = "ender_pearl",
        pressMs = math.floor(os.clock() * 1000 + 0.5)
    })
    Hands.select(windChargeSlot)
    task.wait(0.1)
    Net.send({
        a = "use",
        hand = "main",
        look = Controllerlook,
        item = "wind_charge",
        pressMs = math.floor(os.clock() * 1000 + 0.5),
        predictWind = false
    })
    Hands.select(prevSlot)
end




WindchargeBindFunc = Register("WindchargeBindFunc",Utils:AddFunction({
    Name = "Wind charge Key Bind",
    Description = "При нажатии на горячую клавишу использует заряд ветра",
    Callback = function(state) 
        ConfigData["WindchargeBindFunc"] = state
        SaveConfig()
    end,
    OnBind = function(key) 
        ConfigData["WindchargeBindFunc_Bind"] = key and key.Name or "NONE"
        SaveConfig()
    end
}))

WindchargeBind = Register("WindchargeBind",WindchargeBindFunc:AddKeybind({
    Name = "Кнопка активации",
    Callback = function(key) 
        ConfigData["WindchargeBind"] = key and key.Name or "NONE"
        SaveConfig()
    end,
    Pressed = function() 
        if WindchargeBindFunc:Get() then  UseWindCharge() end
    end,
}))


PearlBindFunc = Register("PearlBindFunc",Utils:AddFunction({
    Name = "Ender Pearl Key Bind",
    Description = "При нажатии на горячую клавишу использует жемчуг края",
    Callback = function(state) 
        ConfigData["PearlBindFunc"] = state
        SaveConfig()
    end,
    OnBind = function(key) 
        ConfigData["PearlBindFunc_Bind"] = key and key.Name or "NONE"
        SaveConfig()
    end
}))

PearlBind = Register("PearlBind",PearlBindFunc:AddKeybind({
    Name = "Кнопка активации",
    Callback = function(key) 
        ConfigData["PearlBind"] = key and key.Name or "NONE"
        SaveConfig()
    end,
    Pressed = function() 
        if PearlBindFunc:Get() then  UsePearl() end
    end,
}))



function UsePearl()
    local prevSlot = Hands.inv.selected
    local EnderPearlSlot = getSlotByName("pearl")
    if not EnderPearlSlot then 
        Window:Notify({
            title = "Pearl Catch Bind",
            content = "You dont have Ender Pearls in hotbar",
            duration = 5,
        })
        return
    end
    local Controllerlook = Controller.look()
    if EnderPearlSlot ~= prevSlot then  Hands.select(EnderPearlSlot) end
    Net.send({
        a = "use",
        hand = "main",
        look = Controllerlook,
        item = "ender_pearl",
        pressMs = math.floor(os.clock() * 1000 + 0.5)
    })
    Hands.select(prevSlot)
end



function UseWindCharge()
    local prevSlot = Hands.inv.selected
    local windChargeSlot = getSlotByName("wind_charge")
    if not windChargeSlot then 
        Window:Notify({
            title = "Wind Charge Bind",
            content = "You dont have Wind Charges in hotbar",
            duration = 5,
        })
        return
    end
    local Controllerlook = Controller.look()
    if windChargeSlot ~= prevSlot then  Hands.select(windChargeSlot) end
    Net.send({
        a = "use",
        hand = "main",
        look = Controllerlook,
        item = "wind_charge",
        pressMs = math.floor(os.clock() * 1000 + 0.5),
        predictWind = false
    })
    Hands.select(prevSlot)
end

local NightFunc, TimeSlider
NightFunc = Register("NightFunc",Visual:AddFunction({
    Name = "Time Change",
    Description = "Меняет время суток на выбранное время",
    Callback = function(state)
        ConfigData["NightFunc"] = state
        SaveConfig()
        Lighting.ClockTime = state and TimeSlider:Get() or 14
    end,
    OnBind = function(key) 
        ConfigData["NightFunc_Bind"] = key and key.Name or "NONE"
        SaveConfig()
    end
}))

TimeSlider = Register("TimeSlider",NightFunc:AddSlider({
    Name = "Время",
    Min = 0, Max = 24, Default = 0, Increment = 1,
    Callback = function(value)
        ConfigData["TimeSlider"] = value
        SaveConfig()
        if NightFunc:Get() then
            Lighting.ClockTime = value
        end
    end,
}))



function CharHaveWeapon()
    if not plr.Character then return false end
    local haveWeapon = false
    for i,v in pairs(weapons) do
        if not plr.Character then break
        elseif plr.Character and plr.Character:FindFirstChild(v) then 
        haveWeapon = true
        break
        end
    end
    return haveWeapon
end


function getSlotByName(ItemName)
    for slot = 1, 9 do
        local item = Hands.inv.hotbar[slot]
        if item and item.id:find(ItemName) then
            return slot
        end
    end   
end




LoadConfig()

print("запущенно")

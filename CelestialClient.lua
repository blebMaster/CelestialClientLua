getgenv().RAYFIELD_SECURE =  true
-- getgenv().RAYFIELD_ASSET_ID = 138361542409015

print("Launch Celestial Client")
--GUI
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
local Window = Rayfield:CreateWindow({
   Name = "Celestial Client",
   LoadingTitle = "Unstable SMP Client",
   LoadingSubtitle = "made by blebik",
   configuration = {
        autoSave = true,     
        autoLoad = true,  
        fileName = "AutoConfig",
        customFolder = "Celestial Client",
    },
   theme = "Amethyst",
})
local UtilsTab = Window:CreateTab({ name = "Utils"})
local CombatTab = Window:CreateTab({ name = "Combat"})
local ConfigTab = Window:CreateTab({ name = "Configs"})



local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local weapons = {"netherite_sword","mace","netherite_spear","diamond_spear","netherite_axe","trident_in_hand","diamond_sword","iron_sword"}
local HitBoxExpansion = 1
local ReachDist = 0
local AutoTotem = false
local lastSwap = 0
local SelectedConfig = "none"
local ConfigNameForSave = nil
for i, upval in ipairs(getupvalues(Net.send)) do
    if typeof(upval) == "function" then
        hookfunction(upval, newcclosure(function()
            return false
        end))
        print("foreignCaller пропатчен")
        break
    end
end



local TriggerBotToggle = CombatTab:CreateToggle({
   Name = "Trigger Bot",
   flag = "TriggerBotToggle",
   CurrentValue = triggerBot,
   Callback = function(v)
        triggerBot = v
   end,
})
local TriggerBotCritsToggle = CombatTab:CreateToggle({
   Name = "Only Crits",
   flag = "TriggerBotCritsToggle",
   CurrentValue = OnlyCritsForTriggerBot,
   Callback = function(v)
        OnlyCritsForTriggerBot = v
   end,
})
CombatTab:CreateDivider()

RunService.RenderStepped:Connect(function()
    if not triggerBot then return end
    local char = plr.Character
    local time = os.clock()
    if time < nextTriggerBotAtack then return end
    if not char or not char:GetAttribute("Alive") then return end
    if not Controller.state or Input.mouseFree or Hands.using then return end
    if not CharHaveWeapon() then return end
    local OnlyFullCharge = true
    if char:FindFirstChild("mace") then OnlyFullCharge = false end
    if OnlyFullCharge and Hands.strength() < 0.92 then
        return
    end
    local eye = Controller.eye()
    local look = Controller.look()
    if not eye or not look then return end
    local target, dist = World.pick(eye, look, Config.REACH+ReachDist)
    if target then
        local webHit = World.blockRay(eye, look, 4.5, { "Webs" })
        if webHit and webHit.dist <= dist then
            return
        end
        if OnlyCritsForTriggerBot then
            local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp and hrp.AssemblyLinearVelocity.Y < -1 then
                mouse1click()   
                nextTriggerBotAtack = time + TriggerBotAttackCooldown
            end   
          
        else
            nextTriggerBotAtack = time + TriggerBotAttackCooldown     
            mouse1click()
        end  
    end
end)



local HitBoxExpansionSlider = CombatTab:CreateSlider({
   Name = "HitBox Size ",
   flag = "HitBoxExpansionSlider",
   Range = {1, 5},
   Increment = 1,
   CurrentValue = HitBoxExpansion,
   Callback = function(v)
      HitBoxExpansion= v
   end,
})

local ReachSlider = CombatTab:CreateSlider({
   Name = "Reach",
   flag = "ReachSlider",
   Range = {0, 1.5},
   Increment = 0.25,
   CurrentValue = ReachDist,
   Callback = function(v)
      ReachDist= v
   end,
})

CombatTab:CreateDivider()
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

local SpeedMultiplier = UtilsTab:CreateSlider({
   Name = "Speed Multiplier",
   flag = "SpeedMultiplier",
   Range = {1, 5},
   Increment = 0.5,
   CurrentValue = 1,
   Callback = function(v)
        if plr.Character and plr.Character:GetAttribute("SpeedMult") then
            plr.Character:SetAttribute("SpeedMult",v)
        end
   end,
})
local AutoTotemToggle = UtilsTab:CreateToggle({
   Name = "Auto Totem of Undying",
   flag = "AutoTotemToggle",
   CurrentValue = AutoTotem,
   Callback = function(v)
        AutoTotem = v
   end,
})


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


local ConfigList = ConfigTab:CreateDropdown({
    name = "Config List",
    multiSelect = false,
    options = Window:ListConfigs(),
    value = Window:ListConfigs()[1] or "none",
    callback = function(selected)
        SelectedConfig = selected
    end,
})

local LoadConfigButton = ConfigTab:CreateButton({
    name = "Load Config",
    callback = function()
    if SelectedConfig then
        print(SelectedConfig)
        Window:Load(SelectedConfig) 
        Window:Notify({
            title = "Load Config",
            content = "Your config ".. SelectedConfig.. "was Loaded",
            duration = 7,
        })
    end    
    end,
})

local ConfigNameInput = ConfigTab:CreateInput({
    name = "Config Name",
    numeric = false,
    value = "AutoConfig",
    placeholder = "Enter a config name",
    callback = function(text)
        ConfigNameForSave = text  
    end,
})


local LoadConfigButton = ConfigTab:CreateButton({
    name = "Save Config",
    callback = function()
        if ConfigNameForSave then
          Save(ConfigNameForSave) 
        end
    end,
})

local LoadConfigButton = ConfigTab:CreateButton({
    name = "Delete Config",
    callback = function()
        if SelectedConfig then
            Window:Popup({
                title = "Delete ".. SelectedConfig .. "?",
                content = "You can't undo it.",
                options = {
                    { text = "Cancel" },
                    { text = "Delete Config", style = "danger", callback = function() Window:DeleteConfig(SelectedConfig) ConfigList:Refresh(Window:ListConfigs()) end },
                },
            })
        else
            Window:Notify({
                title = "Error",
                content = "Didnt selected any config",
                duration = 7,
            })
        end
    end,
})


function Save(Name)
    Window:Save(Name) 
    ConfigList:Refresh(Window:ListConfigs())
end


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



UtilsTab:CreateKeybind({
    name = "Elytra Swap",
    flag = "ElytraSwap",
    value = Enum.KeyCode.X,
    callback = function(key)
        ElytraSwap()
    end,
})


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
    title = "Elytra Swap",
    content = "Elytra Swap doesnt find"..targetName .."in your hotbar",
    duration = 3,
})
end

UtilsTab:CreateKeybind({
    name = "Firework bind",
    flag = "FireworkBind",
    value = nil,
    callback = function(key)
        UseFirework()
    end,
})

function UseFirework()
    local prevSlot = Hands.inv.selected
    local wearingElytra = Hands.inv.armor and Hands.inv.armor.chest and Hands.inv.armor.chest.id == "elytra"
    if not wearingElytra then
        Window:Notify({
        title = "firework Bind",
        content = "Equip Elytra before using this bind",
        duration = 5,
        })
        return
    end
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
    title = "Firework Bind",
    content = "Firework Bind doesnt find Fireworks in your hotbar",
    duration = 3,
})
end

UtilsTab:CreateKeybind({
    name = "Pearl Catch Bind",
    flag = "PearlCatch",
    value = nil,
    callback = function(key)
        AutoPearlCatch()
    end,
})



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


local function getOrCreateLine(id)
    if not lines[id] then
        local line = Drawing.new("Line")
        line.Thickness = LINE_THICKNESS
        line.Color = LINE_COLOR
        line.Transparency = LINE_TRANSPARENCY
        line.Visible = false
        lines[id] = line
    end
    return lines[id]
end


function getSlotByName(ItemName)
    for slot = 1, 9 do
        local item = Hands.inv.hotbar[slot]
        if item and item.id:find(ItemName) then
            return slot
        end
    end   
end


print("Loading Ended")

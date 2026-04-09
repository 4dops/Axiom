-- i cant be assed to add actual useful comments so ask chatgpt what the functions do

-- has a half finished anti aim that i prolly wont touch until next update
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local math_random = math.random
local math_abs = math.abs
local math_huge = math.huge
local math_sqrt = math.sqrt
local math_clamp = math.clamp
local Vector3_new = Vector3.new
local Vector2_new = Vector2.new
local Color3_new = Color3.new
local CFrame_new = CFrame.new
local RaycastParams_new = RaycastParams.new
local Instance_new = Instance.new

local CONFIG = {
    TargetRefreshRate = 0.08,
    BarrelCheckInterval = 0.25,
    ChamsRefreshInterval = 1,
    BarrelOffset = 7.5,
    DynamicFovMultiplier = 1.85,
    FovSmoothSpeed = 0.05,
    SnapLineSmoothSpeed = 22.5,
}

local COLORS = {
    DefaultFov = Color3_new(1, 1, 1),
    DefaultFovFill = Color3_new(83/255, 132/255, 171/255),
    DefaultSnap = Color3_new(1, 1, 1),
    DefaultChams = Color3_new(1, 85/255, 0),
    Black = Color3_new(0, 0, 0),
}

local GameModules = {
    Replication = nil,
    Bullet = nil,
    NetworkClient = nil,
    WeaponController = nil,
    WeaponControllerObject = nil,
    Settings = nil,
    CharacterInterface = nil,
    ReplicationObject = nil,
    ActiveLoadoutUtils = nil,
    PlayerDataClientInterface = nil,
    MainCameraObject = nil,
    Sway = nil,
}

local State = {
    SilentAim = {
        Enabled = false,
        Sticky = false,
        WallCheck = false,
        HitChance = 50,
        HeadshotChance = 100,
        MaxDistance = 500,
        AimPart = "Head",
        Priority = "Closest To Mouse",
        ShowFov = false,
        FovRadius = 120,
        CurrentFov = 120,
        DynamicFov = false,
        FovColor = COLORS.DefaultFov,
        FovFillColor = COLORS.DefaultFovFill,
        FovLockOnTarget = false,
        ShowSnapLine = false,
        SnapColor = COLORS.DefaultSnap,
        SnapOrigin = "Gun Barrel",
        FovOrigin = "Gun Barrel",
        CachedTarget = nil,
        NextTargetUpdate = 0,
        FovCachedTarget = nil,
        FovNextTargetUpdate = 0,
        CurrentFovOrigin = nil,
        HasKnife = false,
        GunBarrel = nil,
        LastBarrelCheck = 0,
    },

    Aimbot = {
        Enabled = false,
        Strength = 0.15,
        Fov = 150,
        TargetPart = "Head",
        TeamCheck = true,
        WallCheck = false,
        IsHolding = false,
    },

    Chams = {
        Enabled = false,
        FillColor = COLORS.DefaultChams,
        FillTransparency = 0.5,
        AlwaysOnTop = true,
        EnemyOnly = true,
        ActiveHighlights = {},
    },

    Esp = {
        Enabled = false,
        ShowVisible = false,
        ShowBox = false,
        Drawings = {},
    },

    FovCircle = {
        Enabled = false,
        ShowAlways = false,
        Color = COLORS.DefaultFov,
        Thickness = 1,
    },

    ThirdPerson = {
        Active = false,
        Distance = 4.5,
        XOffset = 1.5,       
        YOffset = 0.5,    
        Mode = "Interpolation",
        RemoveArms = true,
        RemoveWeapon = true,
        ModelOption = nil,
        ModelScale = 1,
        UseRoot = false,
        ReplicationDelay = 0,
        Storage = {},
        Initialized = false,
        ThirdPersonObject = nil,
        Replication = nil,
        CurrentCustomModel = nil,
        FakeRepObject = nil,
        NeedsRebuild = false,
    },

    Walkspeed = {
        Enabled = false,
        Factor = 50,
        Method = 'Velocity',
        Storage = {
            Repupdate = nil,
            LookAngles = nil,
            LastRepupdate = nil,
            ForcedPosition = nil,
            returnRepupdates = false,
            Counter = 0,
            PreviousTime = 0,
            TimeUpdated = false,
        },
        Initialized = false,
        NetworkHooked = false,
        CharacterObject = nil,
        RootPart = nil,
        Humanoid = nil
    },

    Mods = {
        NoViewBob = false,
    }
}

local Drawings = {
    SilentFovOutline = nil,
    SilentFovCircle = nil,
    SilentFovFill = nil,
    SilentSnapOutline = nil,
    SilentSnapLine = nil,
    AimbotFovCircle = nil,
}

local EspGui = nil
local PendingSilentAimVelocity = nil
local TP_OriginalTransparency = {}
local TP_OriginalSizes = {}

local Utility = {}

function Utility.GetCharacterEntry(player)
    if not GameModules.Replication then return nil end
    return GameModules.Replication.getEntry(player)
end

function Utility.IsEnemy(player)
    if not State.Chams.EnemyOnly then return true end
    local entry = Utility.GetCharacterEntry(player)
    return entry and entry._isEnemy == true
end

function Utility.IsAlive(entry)
    return entry and entry._alive == true
end

function Utility.GetCharacterHash(entry)
    if not Utility.IsAlive(entry) then return nil end
    local thirdPerson = entry._thirdPersonObject
    return thirdPerson and thirdPerson:getCharacterHash()
end

function Utility.HasLineOfSight(targetPart)
    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin
    local params = RaycastParams_new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        Workspace:FindFirstChild("Players"),
        LocalPlayer.Character
    }
    local result = Workspace:Raycast(origin, direction, params)
    if not result then return true end
    local targetModel = targetPart:FindFirstAncestorOfClass("Model")
    return targetModel and result.Instance:IsDescendantOf(targetModel)
end

function Utility.GetOriginPoint(originType)
    if originType == "Gun Barrel" then
        if State.SilentAim.HasKnife or not State.SilentAim.GunBarrel then
            return UserInputService:GetMouseLocation()
        end
        local barrel = State.SilentAim.GunBarrel
        local offset = barrel.CFrame.LookVector * CONFIG.BarrelOffset
        local worldPos = barrel.Position + offset
        local screenPos, onScreen = Camera:WorldToViewportPoint(worldPos)
        if not onScreen then
            return UserInputService:GetMouseLocation()
        end
        return Vector2_new(screenPos.X, screenPos.Y)
    end
    return UserInputService:GetMouseLocation()
end

local function InitializeGameModules()
    if not debug.getupvalue or not debug.getstack then
        error("Executor missing required debug functions")
    end

    local cache = nil

    if getrenv and getrenv().shared then
        local success, result = pcall(function()
            return debug.getupvalue(getrenv().shared.require, 1)._cache
        end)
        if success then cache = result end
    end

    if not cache and getgc then
        for _, func in getgc() do
            if typeof(func) == "function" then
                local name = debug.info(func, "n")
                local source = debug.info(func, "s")
                if name == "require" and string.find(source, "ClientLoader") then
                    cache = debug.getupvalue(func, 1)._cache
                    break
                end
            end
        end
    end

    if not cache then
        error("Failed to acquire module cache")
    end

    local function requireModule(name)
        return cache[name] and cache[name].module
    end

    GameModules.Replication = requireModule("ReplicationInterface")
    GameModules.Bullet = requireModule("BulletInterface")
    GameModules.NetworkClient = requireModule("NetworkClient")
    GameModules.WeaponController = requireModule("WeaponControllerInterface")
    GameModules.WeaponControllerObject = requireModule("WeaponControllerObject")
    GameModules.Settings = requireModule("PublicSettings")
    GameModules.CharacterInterface = requireModule("CharacterInterface")
    GameModules.ReplicationObject = requireModule("ReplicationObject")
    GameModules.ActiveLoadoutUtils = requireModule("ActiveLoadoutUtils")
    GameModules.PlayerDataClientInterface = requireModule("PlayerDataClientInterface")
    GameModules.MainCameraObject = requireModule("MainCameraObject")
    GameModules.Sway = requireModule("Sway")

    if not (GameModules.Replication and GameModules.Bullet and GameModules.Settings) then
        error("Failed to load required game modules")
    end
end

local TargetSelector = {}

function TargetSelector.GetClosestToCursor(maxDistance, wallCheck, aimPart)
    if not GameModules.Replication then return nil end
    local origin = Utility.GetOriginPoint(State.SilentAim.FovOrigin)
    local closestPart = nil
    local shortestDistance = maxDistance
    local rayParams = RaycastParams_new()
    rayParams.IgnoreWater = true
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {
        Workspace.Terrain,
        Camera,
        Workspace:FindFirstChild("Ignore"),
        Workspace:FindFirstChild("Players")
    }

    GameModules.Replication.operateOnAllEntries(function(player, entry)
        if player == LocalPlayer then return end
        if not Utility.IsEnemy(player) or not Utility.IsAlive(entry) then
            return
        end
        local charHash = Utility.GetCharacterHash(entry)
        if not charHash then return end
        local targetPart = charHash[aimPart]
        if not targetPart then return end
        if wallCheck then
            local result = Workspace:Raycast(Camera.CFrame.Position, targetPart.Position - Camera.CFrame.Position, rayParams)
            if result then return end
        end
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen or screenPos.Z <= 0 then return end
        local screenVec = Vector2_new(screenPos.X, screenPos.Y)
        local distance = (screenVec - origin).Magnitude
        if State.SilentAim.Priority == "Closest To You" then
            distance = (Camera.CFrame.Position - targetPart.Position).Magnitude
        end
        if distance < shortestDistance then
            shortestDistance = distance
            closestPart = targetPart
        end
    end)

    return closestPart
end

function TargetSelector.GetAimbotTarget()
    if not GameModules.Replication then return nil end
    local screenCenter = Vector2_new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local closestPart = nil
    local shortestDistance = State.Aimbot.Fov

    GameModules.Replication.operateOnAllEntries(function(player, entry)
        if player == LocalPlayer then return end
        if State.Aimbot.TeamCheck and not Utility.IsEnemy(player) then return end
        if not Utility.IsAlive(entry) then return end
        local charHash = Utility.GetCharacterHash(entry)
        local targetPart = charHash and charHash[State.Aimbot.TargetPart]
        if not targetPart then return end
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen then return end
        local distance = (Vector2_new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
        if distance >= shortestDistance then return end
        if State.Aimbot.WallCheck and not Utility.HasLineOfSight(targetPart) then
            return
        end
        shortestDistance = distance
        closestPart = targetPart
    end)

    return closestPart
end

local SilentAim = {}

function SilentAim:CalculateTrajectory(origin, target, targetVelocity, bulletSpeed, gravity)
    local displacement = target - origin
    local distance = displacement.Magnitude
    local timeToTarget = distance / bulletSpeed
    
    for _ = 1, 3 do
        local predictedTarget = target + (targetVelocity * timeToTarget)
        local newDisplacement = predictedTarget - origin
        local newDistance = newDisplacement.Magnitude
        local horizontalDist = Vector2.new(newDisplacement.X, newDisplacement.Z).Magnitude
        local verticalDist = newDisplacement.Y
        local horizontalTime = horizontalDist / bulletSpeed
        local drop = 0.5 * gravity.Y * horizontalTime * horizontalTime
        local adjustedVertical = verticalDist - drop
        local adjustedDist = math_sqrt(horizontalDist * horizontalDist + adjustedVertical * adjustedVertical)
        timeToTarget = adjustedDist / bulletSpeed
    end
    
    local finalTarget = target + (targetVelocity * timeToTarget)
    local drop = 0.5 * gravity * timeToTarget * timeToTarget
    local aimPosition = finalTarget - drop
    local direction = (aimPosition - origin).Unit
    local velocity = direction * bulletSpeed
    return velocity
end

function SilentAim:GetTarget(origin)
    if not GameModules.Replication then return nil, nil end
    local closestPart = nil
    local closestEntry = nil
    local shortestDistance = State.SilentAim.FovRadius

    if State.SilentAim.DynamicFov then
        shortestDistance = shortestDistance * CONFIG.DynamicFovMultiplier
    end

    if State.SilentAim.Sticky and State.SilentAim.CachedTarget then
        if State.SilentAim.CachedTarget:IsDescendantOf(Workspace) then
            local entry = Utility.GetCharacterEntry(Players:GetPlayerFromCharacter(State.SilentAim.CachedTarget:FindFirstAncestorOfClass("Model")))
            if entry and Utility.IsAlive(entry) then
                local screenPos, onScreen = Camera:WorldToViewportPoint(State.SilentAim.CachedTarget.Position)
                if onScreen and screenPos.Z > 0 then
                    local dist = (Vector2_new(screenPos.X, screenPos.Y) - origin).Magnitude
                    if dist <= shortestDistance * 1.5 then
                        if not State.SilentAim.WallCheck or Utility.HasLineOfSight(State.SilentAim.CachedTarget) then
                            return State.SilentAim.CachedTarget, entry
                        end
                    end
                end
            end
        end
    end

    GameModules.Replication.operateOnAllEntries(function(player, entry)
        if player == LocalPlayer then return end
        if not Utility.IsEnemy(player) or not Utility.IsAlive(entry) then
            return
        end
        local charHash = Utility.GetCharacterHash(entry)
        if not charHash then return end
        local targetPartName = State.SilentAim.AimPart
        if State.SilentAim.AimPart == "Torso" and math_random(1, 100) <= State.SilentAim.HeadshotChance then
            targetPartName = "Head"
        end
        local targetPart = charHash[targetPartName]
        if not targetPart then return end
        if State.SilentAim.WallCheck and not Utility.HasLineOfSight(targetPart) then
            return
        end
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen or screenPos.Z <= 0 then return end
        local screenVec = Vector2_new(screenPos.X, screenPos.Y)
        local distance
        if State.SilentAim.Priority == "Closest To Mouse" then
            distance = (screenVec - origin).Magnitude
        else
            distance = (Camera.CFrame.Position - targetPart.Position).Magnitude
        end
        if distance > shortestDistance then return end
        shortestDistance = distance
        closestPart = targetPart
        closestEntry = entry
    end)

    return closestPart, closestEntry
end

function SilentAim.InitializeHook()
    if not GameModules.Bullet then return end
    local originalNewBullet = GameModules.Bullet.newBullet

    GameModules.Bullet.newBullet = function(bulletData)
        if not State.SilentAim.Enabled then
            return originalNewBullet(bulletData)
        end
        if not bulletData.extra then
            return originalNewBullet(bulletData)
        end
        if math_random(1, 100) > State.SilentAim.HitChance then
            return originalNewBullet(bulletData)
        end

        local origin2D = Utility.GetOriginPoint(State.SilentAim.FovOrigin)
        local targetPart, targetEntry = SilentAim:GetTarget(origin2D)

        if not targetPart or not targetEntry then
            return originalNewBullet(bulletData)
        end

        State.SilentAim.CachedTarget = targetPart
        local weapon = bulletData.extra.firearmObject
        local bulletSpeed = weapon:getWeaponStat("bulletspeed") or 3000
        local acceleration = GameModules.Settings.bulletAcceleration or Vector3_new(0, -196.2, 0)
        local targetVelocity = Vector3_new(0, 0, 0)
        if targetEntry._velspring then
            targetVelocity = targetEntry._velspring.t or Vector3_new(0, 0, 0)
        end

        local newVelocity = SilentAim:CalculateTrajectory(
            bulletData.position,
            targetPart.Position,
            targetVelocity,
            bulletSpeed,
            acceleration
        )

        if math_random(1, 100) > State.SilentAim.HitChance then
            local spread = weapon:getWeaponStat("spread") or 0
            local RandomOffset = Vector3_new(
                math_random(-100, 100) / 100,
                math_random(-100, 100) / 100,
                math_random(-100, 100) / 100
            ) * (spread * 10)
            newVelocity = (newVelocity + RandomOffset).Unit * newVelocity.Magnitude
        end

        PendingSilentAimVelocity = newVelocity
        bulletData.velocity = newVelocity
        return originalNewBullet(bulletData)
    end
end

function SilentAim.EnsureDrawingsExist()
    if State.SilentAim.ShowFov and not Drawings.SilentFovCircle then
        Drawings.SilentFovOutline = Drawing.new("Circle")
        Drawings.SilentFovOutline.Filled = false
        Drawings.SilentFovOutline.Thickness = 3
        Drawings.SilentFovOutline.Color = COLORS.Black
        Drawings.SilentFovOutline.Transparency = 1
        Drawings.SilentFovOutline.Visible = false

        Drawings.SilentFovCircle = Drawing.new("Circle")
        Drawings.SilentFovCircle.Filled = false
        Drawings.SilentFovCircle.Thickness = 1
        Drawings.SilentFovCircle.Color = State.SilentAim.FovColor
        Drawings.SilentFovCircle.Transparency = 1
        Drawings.SilentFovCircle.Visible = false

        Drawings.SilentFovFill = Drawing.new("Circle")
        Drawings.SilentFovFill.Filled = true
        Drawings.SilentFovFill.Thickness = 0
        Drawings.SilentFovFill.Color = State.SilentAim.FovFillColor
        Drawings.SilentFovFill.Transparency = 0.5
        Drawings.SilentFovFill.Visible = false
    end
    
    if State.SilentAim.ShowSnapLine and not Drawings.SilentSnapLine then
        Drawings.SilentSnapOutline = Drawing.new("Line")
        Drawings.SilentSnapOutline.Thickness = 3
        Drawings.SilentSnapOutline.Color = COLORS.Black
        Drawings.SilentSnapOutline.Transparency = 1
        Drawings.SilentSnapOutline.Visible = false

        Drawings.SilentSnapLine = Drawing.new("Line")
        Drawings.SilentSnapLine.Thickness = 1
        Drawings.SilentSnapLine.Color = State.SilentAim.SnapColor
        Drawings.SilentSnapLine.Transparency = 1
        Drawings.SilentSnapLine.Visible = false
    end
end

function SilentAim.DestroyDrawings()
    for key, drawing in ipairs(Drawings) do
        if drawing and key:match("^Silent") then
            pcall(function() drawing:Remove() end)
            Drawings[key] = nil
        end
    end
end

function SilentAim.UpdateGunBarrel()
    if not State.SilentAim.Enabled and not State.SilentAim.ShowSnapLine and not State.SilentAim.ShowFov then
        return
    end

    local now = tick()

    if GameModules.WeaponController then
        local controller = GameModules.WeaponController.getActiveWeaponController()
        if controller then
            local weapon = controller:getActiveWeapon()
            if weapon and weapon._barrelPart then
                State.SilentAim.GunBarrel = weapon._barrelPart
                State.SilentAim.HasKnife = false
                State.SilentAim.LastBarrelCheck = now
                return
            end
        end
    end

    if now >= State.SilentAim.LastBarrelCheck + CONFIG.BarrelCheckInterval then
        local hasKnife = false
        for _, child in ipairs(Camera:GetChildren()) do
            if child:IsA("Model") and child:FindFirstChild("Trigger", true) then
                hasKnife = true
                break
            end
        end
        State.SilentAim.HasKnife = hasKnife
        State.SilentAim.LastBarrelCheck = now
    end

    if State.SilentAim.FovOrigin ~= "Gun Barrel" and State.SilentAim.SnapOrigin ~= "Gun Barrel" then
        State.SilentAim.GunBarrel = nil
        return
    end

    State.SilentAim.GunBarrel = nil
end

function SilentAim.UpdateVisuals(dt)
    if not State.SilentAim.ShowFov and not State.SilentAim.ShowSnapLine then
        if Drawings.SilentFovCircle or Drawings.SilentSnapLine then
            SilentAim.DestroyDrawings()
        end
        return
    end
    
    SilentAim.EnsureDrawingsExist()

    local now = tick()

    if State.SilentAim.ShowFov and Drawings.SilentFovCircle then
        local targetFov = State.SilentAim.FovRadius
        if State.SilentAim.DynamicFov then
            targetFov = targetFov * CONFIG.DynamicFovMultiplier
        end

        State.SilentAim.CurrentFov = State.SilentAim.CurrentFov + (targetFov - State.SilentAim.CurrentFov) * CONFIG.FovSmoothSpeed

        local origin = Utility.GetOriginPoint(State.SilentAim.FovOrigin)

        if State.SilentAim.FovLockOnTarget and State.SilentAim.Enabled then
            if State.SilentAim.CachedTarget and State.SilentAim.CachedTarget:IsDescendantOf(Workspace) then
                State.SilentAim.FovCachedTarget = State.SilentAim.CachedTarget
                State.SilentAim.FovNextTargetUpdate = now + CONFIG.TargetRefreshRate
            elseif now >= State.SilentAim.FovNextTargetUpdate then
                State.SilentAim.FovCachedTarget = TargetSelector.GetClosestToCursor(
                    State.SilentAim.MaxDistance,
                    State.SilentAim.WallCheck,
                    State.SilentAim.AimPart
                )
                State.SilentAim.FovNextTargetUpdate = now + CONFIG.TargetRefreshRate
            end

            if State.SilentAim.FovCachedTarget then
                local pos, onScreen = Camera:WorldToViewportPoint(State.SilentAim.FovCachedTarget.Position)
                if onScreen then
                    local targetVec = Vector2_new(pos.X, pos.Y)
                    State.SilentAim.CurrentFovOrigin = State.SilentAim.CurrentFovOrigin 
                        and State.SilentAim.CurrentFovOrigin:Lerp(targetVec, math_clamp(dt * CONFIG.SnapLineSmoothSpeed, 0, 1))
                        or targetVec
                    origin = State.SilentAim.CurrentFovOrigin
                end
            end
        else
            State.SilentAim.CurrentFovOrigin = nil
        end

        Drawings.SilentFovCircle.Visible = true
        Drawings.SilentFovOutline.Visible = true
        Drawings.SilentFovFill.Visible = true

        Drawings.SilentFovCircle.Position = origin
        Drawings.SilentFovOutline.Position = origin
        Drawings.SilentFovFill.Position = origin

        Drawings.SilentFovCircle.Radius = State.SilentAim.CurrentFov
        Drawings.SilentFovOutline.Radius = State.SilentAim.CurrentFov
        Drawings.SilentFovFill.Radius = State.SilentAim.CurrentFov

        Drawings.SilentFovCircle.Color = State.SilentAim.FovColor
        Drawings.SilentFovFill.Color = State.SilentAim.FovFillColor
    elseif Drawings.SilentFovCircle then
        Drawings.SilentFovCircle.Visible = false
        Drawings.SilentFovOutline.Visible = false
        Drawings.SilentFovFill.Visible = false
    end

    SilentAim.UpdateSnapLines(now)
end

function SilentAim.UpdateSnapLines(now)
    if not State.SilentAim.ShowSnapLine then
        if Drawings.SilentSnapLine then
            Drawings.SilentSnapLine.Visible = false
            Drawings.SilentSnapOutline.Visible = false
        end
        return
    end
    
    if not Drawings.SilentSnapLine then return end

    local origin = Utility.GetOriginPoint(State.SilentAim.SnapOrigin)
    if origin == UserInputService:GetMouseLocation() and State.SilentAim.SnapOrigin == "Gun Barrel" then
        Drawings.SilentSnapLine.Visible = false
        Drawings.SilentSnapOutline.Visible = false
        return
    end

    if now >= State.SilentAim.NextTargetUpdate then
        State.SilentAim.CachedTarget = TargetSelector.GetClosestToCursor(
            State.SilentAim.MaxDistance,
            State.SilentAim.WallCheck,
            State.SilentAim.AimPart
        )
        State.SilentAim.NextTargetUpdate = now + CONFIG.TargetRefreshRate
    end

    local target = State.SilentAim.CachedTarget
    if not target or not target:IsDescendantOf(Workspace) then
        Drawings.SilentSnapLine.Visible = false
        Drawings.SilentSnapOutline.Visible = false
        return
    end

    local screenPos, onScreen = Camera:WorldToViewportPoint(target.Position)

    if not onScreen then
        Drawings.SilentSnapLine.Visible = false
        Drawings.SilentSnapOutline.Visible = false
        return
    end

    local endPos = Vector2_new(screenPos.X, screenPos.Y)

    Drawings.SilentSnapLine.Visible = true
    Drawings.SilentSnapOutline.Visible = true
    Drawings.SilentSnapLine.From = origin
    Drawings.SilentSnapLine.To = endPos
    Drawings.SilentSnapOutline.From = origin
    Drawings.SilentSnapOutline.To = endPos
    Drawings.SilentSnapLine.Color = State.SilentAim.SnapColor
end

local Aimbot = {}

function Aimbot.EnsureDrawingExists()
    if not Drawings.AimbotFovCircle then
        Drawings.AimbotFovCircle = Drawing.new("Circle")
        Drawings.AimbotFovCircle.Thickness = State.FovCircle.Thickness
        Drawings.AimbotFovCircle.Color = State.FovCircle.Color
        Drawings.AimbotFovCircle.NumSides = 64
        Drawings.AimbotFovCircle.Filled = false
        Drawings.AimbotFovCircle.Transparency = 0.7
        Drawings.AimbotFovCircle.Visible = false
    end
end

function Aimbot.Update()
    if not State.Aimbot.Enabled then
        if Drawings.AimbotFovCircle then
            Drawings.AimbotFovCircle.Visible = false
        end
        return
    end
    
    Aimbot.EnsureDrawingExists()
    
    if State.FovCircle.Enabled then
        local center = Vector2_new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        Drawings.AimbotFovCircle.Position = center
        Drawings.AimbotFovCircle.Radius = State.Aimbot.Fov
        Drawings.AimbotFovCircle.Visible = State.Aimbot.Enabled or State.FovCircle.ShowAlways
    else
        Drawings.AimbotFovCircle.Visible = false
    end

    if not State.Aimbot.IsHolding then return end

    local target = TargetSelector.GetAimbotTarget()
    if not target then return end

    local screenPos, onScreen = Camera:WorldToViewportPoint(target.Position)
    if not onScreen then return end

    local mousePos = UserInputService:GetMouseLocation()
    local delta = Vector2_new(screenPos.X - mousePos.X, screenPos.Y - mousePos.Y)

    mousemoverel(delta.X * State.Aimbot.Strength, delta.Y * State.Aimbot.Strength)
end

local Esp = {}

function Esp.Initialize()
    if EspGui then return end
    EspGui = Instance_new("ScreenGui")
    EspGui.Name = "\0"
    EspGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    EspGui.DisplayOrder = 3
    EspGui.ResetOnSpawn = false
    EspGui.IgnoreGuiInset = true
    EspGui.Parent = gethui and gethui() or CoreGui
end

function Esp.Destroy()
    if not EspGui then return end
    for player, drawings in ipairs(State.Esp.Drawings) do
        pcall(function() drawings.Box:Remove() end)
        pcall(function() drawings.Label:Destroy() end)
    end
    State.Esp.Drawings = {}
    pcall(function() EspGui:Destroy() end)
    EspGui = nil
end

function Esp.CreateDrawings(player)
    if not EspGui then Esp.Initialize() end
    local box = Drawing.new("Square")
    box.Thickness = 1.5
    box.Color = COLORS.DefaultChams
    box.Filled = false
    box.Transparency = 1
    box.Visible = false

    local label = Instance_new("TextLabel")
    label.Name = "\0"
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.AnchorPoint = Vector2_new(0.5, 0.5)
    label.Size = UDim2.new(0, 140, 0, 16)
    label.TextSize = 8
    label.TextColor3 = COLORS.DefaultChams
    label.TextStrokeColor3 = COLORS.Black
    label.TextStrokeTransparency = 0
    label.Visible = false
    label.Parent = EspGui

    return {Box = box, Label = label}
end

function Esp.DestroyDrawings(player)
    local drawings = State.Esp.Drawings[player]
    if not drawings then return end
    pcall(function() drawings.Box:Remove() end)
    pcall(function() drawings.Label:Destroy() end)
    State.Esp.Drawings[player] = nil
end

function Esp.ClearAll()
    for player in ipairs(State.Esp.Drawings) do
        Esp.DestroyDrawings(player)
    end
    Esp.Destroy()
end

function Esp.GetDrawings(player)
    if not State.Esp.Drawings[player] then
        State.Esp.Drawings[player] = Esp.CreateDrawings(player)
    end
    return State.Esp.Drawings[player]
end

function Esp.Update()
    if not State.Esp.Enabled then
        if next(State.Esp.Drawings) ~= nil or EspGui then
            Esp.ClearAll()
        end
        return
    end
    
    if not EspGui then
        Esp.Initialize()
    end

    local seenPlayers = {}

    GameModules.Replication.operateOnAllEntries(function(player, entry)
        if player == LocalPlayer then return end
        if not Utility.IsEnemy(player) or not Utility.IsAlive(entry) then
            Esp.DestroyDrawings(player)
            return
        end

        local charHash = Utility.GetCharacterHash(entry)
        local torso = charHash and charHash.Torso
        local head = charHash and charHash.Head

        if not torso or not head then
            Esp.DestroyDrawings(player)
            return
        end

        local lowestY, highestY = math_huge, -math_huge
        for _, part in ipairs(charHash) do
            if typeof(part) == "Instance" and part:IsA("BasePart") then
                local bottom = part.Position.Y - part.Size.Y * 0.5
                local top = part.Position.Y + part.Size.Y * 0.5
                if bottom < lowestY then lowestY = bottom end
                if top > highestY then highestY = top end
            end
        end

        local feetWorld = Vector3_new(torso.Position.X, lowestY, torso.Position.Z)
        local headWorld = Vector3_new(torso.Position.X, highestY, torso.Position.Z)

        local feetScreen, feetVisible = Camera:WorldToViewportPoint(feetWorld)
        local headScreen, headVisible = Camera:WorldToViewportPoint(headWorld)

        if not (feetVisible and headVisible) then
            Esp.DestroyDrawings(player)
            return
        end

        seenPlayers[player] = true
        local drawings = Esp.GetDrawings(player)

        if State.Esp.ShowBox then
            local height = math_abs(feetScreen.Y - headScreen.Y)
            local width = height * 0.6
            drawings.Box.Size = Vector2_new(width, height)
            drawings.Box.Position = Vector2_new(headScreen.X - width / 2, headScreen.Y)
            drawings.Box.Visible = true
        else
            drawings.Box.Visible = false
        end

        if State.Esp.ShowVisible then
            local isVisible = Utility.HasLineOfSight(torso)
            drawings.Label.Text = isVisible and "VISIBLE" or "NOT VISIBLE"
            drawings.Label.Position = UDim2.new(0, feetScreen.X, 0, feetScreen.Y + 6)
            drawings.Label.Visible = true
        else
            drawings.Label.Visible = false
        end
    end)

    for player in ipairs(State.Esp.Drawings) do
        if not seenPlayers[player] then
            Esp.DestroyDrawings(player)
        end
    end
end

local Chams = {}

function Chams.CreateHighlight(model)
    local highlight = Instance_new("Highlight")
    highlight.Adornee = model
    highlight.FillColor = State.Chams.FillColor
    highlight.FillTransparency = State.Chams.FillTransparency
    highlight.OutlineTransparency = 1
    highlight.DepthMode = State.Chams.AlwaysOnTop and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    highlight.Parent = CoreGui
    return highlight
end

function Chams.CleanupPlayer(player)
    local data = State.Chams.ActiveHighlights[player]
    if data then
        pcall(function() data.Highlight:Destroy() end)
    end
    State.Chams.ActiveHighlights[player] = nil
end

function Chams.ClearAll()
    for player in ipairs(State.Chams.ActiveHighlights) do
        Chams.CleanupPlayer(player)
    end
end

function Chams.UpdatePlayer(player, model)
    local data = State.Chams.ActiveHighlights[player]
    if data and data.Model == model then
        data.Highlight.FillColor = State.Chams.FillColor
        data.Highlight.FillTransparency = State.Chams.FillTransparency
        data.Highlight.DepthMode = State.Chams.AlwaysOnTop and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
        return
    end

    Chams.CleanupPlayer(player)

    if not State.Chams.Enabled or not Utility.IsEnemy(player) then
        return
    end

    local highlight = Chams.CreateHighlight(model)
    State.Chams.ActiveHighlights[player] = {Highlight = highlight, Model = model}
end

function Chams.RefreshAll()
    if not State.Chams.Enabled then
        if next(State.Chams.ActiveHighlights) ~= nil then
            Chams.ClearAll()
        end
        return
    end
    
    if not GameModules.Replication then return end

    for player in ipairs(State.Chams.ActiveHighlights) do
        local entry = Utility.GetCharacterEntry(player)
        if not entry or not Utility.IsAlive(entry) or not Utility.IsEnemy(player) then
            Chams.CleanupPlayer(player)
        end
    end

    GameModules.Replication.operateOnAllEntries(function(player, entry)
        if player == LocalPlayer then return end
        if not Utility.IsEnemy(player) or not Utility.IsAlive(entry) then
            return
        end

        local thirdPerson = entry._thirdPersonObject
        local model = thirdPerson and thirdPerson:getCharacterModel()
        if model then
            Chams.UpdatePlayer(player, model)
        end
    end)
end

local TPModels = {
    ['Bart'] = game:GetObjects('rbxassetid://9915662960')[1],
    ['Mrs Puff'] = game:GetObjects('rbxassetid://7163138683')[1],
    ['Isabelle'] = game:GetObjects('rbxassetid://6052148778')[1],
    ['Spongebob'] = game:GetObjects('rbxassetid://5730254764')[1],
}

for _, model in ipairs(TPModels) do
    if typeof(model) == "Instance" then
        TP_OriginalSizes[model] = model.Size
        pcall(function()
            model.Parent = CoreGui
            model.Transparency = 1
            model.CanCollide = false
            model.Anchored = true
        end)
    end
end

local function normalizeAngle(angle)
    while angle > math.pi do
        angle = angle - 2 * math.pi
    end
    while angle < -math.pi do
        angle = angle + 2 * math.pi
    end
    return angle
end

local function lerpAngle(a, b, t)
    local diff = b - a
    while diff > math.pi do
        diff = diff - 2 * math.pi
    end
    while diff < -math.pi do
        diff = diff + 2 * math.pi
    end
    return a + diff * t
end

local ThirdPerson = {
    OriginalScreenCullStep = nil,
    OriginalMCOStep = nil,
    
    InitFakeReplication = function(self)
        if State.ThirdPerson.FakeRepObject then
            return true
        end
        
        local RO = GameModules.ReplicationObject
        local PDCI = GameModules.PlayerDataClientInterface
        
        if not (RO and RO.new and PDCI) then
            return false
        end
        
        local fakePlayerProxy = setmetatable({}, {
            __index = function(_, index)
                if index == "GetPropertyChangedSignal" then
                    return function(_, property)
                        return LocalPlayer:GetPropertyChangedSignal(property)
                    end
                end
                return LocalPlayer[index]
            end,
            __newindex = function(_, index, value)
                LocalPlayer[index] = value
            end
        })
        
        local success, result = pcall(function()
            return RO.new(fakePlayerProxy)
        end)
        
        if not success then
            warn("Failed to create fake replication object:", result)
            return false
        end
        
        State.ThirdPerson.FakeRepObject = result
        return true
    end,
    
    GetCameraAngles = function()
        local cf = Camera.CFrame
        local look = cf.LookVector
        local yaw = math.atan2(-look.X, -look.Z)
        local pitch = math.asin(math.clamp(look.Y, -1, 1))
        return Vector3_new(pitch, normalizeAngle(yaw), 0)
    end,
    
    SpawnCharacter = function(self)
        local fakeRep = State.ThirdPerson.FakeRepObject
        local PDCI = GameModules.PlayerDataClientInterface
        local ALU = GameModules.ActiveLoadoutUtils
        
        if not (fakeRep and PDCI and ALU) then
            return false
        end
        
        local playerData = PDCI.getPlayerData()
        if not playerData then
            return false
        end
        
        local classData = playerData.settings and playerData.settings.classdata
        if not classData then
            return false
        end
        
        local currentClass = classData.curclass
        local loadout = classData[currentClass]
        
        local success, err = pcall(function()
            fakeRep:spawn(nil, loadout)
        end)
        
        if not success then
            warn("Failed to spawn fake character:", err)
            return false
        end
        
        State.ThirdPerson.ThirdPersonObject = fakeRep._thirdPersonObject
        
        if State.ThirdPerson.ThirdPersonObject then
            for i = 1, 3 do
                if fakeRep:getWeaponObjects()[i] then
                    State.ThirdPerson.ThirdPersonObject:buildWeapon(i)
                end
            end
            State.ThirdPerson.ThirdPersonObject.canRenderWeapon = true
        end
        
        return true
    end,
    
    Init = function(self)
        self:Cleanup()
        
        if not self:InitFakeReplication() then
            return false
        end
        
        if not self:SpawnCharacter() then
            return false
        end
        
        self:HookCamera()
        self:StartUpdateLoop()
        
        State.ThirdPerson.Initialized = true
        return true
    end,
    
    HookCamera = function(self)
        local screenCull = GameModules.ScreenCull
        
        if screenCull and screenCull.step then
            self.OriginalScreenCullStep = screenCull.step
            
            screenCull.step = function(...)
                self.OriginalScreenCullStep(...)
                
                if not State.ThirdPerson.Active then
                    return
                end
                
                local controller = GameModules.WeaponControllerInterface and 
                                 GameModules.WeaponControllerInterface.getActiveWeaponController()
                
                if not controller then
                    return
                end
                
                local weapon = controller:getActiveWeapon()
                local aiming = weapon and weapon._aiming
                
                if aiming and not State.ThirdPerson.ShowWhileAiming then
                    return
                end
                
                self:ApplyCameraOffset()
            end
            
            return
        end
        
        local MCO = GameModules.MainCameraObject
        if MCO and MCO.step then
            self.OriginalMCOStep = MCO.step
            
            MCO.step = function(camSelf, dt, ...)
                local result = self.OriginalMCOStep(camSelf, dt, ...)
                
                if State.ThirdPerson.Active then
                    self:ApplyCameraOffset()
                end
                
                return result
            end
        end
    end,
    
    ApplyCameraOffset = function(self)
        local offset = Vector3_new(
            State.ThirdPerson.XOffset or 0,
            State.ThirdPerson.YOffset or 0,
            State.ThirdPerson.Distance or 7.5
        )
        
        local camCF = Camera.CFrame
        local right = camCF.RightVector
        local up = camCF.UpVector
        local back = -camCF.LookVector
        
        local worldOffset = (right * offset.X) + (up * offset.Y) + (back * offset.Z)
        
        local startPos = camCF.Position
        local targetPos = startPos + worldOffset
        
        local RaycastP = RaycastParams_new()
        RaycastP.FilterDescendantsInstances = {
            Workspace:FindFirstChild("Players"),
            Workspace.Terrain,
            Workspace:FindFirstChild("Ignore"),
            Camera
        }
        RaycastP.FilterType = Enum.RaycastFilterType.Exclude
        
        local finalOffset = worldOffset
        
        local RayResult = Workspace:Raycast(startPos, worldOffset, RaycastP)
        if RayResult and RayResult.Instance.CanCollide then
            local hitDistance = (RayResult.Position - startPos).Magnitude - 0.5
            local maxDistance = worldOffset.Magnitude
            local ratio = math.min(hitDistance / maxDistance, 1)
            finalOffset = worldOffset * ratio * 0.99
        end
        
        Camera.CFrame = camCF + finalOffset
    end,
    
    StartUpdateLoop = function(self)
        if State.ThirdPerson.Replication then
            State.ThirdPerson.Replication:Disconnect()
        end
        
        local lastPos = nil
        local lastAngles = nil
        
        State.ThirdPerson.Replication = RunService.Heartbeat:Connect(function(dt)
            if not State.ThirdPerson.Active then
                local fakeRep = State.ThirdPerson.FakeRepObject
                if fakeRep and fakeRep._thirdPersonObject then
                    fakeRep._posspring.t = Vector3_new(0, -1000, 0)
                    fakeRep._posspring.p = Vector3_new(0, -1000, 0)
                end
                lastPos = nil
                lastAngles = nil
                return
            end
            
            local fakeRep = State.ThirdPerson.FakeRepObject
            local tpObj = State.ThirdPerson.ThirdPersonObject
            
            if not (fakeRep and tpObj) then
                return
            end
            
            local charObj = GameModules.CharacterInterface and 
                           GameModules.CharacterInterface.getCharacterObject()
            local rootPart = charObj and charObj:getRealRootPart()
            
            if not rootPart then
                State.ThirdPerson.FakeRepObject:despawn()
                State.ThirdPerson.ThirdPersonObject:Destroy()
                return
            end
            
            local position = rootPart.Position
            lastPos = lastPos or position
            local velocity = (position - lastPos) / dt
            lastPos = position
            
            local targetAngles = self:GetCameraAngles()
            
            if State.AntiAim and State.AntiAim.Enabled then
                targetAngles = self:ApplyAntiAim(targetAngles)
            end
            
            if lastAngles then
                local newPitch = lastAngles.X + (targetAngles.X - lastAngles.X) * 0.3
                local newYaw = lerpAngle(lastAngles.Y, targetAngles.Y, 0.3)
                local newRoll = lastAngles.Z + (targetAngles.Z - lastAngles.Z) * 0.3
                targetAngles = Vector3_new(newPitch, newYaw, newRoll)
            end
            
            lastAngles = targetAngles
            
            fakeRep._posspring.t = position
            fakeRep._posspring.p = position
            fakeRep._lookangles.t = targetAngles
            fakeRep._lookangles.p = targetAngles
            
            local clockTime = os.clock()
            local tickTime = tick()
            
            fakeRep._smoothReplication:receive(clockTime, tickTime, {
                t = tickTime,
                position = position,
                velocity = velocity,
                angles = targetAngles,
                barrelAngles = Vector3.zero,
                breakcount = 0
            }, true)
            
            fakeRep._updaterecieved = true
            fakeRep._receivedPosition = position
            fakeRep._receivedFrameTime = GameModules.NetworkClient and 
                                          GameModules.NetworkClient.getTime() or tickTime
            fakeRep._lastPacketTime = clockTime
            fakeRep._lastBarrelAngles = Vector3.zero
            
            fakeRep:step(3, true)
            tpObj.canRenderWeapon = true
            
            if charObj.getMovementMode then
                local stance = charObj:getMovementMode()
                tpObj:setStance(stance:lower())
            end
        end)
    end,
    
    ApplyAntiAim = function(self, angles)
        local pitch, yaw, roll = angles.X, angles.Y, angles.Z
        
        if State.AntiAim.Pitch then
            local addition = math.rad(State.AntiAim.PitchAmount or 0)
            if State.AntiAim.PitchMode == "Absolute" then
                pitch = addition
            else
                pitch = pitch + addition
            end
            pitch = math.clamp(pitch, -math.pi/2, math.pi/2)
        end
        
        if State.AntiAim.Yaw then
            local addition = math.rad(State.AntiAim.YawAmount or 0)
            if State.AntiAim.YawMode == "Relative" then
                yaw = yaw + addition
            else
                yaw = addition
            end
        end
        
        if State.AntiAim.SpinBot then
            yaw = yaw + (os.clock() - (State.AntiAim.SpinStart or os.clock())) * 
                  math.rad(State.AntiAim.SpinSpeed or 180) * 
                  (State.AntiAim.SpinDirection == "Left" and 1 or -1)
        end
        
        return Vector3_new(pitch, yaw, roll)
    end,
    
    Cleanup = function(self)
        if State.ThirdPerson.Replication then
            State.ThirdPerson.Replication:Disconnect()
            State.ThirdPerson.Replication = nil
        end
        
        if self.OriginalScreenCullStep and GameModules.ScreenCull then
            GameModules.ScreenCull.step = self.OriginalScreenCullStep
            self.OriginalScreenCullStep = nil
        end
        
        if self.OriginalMCOStep and GameModules.MainCameraObject then
            GameModules.MainCameraObject.step = self.OriginalMCOStep
            self.OriginalMCOStep = nil
        end
        
        if State.ThirdPerson.FakeRepObject then
            pcall(function()
                State.ThirdPerson.FakeRepObject:despawn()
            end)
            State.ThirdPerson.FakeRepObject = nil
        end
        
        if State.ThirdPerson.ThirdPersonObject then
            pcall(function()
                State.ThirdPerson.ThirdPersonObject:Destroy()
            end)
            State.ThirdPerson.ThirdPersonObject = nil
        end
        
        State.ThirdPerson.Initialized = false
    end,
}

local Walkspeed = {}

function Walkspeed:GetCharacterObject()
    local CharacterInterface = GameModules.CharacterInterface
    if not CharacterInterface then return nil end
    local success, result = pcall(function()
        return CharacterInterface.getCharacterObject()
    end)
    if success and result then
        State.Walkspeed.CharacterObject = result
        State.Walkspeed.RootPart = result._rootPart
        State.Walkspeed.Humanoid = result._humanoid
        return result
    end
    return nil
end

function Walkspeed:GetMoveDirection()
    local CameraCFrame = Camera.CFrame
    local LookVector = CameraCFrame.LookVector
    local RightVector = CameraCFrame.RightVector
    local MoveDirection = Vector3.zero

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
        MoveDirection += LookVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        MoveDirection -= LookVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        MoveDirection -= RightVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        MoveDirection += RightVector
    end

    return (MoveDirection ~= Vector3.zero and MoveDirection.Unit or MoveDirection)
end

function Walkspeed:HookNetwork()
    if State.Walkspeed.NetworkHooked then return true end
    local NetworkClient = GameModules.NetworkClient
    if not NetworkClient then 
        warn("[Walkspeed] Failed to get NetworkClient")
        return false 
    end
    local _send = NetworkClient.send
    
    NetworkClient.send = function(self, Method, ...)
        local Arguments = {...}
        if Method == 'repupdate' then
            local Position, Angles, BAng, Time = ...
            if Position then
                State.Walkspeed.Storage.LastRepupdate = Position
                State.Walkspeed.Storage.Repupdate = Position
            end
            if Angles then
                State.Walkspeed.Storage.LookAngles = Angles
            end
            
            if not State.Walkspeed.Storage.TimeUpdated then
                State.Walkspeed.Storage.PreviousTime = Time
            end
            
            if (Time - State.Walkspeed.Storage.PreviousTime) > (1 / 60) then
                State.Walkspeed.Storage.TimeUpdated = false
                State.Walkspeed.Storage.PreviousTime = Time
            end
            
            State.Walkspeed.Storage.TimeUpdated = not State.Walkspeed.Storage.TimeUpdated
            Time = State.Walkspeed.Storage.PreviousTime
            
            local ForcedPosition = State.Walkspeed.Storage.ForcedPosition
            if ForcedPosition and Position then
                local Direction = (ForcedPosition - Position)
                local RaycastParams = RaycastParams_new()
                RaycastParams.FilterDescendantsInstances = {
                    Workspace:FindFirstChild("Players"), 
                    Workspace.CurrentCamera,
                    Workspace:FindFirstChild("Ignore")
                }
                RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
                local RayResult = Workspace:Raycast(Position, Direction, RaycastParams)
                
                if RayResult then
                    local YOffset = 0
                    local HeightResult = Workspace:Raycast(
                        RayResult.Position + Vector3_new(0, 4, 0), 
                        Vector3_new(0, -2.5, 0), 
                        RaycastParams
                    )
                    if HeightResult then
                        YOffset = 4.5
                    end
                    Position = RayResult.Position + (Vector3.yAxis * YOffset) - (Direction.Unit * 4)
                else
                    Position = ForcedPosition
                end
                State.Walkspeed.Storage.ForcedPosition = nil
            end
            
            if not Position then
                Position = State.Walkspeed.Storage.LastRepupdate or Vector3.zero
            end
            return _send(self, Method, Position, Angles, BAng, Time)
        end
        return _send(self, Method, ...)
    end
    
    pcall(function()
        local NetworkEvents = getupvalue(NetworkClient.fireReady, 5)
        if NetworkEvents and NetworkEvents.correctposition then
            local _correctposition = NetworkEvents.correctposition
            NetworkEvents.correctposition = function(NewPosition)
                if State.Walkspeed.Enabled and State.Walkspeed.Method == 'Velocity' then
                    return
                end
                return _correctposition(NewPosition)
            end
        end
    end)
    
    State.Walkspeed.NetworkHooked = true
    return true
end

function Walkspeed:Update()
    if not State.Walkspeed.Enabled then return end
    local CharacterObject = self:GetCharacterObject()
    if not CharacterObject then return end
    local RootPart = State.Walkspeed.RootPart
    if not RootPart then return end
    
    if State.Walkspeed.Method == 'Velocity' then
        local MoveDirection = self:GetMoveDirection()
        MoveDirection = Vector3_new(MoveDirection.X, 0, MoveDirection.Z)
        RootPart.Velocity = MoveDirection * State.Walkspeed.Factor + Vector3.yAxis * RootPart.Velocity.Y
    elseif State.Walkspeed.Method == 'WalkSpeed' then
        if CharacterObject._walkspeedspring then
            CharacterObject._walkspeedspring.p = State.Walkspeed.Factor
        end
    end
    
    if State.Walkspeed.FlyEnabled then
        local MoveDirection = self:GetMoveDirection()
        local VerticalDirection = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            VerticalDirection -= Vector3.yAxis * State.Walkspeed.FlyVerticalSpeed
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            VerticalDirection += Vector3.yAxis * State.Walkspeed.FlyVerticalSpeed
        end
        RootPart.Velocity = MoveDirection * State.Walkspeed.FlyFactor + VerticalDirection
    end
end

function Walkspeed:Initialize()
    if State.Walkspeed.Initialized then return true end
    if not self:HookNetwork() then
        warn("[Walkspeed] Failed to hook network")
        return false
    end
    RunService.PreRender:Connect(function()
        pcall(function()
            self:Update()
        end)
    end)
    State.Walkspeed.Initialized = true
    return true
end

function Walkspeed:SetEnabled(StateEnabled)
    State.Walkspeed.Enabled = StateEnabled
    if StateEnabled and not State.Walkspeed.Initialized then
        return self:Initialize()
    end
    return true
end

function Walkspeed:SetFactor(NewFactor)
    State.Walkspeed.Factor = math.clamp(NewFactor, 0, 1000)
end

function Walkspeed:SetMethod(NewMethod)
    if NewMethod == 'Velocity' or NewMethod == 'WalkSpeed' then
        State.Walkspeed.Method = NewMethod
    end
end

function Walkspeed:GetCurrentPosition()
    return State.Walkspeed.Storage.LastRepupdate or 
           (State.Walkspeed.RootPart and State.Walkspeed.RootPart.Position) or 
           Vector3.zero
end

local Mods = {}

function Mods:Initialize()
    if not GameModules.MainCameraObject then return end
    
    local OriginalStep = GameModules.MainCameraObject.step
    
    GameModules.MainCameraObject.step = function(self, ...)
        if State.Mods.NoViewBob then
            local CharacterObject = GameModules.CharacterInterface.getCharacterObject()
            if CharacterObject then
                local OriginalSpeed = CharacterObject._speed
                CharacterObject._speed = 0
                local Result = OriginalStep(self, ...)
                CharacterObject._speed = OriginalSpeed
                return Result
            end
        end
        return OriginalStep(self, ...)
    end
end

function Mods:SetNoViewBob(enabled)
    State.Mods.NoViewBob = enabled
end

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/4dops/XephyrUI/refs/heads/main/ui.luau"))()
local Window = Library:Window({Name = "Axiom [BETA]", FadeSpeed = 0.3})

Library:ChangeTheme("Accent", Color3.fromRGB(0, 191, 255))
Library:ChangeTheme("Light Accent", Color3.fromRGB(0, 191, 255))


local Pages = {
    Combat = Window:Page({Name = "Combat", Columns = 2}),
    Visuals = Window:Page({Name = "Visuals", Columns = 2}),
    Player = Window:Page({Name = "Player", Columns = 2}),
    Mods = Window:Page({Name = "Mods", Columns = 2}),
    Settings = Window:Page({Name = "Settings", Columns = 3}),
}

local UiBuilder = {}

function UiBuilder.BuildCombatTab()
    local aimbotSection = Pages.Combat:Section({Name = "Aimbot", Side = 1})

    local aimbotToggle = aimbotSection:Toggle({
        Name = "Enabled",
        Flag = "aimbot_enabled",
        Default = false,
        Callback = function(value) 
            State.Aimbot.Enabled = value 
            if not value and Drawings.AimbotFovCircle then
                Drawings.AimbotFovCircle.Visible = false
            end
        end
    })

    aimbotToggle:Keybind({
        Name = "Hold Key",
        Flag = "aimbot_key",
        Default = Enum.UserInputType.MouseButton2,
        Mode = "Hold",
        Callback = function(active) State.Aimbot.IsHolding = active end
    })

    aimbotSection:Slider({
        Name = "Strength",
        Flag = "aimbot_strength",
        Min = 0.01, Max = 1, Decimals = 0.01, Default = 0.15,
        Callback = function(value) State.Aimbot.Strength = value end
    })

    aimbotSection:Slider({
        Name = "FOV",
        Flag = "aimbot_fov",
        Min = 10, Max = 500, Decimals = 1, Default = 150,
        Callback = function(value) State.Aimbot.Fov = value end
    })

    aimbotSection:Dropdown({
        Name = "Target Part",
        Flag = "aimbot_target",
        Multi = false, Default = "Head",
        Items = {"Head", "Torso"},
        Callback = function(value) State.Aimbot.TargetPart = value end
    })

    aimbotSection:Toggle({
        Name = "Team Check",
        Flag = "aimbot_team",
        Default = true,
        Callback = function(value) State.Aimbot.TeamCheck = value end
    })

    aimbotSection:Toggle({
        Name = "Wall Check",
        Flag = "aimbot_wall",
        Default = false,
        Callback = function(value) State.Aimbot.WallCheck = value end
    })

    local silentSection = Pages.Combat:Section({Name = "Silent Aim", Side = 2})

    silentSection:Toggle({
        Name = "Enabled",
        Flag = "silent_enabled",
        Default = false,
        Callback = function(value) 
            State.SilentAim.Enabled = value 
        end
    })

    silentSection:Toggle({
        Name = "Sticky Aim",
        Flag = "silent_sticky",
        Default = false,
        Callback = function(value) State.SilentAim.Sticky = value end
    })

    silentSection:Toggle({
        Name = "Wall Check",
        Flag = "silent_wall",
        Default = false,
        Callback = function(value) State.SilentAim.WallCheck = value end
    })

    silentSection:Slider({
        Name = "Hit Chance",
        Flag = "silent_hit",
        Min = 1, Max = 100, Decimals = 1, Default = 50, Suffix = "%",
        Callback = function(value) State.SilentAim.HitChance = value end
    })

    silentSection:Slider({
        Name = "Headshot Chance",
        Flag = "silent_head",
        Min = 0, Max = 100, Decimals = 1, Default = 100, Suffix = "%",
        Callback = function(value) State.SilentAim.HeadshotChance = value end
    })

    silentSection:Slider({
        Name = "Max Distance",
        Flag = "silent_dist",
        Min = 1, Max = 1000, Decimals = 1, Default = 500, Suffix = "studs",
        Callback = function(value) State.SilentAim.MaxDistance = value end
    })

    silentSection:Dropdown({
        Name = "Priority",
        Flag = "silent_priority",
        Multi = false, Default = "Closest To Mouse",
        Items = {"Closest To Mouse", "Closest To You"},
        Callback = function(value) State.SilentAim.Priority = value end
    })

    silentSection:Dropdown({
        Name = "Aim Part",
        Flag = "silent_part",
        Multi = false, Default = "Head",
        Items = {"Head", "Torso"},
        Callback = function(value) State.SilentAim.AimPart = value end
    })

    local silentVisualToggle = silentSection:Toggle({
        Name = "Show FOV",
        Flag = "silent_fov_show",
        Default = false,
        Callback = function(value) 
            State.SilentAim.ShowFov = value 
            if not value then
                if Drawings.SilentFovCircle then
                    pcall(function() Drawings.SilentFovCircle:Remove() end)
                    pcall(function() Drawings.SilentFovOutline:Remove() end)
                    pcall(function() Drawings.SilentFovFill:Remove() end)
                    Drawings.SilentFovCircle = nil
                    Drawings.SilentFovOutline = nil
                    Drawings.SilentFovFill = nil
                end
            end
        end
    })

    silentVisualToggle:Colorpicker({
        Name = "FOV Color",
        Flag = "silent_fov_color",
        Default = COLORS.DefaultFov,
        Callback = function(color) State.SilentAim.FovColor = color end
    })

    silentSection:Slider({
        Name = "FOV Size",
        Flag = "silent_fov_size",
        Min = 0, Max = 500, Decimals = 1, Default = 120, Suffix = "px",
        Callback = function(value) State.SilentAim.FovRadius = value end
    })

    silentSection:Toggle({
        Name = "Dynamic FOV",
        Flag = "silent_fov_dyn",
        Default = false,
        Callback = function(value) State.SilentAim.DynamicFov = value end
    })

    silentSection:Toggle({
        Name = "Lock on Target",
        Flag = "silent_fov_lock",
        Default = false,
        Callback = function(value) State.SilentAim.FovLockOnTarget = value end
    })

    local snapToggle = silentSection:Toggle({
        Name = "Snap Line",
        Flag = "silent_snap",
        Default = false,
        Callback = function(value) 
            State.SilentAim.ShowSnapLine = value 
            if not value then
                if Drawings.SilentSnapLine then
                    pcall(function() Drawings.SilentSnapLine:Remove() end)
                    pcall(function() Drawings.SilentSnapOutline:Remove() end)
                    Drawings.SilentSnapLine = nil
                    Drawings.SilentSnapOutline = nil
                end
            end
        end
    })

    snapToggle:Colorpicker({
        Name = "Snap Color",
        Flag = "silent_snap_color",
        Default = COLORS.DefaultSnap,
        Callback = function(color) State.SilentAim.SnapColor = color end
    })

    silentSection:Dropdown({
        Name = "Snap Origin",
        Flag = "silent_snap_origin",
        Multi = false, Default = "Gun Barrel",
        Items = {"Gun Barrel", "Mouse"},
        Callback = function(value) State.SilentAim.SnapOrigin = value end
    })

    silentSection:Dropdown({
        Name = "FOV Origin",
        Flag = "silent_fov_origin",
        Multi = false, Default = "Gun Barrel",
        Items = {"Gun Barrel", "Mouse"},
        Callback = function(value) State.SilentAim.FovOrigin = value end
    })
end

function UiBuilder.BuildVisualsTab()
    local espSection = Pages.Visuals:Section({Name = "ESP", Side = 1})

    espSection:Toggle({
        Name = "Enabled",
        Flag = "esp_enabled",
        Default = false,
        Callback = function(value)
            State.Esp.Enabled = value
            if not value then 
                Esp.ClearAll()
            end
        end
    })

    espSection:Toggle({
        Name = "Box ESP",
        Flag = "esp_box",
        Default = false,
        Callback = function(value)
            State.Esp.ShowBox = value
        end
    })

    espSection:Toggle({
        Name = "Visible Check",
        Flag = "esp_visible",
        Default = false,
        Callback = function(value)
            State.Esp.ShowVisible = value
        end
    })

    local fovSection = Pages.Visuals:Section({Name = "FOV Circle", Side = 1})

    local fovToggle = fovSection:Toggle({
        Name = "Enabled",
        Flag = "fov_enabled",
        Default = true,
        Callback = function(value) 
            State.FovCircle.Enabled = value 
            if not value and Drawings.AimbotFovCircle then
                Drawings.AimbotFovCircle.Visible = false
            end
        end
    })

    fovToggle:Colorpicker({
        Name = "Color",
        Flag = "fov_color",
        Default = COLORS.DefaultFov,
        Callback = function(color)
            State.FovCircle.Color = color
            if Drawings.AimbotFovCircle then
                Drawings.AimbotFovCircle.Color = color
            end
        end
    })

    fovSection:Toggle({
        Name = "Always Show",
        Flag = "fov_always",
        Default = false,
        Callback = function(value) State.FovCircle.ShowAlways = value end
    })

    fovSection:Slider({
        Name = "Thickness",
        Flag = "fov_thick",
        Min = 1, Max = 5, Decimals = 0.1, Default = 1,
        Callback = function(value)
            State.FovCircle.Thickness = value
            if Drawings.AimbotFovCircle then
                Drawings.AimbotFovCircle.Thickness = value
            end
        end
    })

    local chamsSection = Pages.Visuals:Section({Name = "Chams", Side = 2})

    local chamsToggle = chamsSection:Toggle({
        Name = "Enabled",
        Flag = "chams_enabled",
        Default = false,
        Callback = function(value)
            State.Chams.Enabled = value
            if not value then
                Chams.ClearAll()
            end
        end
    })

    chamsToggle:Colorpicker({
        Name = "Fill Color",
        Flag = "chams_color",
        Default = COLORS.DefaultChams,
        Callback = function(color)
            State.Chams.FillColor = color
        end
    })

    chamsSection:Slider({
        Name = "Fill Transparency",
        Flag = "chams_trans",
        Min = 0, Max = 1, Decimals = 0.01, Default = 0.5,
        Callback = function(value)
            State.Chams.FillTransparency = value
        end
    })

    chamsSection:Dropdown({
        Name = "Depth Mode",
        Flag = "chams_depth",
        Multi = false, Default = "AlwaysOnTop",
        Items = {"AlwaysOnTop", "Occluded"},
        Callback = function(value)
            State.Chams.AlwaysOnTop = value == "AlwaysOnTop"
        end
    })

    chamsSection:Toggle({
        Name = "Enemy Only",
        Flag = "chams_enemy",
        Default = true,
        Callback = function(value)
            State.Chams.EnemyOnly = value
        end
    })
end

function UiBuilder.BuildPlayerTab()
    local tpSection = Pages.Player:Section({Name = "Third Person", Side = 1})

    local tpToggle = tpSection:Toggle({
        Name = "Enabled",
        Flag = "tp_enabled",
        Default = false,
        Callback = function(value)
            State.ThirdPerson.Active = value
            if value then
                if not ThirdPerson:Init() then
                    State.ThirdPerson.Active = false
                    tpToggle:SetValue(false)
                end
            else
                ThirdPerson:Cleanup()
                State.ThirdPerson.Initialized = false
            end
        end
    })

    tpToggle:Keybind({
        Name = "Toggle Key",
        Flag = "tp_key",
        Mode = "Toggle",
        Default = Enum.KeyCode.T,
        Callback = function(active)
            local oldidentity = getidentity()
            setidentity(3)
            State.ThirdPerson.Active = active
            tpToggle:Set(active)
            setidentity(oldidentity)
        end
    })

    tpSection:Slider({
        Name = "Camera Distance",
        Flag = "tp_distance",
        Min = 0, Max = 50, Decimals = 0.5, Default = 4.5,
        Callback = function(value) State.ThirdPerson.Distance = value end
    })

    tpSection:Slider({
        Name = "Camera X Offset",
        Flag = "tp_x_offset",
        Min = -20, Max = 20, Decimals = 0.5, Default = 1.5,
        Suffix = " studs",
        Callback = function(value) 
            State.ThirdPerson.XOffset = value 
        end
    })

    tpSection:Slider({
        Name = "Camera Y Offset", 
        Flag = "tp_y_offset",
        Min = -20, Max = 20, Decimals = 0.5, Default = 0.5,
        Suffix = " studs",
        Callback = function(value) 
            State.ThirdPerson.YOffset = value 
        end
    })

    tpSection:Toggle({
        Name = "Remove Arms",
        Flag = "tp_arms",
        Default = true,
        Callback = function(value) State.ThirdPerson.RemoveArms = value end
    })

    tpSection:Toggle({
        Name = "Remove Weapon",
        Flag = "tp_weapon",
        Default = false,
        Callback = function(value) State.ThirdPerson.RemoveWeapon = value end
    })

    tpSection:Toggle({
        Name = "Use Root Position",
        Flag = "tp_root",
        Default = false,
        Callback = function(value) State.ThirdPerson.UseRoot = value end
    })

    tpSection:Button():NewButton({
        Name = "Reinitialize [ONLY USE IN EMERGENCY]",
        Callback = function()
            ThirdPerson:Init()
        end
    })

    local speedSection = Pages.Player:Section({Name = "Walkspeed", Side = 2})

    speedSection:Toggle({
        Name = "Enabled",
        Flag = "walkspeed_enabled",
        Default = false,
        Callback = function(value)
            Walkspeed:SetEnabled(value)
        end
    })

    speedSection:Slider({
        Name = "Speed Factor",
        Flag = "walkspeed_factor",
        Min = 0, Max = 1000, Decimals = 1, Default = 50, Suffix = " studs/s",
        Callback = function(value)
            Walkspeed:SetFactor(value)
        end
    })

    speedSection:Dropdown({
        Name = "Method",
        Flag = "walkspeed_method",
        Multi = false, Default = "Velocity",
        Items = {"Velocity", "WalkSpeed"},
        Callback = function(value)
            Walkspeed:SetMethod(value)
        end
    })
end

function UiBuilder.BuildModsTab()
    local CameraSection = Pages.Mods:Section({Name = "Camera", Side = 1})
    
    CameraSection:Toggle({
        Name = "Remove View Bob",
        Flag = "noviewbob_enabled",
        Default = false,
        Callback = function(value)
            Mods:SetNoViewBob(value)
        end
    })
end

function UiBuilder.BuildSettingsTab()
    local configSection = Pages.Settings:Section({Name = "Configuration", Side = 1})
    local menuSection = Pages.Settings:Section({Name = "Menu", Side = 3})

    local selectedConfig = nil
    local configName = nil

    local configList = configSection:Dropdown({
        Name = "Configs",
        Flag = "config_list",
        Items = {},
        Callback = function(value) selectedConfig = value end
    })

    configSection:Textbox({
        Name = "Config Name",
        Placeholder = "Enter name...",
        Flag = "config_input",
        Callback = function(value) configName = value end
    })

    local buttonRow1 = configSection:Button()
    buttonRow1:NewButton({
        Name = "Create",
        Callback = function()
            if not configName or configName == "" then return end
            local path = Library.Folders.Configs .. "/" .. configName .. ".json"
            if isfile(path) then
                Library:Notification("Config already exists", 4, Color3_new(1, 0, 0))
                return
            end
            writefile(path, Library:GetConfig())
            Library:Notification("Created config: " .. configName, 4, Color3_new(0, 1, 0))
            Library:RefreshConfigsList(configList)
        end
    })

    buttonRow1:NewButton({
        Name = "Delete",
        Callback = function()
            if not selectedConfig then return end
            local path = Library.Folders.Configs .. "/" .. selectedConfig
            if isfile(path) then
                Library:DeleteConfig(selectedConfig)
                Library:Notification("Deleted config: " .. selectedConfig, 5, Color3_new(0, 1, 0))
                Library:RefreshConfigsList(configList)
            end
        end
    })

    local buttonRow2 = configSection:Button()
    buttonRow2:NewButton({
        Name = "Save",
        Callback = function()
            if not selectedConfig then return end
            Library:SaveConfig(selectedConfig)
            Library:Notification("Saved config: " .. selectedConfig, 5, Color3_new(0, 1, 0))
        end
    })

    buttonRow2:NewButton({
        Name = "Load",
        Callback = function()
            if not selectedConfig then return end
            local path = Library.Folders.Configs .. "/" .. selectedConfig
            local success, err = Library:LoadConfig(readfile(path))
            if not success then
                Library:Notification("Failed to load: " .. tostring(err), 6, Color3_new(1, 0, 0))
            else
                Library:Notification("Loaded config: " .. selectedConfig, 5, Color3_new(0, 1, 0))
            end
        end
    })

    configSection:Button():NewButton({
        Name = "Refresh",
        Callback = function()
            Library:RefreshConfigsList(configList)
            Library:Notification("Refreshed config list", 4, Color3_new(0, 1, 0))
        end
    })

    Library:RefreshConfigsList(configList)

    menuSection:Button():NewButton({
        Name = "Unload",
        Callback = function() 
            ThirdPerson:Cleanup()
            Esp.ClearAll()
            Chams.ClearAll()
            for key, drawing in ipairs(Drawings) do
                if drawing then
                    pcall(function() drawing:Remove() end)
                end
            end
            Library:Unload() 
        end
    })

    menuSection:Label("Menu Key", "Left"):Keybind({
        Name = "MenuKey",
        Flag = "menu_key",
        Mode = "Toggle",
        Default = Library.MenuKeybind,
        Callback = function() Library.MenuKeybind = Library.Flags["menu_key"].Key end
    })

    menuSection:Slider({
        Name = "Tween Time",
        Flag = "tween_time",
        Min = 0, Max = 5, Decimals = 0.1, Default = Library.Tween.Time,
        Callback = function(value) Library.Tween.Time = value end
    })

    menuSection:Dropdown({
        Name = "Tween Style",
        Flag = "tween_style",
        Default = "Cubic",
        Items = {"Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Elastic", "Bounce"},
        Callback = function(value) Library.Tween.Style = Enum.EasingStyle[value] end
    })

    menuSection:Dropdown({
        Name = "Tween Direction",
        Flag = "tween_dir",
        Default = "Out",
        Items = {"In", "Out", "InOut"},
        Callback = function(value) Library.Tween.Direction = Enum.EasingDirection[value] end
    })

    local themeSection = Pages.Settings:Section({Name = "Theming", Side = 2})
    for index, color in Library.Theme do
        themeSection:Label(index, "Left"):Colorpicker({
            Name = index,
            Flag = index .. "_theme",
            Default = color,
            Callback = function(newColor)
                Library.Theme[index] = newColor
                Library:ChangeTheme(index, newColor)
            end
        })
    end
end

local function Initialize()
    if not debug.getupvalue or not debug.getstack then
        return LocalPlayer:Kick("Incompatible executor")
    end

    local success, err = pcall(InitializeGameModules)
    if not success then
        return LocalPlayer:Kick("Module initialization failed: " .. tostring(err))
    end

    do
        local CI = GameModules.CharacterInterface
        if CI then
            local OriginalDespawn = CI.despawn
            CI.despawn = function(...)
                ThirdPerson:Cleanup()
                return OriginalDespawn(...)
            end
        end
        
        local network = GameModules.NetworkClient
        if network then
            local originalSend = network.send
            network.send = function(self, method, ...)
                if method == "spawn" then
                    ThirdPerson:Cleanup()
                    task.delay(0.1, function()
                        if State.ThirdPerson.Active and not State.ThirdPerson.Initialized then
                            ThirdPerson:Init()
                        end
                    end)
                end
                return originalSend(self, method, ...)
            end
        end
        
        RunService.PreRender:Connect(function()
            if not State.ThirdPerson.Active then
                if next(TP_OriginalTransparency) == nil then return end
                for _, Viewmodel in ipairs(Camera:GetChildren()) do
                    if Viewmodel:IsA("Model") then
                        for _, Asset in ipairs(Viewmodel:GetDescendants()) do
                            if TP_OriginalTransparency[Asset] then
                                pcall(function() 
                                    Asset.Transparency = TP_OriginalTransparency[Asset] 
                                end)
                                TP_OriginalTransparency[Asset] = nil
                            end
                        end
                    end
                end
                return
            end
            
            for _, Viewmodel in ipairs(Camera:GetChildren()) do
                if Viewmodel:IsA("Model") then
                    local IsArm = Viewmodel:FindFirstChild("Arm") ~= nil
                    local ShouldHide = (State.ThirdPerson.RemoveArms and IsArm) or 
                                       (State.ThirdPerson.RemoveWeapon and not IsArm)
                    
                    if ShouldHide then
                        for _, Asset in ipairs(Viewmodel:GetDescendants()) do
                            local ok, hasTrans = pcall(function()
                                return Asset.Transparency ~= nil and typeof(Asset.Transparency) == "number"
                            end)
                            
                            if ok and hasTrans and Asset.Transparency ~= 1 then
                                if not TP_OriginalTransparency[Asset] then
                                    TP_OriginalTransparency[Asset] = Asset.Transparency
                                end
                                Asset.Transparency = 1
                            end
                        end
                    end
                end
            end
        end)
        
        if CI and CI.getCharacterObject and CI.getCharacterObject() then
            task.spawn(function()
                ThirdPerson:Init()
            end)
        end
    end

    UiBuilder.BuildCombatTab()
    UiBuilder.BuildVisualsTab()
    UiBuilder.BuildPlayerTab()
    UiBuilder.BuildModsTab()
    UiBuilder.BuildSettingsTab()

    SilentAim.InitializeHook()
    Mods:Initialize()

    UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            State.Aimbot.IsHolding = true
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            State.Aimbot.IsHolding = false
        end
    end)

    local weaponObject = GameModules.WeaponControllerObject

    if weaponObject then
        local originalPreparePickUpFirearm = weaponObject.preparePickUpFirearm
        weaponObject.preparePickUpFirearm = function(self, slot, name, attachments, attData, camoData, magAmmo, spareAmmo, newId, wasClient, ...)
            local wepData = {
                weaponName = name,
                weaponAttachments = attachments,
                weaponAttData = attData,
                weaponCamo = camoData
            }
            
            local fakeRep = State.ThirdPerson.FakeRepObject
            if fakeRep then
                fakeRep:setActiveIndex(slot)
                fakeRep:swapWeapon(slot, wepData)
                
                local tpObj = State.ThirdPerson.ThirdPersonObject
                if tpObj then
                    pcall(function() tpObj:buildWeapon(slot) end)
                end
            end
            
            return originalPreparePickUpFirearm(self, slot, name, attachments, attData, camoData, magAmmo, spareAmmo, newId, wasClient, ...)
        end
        
        local originalPreparePickUpMelee = weaponObject.preparePickUpMelee
        weaponObject.preparePickUpMelee = function(self, name, camoData, newId, wasClient, ...)
            local wepData = {
                weaponName = name,
                weaponCamo = camoData
            }
            
            local fakeRep = State.ThirdPerson.FakeRepObject
            if fakeRep then
                fakeRep:setActiveIndex(3)
                fakeRep:swapWeapon(3, wepData)
                
                local tpObj = State.ThirdPerson.ThirdPersonObject
                if tpObj then
                    pcall(function() tpObj:buildWeapon(3) end)
                end
            end
            
            return originalPreparePickUpMelee(self, name, camoData, newId, wasClient, ...)
        end
    end

    local originalNetworkSend = GameModules.NetworkClient.send

    function GameModules.NetworkClient:send(method, ...)
        local args = {...}

        if method == "newbullets" and PendingSilentAimVelocity then
            local bulletData = args[2]
            if bulletData and bulletData.bullets then
                for _, bullet in ipairs(bulletData.bullets) do
                    bullet[1] = PendingSilentAimVelocity
                end
            end
            PendingSilentAimVelocity = nil
        end

        if method == "repupdate" then
            State.ThirdPerson.Storage.Repupdate = args[1]
            State.ThirdPerson.Storage.LookAngles = args[2]
        elseif method == "spawn" then
            State.ThirdPerson.Initialized = false
            task.delay(0.1, function()
                if not State.ThirdPerson.Initialized then
                    ThirdPerson:Init()
                end
            end)
        end

        if State.ThirdPerson.ThirdPersonObject and State.ThirdPerson.Active then
            if method == "equip" then
                 pcall(function()
                    local Slot = args[1]
                    local tpObj = State.ThirdPerson.ThirdPersonObject
                    if not tpObj then return end
                    if Slot == 3 then
                        tpObj:equipMelee()
                    else
                        tpObj:equip(Slot)
                    end
                end)
            elseif method == "newbullets" then
                pcall(function() 
                    if State.ThirdPerson.ThirdPersonObject and State.ThirdPerson.ThirdPersonObject.kickWeapon then
                        State.ThirdPerson.ThirdPersonObject:kickWeapon(0, Vector3_new(0, 0, 0), Vector3_new(0, 0, 0), 0) 
                    end
                end)
            elseif method == "sprint" then
                pcall(function() State.ThirdPerson.ThirdPersonObject:setSprint(args[1]) end)
            elseif method == "aim" then
                pcall(function() State.ThirdPerson.ThirdPersonObject:setAim(args[1]) end)
            elseif method == "stab" then
                pcall(function() State.ThirdPerson.ThirdPersonObject:stab() end)
            end
        end

        return originalNetworkSend(self, method, unpack(args))
    end

    local lastChamsRefresh = 0

    RunService.RenderStepped:Connect(function(dt)
        local hasAnyFeature = State.SilentAim.Enabled 
            or State.SilentAim.ShowFov 
            or State.SilentAim.ShowSnapLine
            or State.Aimbot.Enabled 
            or State.Esp.Enabled 
            or State.Chams.Enabled
            or State.FovCircle.Enabled
            
        if not hasAnyFeature then
            return
        end
        
        if State.SilentAim.Enabled or State.SilentAim.ShowFov or State.SilentAim.ShowSnapLine then
            SilentAim.UpdateGunBarrel()
            SilentAim.UpdateVisuals(dt)
        end
        
        if State.Aimbot.Enabled or State.FovCircle.Enabled then
            Aimbot.Update()
        end
        
        if State.Esp.Enabled then
            Esp.Update()
        end
        
        if State.Chams.Enabled and (tick() - lastChamsRefresh >= CONFIG.ChamsRefreshInterval) then
            lastChamsRefresh = tick()
            Chams.RefreshAll()
        elseif not State.Chams.Enabled and next(State.Chams.ActiveHighlights) ~= nil then
            Chams.ClearAll()
        end
    end)
end

Initialize()

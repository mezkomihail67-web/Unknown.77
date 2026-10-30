local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera

local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
if PlayerGui then
    local ExistingGui = PlayerGui:FindFirstChild("DeltaUltimateAdaptiveHubV5")
    if ExistingGui then ExistingGui:Destroy() end
else
    warn("Delta Hub: PlayerGui не прогрузился вовремя!")
end

_G.BombConfig = {
    forwardVelocity = 60,
    upwardVelocity = 35,
    maxSpeed = 250,
    Prediction = 2,
    fuseTime = 5.0,
    isCounting = false,
    selectedTarget = nil,
    explosionTick = 0,
    homingMode = "Auto Time",
    turretOwner = LocalPlayer.Name,
    turretAimMode = "Auto-Lock",
    turretTypeMode = "Single",
    maxTurrets = 5,
    BombNoclip = false,
    modeRobotFlyer = false
}

local trailParts = {}
local activeTurretBase = nil
local activeTurretsList = {}
local currentSpectateTarget = nil
local spinAngle = 0
local ActiveBomb = nil

local targetCross = workspace:FindFirstChild("FE_BombCross_Ultimate")
if not targetCross then
    targetCross = Instance.new("Part")
    targetCross.Name = "FE_BombCross_Ultimate"
    targetCross.Shape = Enum.PartType.Ball
    targetCross.Size = Vector3.new(1.5, 1.5, 1.5)
    targetCross.Color = Color3.fromRGB(255, 0, 0)
    targetCross.Material = Enum.Material.Neon
    targetCross.CanCollide = false
    targetCross.Anchored = true
    targetCross.Parent = workspace
end

local function clearTrail()
    for _, p in ipairs(trailParts) do p:Destroy() end
    table.clear(trailParts)
end

local function drawSegment(startPos, endPos)
    local distance = (endPos - startPos).Magnitude
    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = false
    p.Size = Vector3.new(0.3, 0.3, distance)
    p.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -distance/2)
    p.Color = Color3.fromRGB(0, 255, 255)
    p.Material = Enum.Material.Neon
    p.Transparency = 0.4
    p.Parent = workspace
    table.insert(trailParts, p)
end

local function getComplexTrajectory(startPos, initialVelocity)
    local gravity = workspace.Gravity
    local dt = 0.04
    local currentPos = startPos
    local currentVel = initialVelocity
    local lastPos = startPos
    local totalTime = 0
    local finalLandingPos = startPos
    local bouncesLeft = 3
    clearTrail()
    
    for i = 1, 120 do
        totalTime = totalTime + dt
        local nextPos = currentPos + currentVel * dt + 0.5 * Vector3.new(0, -gravity, 0) * dt * dt
        currentVel = currentVel + Vector3.new(0, -gravity, 0) * dt
        
        local raycastParams = RaycastParams.new()
        raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, targetCross}
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        for _, p in ipairs(trailParts) do table.insert(raycastParams.FilterDescendantsInstances, p) end

        local raycastResult = workspace:Raycast(currentPos, nextPos - currentPos, raycastParams)
        if raycastResult then
            drawSegment(lastPos, raycastResult.Position)
            if bouncesLeft > 0 then
                local normal = raycastResult.Normal
                currentVel = (currentVel - 2 * currentVel:Dot(normal) * normal) * 0.6
                currentPos = raycastResult.Position + (normal * 0.2)
                lastPos = currentPos
                bouncesLeft = bouncesLeft - 1
            else
                finalLandingPos = raycastResult.Position
                return finalLandingPos, totalTime
            end
        else
            if i % 3 == 0 or i == 1 then
                drawSegment(lastPos, nextPos)
                lastPos = nextPos
            end
            currentPos = nextPos
        end
        finalLandingPos = currentPos
    end
    return finalLandingPos, totalTime
end

local function findPlayer(str)
    if not str or str == "" then return nil end
    str = string.lower(str)
    for _, player in ipairs(Players:GetPlayers()) do
        if string.find(string.lower(player.Name), str) or string.find(string.lower(player.DisplayName), str) then
            return player
        end
    end
    return nil
end

local function findFuseBomb()
    local bomb = workspace:FindFirstChild("FuseBomb", true) or workspace:FindFirstChild("Bomb", true)
    if bomb and bomb:IsA("BasePart") then return bomb end
    return nil
end

local function claimNetworkOwnership(part)
    if part and part:IsA("BasePart") then
        task.spawn(function()
            while part and part.Parent do
                settings().Physics.AllowSleep = false
                pcall(function()
                    part.AssemblyLinearVelocity = part.AssemblyLinearVelocity + Vector3.new(0, 0.05, 0)
                end)
                task.wait(0.05)
            end
        end)
    end
end

if PlayerGui then
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "DeltaUltimateAdaptiveHubV5"
    ScreenGui.Parent = PlayerGui
    ScreenGui.ResetOnSpawn = false

    local ToggleCircle = Instance.new("TextButton")
    local CircleCorner = Instance.new("UICorner")
    ToggleCircle.Name = "ToggleCircle"
    ToggleCircle.Parent = ScreenGui
    ToggleCircle.Size = UDim2.new(0, 45, 0, 45)
    ToggleCircle.Position = UDim2.new(0.02, 0, 0.15, 0)
    ToggleCircle.BackgroundColor3 = Color3.fromRGB(255, 100, 0)
    ToggleCircle.Text = "B"
    ToggleCircle.TextColor3 = Color3.fromRGB(255, 255, 255)
    ToggleCircle.TextSize = 20
    ToggleCircle.Font = Enum.Font.SourceSansBold
    ToggleCircle.Active = true
    ToggleCircle.Draggable = true

    CircleCorner.CornerRadius = UDim.new(1, 0)
    CircleCorner.Parent = ToggleCircle

    local MainFrame = Instance.new("Frame")
    local MainCorner = Instance.new("UICorner")
    MainFrame.Name = "MainFrame"
    MainFrame.Parent = ScreenGui
    MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    MainFrame.Position = UDim2.new(0.15, 0, 0.15, 0)
    MainFrame.Size = UDim2.new(0, 260, 0, 420)
    MainFrame.Active = true
    MainFrame.Draggable = true

    MainCorner.CornerRadius = UDim.new(0, 8)
    MainCorner.Parent = MainFrame

    ToggleCircle.MouseButton1Click:Connect(function()
        MainFrame.Visible = not MainFrame.Visible
    end)

    local Container = Instance.new("ScrollingFrame")
    local UIList = Instance.new("UIListLayout")
    Container.Parent = MainFrame
    Container.Size = UDim2.new(1, -10, 1, -10)
    Container.Position = UDim2.new(0, 5, 0, 5)
    Container.BackgroundTransparency = 1
    Container.ScrollBarThickness = 4
    Container.ClipsDescendants = false

    UIList.Parent = Container
    UIList.SortOrder = Enum.SortOrder.LayoutOrder
    UIList.Padding = UDim.new(0, 6)

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 30)
    Title.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    Title.Text = "Ultimate Launcher v5 (Fixed)"
    Title.TextColor3 = Color3.fromRGB(255, 255, 255)
    Title.Font = Enum.Font.SourceSansBold
    Title.Parent = Container

    local InputHolder = Instance.new("Frame")
    InputHolder.Size = UDim2.new(1, 0, 0, 32)
    InputHolder.BackgroundTransparency = 1
    InputHolder.Parent = Container

    local ForwardInput = Instance.new("TextBox")
    ForwardInput.Size = UDim2.new(0.48, 0, 1, 0)
    ForwardInput.PlaceholderText = "Forward"
    ForwardInput.Text = "60"
    ForwardInput.Parent = InputHolder

    local UpwardInput = Instance.new("TextBox")
    UpwardInput.Position = UDim2.new(0.52, 0, 0, 0)
    UpwardInput.Size = UDim2.new(0.48, 0, 1, 0)
    UpwardInput.PlaceholderText = "Upward"
    UpwardInput.Text = "35"
    UpwardInput.Parent = InputHolder

    local NameInput = Instance.new("TextBox")
    NameInput.Size = UDim2.new(1, 0, 0, 32)
    NameInput.PlaceholderText = "Target Player Name..."
    NameInput.Text = ""
    NameInput.Parent = Container

    local TimerDisplay = Instance.new("TextLabel")
    TimerDisplay.Size = UDim2.new(1, 0, 0, 32)
    TimerDisplay.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
    TimerDisplay.Text = "STATUS: READY"
    TimerDisplay.TextColor3 = Color3.fromRGB(100, 255, 100)
    TimerDisplay.Font = Enum.Font.Code
    TimerDisplay.Parent = Container

    local function makeUiButton(text, bgCol, parent)
        local btn = Instance.new("TextButton")
        local corn = Instance.new("UICorner")
        btn.Size = UDim2.new(1, 0, 0, 35)
        btn.BackgroundColor3 = bgCol
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.SourceSansBold
        btn.TextSize = 13
        corn.CornerRadius = UDim.new(0, 5)
        corn.Parent = btn
        btn.Parent = parent
        return btn
    end

    local ToggleModeBtn = makeUiButton("MODE: Auto Time", Color3.fromRGB(45, 45, 60), Container)
    local DetectFuseBtn = makeUiButton("DETECT FUSE TIME (5s)", Color3.fromRGB(40, 70, 70), Container)
    local ViewTargetBtn = makeUiButton("VIEW SUBJECT: SELF", Color3.fromRGB(70, 50, 90), Container)
    local LaunchButton = makeUiButton("LAUNCH STANDARD", Color3.fromRGB(40, 140, 40), Container)
    local LaunchHomingButton = makeUiButton("⚡ LAUNCH HOMING (FE) ⚡", Color3.fromRGB(180, 50, 50), Container)

    local SeparationLine = Instance.new("TextLabel")
    SeparationLine.Size = UDim2.new(1, 0, 0, 25)
    SeparationLine.Text = "— TURRET & SENTRY SYSTEMS —"
    SeparationLine.TextColor3 = Color3.fromRGB(150, 150, 150)
    SeparationLine.BackgroundTransparency = 1
    SeparationLine.Font = Enum.Font.SourceSansBold
    SeparationLine.Parent = Container

    local TurretOwnerInput = Instance.new("TextBox")
    TurretOwnerInput.Size = UDim2.new(1, 0, 0, 32)
    TurretOwnerInput.PlaceholderText = "Turret Owner (Ignore)..."
    TurretOwnerInput.Text = LocalPlayer.Name
    TurretOwnerInput.Parent = Container

    local TurretAimModeBtn = makeUiButton("AIM MODE: Auto-Lock", Color3.fromRGB(60, 60, 80), Container)
    local TurretTypeBtn = makeUiButton("SYSTEM: Single (Flyer)", Color3.fromRGB(50, 80, 80), Container)
    local SetSentryBtn = makeUiButton("📍 SET SENTRY UNDER FEET", Color3.fromRGB(140, 90, 40), Container)
    local ClearAllSentryBtn = makeUiButton("❌ CLEAR ALL SENTRY LOGS", Color3.fromRGB(120, 60, 60), Container)
    local ToggleTurretSystemBtn = makeUiButton("TURRET SYSTEM: OFF", Color3.fromRGB(90, 40, 40), Container)

    local totalItems = 15
    Container.CanvasSize = UDim2.new(0, 0, 0, (totalItems * 42) + 20)

    ForwardInput.FocusLost:Connect(function() _G.BombConfig.forwardVelocity = tonumber(ForwardInput.Text) or 60 end)
    UpwardInput.FocusLost:Connect(function() _G.BombConfig.upwardVelocity = tonumber(UpwardInput.Text) or 35 end)
    NameInput.FocusLost:Connect(function() _G.BombConfig.selectedTarget = findPlayer(NameInput.Text) end)
    TurretOwnerInput.FocusLost:Connect(function() _G.BombConfig.turretOwner = TurretOwnerInput.Text end)

    ToggleModeBtn.MouseButton1Click:Connect(function()
        if _G.BombConfig.homingMode == "Auto Time" then
            _G.BombConfig.homingMode = "Noclip Direct"
            _G.BombConfig.BombNoclip = true
            ToggleModeBtn.Text = "MODE: Noclip Direct"
        else
            _G.BombConfig.homingMode = "Auto Time"
            _G.BombConfig.BombNoclip = false
            ToggleModeBtn.Text = "MODE: Auto Time"
        end
    end)

    DetectFuseBtn.MouseButton1Click:Connect(function()
        local val = tonumber(string.match(DetectFuseBtn.Text, "%d+")) or 5
        val = val + 5 if val > 30 then val = 5 end
        _G.BombConfig.fuseTime = val
        DetectFuseBtn.Text = "DETECT FUSE TIME ("..val.."s)"
    end)

    ViewTargetBtn.MouseButton1Click:Connect(function()
        local bomb = findFuseBomb()
        if currentSpectateTarget == nil and _G.BombConfig.selectedTarget then
            currentSpectateTarget = "Target"
            ViewTargetBtn.Text = "VIEW SUBJECT: TARGET"
        elseif currentSpectateTarget == "Target" and bomb then
            currentSpectateTarget = "Bomb"
            ViewTargetBtn.Text = "VIEW SUBJECT: BOMB"
        else
            currentSpectateTarget = nil
            ViewTargetBtn.Text = "VIEW SUBJECT: SELF"
            Camera.CameraType = Enum.CameraType.Custom
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                Camera.CameraSubject = LocalPlayer.Character.Humanoid
            end
        end
    end)

    local function updateCrossAndTrailLogic()
        local now = tick()
        if _G.BombConfig.isCounting then
            local timeLeft = _G.BombConfig.explosionTick - now
            if timeLeft > 0 then
                TimerDisplay.Text = string.format("FUSE TIME: %.2fs", timeLeft)
                TimerDisplay.TextColor3 = Color3.fromRGB(255, 80, 80)
                return
            else
                _G.BombConfig.isCounting = false
                TimerDisplay.Text = "STATUS: READY"
                TimerDisplay.TextColor3 = Color3.fromRGB(100, 255, 100)
            end
        end
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local hrp = char.HumanoidRootPart
            local launchVelocity = (hrp.CFrame.LookVector * _G.BombConfig.forwardVelocity) + (Vector3.new(0, 1, 0) * _G.BombConfig.upwardVelocity)
            local landingPos, travelTime = getComplexTrajectory(hrp.Position, launchVelocity)
            targetCross.Position = landingPos
            if not _G.BombConfig.isCounting then
                TimerDisplay.Text = string.format("Est. Bounce Time: %.1fs", travelTime)
                TimerDisplay.TextColor3 = Color3.fromRGB(200, 200, 250)
            end
        end
    end

    RunService.Stepped:Connect(function()
        if _G.BombConfig.BombNoclip and ActiveBomb and ActiveBomb.Parent then
            ActiveBomb.CanCollide = false
        end
    end)

    RunService.RenderStepped:Connect(function()
        pcall(updateCrossAndTrailLogic)
        if currentSpectateTarget == "Target" and _G.BombConfig.selectedTarget and _G.BombConfig.selectedTarget.Character then
            local hrp = _G.BombConfig.selectedTarget.Character:FindFirstChild("HumanoidRootPart")
            if hrp then Camera.CameraSubject = hrp end
        elseif currentSpectateTarget == "Bomb" then
            local bomb = findFuseBomb()
            if bomb then Camera.CameraSubject = bomb end
        end
        if _G.BombConfig.modeRobotFlyer and _G.BombConfig.turretAimMode == "Manual FPS" and activeTurretBase and activeTurretBase.Parent then
            Camera.CameraType = Enum.CameraType.Scriptable
            Camera.CFrame = CFrame.new(activeTurretBase.Position) * CFrame.new(0, 0, -1) * (Camera.CFrame - Camera.CFrame.Position)
        end
    end)

    TurretAimModeBtn.MouseButton1Click:Connect(function()
        if _G.BombConfig.turretAimMode == "Auto-Lock" then _G.BombConfig.turretAimMode = "Spin+Y-Track"
        elseif _G.BombConfig.turretAimMode == "Spin+Y-Track" then _G.BombConfig.turretAimMode = "Manual FPS"
        else _G.BombConfig.turretAimMode = "Auto-Lock" Camera.CameraType = Enum.CameraType.Custom end
        TurretAimModeBtn.Text = "AIM MODE: " .. _G.BombConfig.turretAimMode
    end)

    TurretTypeBtn.MouseButton1Click:Connect(function()
        _G.BombConfig.turretTypeMode = _G.BombConfig.turretTypeMode == "Single" and "Multi" or "Single"
        TurretTypeBtn.Text = "SYSTEM: " .. (_G.BombConfig.turretTypeMode == "Single" and "Single (Flyer)" or "Multi (Sentry)")
    end)

    ClearAllSentryBtn.MouseButton1Click:Connect(function()
        for _, t in ipairs(activeTurretsList) do pcall(function() t:Destroy() end) end
        table.clear(activeTurretsList)
    end)
end

local function handleTurretCombat(turretPart)
    local att = turretPart:FindFirstChild("TurretAttachment") or Instance.new("Attachment", turretPart)
    local alignOrient = turretPart:FindFirstChild("TurretGyro") or Instance.new("AlignOrientation", turretPart)
    alignOrient.Attachment0 = att
    alignOrient.MaxTorque = math.huge
    alignOrient.Responsiveness = 200
    
    task.spawn(function()
        while turretPart and turretPart.Parent and _G.BombConfig.modeRobotFlyer do
            local owner = findPlayer(_G.BombConfig.turretOwner)
            local closest, dist = nil, 200
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= owner and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                    local d = (p.Character.HumanoidRootPart.Position - turretPart.Position).Magnitude
                    if d < dist then dist = d closest = p end
                end
            end
            if _G.BombConfig.turretAimMode == "Auto-Lock" and closest then
                alignOrient.CFrame = CFrame.lookAt(turretPart.Position, closest.Character.HumanoidRootPart.Position)
            elseif _G.BombConfig.turretAimMode == "Spin+Y-Track" then
                spinAngle = spinAngle + 5
                local yTarget = closest and closest.Character.HumanoidRootPart.Position.Y or turretPart.Position.Y
                local lookPos = turretPart.Position + Vector3.new(math.sin(math.rad(spinAngle)), 0, math.cos(math.rad(spinAngle)))
                alignOrient.CFrame = CFrame.lookAt(turretPart.Position, Vector3.new(lookPos.X, yTarget, lookPos.Z))
            elseif _G.BombConfig.turretAimMode == "Manual FPS" then
                alignOrient.CFrame = CFrame.lookAt(turretPart.Position, turretPart.Position + Camera.CFrame.LookVector)
            end
            task.wait(0.02)
        end
    end)
    
    task.spawn(function()
        while turretPart and turretPart.Parent and _G.BombConfig.modeRobotFlyer do
            local owner = findPlayer(_G.BombConfig.turretOwner)
            local firePos = nil
            if _G.BombConfig.turretAimMode == "Manual FPS" then
                firePos = turretPart.Position + Camera.CFrame.LookVector * 100
            else
                local closest, dist = nil, 200
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= owner and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                        local d = (p.Character.HumanoidRootPart.Position - turretPart.Position).Magnitude
                        if d < dist then dist = d closest = p end
                    end
                end
                if closest then firePos = closest.Character.HumanoidRootPart.Position end
            end
            if firePos then
                local dart = Instance.new("Part")
                dart.Size = Vector3.new(0.4, 0.4, 2)
                dart.Color = Color3.fromRGB(255, 170, 0)
                dart.Position = turretPart.Position
                dart.CanCollide = false
                dart.Parent = workspace
                claimNetworkOwnership(dart)
                local dAtt = Instance.new("Attachment", dart)
                local vel = Instance.new("LinearVelocity", dart)
                vel.Attachment0 = dAtt; vel.MaxForce = math.huge
                vel.VectorVelocity = (firePos - dart.Position).Unit * 180
                dart.Touched:Connect(function(hit)
                    if hit.Parent and hit.Parent:FindFirstChild("Humanoid") and hit.Parent.Name ~= _G.BombConfig.turretOwner then
                        hit.Parent.Humanoid.Health = 0; dart:Destroy()
                    end
                end)
                game:GetService("Debris"):AddItem(dart, 3)
            end
            task.wait(0.5)
        end
    end)
end

if PlayerGui then
    local MainFrame = PlayerGui.DeltaUltimateAdaptiveHubV5:FindFirstChild("MainFrame")
    local Container = MainFrame and MainFrame:FindFirstChild("ScrollingFrame")
    
    if Container then
        local SetSentryBtn = Container:FindFirstChild("📍 SET SENTRY UNDER FEET")
        local ToggleTurretSystemBtn = Container:FindFirstChild("TURRET SYSTEM: OFF")
        
        if SetSentryBtn then
            SetSentryBtn.MouseButton1Click:Connect(function()
                if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
                if #activeTurretsList >= _G.BombConfig.maxTurrets then
                    local oldest = table.remove(activeTurretsList, 1)
                    if oldest then oldest:Destroy() end
                end
                local sentry = Instance.new("Part")
                sentry.Size = Vector3.new(2.5, 2.5, 2.5)
                sentry.Color = Color3.fromRGB(255, 0, 100)
                sentry.Material = Enum.Material.Neon
                sentry.Position = LocalPlayer.Character.HumanoidRootPart.Position + Vector3.new(0, -1, 0)
                sentry.Parent = workspace
                claimNetworkOwnership(sentry)
                table.insert(activeTurretsList, sentry)
                handleTurretCombat(sentry)
            end)
        end

        if ToggleTurretSystemBtn then
            ToggleTurretSystemBtn.MouseButton1Click:Connect(function()
                _G.BombConfig.modeRobotFlyer = not _G.BombConfig.modeRobotFlyer
                ToggleTurretSystemBtn.Text = _G.BombConfig.modeRobotFlyer and "TURRET SYSTEM: ON" or "TURRET SYSTEM: OFF"
                if _G.BombConfig.modeRobotFlyer and _G.BombConfig.turretTypeMode == "Single" then
                    activeTurretBase = Instance.new("Part")
                    activeTurretBase.Size = Vector3.new(3, 1, 3)
                    activeTurretBase.Color = Color3.fromRGB(0, 170, 255)
                    activeTurretBase.Material = Enum.Material.Neon
                    activeTurretBase.CanCollide = false
                    activeTurretBase.Parent = workspace
                    claimNetworkOwnership(activeTurretBase)
                    handleTurretCombat(activeTurretBase)
                    task.spawn(function()
                        while _G.BombConfig.modeRobotFlyer and _G.BombConfig.turretTypeMode == "Single" and activeTurretBase and activeTurretBase.Parent do
                            local owner = findPlayer(_G.BombConfig.turretOwner)
                            if owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart") then
                                activeTurretBase.Position = owner.Character.HumanoidRootPart.Position + Vector3.new(0, 7, 0)
                            end
                            task.wait(0.03)
                        end
                        if activeTurretBase then activeTurretBase:Destroy() end
                    end)
                elseif not _G.BombConfig.modeRobotFlyer then
                    Camera.CameraType = Enum.CameraType.Custom
                    if activeTurretBase then activeTurretBase:Destroy() end
                    for _, t in ipairs(activeTurretsList) do t:Destroy() end
                    table.clear(activeTurretsList)
                end
            end)
        end
    end
end

local function launchLogic(isHoming)
    ActiveBomb = findFuseBomb()
    if not ActiveBomb then return end
    claimNetworkOwnership(ActiveBomb)
    _G.BombConfig.explosionTick = tick() + _G.BombConfig.fuseTime
    _G.BombConfig.isCounting = true
    if isHoming then
        local att = ActiveBomb:FindFirstChild("BombAttachment") or Instance.new("Attachment", ActiveBomb)
        local vel = ActiveBomb:FindFirstChild("BombVelocity") or Instance.new("LinearVelocity", ActiveBomb)
        vel.Attachment0 = att; vel.MaxForce = math.huge; vel.RelativeTo = Enum.ActuatorRelativeTo.World
        task.spawn(function()
            while _G.BombConfig.isCounting and ActiveBomb and ActiveBomb.Parent and _G.BombConfig.selectedTarget and _G.BombConfig.selectedTarget.Character do
                local hrp = _G.BombConfig.selectedTarget.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local nextPoint = hrp.Position + (hrp.AssemblyLinearVelocity * (_G.BombConfig.Prediction / 10))
                    local currentSpeed = _G.BombConfig.forwardVelocity
                    if _G.BombConfig.homingMode == "Noclip Direct" then
                        ActiveBomb.CanCollide = false
                        currentSpeed = _G.BombConfig.maxSpeed
                    else
                        local path = PathfindingService:CreatePath({AgentRadius = 3, AgentHeight = 6, AgentCanJump = true})
                        path:ComputeAsync(ActiveBomb.Position, nextPoint)
                        if path.Status == Enum.PathStatus.Success then
                            local w = path:GetWaypoints()
                            if #w > 1 then nextPoint = w[2].Position currentSpeed = _G.BombConfig.maxSpeed end
                        end
                    end
                    vel.VectorVelocity = (nextPoint - ActiveBomb.Position).Unit * currentSpeed
                end
                task.wait(0.02)
            end
            if _G.BombConfig.selectedTarget and _G.BombConfig.selectedTarget.Character and ActiveBomb and ActiveBomb.Parent do
                local targetHrp = _G.BombConfig.selectedTarget.Character:FindFirstChild("HumanoidRootPart")
                if targetHrp then
                    ActiveBomb.CFrame = targetHrp.CFrame
                    ActiveBomb.AssemblyLinearVelocity = Vector3.new(0, 600, 0)
                    for i = 1, 15 do
                        if ActiveBomb and targetHrp then
                            ActiveBomb.Position = targetHrp.Position
                            targetHrp.AssemblyLinearVelocity = Vector3.new(0, -1000, 0)
                        end
                        task.wait()
                    end
                end
            end
            if vel then vel:Destroy() end
        end)
    end
end

if PlayerGui then
    local MainFrame = PlayerGui.DeltaUltimateAdaptiveHubV5:FindFirstChild("MainFrame")
    local Container = MainFrame and MainFrame:FindFirstChild("ScrollingFrame")
    if Container then
        local LaunchButton = Container:FindFirstChild("LAUNCH STANDARD")
        local LaunchHomingButton = Container:FindFirstChild("⚡ LAUNCH HOMING (FE) ⚡")
        if LaunchButton then LaunchButton.MouseButton1Click:Connect(function() launchLogic(false) end) end
        if LaunchHomingButton then LaunchHomingButton.MouseButton1Click:Connect(function() launchLogic(true) end) end
    end
end
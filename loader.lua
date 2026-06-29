local Players = game:GetService("Players") 
local UIS = game:GetService("UserInputService") 
local RunService = game:GetService("RunService")  
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer 
local playerGui = player:WaitForChild("PlayerGui")  

getgenv().FlyHUDSettings = getgenv().FlyHUDSettings or { 
	speedLevel = 1, 
	posX = 20, 
	posY = 20, 
} 
 
local Save = getgenv().FlyHUDSettings  

local function savePositionFromFrame(frame) 
	Save.posX = frame.Position.X.Offset 
	Save.posY = frame.Position.Y.Offset 
end  

local function saveSpeed(value) 
	Save.speedLevel = value 
end  

local oldGui = playerGui:FindFirstChild("FlyHUD") 
if oldGui then 
	oldGui:Destroy() 
end  

local gui = Instance.new("ScreenGui") 
gui.Name = "FlyHUD" 
gui.ResetOnSpawn = false 
gui.Parent = playerGui  

local frame = Instance.new("Frame") 
frame.Size = UDim2.new(0, 125, 0, 12) 
frame.Position = UDim2.new(0, Save.posX, 0, Save.posY) 
frame.BackgroundColor3 = Color3.fromRGB(10, 10, 10) 
frame.BorderSizePixel = 0 
frame.Active = true 
frame.Parent = gui 

Instance.new("UICorner", frame)  

local speedLevel = math.clamp(tonumber(Save.speedLevel) or 1, 0.1, 50) 
local baseSpeed = 60 
local minSpeed = 0.1 
local maxSpeed = 9999 
local flyEnabled = false 
local autoForward = false 
local rotation = 0  

local isAntiAFKActive = false
local antiAFKConnection = nil
local halfTurnConnection = nil
local lastHalfTurnTime = 0

local spaceHeld = false
local spaceReleaseTimer = nil

local bv, bg 
local renderConn, charAddedConn 
local dragging = false 
local dragInput = nil 
local dragStart = Vector2.zero 
local startPos = UDim2.new() 
local editingSpeed = false  

local function formatSpeedText(v) 
	local s = string.format("%.2f", v) 
	s = s:gsub("%.?0+$", "") 
	return s .. "x" 
end  

local function setButtonState(button, enabled) 
	button.BackgroundColor3 = enabled and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 60, 60) 
end  

local function setSpeed(v)
	speedLevel = math.clamp(v, minSpeed, maxSpeed)
	saveSpeed(speedLevel)

	if speedDisplay then
		speedDisplay.Text = formatSpeedText(speedLevel)
	end
end  

local function holdSpace()
	if spaceHeld then return end
	spaceHeld = true
	VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
	print("Espace enfoncé (monte)")
end

local function releaseSpace()
	if not spaceHeld then return end
	spaceHeld = false
	VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
	print("Espace relâché (arrête de monter)")
end

local function holdSpaceForFifteenSeconds()
	releaseSpace()
	if spaceReleaseTimer then
		task.cancel(spaceReleaseTimer)
		spaceReleaseTimer = nil
	end
	holdSpace()
	spaceReleaseTimer = task.delay(15, function()
		releaseSpace()
		spaceReleaseTimer = nil
		print("15 secondes écoulées, Espace relâché")
	end)
end

local function stopHoldingSpace()
	if spaceReleaseTimer then
		task.cancel(spaceReleaseTimer)
		spaceReleaseTimer = nil
	end
	releaseSpace()
end

local function startContinuousAntiAFK()
	if antiAFKConnection then
		antiAFKConnection:Disconnect()
	end
	
	isAntiAFKActive = true
	
	antiAFKConnection = RunService.RenderStepped:Connect(function()
		if not isAntiAFKActive then return end
		
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Z, false, game)
		task.wait(0.1)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Z, false, game)
		task.wait(0.1)
		
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
		task.wait(0.1)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
		task.wait(0.1)
		
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.S, false, game)
		task.wait(0.1)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.S, false, game)
		task.wait(0.1)
		
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.D, false, game)
		task.wait(0.1)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.D, false, game)
		task.wait(0.1)
	end)
end

local function stopAntiAFK()
	isAntiAFKActive = false
	if antiAFKConnection then
		antiAFKConnection:Disconnect()
		antiAFKConnection = nil
	end
end

local function startHalfTurnTimer()
	if halfTurnConnection then
		halfTurnConnection:Disconnect()
	end
	
	lastHalfTurnTime = tick()
	
	halfTurnConnection = RunService.RenderStepped:Connect(function()
		if not autoForward then return end
		
		local currentTime = tick()
		if currentTime - lastHalfTurnTime >= 3600 then
			rotation = (rotation + 180) % 360
			lastHalfTurnTime = currentTime
		end
	end)
end

local function stopHalfTurnTimer()
	if halfTurnConnection then
		halfTurnConnection:Disconnect()
		halfTurnConnection = nil
	end
end

-- BOUTON FLY - Utilisation d'un séparateur invisible pour casser la détection
local fly = Instance.new("TextButton") 
fly.Size = UDim2.new(0, 24, 0, 9) 
fly.Position = UDim2.new(0, 3, 0.5, -4.)
fly.Text = "F﻿L﻿Y"  -- Caractère de contrôle U+FEFF (BOM) invisible
fly.Font = Enum.Font.GothamBold 
fly.TextSize = 9 
fly.TextColor3 = Color3.fromRGB(0, 0, 0) 
fly.BackgroundColor3 = Color3.fromRGB(255, 60, 60) 
fly.BorderSizePixel = 999 
fly.TextYAlignment = Enum.TextYAlignment.Center
fly.Parent = frame 
Instance.new("UICorner", fly)  

local autoZ = Instance.new("TextButton") 
autoZ.Size = UDim2.new(0, 28, 0, 9) 
autoZ.Position = UDim2.new(0, 30, 0.5, -4.5)
autoZ.Text = "" 
autoZ.Font = Enum.Font.GothamBold 
autoZ.TextSize = 9 
autoZ.TextColor3 = Color3.fromRGB(0, 0, 0) 
autoZ.BackgroundColor3 = Color3.fromRGB(255, 60, 60) 
autoZ.BorderSizePixel = 0 
autoZ.Parent = frame 
Instance.new("UICorner", autoZ)  

local autoText = Instance.new("TextLabel")
autoText.Size = UDim2.new(1, 0, 1, 0)
autoText.Position = UDim2.new(0, 0, 0, -1.000)
autoText.BackgroundTransparency = 1
autoText.Text = "AUTO"
autoText.Font = Enum.Font.GothamBold
autoText.TextSize = 8
autoText.TextColor3 = Color3.fromRGB(0, 0, 0)
autoText.TextYAlignment = Enum.TextYAlignment.Center
autoText.Parent = autoZ

local minus = Instance.new("TextButton") 
minus.Size = UDim2.new(0, 10, 0, 10) 
minus.Position = UDim2.new(0, 62, 0.5, -6)
minus.Text = "-" 
minus.Font = Enum.Font.GothamBold 
minus.TextSize = 15 
minus.TextColor3 = Color3.fromRGB(255, 255, 255) 
minus.BackgroundColor3 = Color3.fromRGB(0, 0, 0) 
minus.BorderSizePixel = 0 
minus.TextYAlignment = Enum.TextYAlignment.Center
minus.Parent = frame 
Instance.new("UICorner", minus)  

local speedDisplay = Instance.new("TextButton") 
speedDisplay.Size = UDim2.new(0, 30, 0, 10) 
speedDisplay.Position = UDim2.new(0, 90, 0.5, -7)
speedDisplay.Text = formatSpeedText(speedLevel) 
speedDisplay.Font = Enum.Font.GothamBold 
speedDisplay.TextSize = 10 
speedDisplay.TextColor3 = Color3.fromRGB(255, 255, 255) 
speedDisplay.BackgroundTransparency = 1 
speedDisplay.BorderSizePixel = 0 
speedDisplay.AutoButtonColor = true 
speedDisplay.TextYAlignment = Enum.TextYAlignment.Top
speedDisplay.Parent = frame  

speedDisplay.Position = UDim2.new(0, 72, 0.4, -4.900)

local speedInput = Instance.new("TextBox") 
speedInput.Size = UDim2.new(0, 30, 0, 10) 
speedInput.Position = UDim2.new(0, 72, 0.5, -5)
speedInput.Text = "" 
speedInput.PlaceholderText = "2.5" 
speedInput.Font = Enum.Font.GothamBold 
speedInput.TextSize = 10 
speedInput.TextColor3 = Color3.fromRGB(255, 255, 255)
speedInput.BackgroundColor3 = Color3.fromRGB(35, 35, 35) 
speedInput.BackgroundTransparency = 0.1 
speedInput.BorderSizePixel = 0 
speedInput.Visible = false 
speedInput.ClearTextOnFocus = false 
speedInput.TextXAlignment = Enum.TextXAlignment.Center 
speedInput.Parent = frame  

Instance.new("UICorner", speedInput)  

local plus = Instance.new("TextButton") 
plus.Size = UDim2.new(0, 10, 0, 10) 
plus.Position = UDim2.new(0, 102, 0.5, -5)
plus.Text = "+" 
plus.Font = Enum.Font.GothamBold 
plus.TextSize = 12 
plus.TextColor3 = Color3.fromRGB(255, 255, 255) 
plus.BackgroundColor3 = Color3.fromRGB(0, 0, 0) 
plus.BorderSizePixel = 0 
plus.TextYAlignment = Enum.TextYAlignment.Center
plus.Parent = frame 
Instance.new("UICorner", plus)  

local close = Instance.new("TextButton") 
close.Size = UDim2.new(0, 12, 0, 10) 
close.Position = UDim2.new(1, -13, 0.5, -6.000)
close.Text = "X" 
close.Font = Enum.Font.GothamBold 
close.TextSize = 9 
close.TextColor3 = Color3.fromRGB(255, 255, 255) 
close.BackgroundColor3 = Color3.fromRGB(0, 0, 0) 
close.BorderSizePixel = 0 
close.TextYAlignment = Enum.TextYAlignment.Center
close.Parent = frame 
Instance.new("UICorner", close)  

frame.InputBegan:Connect(function(input) 
	if editingSpeed then return end 
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
		dragging = true 
		dragInput = input 
		dragStart = input.Position 
		startPos = frame.Position  

		input.Changed:Connect(function() 
			if input.UserInputState == Enum.UserInputState.End then 
				dragging = false 
				dragInput = nil 
				savePositionFromFrame(frame) 
			end 
		end) 
	end 
end)  

UIS.InputChanged:Connect(function(input) 
	if not dragging or input ~= dragInput then return end 
	local delta = input.Position - dragStart 
	frame.Position = UDim2.new( 
		startPos.X.Scale, startPos.X.Offset + delta.X, 
		startPos.Y.Scale, startPos.Y.Offset + delta.Y 
	) 
end)  

local function getHRP() 
	local char = player.Character 
	if not char then return nil end 
	return char:FindFirstChild("HumanoidRootPart") 
end  

local function stopFly() 
	if bv then bv:Destroy(); bv = nil end 
	if bg then bg:Destroy(); bg = nil end 
end  

local function startFly() 
	local hrp = getHRP() 
	if not hrp then return end 
	stopFly()  

	bv = Instance.new("BodyVelocity") 
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5) 
	bv.Velocity = Vector3.zero 
	bv.Parent = hrp  

	bg = Instance.new("BodyGyro") 
	bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5) 
	bg.P = 9000 
	bg.CFrame = hrp.CFrame 
	bg.Parent = hrp 
end  

renderConn = RunService.RenderStepped:Connect(function(dt) 
	if not flyEnabled then return end 
	local hrp = getHRP() 
	if not hrp then return end  

	if UIS:IsKeyDown(Enum.KeyCode.Left) then rotation += 120 * dt end 
	if UIS:IsKeyDown(Enum.KeyCode.Right) then rotation -= 120 * dt end 
	rotation = rotation % 360  

	local rotCF = CFrame.Angles(0, math.rad(rotation), 0) 
	local move = Vector3.zero  

	if UIS:IsKeyDown(Enum.KeyCode.Up) or autoForward then 
		move += Vector3.new(0, 0, -1) 
	end 
	if UIS:IsKeyDown(Enum.KeyCode.Down) then 
		move += Vector3.new(0, 0, 1) 
	end 
	if UIS:IsKeyDown(Enum.KeyCode.Space) or spaceHeld then
		move += Vector3.new(0, 1, 0) 
	end 
	if UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift) then 
		move += Vector3.new(0, -1, 0) 
	end  

	local speed = baseSpeed * speedLevel 
	if bv then 
		bv.Velocity = (move.Magnitude > 0) and (rotCF:VectorToWorldSpace(move.Unit) * speed) or Vector3.zero 
	end 
	if bg then 
		bg.CFrame = CFrame.new(hrp.Position) * rotCF 
	end 
end)  

charAddedConn = player.CharacterAdded:Connect(function() 
	task.wait(0.2) 
	if flyEnabled then startFly() end 
end)  

local function openSpeedInput() 
	editingSpeed = true 
	dragging = false 
	speedInput.Visible = true 
	speedDisplay.Visible = false 
	speedInput.Text = tostring(speedLevel) 
	speedInput:CaptureFocus() 
	speedInput.CursorPosition = #speedInput.Text + 1 
end  

local function closeSpeedInput(applyValue) 
	if applyValue then 
		local raw = speedInput.Text:gsub(",", "."):gsub("[xX]", "") 
		local value = tonumber(raw) 
		if value then setSpeed(value) end 
	end 
	speedInput.Visible = false 
	speedDisplay.Visible = true 
	speedDisplay.Text = formatSpeedText(speedLevel) 
	editingSpeed = false 
end  

speedDisplay.MouseButton1Click:Connect(openSpeedInput) 
speedInput.FocusLost:Connect(function() closeSpeedInput(true) end)  

fly.MouseButton1Click:Connect(function() 
	flyEnabled = not flyEnabled 
	setButtonState(fly, flyEnabled) 
	if flyEnabled then 
		startFly() 
	else 
		stopFly() 
	end 
end)  

autoZ.MouseButton1Click:Connect(function() 
	autoForward = not autoForward 
	setButtonState(autoZ, autoForward) 
	
	if autoForward then
		startContinuousAntiAFK()
		startHalfTurnTimer()
		holdSpaceForFifteenSeconds()
	else
		stopAntiAFK()
		stopHalfTurnTimer()
		stopHoldingSpace()
	end
end)  

plus.MouseButton1Click:Connect(function() 
	setSpeed(speedLevel + 0.5) 
end) 

minus.MouseButton1Click:Connect(function() 
	setSpeed(speedLevel - 0.5) 
end)  

close.MouseButton1Click:Connect(function() 
	flyEnabled = false 
	autoForward = false 
	stopFly() 
	stopAntiAFK()
	stopHalfTurnTimer()
	stopHoldingSpace()
	savePositionFromFrame(frame) 
	saveSpeed(speedLevel)  

	if renderConn then renderConn:Disconnect(); renderConn = nil end 
	if charAddedConn then charAddedConn:Disconnect(); charAddedConn = nil end 
	gui:Destroy() 
end)  

setButtonState(fly, false) 
setButtonState(autoZ, false)

if getgenv().KeepAmount == nil then
	getgenv().KeepAmount = 99
end
if getgenv().ResetCharacter == nil then
	getgenv().ResetCharacter = true
end
if getgenv().TargetLocation == nil then
	getgenv().TargetLocation = Vector3.new(-572.6912841796875, 279.4130554199219, -1449.682373046875)
end
if getgenv().JobId == nil or #getgenv().JobId <= 5 then
	getgenv().JobId = game.JobId
end
if getgenv().PreventMultipleRuns == nil then
	getgenv().PreventMultipleRuns = false
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end

if getgenv().PreventMultipleRuns then
	if getgenv().Running then
		error("Already running")
	else
		getgenv().Running = true
		task.wait(3)
	end
else
	getgenv().Running = false
	task.wait(0.5)
	getgenv().Running = true
end

function filter<T>(arr: { T }, func: (T) -> boolean): { T }
	local new_arr = {}
	for _, v in pairs(arr) do
		if func(v) then
			table.insert(new_arr, v)
		end
	end
	return new_arr
end

function map<T, U>(arr: { T }, func: (T) -> U): { U }
	local new_arr = {}
	for i, v in pairs(arr) do
		new_arr[i] = func(v)
	end
	return new_arr
end

--- Constants ---
local Players = game:GetService("Players")
local VIM = Instance.new("VirtualInputManager")
local TS = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")
local TeleportService = game:GetService("TeleportService")

local Player = Players.LocalPlayer

if game.JobId ~= getgenv().JobId then
	while task.wait(5) do
		TeleportService:TeleportToPlaceInstance(game.PlaceId, getgenv().JobId, Player)
	end
end

local Gui = Player.PlayerGui :: PlayerGui
local Map = workspace:WaitForChild("Map") :: Folder
local Props = Map:WaitForChild("Props") :: Folder
local ATMFolder = Props:WaitForChild("ATMs") :: Folder

local ATMs = ATMFolder:GetChildren() :: { Model }
assert(#ATMs > 0, "ATMs not found (they probably changed where ATMs are)")
local function findNewATMs()
	local newATMs = ATMFolder:GetChildren() :: { Model }
	for _, new in pairs(newATMs) do
		local already = false
		for _, old in pairs(ATMs) do
			if new == old then
				already = true
				break
			end
		end
		if not already then
			table.insert(ATMs, new)
		end
	end
end

if Player.DisplayName == getgenv().TargetPlayer then
	return
end

local RespawnButton = Gui.DeathScreen.DeathScreenHolder.Frame.RespawnButtonFrame.RespawnButton :: TextButton

local Tutorial = Gui:WaitForChild("Slideshow"):WaitForChild("SlideshowHolder")
local TutorialCloseButton = Tutorial:WaitForChild("SlideshowCloseButton")

local Inventory = Gui.Items.ItemsHolder.ItemsScrollingFrame :: Frame

local EquipItemButton = Gui.ItemInfoGui.ItemInfoHolder.PromptButtons.EquipItemButton :: TextButton
local DropItemButton = Gui.ItemInfoGui.ItemInfoHolder.PromptButtons.DropItemButton :: TextButton
local RepairItemButton = Gui.ItemInfoGui.ItemInfoHolder.PromptButtons.RepairItemButton :: TextButton

local InteractionFolder = Gui.ProximityPrompts :: Folder

local NotificationFolder = Gui.Notifications.Frame :: Frame

local ATMActionPageOptions = Gui:FindFirstChild("ATMActionAmount", true).Parent
local ATMGui = ATMActionPageOptions.Parent.Parent
local ATMWithdrawButton = ATMGui:FindFirstChild("ATMWithdrawButton", true) :: TextButton
local ATMMainPageOptions = ATMWithdrawButton.Parent

local ATMAmount = ATMActionPageOptions:FindFirstChild("Frame"):FindFirstChildOfClass("TextBox") :: TextBox

local ATMConfirmButton
for _, v in pairs(ATMActionPageOptions:GetChildren()) do
	if v:IsA("TextButton") and v.ZIndex == 1 then
		ATMConfirmButton = v
	end
end

local WalkSpeed = 18
local RunSpeed = 34
local VehicleSpeeds = {
	["BMX"] = 58,
	["BMX2"] = 58,
	["EScooter"] = 58,
}

--- Functions ---
local function notify(text: string, duration: number?)
	print(text)
	game:GetService("StarterGui"):SetCore("SendNotification", {
		Title = "AutoDrop",
		Text = text,
		Duration = duration or 3,
	})
end

local function rejoin()
	while task.wait(5) do
		TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, Player)
	end
end

local function keypress(key: Enum.KeyCode, holdTime: number?)
	VIM:SendKeyEvent(true, key, false, game)
	task.wait(holdTime)
	VIM:SendKeyEvent(false, key, false, game)
	task.wait()
end

local function clickOnUi(element: GuiButton)
    task.spawn(function()
        setthreadidentity(2)
        -- Try firing Activated event (works for both PC and mobile)
        if element:IsA("GuiButton") and element.Activated then
            firesignal(element.Activated)
        end
        -- Fallback to MouseButton1Click for PC compatibility
        if element:IsA("TextButton") or element:IsA("ImageButton") then
            firesignal(element.MouseButton1Click, 0, 0)
        end
    end)
    task.wait(0.1) -- Small delay to allow event processing
end

local function isCombatLogging()
	return Gui.Hotbar.HotbarHolder.List.HotbarCombatLogging.Visible
end

local function Character()
	return Player.Character or Player.CharacterAdded:Wait()
end

local function Humanoid()
	return Character():WaitForChild("Humanoid") :: Humanoid
end

local function HRP()
	return Character():WaitForChild("HumanoidRootPart") :: Part
end

local function closest(parts: { BasePart | Model }): BasePart
	local closest = nil
	local closest_distance = math.huge
	for _, part in pairs(parts) do
		local position = part:IsA("BasePart") and part.Position or part:GetPivot().Position
		local distance = (position - HRP().Position).magnitude
		if distance < closest_distance then
			closest = part
			closest_distance = distance
		end
	end
	return closest
end

local function isAtmWorking(atm: Model)
	local screen = atm:FindFirstChild("Screen", true) :: ScreenGui
	return screen and not screen.Enabled
end

local function withdraw(amount: number?)
	clickOnUi(ATMWithdrawButton)
	ATMAmount.Text = amount or 999999999
	clickOnUi(ATMConfirmButton)
end

local function notificationDetected(): boolean
	local detections = { "Teleport detected", "Fly detected", "Anti noclip triggered" }
	for _, notification in pairs(NotificationFolder:GetChildren()) do
		if
			notification:IsA("TextLabel")
			and notification.Name == "Notification"
			and table.find(detections, notification.Text)
		then
			notification.Name = "Notification_" -- Rename it so it's not detected again.
			return true
		end
	end
	return false
end

local function groundPos(pos: Vector3, ignoreList: Instance | { Instance }): Vector3?
	return pos -- Fallback
end

local vehicle = nil
local function getVehicle()
	local vehiclesFolder = workspace:FindFirstChild("Vehicles") :: Folder
	local spawnedVehicles = vehiclesFolder:GetChildren() :: { Model }
	for _, v in pairs(spawnedVehicles) do
		if v:FindFirstChildOfClass("ObjectValue").Value == Humanoid() then
			return v
		end
	end
	return nil
end

local function spawnVehicle()
	if vehicle then
		return
	end
	if getVehicle() then
		vehicle = getVehicle()
		return
	end
	notify("Trying to spawn vehicle")
	local vehicleItems = filter(Inventory:GetChildren(), function(v)
		if not v:IsA("ImageButton") then
			return false
		end
		local itemNameLabel = v:FindFirstChild("ItemName") :: TextLabel?
		if not itemNameLabel then
			return false
		end
		local name = itemNameLabel.Text
		return VehicleSpeeds[name] ~= nil
	end)
	if #vehicleItems == 0 then
		notify("No vehicles found in inventory")
		return
	end
	local vehicleItem = vehicleItems[1]
	notify("Spawning " .. vehicleItem.ItemName.Text)
	clickOnUi(vehicleItem)
	clickOnUi(EquipItemButton)
	task.wait(1)
	vehicle = getVehicle()
	if vehicle then
		return
	end
	keypress(Enum.KeyCode.E, 2)
	vehicle = getVehicle()
	if vehicle then
		return
	end
	notify("Couldn't find vehicle after spawning.")
	error("Couldn't find vehicle after spawning.")
end

local function leaveVehicle()
	if not getVehicle() then
		return
	end
	notify("Leaving vehicle")
	keypress(Enum.KeyCode.E, 1)
end

local function enterVehicle()
	if not vehicle or getVehicle() then
		return
	end
	notify("Entering vehicle")
	vehicle:PivotTo(Character():GetPivot())
	keypress(Enum.KeyCode.E, 1)
	if not getVehicle() then
		notify("Couldn't find vehicle after entering.")
	end
end

local function moveTo(target: BasePart | Model | Vector3 | CFrame, epsilon: number?, checkATM: boolean?)
	enterVehicle()
	local usingVehicle = vehicle and true or false
	local waypointSpacing = usingVehicle and 3 or 3
	local speed = usingVehicle and VehicleSpeeds[vehicle.Name] or RunSpeed
	local timePerWaypoint = waypointSpacing / speed
	local yOffset = 4
	for _, part in pairs(workspace:GetChildren()) do
		if part:IsA("Part") and (part.Name == "Waypoint") then
			part:Destroy()
		end
	end
	epsilon = epsilon == nil and 7 or epsilon
	local position
	local temp = {}
	local targetModel = nil
	if typeof(target) == "Vector3" then
		position = target
	elseif typeof(target) == "CFrame" then
		position = target.Position
	else
		position = target:IsA("BasePart") and target.Position or target:GetPivot().Position
		targetModel = target
		for _, v in pairs((target :: BasePart | Model):GetChildren()) do
			if v:IsA("BasePart") and v.CanCollide then
				table.insert(temp, v)
				v.CanCollide = false
			end
		end
		if usingVehicle then
			for _, v in pairs(vehicle:GetDescendants()) do
				if v:IsA("BasePart") and v.CanCollide then
					table.insert(temp, v)
					v.CanCollide = false
				end
			end
		end
	end
	local path = PathfindingService:CreatePath({
		AgentCanJump = false,
		AgentCanClimb = true,
		WaypointSpacing = waypointSpacing,
	})
	local success, errorMessage = pcall(function()
		path:ComputeAsync(HRP().Position, position)
	end)
	for _, v in pairs(temp) do
		v.CanCollide = true
	end
	if success and path.Status == Enum.PathStatus.Success then
		for _, waypoint in ipairs(path:GetWaypoints()) do
			local p = Instance.new("Part", workspace)
			p.Position = waypoint.Position
			p.Name = "Waypoint"
			p.Anchored = true
			p.CanCollide = false
			p.Color = Color3.new(1, 0, 0)
			p.Size = Vector3.new(0.2, 0.2, 0.2)
		end
		local function gotoWaypoint(waypoint: PathWaypoint)
			if not getgenv().Running then
				error("Aborted")
			end
			if (position - HRP().Position).magnitude <= epsilon then
				return 2 -- Reached
			end
			if checkATM and targetModel and not isAtmWorking(targetModel) then
				notify("ATM stopped working, finding another one")
				return 1 -- Failed
			end
			if usingVehicle then
				local cframe = CFrame.lookAt(
					vehicle:GetPivot().Position,
					waypoint.Position * Vector3.new(1, 0, 1) + vehicle:GetPivot().Position * Vector3.new(0, 1, 0)
				)
				cframe = cframe - cframe.Position
				cframe = cframe + groundPos(waypoint.Position, { Character(), vehicle })
				cframe = cframe + Vector3.new(0, yOffset, 0)
				vehicle:PivotTo(cframe)
				task.wait(timePerWaypoint)
			else
				VIM:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
				local cframe = CFrame.lookAt(
					Character():GetPivot().Position,
					waypoint.Position * Vector3.new(1, 0, 1) + Character():GetPivot().Position * Vector3.new(0, 1, 0)
				)
				cframe = cframe - cframe.Position
				cframe = cframe + groundPos(waypoint.Position, { Character() })
				cframe = cframe + Vector3.new(0, yOffset, 0)
				Character():MoveTo(cframe.Position)
				task.wait(timePerWaypoint)
			end
			return 0 -- Continue
		end
		local waypoints = path:GetWaypoints()
		local i = 1
		while true do
			if i > #waypoints then
				return true -- Reached
			end
			if notificationDetected() then
				task.wait(1)
				return moveTo(target, epsilon, checkATM)
			end
			local waypoint = waypoints[i]
			local result = gotoWaypoint(waypoint)
			if result == 1 then
				return false -- Failed
			end
			if result == 2 then
				return true -- Reached
			end
			i += 1
		end
		if not usingVehicle then
			VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
		end
		return true -- Reached
	else
		notify("Path not computed " .. (errorMessage or "") .. tostring(path.Status))
		rejoin()
		error("Path not computed " .. (errorMessage or "") .. tostring(path.Status))
	end
end

local function bank()
	for _, v in pairs(ATMMainPageOptions:GetChildren()) do
		if v:IsA("TextLabel") and v.Text:find("Bank") then
			local bank = tonumber(v.Text:sub(16))
			if not bank then
				error("Couldn't get bank balance " .. v.Text)
			end
			return bank
		end
	end
	error("Couldn't get bank balance")
end

local function resetCharacter()
	keypress(Enum.KeyCode.Escape)
	task.wait(0.1)
	keypress(Enum.KeyCode.R)
	task.wait(0.1)
	keypress(Enum.KeyCode.Return)
	task.wait(1)
	rejoin()
end

--- Setup ---
local function waitForGuiElement(path: string, timeout: number?): Instance?
    timeout = timeout or 10
    local start = tick()
    while tick() - start < timeout do
        local element = Gui:FindFirstChild(path, true)
        if element then
            return element
        end
        task.wait(0.1)
    end
    return nil
end

print("Waiting for loading screen to disappear")
while waitForGuiElement("LoadingScreen", 30) do
    task.wait(0.1)
end
print("Loading screen gone")

local splashScreen = waitForGuiElement("SplashScreenGui", 10)
if splashScreen and splashScreen:IsA("ScreenGui") and splashScreen.Enabled then
    print("Entering game")
    local playButton = splashScreen:FindFirstChild("Frame"):FindFirstChild("PlayButton")
    if playButton and playButton:IsA("GuiButton") then
        for _ = 1, 3 do
            clickOnUi(playButton)
            task.wait(2)
            if not waitForGuiElement("SplashScreenGui", 2) then
                break
            end
        end
    else
        print("PlayButton not found")
    end
end

if Gui.CharacterCreator and Gui.CharacterCreator:IsA("ScreenGui") and Gui.CharacterCreator.Enabled then
    print("Skipping character creator")
    local skipButton = waitForGuiElement("AvatarMenuSkipButton", 5)
    if skipButton and skipButton:IsA("GuiButton") then
        for _ = 1, 3 do
            clickOnUi(skipButton)
            task.wait(2)
            if not Gui.CharacterCreator.Enabled then
                break
            end
        end
    else
        print("AvatarMenuSkipButton not found")
    end
end

if Tutorial and Tutorial:IsA("GuiObject") and Tutorial.Visible then
    print("Skipping tutorial")
    local closeButton = Tutorial:FindFirstChild("SlideshowCloseButton")
    if closeButton and closeButton:IsA("GuiButton") then
        for _ = 1, 3 do
            clickOnUi(closeButton)
            task.wait(2)
            if not Tutorial.Visible then
                break
            end
        end
    else
        print("SlideshowCloseButton not found")
    end
end

task.spawn(function()
    while task.wait(1) do
        local splash = waitForGuiElement("SplashScreenGui", 2)
        if splash and splash:IsA("ScreenGui") and splash.Enabled then
            print("Re-entering game")
            local playButton = splash:FindFirstChild("Frame"):FindFirstChild("PlayButton")
            if playButton and playButton:IsA("GuiButton") then
                clickOnUi(playButton)
            end
        end
        if Gui.CharacterCreator and Gui.CharacterCreator:IsA("ScreenGui") and Gui.CharacterCreator.Enabled then
            print("Re-skipping character creator")
            local skipButton = waitForGuiElement("AvatarMenuSkipButton", 2)
            if skipButton and skipButton:IsA("GuiButton") then
                clickOnUi(skipButton)
            end
        end
        if Tutorial and Tutorial:IsA("GuiObject") and Tutorial.Visible then
            print("Re-skipping tutorial")
            local closeButton = Tutorial:FindFirstChild("SlideshowCloseButton")
            if closeButton and closeButton:IsA("GuiButton") then
                clickOnUi(closeButton)
            end
        end
    end
end)

--- Main Loop ---
print("Disabling door collision")
for _, v in pairs(workspace:GetDescendants()) do
	if v:IsA("Model") and v.Name == "DoorSystem" then
		for _, v in pairs(v:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CanCollide = false
			end
		end
	end
end

spawnVehicle()

if bank() > getgenv().KeepAmount then
	notify("Moving to ATM")
	while task.wait(0.1) do
		findNewATMs()
		local workingATMs = filter(ATMs, isAtmWorking)
		local atm = closest(workingATMs)
		notify(
			tostring(#ATMs)
				.. " ATMs, "
				.. tostring(#workingATMs)
				.. " working ATMs, "
				.. tostring(atm)
				.. "closest working ATM"
		)
		if not atm or not isAtmWorking(atm) then
			notify("ATM is nil or not working")
			continue
		end
		local moved = moveTo(atm, nil, true)
		if moved and isAtmWorking(atm) then
			notify("Moved to ATM")
			break
		end
	end
	notify("Withdrawing 1")
	withdraw(bank() - getgenv().KeepAmount)
	task.wait(0.1)
	notify("Withdrawing 2")
	withdraw(bank() - getgenv().KeepAmount)
	task.wait(0.1)
	notify("Withdrawing 3")
	withdraw(bank() - getgenv().KeepAmount)
	task.wait(0.1)
end
notify("Moving to target location")
moveTo(getgenv().TargetLocation, 10)
leaveVehicle()
vehicle = nil
moveTo(getgenv().TargetLocation, 2)

while not isCombatLogging() do
	task.wait()
end

if getgenv().ResetCharacter then
	resetCharacter()
else
	while not Gui.DeathScreen.DeathScreenHolder.Visible do
		task.wait()
	end
	task.wait(1)
	rejoin()
end

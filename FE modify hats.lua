print(game:GetService("Players").LocalPlayer.Character:WaitForChild("New Tonk"))

folder = Instance.new("Folder",workspace)

local vispet = game:GetService("Players").LocalPlayer.Character:WaitForChild("New Tonk").Handle

local pet = Instance.new("Part",folder)
pet.Name = "pet"
pet.Size = Vector3.new(1,1,1)
pet.Transparency = 1
pet.Position = game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position
pet.Anchored = true
pet.CanCollide = false

vispet.AccessoryWeld:Destroy()

local replicate = Instance.new("RopeConstraint",game:GetService("Players").LocalPlayer.Character.Torso)
replicate.Attachment0 = Instance.new("Attachment",game:GetService("Players").LocalPlayer.Character.Torso)
replicate.Attachment1 = Instance.new("Attachment",vispet)
replicate.Length = math.huge

coroutine.wrap(function()
	while task.wait() do
		vispet.CFrame = pet.CFrame
	end
end)()

--coroutine.wrap(function()
	while wait(0.1) do
		pet.CFrame = game:GetService("Players").willywonkylonky.Character.Head.CFrame * CFrame.new(0, 1, 0)
	end
--end)()
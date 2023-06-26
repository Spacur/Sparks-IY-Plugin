--[[
- Player handler - For targetting several users/looping interactions
- Handles targets for scripts
- Connects to characteradded/ondied remote events to figure which targets are alive or dead. (Default job start/stop behaviour)
- Automatically update targets if necessary
- Handles setting exceptions
- Accepts functions (the jobs) which will be partaken on the target player
- Will queue up jobs as necessary based on events to figure out if particular target user is available or not
- Executes the jobs on a new thread via the job handler
--]]

local function getTableSize(t)
    local count = 0
    for _, __ in pairs(t) do
        count = count + 1
    end
    return count
end

local PlayerHandler = {
    init = false,
    first_init = true,
    player_added_events = {  },
    -- player_deleted_events = {  },
    player_custom_events = {  },
    child_deleted_event = nil,
    team_player_added_events = {   },
    team_player_removed_events = {   },
    global_player_added_event = nil,
    global_player_removed_event = nil,
    ignoreforcefield = false, -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
    ignorefriends = true, -- Set to true if you want the command to ignore friends
    ignoreself = true, -- Set to true if you want the command to ignore yourself
    looping = false, -- Set to true if you want the command to re-add target back to queue when they are alive again
    requeue_after_job = false, -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
    teams = game:GetService("Teams"),
    players = game:GetService("Players"),
    userinputservice = game:GetService("UserInputService"),
    userinputservice_event = nil,
    allteams = nil,
    already_refreshing = false,

    jobs_queue = { },
    jobs_count = function(self)
       return getTableSize(self.jobs_queue)
    end,
    jobs_executed = 0,
    job_thread = nil,
    job_running = false,
    executejob = function(self)
       pcall(function () self:targetaction(self.jobs_queue[1]) end) -- The job itself is synchronous here so will not action another job till completed
       if self:jobs_count() <= 1 then pcall(function () self:targetaction_stop(self.jobs_queue[1]) end) end
       if self.requeue_after_job and self.looping then table.insert(self.jobs_queue, self.jobs_queue[1]) end
       table.remove(self.jobs_queue, 1)
       self.job_running = false
       self.jobs_executed = self.jobs_executed + 1
       if self:jobs_count() == 0 and self.looping then -- Pause and wait for new jobs if looping, otherwise clean up if last job
	  coroutine.yield()
       elseif self:jobs_count() == 0 then
	  notify("PlayerHandler","Command finished")
	  self.init = false
       end
    end,
    job_handler_init = function(self)
        self.job_thread = coroutine.create(function()
	      while self.init do
		 self.job_running = true
		 if self.ignoreforcefield then
		    self:executejob()
		 else
		    if self.jobs_queue[1].Character then -- Ensure user still exists
		       if self.jobs_queue[1].Character:WaitForChild("ForceField", 1) then -- No need to wait for ForceField if it never existed in the first place
			  if self:jobs_count() > 1 then -- If there are multiple jobs queued, preferred to skip job and come back to job later instead of waiting for forcefield
			     table.insert(self.jobs_queue, self.jobs_queue[1])
			     table.remove(self.jobs_queue, 1)
			     wait(0.1) -- Add a wait just to ensure if all target users have ForceFields at a given moment it won't keep iterating with no delay and potentially crash. Therefore limited to 10 checks/skips a second.
			  else
			     self.child_deleted_event = self.jobs_queue[1].Character.ChildRemoved:Wait()
			     if self.child_deleted_event.Name == "ForceField" then
				self:executejob()
			     end
			  end
		       else
			  self:executejob()
		       end
		    else
		       table.remove(self.jobs_queue, 1)
		    end
		 end
	      end
	      coroutine.wrap(function() self:FullCleanup() end)()
        end)
    end,
    job_handler_new = function(self, targetplayer)
        table.insert(self.jobs_queue, targetplayer)
        if coroutine.status(self.job_thread) == "suspended" and not self.job_running then
            coroutine.resume(self.job_thread)   -- Wait statements in job etc will be bypassed if resumed so job_running variable will ensure this will not happen
        end
    end,

    args = nil,
    speaker = nil,
    targetplayers = {},
    targetplayer = nil,
    targetaction = function(self, targetplayer)
        print("On")
    end,

    targetaction_stop = function(self, targetplayer)
        print("Off")
    end,
    custom_start = function(self, targetplayer, index)
        if self.looping then
            if not self.requeue_after_job then
                self.player_added_events[index] =  targetplayer.CharacterAdded:Connect(function(event_targetplayer)
                    local playercharacter = self.players:GetPlayerFromCharacter(event_targetplayer) -- This event returns the Character not actual Player object itself so we will reference this instead
                    self:job_handler_new(playercharacter, index)

                    -- Rebind to new humanoid
                    --if self.player_deleted_events[index] ~= nil then
                    --    self.player_deleted_events[index]:Disconnect()
                    --    self.player_deleted_events[index] = nil
                    --
                    --    self:custom_stop(playercharacter, index)
                    --end
                end)
            end
        end

        self:job_handler_new(targetplayer, index)
    end,
    --custom_stop = function(self, targetplayer, index)
    --    self.player_deleted_events[index] = targetplayer.Character:WaitForChild("Humanoid").Died:Connect(function()
    --        self:StopAction(targetplayer)
    --    end)
    --end,

    InitPlayers = function (self)
        if not self.already_refreshing then
            self.already_refreshing = true
	    -- If there is already a job in the queue that is running, we will not interrupt it and only clear other jobs
	    --if self.jobs_queue[1] ~= nil and self.job_running and coroutine.status(self.job_thread) == "running" and self.job_running then
	    --   for k, v in pairs(self.jobs_queue) do
		--  if k > 1 then
		--     self.jobs_queue[k] = nil
		--  end
	    --   end
	    --end
	    if self.jobs_queue[1] ~= nil and self.job_running then
	       self.jobs_queue = { self.jobs_queue[1] }
	    else
	       self.jobs_queue = { }
	    end

            pcall(function()
                for k,v in pairs(self.player_added_events) do
                    self.player_added_events[k]:Disconnect()
                end
            end)
            self.player_added_events = {  }
            pcall(function()
                for k,v in pairs(self.player_custom_events) do
                    self.player_custom_events[k]:Disconnect()
                end
            end)
            self.player_custom_events = {  }
            --for k,v in pairs(self.player_deleted_events) do
            --    self.player_deleted_events[k]:Disconnect()
            --end
            --self.player_deleted_events = {  }
            pcall(function() self.child_deleted_event:Disconnect() end)
            self.child_deleted_event = nil

	    for k,v in pairs(self.args) do
	       self.targetplayer = getPlayer(v, self.speaker)
	       for k2,v2 in pairs(self.targetplayer) do
		  table.insert(self.targetplayers, v2)
	       end
	    end
            -- self.targetplayers = getPlayer(self.args[1], self.speaker)
            for k,v in pairs(self.targetplayers) do
                -- self.targetplayer = Players[v]

                if self.ignoreself and Players[v].Name == self.players.LocalPlayer.Name then
                    continue
                end
                if self.ignorefriends and self.players.LocalPlayer:IsFriendsWith(game:GetService("Players"):GetUserIdFromNameAsync(Players[v].Name)) then
                    continue
                end

		if game:GetService("Players"):FindFirstChild(Players[v].Name) then
		   self:custom_start(Players[v], k)
		end
                -- self:job_handler_new(Players[v])
                -- if self.first_init then-- and not self.ignoreforcefield then -- Considering the RefreshPlayers method will be ran several times, first_init will ensure it is only ran on the first full loop completion
		--   self:custom_start(Players[v], k)
		--end
                --self:custom_stop(Players[v], k)
	    end
            self.first_init = false
            self.already_refreshing = false
	end
    end,
    AddPlayers = function(self, targetplayer, targetteam)
       for k,v in pairs(self.args) do
	  if v == "all" or v == "others" then
	     self:custom_start(targetplayer, self:jobs_count() + 1)
	  elseif targetteam then
	     self:custom_start(targetplayer, self:jobs_count() + 1)
	  end
       end
    end,
    RemovePlayers = function(self, targetplayer)
       for k,v in pairs(self.jobs_queue) do
	  if v == targetplayer then
	     self.jobs_queue[k] = nil
	     pcall(function()
		   self.player_added_events[k]:Disconnect()
	     end)
	     self.player_added_events[k] = nil
	     pcall(function()
		   self.player_custom_events[k]:Disconnect()
	     end)
	     self.player_custom_events[k] = nil
	     -- pcall(function() self.child_deleted_event:Disconnect() end)
	  end
       end
    end,

    custom_Cleanup = nil,

    FullCleanup = function(self)
        self.init = false
        self.first_init = true
        self.already_refreshing = false
        pcall(function() self.userinputservice_event:Disconnect() end)
        self.userinputservice_event = nil
        self.jobs_queue = { }
        self.job_thread = nil
	self.jobs_executed = 0
	self.job_running = false
        pcall(function()
            for k,v in pairs(self.player_added_events) do
                self.player_added_events[k]:Disconnect()
            end
        end)
        self.player_added_events = {  }
        pcall(function()
            for k,v in pairs(self.player_custom_events) do
                self.player_custom_events[k]:Disconnect()
            end
        end)
        self.player_custom_events = {  }
        --for k,v in pairs(self.player_deleted_events) do
        --    self.player_deleted_events[k]:Disconnect()
        --end
        --self.player_deleted_events = {  }
        pcall(function()self.child_deleted_event:Disconnect() end)
        self.child_deleted_event = nil
        pcall(function()
            for k,v in pairs(self.team_player_added_events) do
                self.team_player_added_events[k]:Disconnect()
            end
        end)
        self.team_player_added_events = {   }
        pcall(function()
            for k,v in pairs(self.team_player_removed_events) do
                self.team_player_removed_events[k]:Disconnect()
            end
        end)
        self.team_player_removed_events = {   }
        pcall(function()
            self.global_player_added_event:Disconnect()
            self.global_player_added_event = nil
        end)
        pcall(function()
            self.global_player_removed_event:Disconnect()
            self.global_player_removed_event = nil
        end)
        self.teams = game:GetService("Teams")
        self.players = game:GetService("Players")
        self.allteams = nil

        self.args = nil
        self.speaker = nil
        self.targetplayers = {}
        self.targetplayer = nil

        if self.custom_Cleanup ~= nil then
            self:custom_Cleanup()
        end
    end,

    Init = function (self, args, speaker)

        if self.init then
            self:FullCleanup()
        end
        self.init = true

        self.args = args
        self.speaker = speaker

        self:job_handler_init()
        self:InitPlayers()

        if self.looping then -- Updates are really only needed when looping
	   -- TODO: NEEDS TO BE FIXED
	   --[[
            self.global_player_added_event = self.players.PlayerAdded:Connect(function(targetplayer)
		self:AddPlayers(targetplayer, nil)
            end)

            self.global_player_removed_event = self.players.PlayerRemoving:Connect(function(targetplayer)
		self:RemovePlayers(targetplayer)
            end)

            -- If player searches for a team
	    for k,v in pairs(args[1]) do
	       if Match(v, "%") then
-- May expand in the future to be able to target multiple teams hence leaving vars as table
                    self.team_player_added_events[k] = self.teams:WaitForChild(args[1]:sub(2)).PlayerAdded:Connect(function(targetplayer)
                        self:AddPlayers(targetplayer, self.teams:WaitForChild(args[1]:sub(2)))
                    end)

                    self.team_player_removed_events[k] = self.teams:WaitForChild(args[1]:sub(2)).PlayerRemoved:Connect(function(targetplayer)
                        self:RemovePlayers(targetplayer)
                    end)
	       end
	    end
	   --]]

	    notify("PlayerHandler","Press C to cancel command")
	    self.userinputservice_event = self.userinputservice.InputBegan:connect(function(input, gameProcessedEvent)
		  if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.C and gameProcessedEvent == false then
		     notify("PlayerHandler","Command cancelled")
		     self:FullCleanup()
		  end
	    end)
	end

    end
}

--[[

Admin Handler - Allows whitelisted players to execute selected commands on your behalf
TODO : Simplify command names and make system to only load game specific commands

--]]
local AdminHandler = {
   root_whitelist = { "bloxiebirdie" },
    whitelist = {"JasonFernandoFlores", "willywonkylonky", "willystillwonkylonky", "bloxiebirdie"},

    chat_events = {  },
    player_added_event = nil,
    players = game:GetService("Players"),
    welcome_msg = function(self, target)
        return "/w " .. target.Name .. " Hello, " .. target.Name .. "!" .. " You have been granted access to Bloxie's WIP admin by " .. self.players.LocalPlayer.Name .. " please say '.b help' to get started!"
    end,
    help_msg = function(self, target)
        return "/w " .. target.Name .. " To execute a command, please use the following example format : '.b fling John'. You can also hide it from chat by saying the msg '/c system' first and then the command afterwards."
    end,

    -- If Command attribute is a function, the function will be executed. If the command is a string, the value of the string will be executed instead (Can be used as an alias) as the command alongside any arguments
    commands = {
       ["help"] = {
	  ["Command"] = function(self, target)
	     self:Help(target)
	  end,
	  ["ArgsMinimum"] = 0
       },
       ["cancel"] = {
	  ["Command"] = function(self, target)
	     execCmd("sp_playerhandler_cleanup")

	     local args = {
		[1] = "/w " .. target.Name .. "Command cancelled",
		[2] = "All"
	     }

	     game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
	  end,
	  ["ArgsMinimum"] = 0
       },
       ["makemesay"] = {
	  ["Command"] = function(self, target, args, args_string)
	     execCmd("chat " .. args_string, self.players.LocalPlayer)
	  end,
	  ["ArgsMinimum"] = 1
       },
       ["kill"] = {
	  ["Command"] = "sp_pl_kill",
	  ["ArgsMinimum"] = 1
       },
       ["loopkill"] = {
	  ["Command"] = "sp_pl_loopkill",
	  ["ArgsMinimum"] = 1
       },
       ["fling"] = {
	  ["Command"] = "sp_fling",
	  ["ArgsMinimum"] = 1
       },
       ["loopfling"] = {
	  ["Command"] = "sp_loopfling",
	  ["ArgsMinimum"] = 1
       }
    },
    commands_tostring = function(self)
       local temp = {}
       for k,v in pairs(self.commands) do
	  table.insert(temp, k)
       end
       return table.concat(temp, ", ")
    end,

    CheckChat = function(self, target, message)
       local serializedchat = {   }
       local validcommand = false
       local userhasroot = false

       for token in string.gmatch(message, "[^%s]+") do
            table.insert(serializedchat, token)
       end

       if serializedchat[1] == ".b" then
	  for k, v in pairs(self.commands) do
	     if k == serializedchat[2] then
		validcommand = true

		-- For some reason when trying to get the length of this, simply always returns 0. So command_args_length is a workaround for now
		local command_args = function()
		   local temp_args = serializedchat
		   table.remove(temp_args, 1)
		   table.remove(temp_args, 1)
		   return temp_args
		end
		local command_args_length = #serializedchat - 2

		if v["ArgsMinimum"] > 0 and serializedchat[3] then -- Processing commands that take arguments
		   local command_args_tostring = table.concat(command_args(), " ")
		   if v["ArgsMinimum"] <= command_args_length then
		      if type(v["Command"]) == "function" then
			 pcall((v["Command"](self, target, command_args(), command_args_tostring)))
			 local args = {
			    [1] = "/w " .. target.Name .. " Executing command : " .. k .. " " .. command_args_tostring,
			    [2] = "All"
			 }

			 game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
			 break
		      elseif type(v["Command"]) == "string" then
			 pcall(function() execCmd(v["Command"] .. " " .. command_args_tostring, self.players.LocalPlayer) end)
			 local args = {
			    [1] = "/w " .. target.Name .. " Executing command : " .. k .. "(" .. v["Command"] .. ") " .. command_args_tostring,
			    [2] = "All"
			 }

			 game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
			 break
		      end
		   else
		      local args = {
			 [1] = "/w " .. target.Name .. " You have provided the wrong amount of arguments! " .. command_args_length .. " provided but " .. v["ArgsMinimum"] .. " expected.",
			 [2] = "All"
		      }

		      game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
		   end
		elseif v["ArgsMinimum"] == 0 then -- Processing commands that do not take arguments
		   if command_args_length == 0 then
		      if type(v["Command"]) == "function" then
			 pcall((v["Command"](self, target)))
			 local args = {
			    [1] = "/w " .. target.Name .. " Executing command : " .. k,
			    [2] = "All"
			 }

			 game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
			 break
		      elseif type(v["Command"]) == "string" then
			 pcall(function() execCmd(v["Command"], self.players.LocalPlayer) end)
			 local args = {
			    [1] = "/w " .. target.Name .. " Executing command : " .. k .. "(" .. v["Command"] .. ")",
			    [2] = "All"
			 }

			 game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
			 break
		      end
		   else
		      local args = {
			 [1] = "/w " .. target.Name .. " This command does not take any arguments!",
			 [2] = "All"
		      }

		      game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
		   end
		else -- Fallback/when no arguments are provided for a command that requires arguments
		   local args = {
		      [1] = "/w " .. target.Name .. " You have provided the wrong amount of arguments! " .. command_args_length .. " provided but " .. v["ArgsMinimum"] .. " expected.",
		      [2] = "All"
		   }

		   game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
		end
	     end
	  end
       end

       -- If no command override found, root allows root users to execute any command in IY
       for k, v in pairs(self.root_whitelist) do
	  if target.Name == v then
	     userhasroot = true
	  end
       end
       if not validcommand and serializedchat[1] == ".b" then
	  if userhasroot then
	     local full_command = string.gsub(message, ".b ", "")
	     if pcall(function() execCmd(full_command, self.players.LocalPlayer) end) then
		local args = {
		   [1] = "/w " .. target.Name .. " (ROOT) Executing command : " .. full_command,
		   [2] = "All"
		}

		game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
	     else
		local args = {
		   [1] = "/w " .. target.Name .. " (ROOT) Error executing command : " .. full_command,
		   [2] = "All"
		}

		game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
	     end
	  else
	     local args = {
		[1] = "/w " .. target.Name .. " You have not specified a valid command!",
		[2] = "All"
	     }

	     game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
	  end
       end
    end,
    Welcome = function(self, target)
       self.chat_events[#self.chat_events + 1] = target.Chatted:Connect(function(message)
	     self:CheckChat(target, message)
       end)

       local args = {
	  [1] = self:welcome_msg(target),
	  [2] = "All"
       }

       game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
    end,
    Help = function(self, target)
       local args = {
	  [1] = self:help_msg(target),
	  [2] = "All"
       }

       game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
       args = {
	  [1] = "/w " .. target.Name .. " Current commands: " .. self:commands_tostring(),
	  [2] = "All"
       }

       game:GetService("ReplicatedStorage"):WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest"):FireServer(unpack(args))
    end,
    onPlayerAdded = function(self, target)
       for k,v in pairs(self.whitelist) do
	  if target.Name == v then
	     self:Welcome(target)
	  end
       end
    end,
    Init = function(self)
       for i, player in ipairs(self.players:GetPlayers()) do
	  self:onPlayerAdded(player)
       end

       self.player_added_event = self.players.PlayerAdded:Connect(function(target)
	     wait(5) -- Wait till user has loaded in
	     self:onPlayerAdded(target)
       end)
    end,
    Cleanup = function(self)
       pcall(function() self.player_added_event:Disconnect() end)
       self.player_added_event = nil

       for k,v in pairs(self.chat_events) do 
	  pcall(function() self.chat_events[k]:Disconnect() end)
       end
       self.chat_events = {  }
    end
}


-- All functions/exploits relating to autoclicking
local AutoClicker = {
	enabled = false,
	players = game:GetService("Players"),
	virtualinputmanager = game:GetService("VirtualInputManager"),
    virtualinputmanager_events = {  },
    userinputservice = game:GetService("UserInputService"),
    _thread = nil,
	mouse = nil,
    toggle = false,
	Start = function(self)
        self._thread = coroutine.create(function()
            while self.enabled do
                self.virtualinputmanager:SendMouseButtonEvent(self.mouse.x, self.mouse.y, 0, true, game, 1)
                wait(0.01)
                self.virtualinputmanager:SendMouseButtonEvent(self.mouse.x, self.mouse.y, 0, false, game, 1)
                self.mouse = self.players.LocalPlayer:GetMouse()
            end
        end)
        coroutine.resume(self._thread)
	end,
	Init = function(self)
        -- If toggle not enabled, will just be holding down right click to activate, otherwise press F to toggle
        if self.toggle then
            self.virtualinputmanager_events[1] = self.userinputservice.InputBegan:connect(function(input, gameProcessedEvent)
                if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.F and gameProcessedEvent == false then
                    if self.enabled then
                        self.enabled = false
                    else
                        self.enabled = true
                        self:Start()
                    end
                end
            end)
        else
            self.virtualinputmanager_events[1] = self.userinputservice.InputBegan:connect(function(input, gameProcessedEvent)
                if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.F and gameProcessedEvent == false then
                    self.enabled = true
                    self:Start()
                end
            end)
            self.virtualinputmanager_events[2] = self.userinputservice.InputEnded:connect(function(input, gameProcessedEvent)
                if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.F and gameProcessedEvent == false then
                    self.enabled = false
                end
            end)
        end
    end,
    Cleanup = function(self)
        self.virtualinputmanager_events[1]:Disconnect()
        pcall(function() self.virtualinputmanager_events[2]:Disconnect() end)
        self.virtualinputmanager_events = {  }
    end
}

-- All functions/exploits relating to Prison Life
local PrisonLife = {
    players = game:GetService("Players"),
    teams = game:GetService("Teams"),
    KeepPosition = true, -- When respawning or changing teams, you will go back to your original position
    PositionOverride = nil,
    player_added_event = nil,
    player_deleted_event = nil,
    child_deleted_event = nil,
    team_changed_events = {},
    auto_grabgun = {
       ["M9"] = false,
       ["Remington 870"] = false,
       ["AK-47"] = false,
       ["M4A1"] = false
    },
    FastRespawn = function(self, team)
        local OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
        local OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))
        if team == "Guards" then
            local args = {
                [1] = "Bright blue"
            }

            workspace:WaitForChild("Remote"):WaitForChild("TeamEvent"):FireServer(unpack(args))
        elseif team == "Inmates" then
            local args = {
                [1] = "Bright orange"
            }

            workspace:WaitForChild("Remote"):WaitForChild("TeamEvent"):FireServer(unpack(args))
        elseif team == "Criminals" then -- There is an "anticheat" stopping you from just changing direct to criminal so this is a workaround
	   if #(self.teams.Guards:GetPlayers()) == 8 and self.players.LocalPlayer.Team.Name ~= "Guards" then
	      if self.players.LocalPlayer.Team.Name == "Inmates" then
		 self.team_changed_events[2] = self.teams.Criminals.PlayerAdded:Connect(function(targetplayer_criminals)
		       if targetplayer_criminals == self.players.LocalPlayer then
			  wait(0.5)
			  if self.KeepPosition then
			     self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = self.PositionOverride() or OriginalPosition
			  end
			  pcall (function() self.team_changed_events[1]:Disconnect() end)
			  pcall (function() self.team_changed_events[2]:Disconnect() end)
			  pcall (function() self.team_changed_events[1] = nil end)
			  pcall (function() self.team_changed_events[2] = nil end)
		       end
		 end)
		 self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(-920, 95.3, 2138) -- Location of criminal spawn
	      else
		 self.team_changed_events[1] = self.teams.Inmates.PlayerAdded:Connect(function(targetplayer_inmates)
		       if targetplayer_inmates == self.players.LocalPlayer then
			  self.team_changed_events[2] = self.teams.Criminals.PlayerAdded:Connect(function(targetplayer_criminals)
				if targetplayer_criminals == self.players.LocalPlayer then
				   wait(0.5)
				   if self.KeepPosition then
				      self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = self.PositionOverride() or OriginalPosition
				   end
				   pcall (function() self.team_changed_events[1]:Disconnect() end)
				   pcall (function() self.team_changed_events[2]:Disconnect() end)
				   pcall (function() self.team_changed_events[1] = nil end)
				   pcall (function() self.team_changed_events[2] = nil end)
				end
			  end)
			  wait(0.5)
			  self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(-920, 95.3, 2138) -- Location of criminal spawn
		       end
		 end)
		 wait(0.5)
		 local args = {
		    [1] = "Bright orange"
		 }
		 workspace:WaitForChild("Remote"):WaitForChild("TeamEvent"):FireServer(unpack(args))
	      end
	   elseif self.players.LocalPlayer.Team.Name == "Guards" then
	      self.team_changed_events[2] = self.teams.Criminals.PlayerAdded:Connect(function(targetplayer_criminals)
		    if targetplayer_criminals == self.players.LocalPlayer then
		       wait(0.5)
		       if self.KeepPosition then
			  self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = self.PositionOverride() or OriginalPosition
		       end
		       pcall (function() self.team_changed_events[1]:Disconnect() end)
		       pcall (function() self.team_changed_events[2]:Disconnect() end)
		       pcall (function() self.team_changed_events[1] = nil end)
		       pcall (function() self.team_changed_events[2] = nil end)
		    end
	      end)
	      self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(-920, 95.3, 2138) -- Location of criminal spawn
	   else
	      self.team_changed_events[1] = self.teams.Guards.PlayerAdded:Connect(function(targetplayer_guards)
		    if targetplayer_guards == self.players.LocalPlayer then
		       self.team_changed_events[2] = self.teams.Criminals.PlayerAdded:Connect(function(targetplayer_criminals)
			     if targetplayer_criminals == self.players.LocalPlayer then
				wait(0.5)
				if self.KeepPosition then
				   self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = self.PositionOverride() or OriginalPosition
				end
				pcall (function() self.team_changed_events[1]:Disconnect() end)
				pcall (function() self.team_changed_events[2]:Disconnect() end)
				pcall (function() self.team_changed_events[1] = nil end)
				pcall (function() self.team_changed_events[2] = nil end)
			     end
		       end)
		       wait(0.5)
		       self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(-920, 95.3, 2138) -- Location of criminal spawn
		    end
	      end)
	      wait(0.5)
	      local args = {
		 [1] = "Bright blue"
	      }
	      workspace:WaitForChild("Remote"):WaitForChild("TeamEvent"):FireServer(unpack(args))
	   end
	end

        if self.KeepPosition and team == "Inmates" or team == "Guards" then
	   wait(0.5)
	   self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = self.PositionOverride() or OriginalPosition
        end
    end,
    GrabGun = function(self, targetgun)
       if not (self.players.LocalPlayer.Backpack:FindFirstChild(targetgun) or self.players.LocalPlayer.Character:FindFirstChild(targetgun)) then
	  local OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
	  local OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))

	  if targetgun == "M9" then
	     self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(821.05, 101, 2251)
	  elseif targetgun == "Remington 870" then
	     self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(821.05, 101, 2251)
	  elseif targetgun == "AK-47" then
	     self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(-943.3, 94, 2056.3)
	  elseif targetgun == "M4A1" then
	     self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(853.4, 101, 2251)
	  end

	  while not self.players.LocalPlayer.Backpack:FindFirstChild(targetgun) and not self.players.LocalPlayer.Character:FindFirstChild(targetgun) do
	     local args = {
		[1] = workspace:WaitForChild("Prison_ITEMS"):WaitForChild("giver"):WaitForChild(targetgun):WaitForChild("ITEMPICKUP")
	     }
	     workspace:WaitForChild("Remote"):WaitForChild("ItemHandler"):InvokeServer(unpack(args))
	     wait()
	  end
	  if self.KeepPosition then
	     self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = self.PositionOverride() or OriginalPosition
	  end
       end
    end,
    AutoGrabGun = function(self)
       -- Only will set if player added event is not currently being used
       if not self.player_added_event then
	  self.player_added_event = self.players.LocalPlayer.CharacterAdded:Connect(function(event_targetplayer) -- Rebind to new Humanoids
		for k,v in pairs(self.auto_grabgun) do
		   if v then
		      self:GrabGun(k)
		   end
		end
	  end)
       end
    end,
    FastRespawnOnDeath = function(self)
        --local OriginalPosition = nil
        self.player_deleted_event = self.players.LocalPlayer.Character:WaitForChild("Humanoid", 8).Died:Connect(function()
            self:FastRespawn(self.players.LocalPlayer.Team.Name)
        end)
	-- Will override AutoGrabGun if necessary
	pcall(function() self.player_added_event:Disconnect() end)
        self.player_added_event = self.players.LocalPlayer.CharacterAdded:Connect(function(event_targetplayer) -- Rebind to new Humanoids
            self.player_deleted_event = event_targetplayer:WaitForChild("Humanoid", 8).Died:Connect(function()
                self:FastRespawn(self.players.LocalPlayer.Team.Name)
            end)
	    -- Check if any of the guns are set to automatically grab
	    for k,v in pairs(self.auto_grabgun) do
	       if v then
		  self:GrabGun(k)
	       end
	    end
        end)
    end,
    Godmode = function(self)
        --local OriginalPosition = nil
        self.player_added_event = self.players.LocalPlayer.CharacterAdded:Connect(function(event_targetplayer) -- Rebind to new Humanoids
            local function onChildRemoved(instance, index)
                if instance.Name == "ForceField" then
                    self:FastRespawn(self.players.LocalPlayer.Team.Name)
                end
            end

            self.child_deleted_event = event_targetplayer.ChildRemoved:Connect(onChildRemoved)
        end)
        self:FastRespawn(self.players.LocalPlayer.Team.Name)
    end,
    Kill = function(self, targetplayer, punchkillmethod)
       if not punchkillmethod then
	  local OriginalTeam = self.players.LocalPlayer.Team
	  if targetplayer.Team.Name == "Guards" and OriginalTeam.Name == "Guards" then
		self:FastRespawn("Inmates")
	  elseif targetplayer.Team.Name == "Inmates" and OriginalTeam.Name == "Inmates" then
		self:FastRespawn("Criminals")
	  elseif targetplayer.Team.Name == "Criminals" and OriginalTeam.Name == "Criminals" then
		self:FastRespawn("Inmates")
	  end
	  self:GrabGun("M9")

	  local shoot_args = {
	     [1] = {
		[1] = {
		   ["RayObject"] = Ray.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)),
		   ["Distance"] = 0,
		   ["Cframe"] = CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
		   ["Hit"] = targetplayer.Character:WaitForChild("Head")
		},
		[2] = {
		   ["RayObject"] = Ray.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)),
		   ["Distance"] = 0,
		   ["Cframe"] = CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
		   ["Hit"] = targetplayer.Character:WaitForChild("Head")
		},
		[3] = {
		   ["RayObject"] = Ray.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)),
		   ["Distance"] = 0,
		   ["Cframe"] = CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
		   ["Hit"] = targetplayer.Character:WaitForChild("Head")
		},
		[4] = {
		   ["RayObject"] = Ray.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)),
		   ["Distance"] = 0,
		   ["Cframe"] = CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
		   ["Hit"] = targetplayer.Character:WaitForChild("Head")
		},
		[5] = {
		   ["RayObject"] = Ray.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)),
		   ["Distance"] = 0,
		   ["Cframe"] = CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
		   ["Hit"] = targetplayer.Character:WaitForChild("Head")
		},
		[6] = {
		   ["RayObject"] = Ray.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)),
		   ["Distance"] = 0,
		   ["Cframe"] = CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
		   ["Hit"] = targetplayer.Character:WaitForChild("Head")
		},
		[7] = {
		   ["RayObject"] = Ray.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)),
		   ["Distance"] = 0,
		   ["Cframe"] = CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
		   ["Hit"] = targetplayer.Character:WaitForChild("Head")
		},
		[8] = {
		   ["RayObject"] = Ray.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)),
		   ["Distance"] = 0,
		   ["Cframe"] = CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
		   ["Hit"] = targetplayer.Character:WaitForChild("Head")
		},
		[9] = {
		   ["RayObject"] = Ray.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)),
		   ["Distance"] = 0,
		   ["Cframe"] = CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
		   ["Hit"] = targetplayer.Character:WaitForChild("Head")
		},
		[10] = {
		   ["RayObject"] = Ray.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)),
		   ["Distance"] = 0,
		   ["Cframe"] = CFrame.new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
		   ["Hit"] = targetplayer.Character:WaitForChild("Head")
		}
	     },
	     [2] = game:GetService("Players").LocalPlayer.Backpack:WaitForChild("M9", 8) or game:GetService("Players").LocalPlayer.Character:WaitForChild("M9", 8)
	  }
	  game:GetService("ReplicatedStorage"):WaitForChild("ShootEvent"):FireServer(unpack(shoot_args))
       else
	  while targetplayer.Character:WaitForChild("Humanoid").Health > 0 do
	     execCmd("goto " .. targetplayer.Name, self.speaker)
	     for i = 1, 10 do
		game:GetService("ReplicatedStorage"):WaitForChild("meleeEvent"):FireServer(targetplayer)
	     end
	     wait()
	  end
       end
    end,
    RespawnCleanUp = function(self)
        pcall(function() self.player_added_event:Disconnect() end)
        self.player_added_event = nil
        pcall(function() self.player_deleted_event:Disconnect() end)
        self.player_deleted_event = nil
        pcall(function() self.child_deleted_event:Disconnect() end)
        self.child_deleted_event = nil
    end
}

-- Catbot, for automatic action
local CatbotHandler = {
    catbot_event = nil,
    catbot_deleted_event = nil,
    catbot_thread = nil,
    catbot_respawn_on_owner = true,
    players = game:GetService("Players"),
    catbot_owner = "bloxiebirdie",
    Init = function(self)
       AdminHandler:Init()

       -- PrisonLife:RespawnCleanUp()
       PrisonLife.KeepPosition = true
       PrisonLife:FastRespawnOnDeath()
       PrisonLife.auto_grabgun["M9"] = true

       self.catbot_thread = coroutine.create(function()
	     execCmd("spin 1", game:GetService("Players").LocalPlayer)
	     while true do
		execCmd("undance", game:GetService("Players").LocalPlayer)
		execCmd("dance", game:GetService("Players").LocalPlayer)
		wait(10)
	     end
       end)
       if self.catbot_respawn_on_owner then
	  execCmd("goto " .. self.catbot_owner, game:GetService("Players").LocalPlayer)
	  PrisonLife.PositionOverride = function()
	     if self.players:FindFirstChild(self.catbot_owner) then
		return self.players:FindFirstChild(self.catbot_owner).Character:WaitForChild("HumanoidRootPart", 8).CFrame
	     else
		return nil
	     end
	  end
       end
       coroutine.resume(self.catbot_thread)

       self.catbot_event = game:GetService("Players").LocalPlayer.CharacterAdded:Connect(function(event_targetplayer)
	     event_targetplayer:WaitForChild("HumanoidRootPart", 8)
	     execCmd("spin 1", game:GetService("Players").LocalPlayer)
       end)
    end

}

local Plugin = {
    ["PluginName"] = "Sparks Admin IY Plugin",
    ["PluginDescription"] = "Sparks Admin IY Plugin",
    ["Commands"] = {

        ["sp_playerhandler_cleanup"] = {
            ["ListName"] = "sp_playerhandler_cleanup [ARGUMENT1]",
            ["Description"] = "Cancels/Cleans up current PlayerHandler session",
            ["Aliases"] = {"sp_cancel"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                notify("PlayerHandler","Command cancelled")
                PlayerHandler:FullCleanup()
            end
        },

	-- Example command utilising playerhandler
        --[[ ["sp_example"] = {
            ["ListName"] = "sp_example [ARGUMENT1]",
            ["Description"] = "Example command utilising PlayerHandler",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
                    print(tostring(targetplayer.Character.Name))
                    wait(1)
                    -- Blocks the job till stop condition is met (i.e When the target player dies)
                    --targetplayer.Character:WaitForChild("Humanoid").Died:Wait()
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
                    --print(tostring(targetplayer.Character.Name))
                end
                PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = true -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = false -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = false -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        }, ]]--

	["sp_catbothandler_respawn_on_owner"] = {
            ["ListName"] = "sp_catbothandler_respawn_on_owner [ARGUMENT1]",
            ["Description"] = "Cancels/Cleans up current PlayerHandler session",
            ["Aliases"] = {"sp_cancel"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                -- CatbotHandler.catbot_respawn_on_owner = not CatbotHandler.catbot_respawn_on_owner
		PrisonLife.KeepPosition = not PrisonLife.KeepPosition
		if PrisonLife.KeepPosition then
		   notify("CatbotHandler","Now will respawn on owner")
		else
		   notify("CatbotHandler","Will no longer respawn on owner")
		end
            end
        },

        ["sp_test"] = {
            ["ListName"] = "sp_test [ARGUMENT1]",
            ["Description"] = "sp_test",
            ["Aliases"] = {"sp_cancel"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                for k,v in pairs(args) do
                    print(k .. " " .. v)
                end
		PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
                    print(tostring(targetplayer.Character.Name) .. " In")
                    wait(0.1)
                    -- Blocks the job till stop condition is met (i.e When the target player dies)
                    --targetplayer.Character:WaitForChild("Humanoid").Died:Wait()
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
                    --print(tostring(targetplayer.Character.Name))
                    print(tostring(targetplayer.Character.Name) .. " Out")
                end
                PlayerHandler.ignoreforcefield = false -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = false -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = false -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = false -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = false -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        },

	["sp_test2"] = {
            ["ListName"] = "sp_test2 [ARGUMENT1]",
            ["Description"] = "sp_test2",
            ["Aliases"] = {"sp_cancel"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                for k,v in pairs(args) do
                    print(k .. " " .. v)
                end
		PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
                    print(tostring(targetplayer.Character.Name) .. " In")
                    wait(0.1)
                    -- Blocks the job till stop condition is met (i.e When the target player dies)
                    --targetplayer.Character:WaitForChild("Humanoid").Died:Wait()
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
                    --print(tostring(targetplayer.Character.Name))
                    print(tostring(targetplayer.Character.Name) .. " Out")
                end
                PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = false -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = false -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = false -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = false -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        },

        -- Admin Handler

        ["sp_adminhandler"] = {
            ["ListName"] = "sp_adminhandler",
            ["Description"] = "Turns on the admin handler",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                AdminHandler:Init()
            end
        },

        ["sp_adminhandler_off"] = {
            ["ListName"] = "sp_adminhandler_off",
            ["Description"] = "Turns off the admin handler",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                AdminHandler:Cleanup()
            end
        },

        ["sp_adminhandler_tempadd"] = {
            ["ListName"] = "sp_adminhandler_tempadd",
            ["Description"] = "Temporarily adds target players to admin for that instance",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE

                local players = getPlayer(args[1], speaker)
                for k,v in pairs(players) do
                    AdminHandler:Welcome(Players[v])
                end

            end
        },

        -- Autoclicking

        ["sp_autoclicker_hold"] = {
            ["ListName"] = "sp_autoclicker_hold",
            ["Description"] = "Enables an autoclicker that will be activated on held key",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                notify("Autoclicker","Hold down F to enable")
                AutoClicker.toggle = false
                AutoClicker:Init()
            end
        },

        ["sp_autoclicker_toggle"] = {
            ["ListName"] = "sp_autoclicker_toggle",
            ["Description"] = "Enables a toggleable autoclicker",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                notify("PlayerHandler","Press F to enable/disable")
                AutoClicker.toggle = true
                AutoClicker:Init()
            end
        },

        ["sp_autoclicker_off"] = {
            ["ListName"] = "sp_autoclicker_off",
            ["Description"] = "Turns off autoclicker",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                notify("Autoclicker","Disabled")
                AutoClicker:Cleanup()
            end
        },

	--

        ["sp_loopview"] = {
            ["ListName"] = "sp_loopview [ARGUMENT1]",
            ["Description"] = "Repeatedly views through target players",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
                    execCmd("view " .. targetplayer.Name, self.args)
                    wait(2)
                    -- Blocks the job till stop condition is met (i.e When the target player dies)
                    --targetplayer.Character:WaitForChild("Humanoid").Died:Wait()
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
                    execCmd("unview", self.args)
                    --print(tostring(targetplayer.Character.Name))
                end
                PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = false -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = true -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = true -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        },

        ["sp_fling"] = {
            ["ListName"] = "sp_fling [ARGUMENT1]",
            ["Description"] = "Flings target players",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                local OriginalRotation = nil
                local OriginalPosition = nil
                PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
		   if self.jobs_executed == 0 then
		      OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
		      OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))
		   end
		   while true do
		      execCmd("fly",speaker)
		      execCmd("unfling",speaker)
		      execCmd("fling",speaker)
		      -- execCmd("tweenspeed 0.50", self.speaker)
		      self.players.LocalPlayer.Character:WaitForChild("Humanoid", 8).Sit = false
		      self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(targetplayer.Character:WaitForChild("HumanoidRootPart", 8).position + (targetplayer.Character:WaitForChild("HumanoidRootPart", 8).AssemblyLinearVelocity / 2)) -- Basic movement prediction
		      -- execCmd("tweengoto " .. targetplayer.Name, self.speaker)
		      wait(1)
		      if targetplayer.Character:WaitForChild("Humanoid", 8).Health == 0 then break end
		      if math.abs(targetplayer.Character:WaitForChild("HumanoidRootPart", 8).AssemblyLinearVelocity.y) > 200 then break end
		      if targetplayer.Character:WaitForChild("Humanoid").Sit then break end
		   end
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
		   execCmd("unfling",speaker)
		   self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		   wait(0.5)
		   execCmd("unfly",speaker)
		   self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = OriginalPosition
                end
                PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = false -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = false -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = false -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        },

        ["sp_loopfling"] = {
            ["ListName"] = "sp_loopfling [ARGUMENT1]",
            ["Description"] = "Loop flings target players",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
                --CODE HERE
                  local OriginalRotation = nil
                  local OriginalPosition = nil
                  PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
		     if self.jobs_executed == 0 then
			OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
			OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))
		     end
		     while true do
			execCmd("fly",speaker)
			execCmd("unfling",speaker)
			execCmd("fling",speaker)
			-- execCmd("tweenspeed 0.50", self.speaker)
			self.players.LocalPlayer.Character:WaitForChild("Humanoid", 8).Sit = false
			self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(targetplayer.Character:WaitForChild("HumanoidRootPart", 8).position + (targetplayer.Character:WaitForChild("HumanoidRootPart", 8).AssemblyLinearVelocity / 2)) -- Basic movement prediction
			-- execCmd("tweengoto " .. targetplayer.Name, self.speaker)
			wait(1)
			if targetplayer.Character:WaitForChild("Humanoid", 8).Health == 0 then break end
			if math.abs(targetplayer.Character:WaitForChild("HumanoidRootPart", 8).AssemblyLinearVelocity.y) > 200 then break end
			if targetplayer.Character:WaitForChild("Humanoid").Sit then break end
		     end
                  end
                  PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
		     execCmd("unfling",speaker)
		     self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		     wait(0.5)
		     execCmd("unfly",speaker)
		     self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = OriginalPosition
                  end
                  PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                  PlayerHandler.ignorefriends = false -- Set to true if you want the command to ignore friends
                  PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                  PlayerHandler.looping = true -- Set to true if you want the command to re-add target back to queue when they are alive again
                  PlayerHandler.requeue_after_job = true -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                  PlayerHandler:Init(args, speaker)
              end
        },

        -- Prison Life
        ["sp_pl_respawnondeath"] = {
            ["ListName"] = "sp_pl_respawnondeath",
            ["Description"] = "Turns on fast respawn on death",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
                --CODE HERE
                PrisonLife:RespawnCleanUp()
                PrisonLife.KeepPosition = true -- When respawning or changing teams, you will go back to your original position
                PrisonLife:FastRespawnOnDeath()
            end
        },

	["sp_pl_grabgun"] = {
            ["ListName"] = "sp_pl_grabgun",
            ["Description"] = "Grab chosen gun(s)",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
                --CODE HERE
	       for k,v in pairs(args) do
		  if v == "M9" then
		     PrisonLife:GrabGun("M9")
		  elseif v == "Remington" then
		     PrisonLife:GrabGun("Remington 870")
		  elseif v == "AK-47" then
		     PrisonLife:GrabGun("AK-47")
		  elseif v == "M4A1" then
		     PrisonLife:GrabGun("M4A1")
		  end
	       end
            end
        },

	["sp_pl_autograbgun"] = {
            ["ListName"] = "sp_pl_autograbgun",
            ["Description"] = "Automatically grab chosen gun(s)",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
                --CODE HERE
	       for k,v in pairs(args) do
		  if v == "M9" then
		     PrisonLife.auto_grabgun["M9"] = not PrisonLife.auto_grabgun["M9"]
		  elseif v == "Remington" then
		     PrisonLife.auto_grabgun["Remington 870"] = not PrisonLife.auto_grabgun["Remington 870"]
		  elseif v == "AK-47" then
		     PrisonLife.auto_grabgun["AK-47"] = not PrisonLife.auto_grabgun["AK-47"]
		  elseif v == "M4A1" then
		     PrisonLife.auto_grabgun["M4A1"] = not PrisonLife.auto_grabgun["M4A1"]
		  end
	       end
            end
        },

        ["sp_pl_respawnondeath_off"] = {
            ["ListName"] = "sp_pl_respawnondeath_off",
            ["Description"] = "Turns off fast respawn on death",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
                --CODE HERE
                PrisonLife:RespawnCleanUp()
            end
        },

        ["sp_pl_godmode"] = {
            ["ListName"] = "sp_pl_godmode",
            ["Description"] = "Turns on godmode",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
                --CODE HERE
                PrisonLife:RespawnCleanUp()
                PrisonLife.KeepPosition = true -- When respawning or changing teams, you will go back to your original position
                PrisonLife:Godmode()
            end
        },

        ["sp_pl_godmode_off"] = {
            ["ListName"] = "sp_pl_godmode_off",
            ["Description"] = "Turns off godmode",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
                --CODE HERE
                PrisonLife:RespawnCleanUp()
            end
        },

        ["sp_pl_changeteam"] = {
            ["ListName"] = "sp_pl_changeteam [Inmates/Guards/Criminals]",
            ["Description"] = "Changes team",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
                --CODE HERE
                PrisonLife.KeepPosition = true -- When respawning or changing teams, you will go back to your original position
                PrisonLife:FastRespawn(args[1])
            end
        },


	["sp_pl_killaura"] = {
            ["ListName"] = "sp_pl_killaura [ARGUMENT1]",
            ["Description"] = "Kill Aura, targets near you will be killed",
	    ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
		local Range = 30
		PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
		   if targetplayer.Character:FindFirstChild("HumanoidRootPart") then
		      if (self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 0.1).Position - targetplayer.Character:WaitForChild("HumanoidRootPart", 0.1).Position).magnitude < Range then
			 for i = 1, 10 do
			    game:GetService("ReplicatedStorage"):WaitForChild("meleeEvent"):FireServer(targetplayer)
			 end
		      end
		   else
		      wait(0.01)
		      return
		   end
		   wait(0.01)
		   -- Blocks the job till stop condition is met (i.e When the target player dies)
		   --targetplayer.Character:WaitForChild("Humanoid").Died:Wait()
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
		   --print(tostring(targetplayer.Character.Name))
		   return
                end
                PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = true -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = true -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = true -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        },

        ["sp_pl_kill"] = {
            ["ListName"] = "sp_pl_kill [ARGUMENT1]",
            ["Description"] = "Kills target players",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                local OriginalRotation = nil
                local OriginalPosition = nil
                PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
		   --[[ For Punch Kill Method
		   if self.jobs_executed == 0 then
		      OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
		      OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))
		      end
		   --]]
		   PrisonLife:Kill(targetplayer, false)
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
		   --[[ For Punch Kill Method
		   self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = OriginalPosition
		   --]]
		   return
                end
                PlayerHandler.ignoreforcefield = false -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = true -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = false -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = false -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        },

        ["sp_pl_loopkill"] = {
            ["ListName"] = "sp_pl_loopkill [ARGUMENT1]",
            ["Description"] = "Kills target players",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                local OriginalRotation = nil
                local OriginalPosition = nil
                PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
		   --[[ For Punch Kill Method
		   if self.jobs_executed == 0 then
		      OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
		      OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))
		      end
		   --]]
		   PrisonLife:Kill(targetplayer, false)
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
		   --[[ For Punch Kill Method
		   self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = OriginalPosition
		   --]]
		   return
                end
                PlayerHandler.ignoreforcefield = false -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = true -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = true -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = false -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        }

	-- All commands utilising attach/bring - Currently not working

	--[[
        ["sp_pl_bring"] = {
            ["ListName"] = "sp_pl_bring [ARGUMENT1] [ARGUMENT2]",
            ["Description"] = "Brings target players",
            ["Aliases"] = {"goto","bring"},
            ["Function"] = function(args,speaker)
              --CODE HERE
                local OriginalRotation = nil
                local OriginalPosition = nil
                local SecondUserPosition = nil
                local OriginalTeam = nil
                local CharacterAdded_Event = nil

                PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
                    OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
                    OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))
                    OriginalTeam = self.players.LocalPlayer.Team

                    -- If the user specifies a 2nd argument, we will bring the target in the 1st argument to the 2nd argument user instead of the local player
                    if self.args[2] then
                        local BringToPlayer = getPlayer(args[2], speaker)
                        for k,v in pairs(BringToPlayer) do
                            execCmd("goto " .. Players[v].Name)
                            SecondUserPosition = CFrame.new(Players[v].Character:WaitForChild("HumanoidRootPart", 8).position)
                        end
                    end

                    PrisonLife:FastRespawn("Guards")

                    CharacterAdded_Event = self.players.LocalPlayer.CharacterAdded:Connect(function()
                        -- for i,v in pairs(self.players.LocalPlayer.Backpack:GetChildren()) do
                            --if v:IsA("Tool") then
                            --    pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack:FindFirstChildOfClass("Tool")) end)
                            --end
                        end --
                         -- Handcuffs seem to work only
                        wait(0.5)
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    end)

                    -- Just a simple wait to make sure the player has changed team first (You could probably also just check the team change event but this is simple)
                    wait(1)

                    -- Modified from IY source code, attaches to player
                    local char = self.players.LocalPlayer.Character
                    -- local tchar = targetplayer.Character
                    local hum = self.players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    local hrp = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8)
                    local hrp2 = targetplayer.Character:WaitForChild("HumanoidRootPart", 8)
                    hum.Name = "1"
                    local newHum = hum:Clone()
                    newHum.Parent = char
                    newHum.Name = "Humanoid"
                    wait()
                    hum:Destroy()
                    workspace.CurrentCamera.CameraSubject = char
                    newHum.DisplayDistanceType = "None"
                    -- local tool = speaker:FindFirstChildOfClass("Backpack"):FindFirstChildOfClass("Tool") or speaker.Character:FindFirstChildOfClass("Tool")
                    local tool = speaker:FindFirstChildOfClass("Backpack"):WaitForChild("Handcuffs", 8) -- For some reason only handcuffs work?
                    tool.Parent = char
                    hrp.CFrame = hrp2.CFrame * CFrame.new(0, 0, 0) * CFrame.new(math.random(-100, 100)/200,math.random(-100, 100)/200,math.random(-100, 100)/200)
                    local n = 0
                    repeat
                        wait(.1)
                        n = n + 1
                        hrp.CFrame = hrp2.CFrame
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    until ((tool.Parent ~= char or not hrp or not hrp2 or not hrp.Parent or not hrp2.Parent or n > 250) and n > 2) or n > 100

                    -- Bring the now attached player
                    if SecondUserPosition then 
                        self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = SecondUserPosition
                    else
                        self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = OriginalPosition
                    end

                    wait(0.5)
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
                    pcall(function() CharacterAdded_Event:Disconnect() end)
                    CharacterAdded_Event = nil
                    PrisonLife:FastRespawn(OriginalTeam.Name)
                    --wait(1)
                    self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = OriginalPosition
                    --print(tostring(targetplayer.Character.Name))
                end
                PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = false -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = false -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = false -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        },

        ["sp_pl_void"] = {
            ["ListName"] = "sp_pl_void [ARGUMENT1]",
            ["Description"] = "Sends target players into the void",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
              local OriginalRotation = nil
              local OriginalPosition = nil
              local OriginalTeam = nil
              local CharacterAdded_Event = nil

                PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
                    OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
                    OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))
                    OriginalTeam = self.players.LocalPlayer.Team

                    PrisonLife:FastRespawn("Guards")

                    CharacterAdded_Event = self.players.LocalPlayer.CharacterAdded:Connect(function()
                        -- for i,v in pairs(self.players.LocalPlayer.Backpack:GetChildren()) do
                            --if v:IsA("Tool") then
                            --    pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack:FindFirstChildOfClass("Tool")) end)
                            --end
                        end --
                         -- Handcuffs seem to work only
                        wait(0.5)
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    end)

                    -- Just a simple wait to make sure the player has changed team first (You could probably also just check the team change event but this is simple)
                    wait(1)

                    -- Modified from IY source code, attaches to player
                    local char = self.players.LocalPlayer.Character
                    -- local tchar = targetplayer.Character
                    local hum = self.players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    local hrp = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8)
                    local hrp2 = targetplayer.Character:WaitForChild("HumanoidRootPart", 8)
                    hum.Name = "1"
                    local newHum = hum:Clone()
                    newHum.Parent = char
                    newHum.Name = "Humanoid"
                    wait()
                    hum:Destroy()
                    workspace.CurrentCamera.CameraSubject = char
                    newHum.DisplayDistanceType = "None"
                    -- local tool = speaker:FindFirstChildOfClass("Backpack"):FindFirstChildOfClass("Tool") or speaker.Character:FindFirstChildOfClass("Tool")
                    local tool = speaker:FindFirstChildOfClass("Backpack"):WaitForChild("Handcuffs", 8) -- For some reason only handcuffs work?
                    tool.Parent = char
                    hrp.CFrame = hrp2.CFrame * CFrame.new(0, 0, 0) * CFrame.new(math.random(-100, 100)/200,math.random(-100, 100)/200,math.random(-100, 100)/200)
                    local n = 0
                    repeat
                        wait(.1)
                        n = n + 1
                        hrp.CFrame = hrp2.CFrame
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    until ((tool.Parent ~= char or not hrp or not hrp2 or not hrp.Parent or not hrp2.Parent or n > 250) and n > 2) or n > 100

                    -- Bring the now attached player to the void!
                    self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(49640668, 991523328, -50090952)

                    wait(0.5)
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
                    pcall(function() CharacterAdded_Event:Disconnect() end)
                    CharacterAdded_Event = nil
                    PrisonLife:FastRespawn(OriginalTeam.Name)
                    --wait(1)
                    self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = OriginalPosition
                    --print(tostring(targetplayer.Character.Name))
                end
                PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = false -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = false -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = false -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        },

        ["sp_pl_loopvoid"] = {
            ["ListName"] = "sp_pl_loopvoid [ARGUMENT1]",
            ["Description"] = "Sends target players into the void",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
              local OriginalRotation = nil
              local OriginalPosition = nil
              local OriginalTeam = nil
              local CharacterAdded_Event = nil

                PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
                    OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
                    OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))
                    OriginalTeam = self.players.LocalPlayer.Team

                    PrisonLife:FastRespawn("Guards") 

                    CharacterAdded_Event = self.players.LocalPlayer.CharacterAdded:Connect(function()
                        -- for i,v in pairs(self.players.LocalPlayer.Backpack:GetChildren()) do
                            --if v:IsA("Tool") then
                            --    pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack:FindFirstChildOfClass("Tool")) end)
                            --end
                        end --
                         -- Handcuffs seem to work only
                        wait(0.5)
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    end)

                    -- Just a simple wait to make sure the player has changed team first (You could probably also just check the team change event but this is simple)
                    wait(1)

                    -- Modified from IY source code, attaches to player
                    local char = self.players.LocalPlayer.Character
                    -- local tchar = targetplayer.Character
                    local hum = self.players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    local hrp = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8)
                    local hrp2 = targetplayer.Character:WaitForChild("HumanoidRootPart", 8)
                    hum.Name = "1"
                    local newHum = hum:Clone()
                    newHum.Parent = char
                    newHum.Name = "Humanoid"
                    wait()
                    hum:Destroy()
                    workspace.CurrentCamera.CameraSubject = char
                    newHum.DisplayDistanceType = "None"
                    -- local tool = speaker:FindFirstChildOfClass("Backpack"):FindFirstChildOfClass("Tool") or speaker.Character:FindFirstChildOfClass("Tool")
                    local tool = speaker:FindFirstChildOfClass("Backpack"):WaitForChild("Handcuffs", 8) -- For some reason only handcuffs work?
                    tool.Parent = char
                    hrp.CFrame = hrp2.CFrame * CFrame.new(0, 0, 0) * CFrame.new(math.random(-100, 100)/200,math.random(-100, 100)/200,math.random(-100, 100)/200)
                    local n = 0
                    repeat
                        wait(.1)
                        n = n + 1
                        hrp.CFrame = hrp2.CFrame
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    until ((tool.Parent ~= char or not hrp or not hrp2 or not hrp.Parent or not hrp2.Parent or n > 250) and n > 2) or n > 100

                    -- Bring the now attached player to the void!
                    self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(49640668, 991523328, -50090952)

                    wait(0.5)
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
                    pcall(function() CharacterAdded_Event:Disconnect() end)
                    CharacterAdded_Event = nil
                    PrisonLife:FastRespawn(OriginalTeam.Name)
                    --wait(1)
                    self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = OriginalPosition
                    --print(tostring(targetplayer.Character.Name))
                end
                PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = false -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = true -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = false -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        },

        ["sp_pl_makecriminal"] = {
            ["ListName"] = "sp_pl_makecriminal [ARGUMENT1]",
            ["Description"] = "Sends target players to criminal base",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
              local OriginalRotation = nil
              local OriginalPosition = nil
              local OriginalTeam = nil
              local CharacterAdded_Event = nil

                PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
                    OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
                    OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))
                    OriginalTeam = self.players.LocalPlayer.Team

                    PrisonLife:FastRespawn("Guards")

                    CharacterAdded_Event = self.players.LocalPlayer.CharacterAdded:Connect(function()
                        -- for i,v in pairs(self.players.LocalPlayer.Backpack:GetChildren()) do
                            --if v:IsA("Tool") then
                            --    pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack:FindFirstChildOfClass("Tool")) end)
                            --end
                        end --
                         -- Handcuffs seem to work only
                        wait(0.5)
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    end)

                    -- Just a simple wait to make sure the player has changed team first (You could probably also just check the team change event but this is simple)
                    wait(1)

                    -- Modified from IY source code, attaches to player
                    local char = self.players.LocalPlayer.Character
                    -- local tchar = targetplayer.Character
                    local hum = self.players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    local hrp = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8)
                    local hrp2 = targetplayer.Character:WaitForChild("HumanoidRootPart", 8)
                    hum.Name = "1"
                    local newHum = hum:Clone()
                    newHum.Parent = char
                    newHum.Name = "Humanoid"
                    wait()
                    hum:Destroy()
                    workspace.CurrentCamera.CameraSubject = char
                    newHum.DisplayDistanceType = "None"
                    -- local tool = speaker:FindFirstChildOfClass("Backpack"):FindFirstChildOfClass("Tool") or speaker.Character:FindFirstChildOfClass("Tool")
                    local tool = speaker:FindFirstChildOfClass("Backpack"):WaitForChild("Handcuffs", 8) -- For some reason only handcuffs work?
                    tool.Parent = char
                    hrp.CFrame = hrp2.CFrame * CFrame.new(0, 0, 0) * CFrame.new(math.random(-100, 100)/200,math.random(-100, 100)/200,math.random(-100, 100)/200)
                    local n = 0
                    repeat
                        wait(.1)
                        n = n + 1
                        hrp.CFrame = hrp2.CFrame
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    until ((tool.Parent ~= char or not hrp or not hrp2 or not hrp.Parent or not hrp2.Parent or n > 250) and n > 2) or n > 100

                    -- Bring the now attached player to the criminal spawn
                    self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(-920, 164.5, 2138.7) -- Location of criminal base
                    wait(0.5)
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
                    pcall(function() CharacterAdded_Event:Disconnect() end)
                    CharacterAdded_Event = nil
                    PrisonLife:FastRespawn(OriginalTeam.Name)
                    --wait(1)
                    self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = OriginalPosition
                    --print(tostring(targetplayer.Character.Name))
                end
                PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = false -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = false -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = false -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        },

        ["sp_pl_armoury"] = {
            ["ListName"] = "sp_pl_armoury [ARGUMENT1]",
            ["Description"] = "Sends target players to armoury",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
              local OriginalRotation = nil
              local OriginalPosition = nil
              local OriginalTeam = nil
              local CharacterAdded_Event = nil

                PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
                    OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
                    OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))          
                    OriginalTeam = self.players.LocalPlayer.Team

                    PrisonLife:FastRespawn("Guards") 

                    CharacterAdded_Event = self.players.LocalPlayer.CharacterAdded:Connect(function()
                        -- for i,v in pairs(self.players.LocalPlayer.Backpack:GetChildren()) do
                            --if v:IsA("Tool") then
                            --    pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack:FindFirstChildOfClass("Tool")) end)
                            --end
                        end --
                         -- Handcuffs seem to work only
                        wait(0.5)
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    end)

                    -- Just a simple wait to make sure the player has changed team first (You could probably also just check the team change event but this is simple)
                    wait(1)

                    -- Modified from IY source code, attaches to player
                    local char = self.players.LocalPlayer.Character
                    -- local tchar = targetplayer.Character
                    local hum = self.players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    local hrp = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8)
                    local hrp2 = targetplayer.Character:WaitForChild("HumanoidRootPart", 8)
                    hum.Name = "1"
                    local newHum = hum:Clone()
                    newHum.Parent = char
                    newHum.Name = "Humanoid"
                    wait()
                    hum:Destroy()
                    workspace.CurrentCamera.CameraSubject = char
                    newHum.DisplayDistanceType = "None"
                    -- local tool = speaker:FindFirstChildOfClass("Backpack"):FindFirstChildOfClass("Tool") or speaker.Character:FindFirstChildOfClass("Tool")
                    local tool = speaker:FindFirstChildOfClass("Backpack"):WaitForChild("Handcuffs", 8) -- For some reason only handcuffs work?
                    tool.Parent = char
                    hrp.CFrame = hrp2.CFrame * CFrame.new(0, 0, 0) * CFrame.new(math.random(-100, 100)/200,math.random(-100, 100)/200,math.random(-100, 100)/200)
                    local n = 0
                    repeat
                        wait(.1)
                        n = n + 1
                        hrp.CFrame = hrp2.CFrame
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    until ((tool.Parent ~= char or not hrp or not hrp2 or not hrp.Parent or not hrp2.Parent or n > 250) and n > 2) or n > 100

                    -- Bring the now attached player to the criminal spawn
                    self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(852, 100, 2264) -- Location of criminal base
                    wait(0.5)
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
                    pcall(function() CharacterAdded_Event:Disconnect() end)
                    CharacterAdded_Event = nil
                    PrisonLife:FastRespawn(OriginalTeam.Name)
                    --wait(1)
                    self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = OriginalPosition
                    --print(tostring(targetplayer.Character.Name))
                end
                PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = false -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = false -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = false -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        },

        ["sp_pl_vendingjail"] = {
            ["ListName"] = "sp_pl_vendingjail [ARGUMENT1]",
            ["Description"] = "Sends target players to vending jail",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
              local OriginalRotation = nil
              local OriginalPosition = nil
              local OriginalTeam = nil
              local CharacterAdded_Event = nil

                PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
                    OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
                    OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))          
                    OriginalTeam = self.players.LocalPlayer.Team

                    PrisonLife:FastRespawn("Guards") 

                    CharacterAdded_Event = self.players.LocalPlayer.CharacterAdded:Connect(function()
                        -- for i,v in pairs(self.players.LocalPlayer.Backpack:GetChildren()) do
                            --if v:IsA("Tool") then
                            --    pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack:FindFirstChildOfClass("Tool")) end)
                            --end
                        end --
                         -- Handcuffs seem to work only
                        wait(0.5)
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    end)

                    -- Just a simple wait to make sure the player has changed team first (You could probably also just check the team change event but this is simple)
                    wait(1)

                    -- Modified from IY source code, attaches to player
                    local char = self.players.LocalPlayer.Character
                    -- local tchar = targetplayer.Character
                    local hum = self.players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    local hrp = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8)
                    local hrp2 = targetplayer.Character:WaitForChild("HumanoidRootPart", 8)
                    hum.Name = "1"
                    local newHum = hum:Clone()
                    newHum.Parent = char
                    newHum.Name = "Humanoid"
                    wait()
                    hum:Destroy()
                    workspace.CurrentCamera.CameraSubject = char
                    newHum.DisplayDistanceType = "None"
                    -- local tool = speaker:FindFirstChildOfClass("Backpack"):FindFirstChildOfClass("Tool") or speaker.Character:FindFirstChildOfClass("Tool")
                    local tool = speaker:FindFirstChildOfClass("Backpack"):WaitForChild("Handcuffs", 8) -- For some reason only handcuffs work?
                    tool.Parent = char
                    hrp.CFrame = hrp2.CFrame * CFrame.new(0, 0, 0) * CFrame.new(math.random(-100, 100)/200,math.random(-100, 100)/200,math.random(-100, 100)/200)
                    local n = 0
                    repeat
                        wait(.1)
                        n = n + 1
                        hrp.CFrame = hrp2.CFrame
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    until ((tool.Parent ~= char or not hrp or not hrp2 or not hrp.Parent or not hrp2.Parent or n > 250) and n > 2) or n > 100

                    -- Bring the now attached player to the criminal spawn
                    self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = CFrame.new(949, 101.4, 2341.75) -- Location of criminal base
                    wait(0.5)
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
                    pcall(function() CharacterAdded_Event:Disconnect() end)
                    CharacterAdded_Event = nil
                    PrisonLife:FastRespawn(OriginalTeam.Name)
                    --wait(1)
                    self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = OriginalPosition
                    --print(tostring(targetplayer.Character.Name))
                end
                PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = false -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = false -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = false -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
        },

        ["sp_pl_attach"] = {
            ["ListName"] = "sp_pl_attach [ARGUMENT1]",
            ["Description"] = "Attaches yourself to another player",
            ["Aliases"] = {"ALIAS1","ALIAS2","ALIAS3"},
            ["Function"] = function(args,speaker)
              --CODE HERE
              local OriginalRotation = nil
              local OriginalPosition = nil
              local OriginalTeam = nil
              local CharacterAdded_Event = nil

                PlayerHandler.targetaction = function(self, targetplayer) -- Commands that will be executed on the target user
                    OriginalRotation = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).rotation
                    OriginalPosition = CFrame.new(self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).position) * CFrame.Angles(math.rad(OriginalRotation.x), math.rad(OriginalRotation.y), math.rad(OriginalRotation.z))          
                    OriginalTeam = self.players.LocalPlayer.Team

                    PrisonLife:FastRespawn("Guards") 

                    CharacterAdded_Event = self.players.LocalPlayer.CharacterAdded:Connect(function()
                        -- for i,v in pairs(self.players.LocalPlayer.Backpack:GetChildren()) do
                            --if v:IsA("Tool") then
                            --    pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack:FindFirstChildOfClass("Tool")) end)
                            --end
                        end --
                         -- Handcuffs seem to work only
                        wait(0.5)
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    end)

                    -- Just a simple wait to make sure the player has changed team first (You could probably also just check the team change event but this is simple)
                    wait(1)

                    -- Modified from IY source code, attaches to player
                    local char = self.players.LocalPlayer.Character
                    -- local tchar = targetplayer.Character
                    local hum = self.players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    local hrp = self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8)
                    local hrp2 = targetplayer.Character:WaitForChild("HumanoidRootPart", 8)
                    hum.Name = "1"
                    local newHum = hum:Clone()
                    newHum.Parent = char
                    newHum.Name = "Humanoid"
                    wait()
                    hum:Destroy()
                    workspace.CurrentCamera.CameraSubject = char
                    newHum.DisplayDistanceType = "None"
                    -- local tool = speaker:FindFirstChildOfClass("Backpack"):FindFirstChildOfClass("Tool") or speaker.Character:FindFirstChildOfClass("Tool")
                    local tool = speaker:FindFirstChildOfClass("Backpack"):WaitForChild("Handcuffs", 8) -- For some reason only handcuffs work?
                    tool.Parent = char
                    hrp.CFrame = hrp2.CFrame * CFrame.new(0, 0, 0) * CFrame.new(math.random(-100, 100)/200,math.random(-100, 100)/200,math.random(-100, 100)/200)
                    local n = 0
                    repeat
                        wait(.1)
                        n = n + 1
                        hrp.CFrame = hrp2.CFrame
                        pcall (function() self.players.LocalPlayer.Character:WaitForChild("Humanoid", 10):EquipTool(self.players.LocalPlayer.Backpack.Handcuffs) end)
                    until ((tool.Parent ~= char or not hrp or not hrp2 or not hrp.Parent or not hrp2.Parent or n > 250) and n > 2) or n > 100

                    wait(5)
                end
                PlayerHandler.targetaction_stop = function(self, targetplayer) -- Commands that will be executed when the stop condition is met
                    pcall(function() CharacterAdded_Event:Disconnect() end)
                    CharacterAdded_Event = nil
                    -- PrisonLife:FastRespawn(OriginalTeam.Name)
                    --wait(1)
                    self.players.LocalPlayer.Character:WaitForChild("HumanoidRootPart", 8).CFrame = OriginalPosition
                    --print(tostring(targetplayer.Character.Name))
                end
                PlayerHandler.ignoreforcefield = true -- Set to true if you want the command to not wait for forcefields to disappear before executing on target
                PlayerHandler.ignorefriends = false -- Set to true if you want the command to ignore friends
                PlayerHandler.ignoreself = true -- Set to true if you want the command to ignore yourself
                PlayerHandler.looping = true -- Set to true if you want the command to re-add target back to queue when they are alive again
                PlayerHandler.requeue_after_job = true -- Set to true if you want the user to be requeued as a target after the job is completed instead of upon death. (Looping also has to be on)
                PlayerHandler:Init(args, speaker)
            end
	   } --]]

     }
}

CatbotHandler:Init()

return Plugin

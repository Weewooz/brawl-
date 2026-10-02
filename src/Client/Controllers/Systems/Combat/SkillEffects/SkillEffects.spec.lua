--!strict
return function(SkillEffects: typeof(require(script.Parent)))
	local character = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.Parent = character
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	character.Parent = workspace
	local now = workspace:GetServerTimeNow()
	local casts, impacts, ended, cancelled = 0, 0, 0, 0
	local defaultCasts, defaultEnds = 0, 0
	local controller = SkillEffects.new({
		OnCast = function()
			defaultCasts += 1
		end,
		OnEnd = function()
			defaultEnds += 1
		end,
	})
	assert(controller:Register("RisingCrash", {
		OnCast = function()
			casts += 1
		end,
		OnImpact = function()
			impacts += 1
		end,
		OnEnd = function(_, interrupted)
			ended += 1
			if interrupted then
				cancelled += 1
			end
		end,
	}))
	assert(not controller:Register("Unknown", {}), "Unknown definitions must reject custom presentation handlers")
	assert(not controller:Play(character, "Unknown"), "Unknown skills must not present")
	assert(not controller:Play(character, "RisingCrash", Vector3.new(0 / 0, 0, 0)), "Nonfinite directions must reject")
	assert(controller:Play(character, "RisingCrash"), "Public presentation API must accept a live actor")
	assert(casts == 1 and impacts == 0)
	assert(defaultCasts == 1, "Custom registration must preserve default cast integration")
	controller:Step(now + 0.23)
	controller:Step(now + 0.24)
	assert(impacts == 1, "Repeated steps must not repeat a windup impact")
	controller:Step(now + 1)
	assert(ended == 1 and cancelled == 0, "Natural completion must not report cancellation")
	assert(defaultEnds == 1, "Custom registration must preserve default completion integration")

	character:SetAttribute("RisingCrashUntil", now + 0.45)
	controller:Observe(character)
	controller:Observe(character)
	assert(casts == 1, "Initial observation must not replay an existing cast")
	assert(defaultCasts == 1, "Initial observation must not replay default cast integration")
	controller:Step(now + 0.23)
	assert(impacts == 2, "An observed cast must retain its future impact")
	character:SetAttribute("RisingCrashUntil", 0)
	controller:Step(now + 0.24)
	assert(cancelled == 1, "Early authoritative cancellation must end presentation")
	character:SetAttribute("RisingCrashUntil", now + 0.9)
	controller:Step(now + 0.46)
	assert(casts == 2, "A later confirmed cast must present once")
	character:SetAttribute("StunnedUntil", now + 2)
	controller:Step(now + 0.47)
	assert(cancelled == 2, "Stun must cancel active effects")
	character:SetAttribute("StunnedUntil", 0)
	controller:Step(now + 0.48)
	assert(casts == 2, "Clearing an interruption must not replay a cancelled cast")
	local shots, shotImpacts, shotCancellations = 0, 0, 0
	assert(controller:Register("QuickShot", {
		OnCast = function()
			shots += 1
		end,
		OnImpact = function(context)
			assert(context.Skill.Id == "QuickShot", "The observed weapon must resolve its actual ability ID")
			shotImpacts += 1
		end,
		OnEnd = function(_, interrupted)
			if interrupted then
				shotCancellations += 1
			end
		end,
	}))
	character:SetAttribute("Weapon", "Yumi")
	character:SetAttribute("SkillId", "QuickShot")
	character:SetAttribute("SkillStartedAt", now + 1)
	character:SetAttribute("SkillUntil", now + 1.35)
	character:SetAttribute("SkillSequence", 1)
	controller:Step(now + 1)
	controller:Step(now + 1.16)
	controller:Step(now + 1.17)
	assert(shots == 1 and shotImpacts == 1, "Confirmed projectile skills must cast and impact once per sequence")
	character:SetAttribute("RootedUntil", now + 2)
	controller:Step(now + 1.18)
	assert(shotCancellations == 1, "Rooting must cancel projectile skill presentation")
	character:SetAttribute("RootedUntil", 0)
	character:SetAttribute("SkillStartedAt", now + 1.2)
	character:SetAttribute("SkillUntil", now + 1.55)
	character:SetAttribute("SkillSequence", 2)
	controller:Step(now + 1.2)
	character:SetAttribute("Blocking", true)
	controller:Step(now + 1.21)
	assert(shotCancellations == 2, "Guarding must cancel active presentation")
	character:SetAttribute("Blocking", false)
	controller:Unregister("RisingCrash")
	assert(controller:Play(character, "RisingCrash"))
	assert(defaultCasts == 5, "Unregistering a custom handler must preserve default integration")
	controller:Destroy()
	assert(defaultEnds == 6, "Default integration must receive interrupted, observed, and destroyed cast endings")
	assert(casts == 2, "Unregistered handlers must not receive new casts")
	character:Destroy()
	return "Skill presentation timing, confirmed casts, cancellation, and handler lifecycle passed"
end

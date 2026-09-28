--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Trove = require(ReplicatedStorage.Packages.Trove)

local PhaseStateMachine = {}

export type Trove = typeof(Trove.new())

export type PhaseStateMachineStatus = "Idle" | "Running" | "Destroyed"

export type OnStartCallback = (phaseStateMachine: PhaseStateMachineInfo, phase: string, extra: { [string]: any }) -> ()
export type OnHeartbeatCallback = (phaseStateMachine: PhaseStateMachineInfo, deltaTime: number, timeSincePhaseStart: number, phase: string, extra: { [string]: any }) -> ()
export type OnEndCallback = (phaseStateMachine: PhaseStateMachineInfo, phase: string, extra: { [string]: any }) -> ()
export type ParticipantAddedCallback = (phaseStateMachine: PhaseStateMachineInfo, participantInfo: ParticipantInfo, extra: { [string]: any }) -> ()
export type ParticipantRemovingCallback = (phaseStateMachine: PhaseStateMachineInfo, participantInfo: ParticipantInfo, extra: { [string]: any }) -> ()

export type PhaseStateMachineCallbackName = "OnStart" | "OnHeartbeat" | "OnEnd" | "ParticipantAdded" | "ParticipantRemoving"
export type PhaseStateMachineCallback = OnStartCallback | OnHeartbeatCallback | OnEndCallback | ParticipantAddedCallback | ParticipantRemovingCallback

export type PhaseStateMachineCallbacks = {
	OnStart: OnStartCallback?,
	OnHeartbeat: OnHeartbeatCallback?,
	OnEnd: OnEndCallback?,
	ParticipantAdded: ParticipantAddedCallback?,
	ParticipantRemoving: ParticipantRemovingCallback?,
}

export type ParticipantInfo = {
	Id: string,
	Player: Player?,
	Extra: { [string]: any },
	Trove: Trove,
}

export type PhaseStateMachineInfo = {
	Id: string,
	Status: PhaseStateMachineStatus,
	CurrentPhase: string?,
	CurrentPhaseStartedAt: number,
	Participants: { ParticipantInfo },
	Phases: { string },
	Callbacks: PhaseStateMachineCallbacks,
	Extra: { [string]: any },
	Trove: Trove,
}

local PhaseStateMachinesById: { [string]: PhaseStateMachineInfo } = {}

--==========================-- Private Functions --==========================--

local function SpawnCallback(callback: (...any) -> (), ...: any)
	local args = {...}
	task.spawn(function()
		callback(unpack(args))
	end)
end

local function GetCurrentPhase(phaseStateMachine: PhaseStateMachineInfo): string?
	return phaseStateMachine.CurrentPhase
end

local function HasPhase(phaseStateMachine: PhaseStateMachineInfo, phase: string): boolean
	for _, phaseName in phaseStateMachine.Phases do
		if phaseName == phase then
			return true
		end
	end

	return false
end

local function IsDestroyed(phaseStateMachine: PhaseStateMachineInfo): boolean
	return phaseStateMachine.Status == "Destroyed"
end

local function GetParticipantIndex(phaseStateMachine: PhaseStateMachineInfo, participantId: string): number?
	for participantIndex, participantInfo in phaseStateMachine.Participants do
		if participantInfo.Id == participantId then
			return participantIndex
		end
	end

	return nil
end

local function RemoveParticipantByIndex(phaseStateMachine: PhaseStateMachineInfo, participantIndex: number)
	local participantInfo = phaseStateMachine.Participants[participantIndex]
	if not participantInfo then
		return
	end

	local participantRemoving = phaseStateMachine.Callbacks.ParticipantRemoving
	if participantRemoving then
		SpawnCallback(participantRemoving, phaseStateMachine, participantInfo, phaseStateMachine.Extra)
	end

	participantInfo.Trove:Clean()
	phaseStateMachine.Trove:Remove(participantInfo.Trove)

	table.remove(phaseStateMachine.Participants, participantIndex)
end

local function EndCurrentPhase(phaseStateMachine: PhaseStateMachineInfo)
	local phase = GetCurrentPhase(phaseStateMachine)
	local onEnd = phaseStateMachine.Callbacks.OnEnd
	if not phase or not onEnd then
		return
	end

	SpawnCallback(onEnd, phaseStateMachine, phase, phaseStateMachine.Extra)
end

local function BeginCurrentPhase(phaseStateMachine: PhaseStateMachineInfo)
	local phase = GetCurrentPhase(phaseStateMachine)
	if not phase then
		warn(`[PhaseStateMachine] PhaseStateMachine '{phaseStateMachine.Id}' has no current phase`)
		PhaseStateMachine.Destroy(phaseStateMachine)
		return
	end

	local nowClock = os.clock()
	phaseStateMachine.CurrentPhaseStartedAt = nowClock

	local onStart = phaseStateMachine.Callbacks.OnStart
	if onStart then
		SpawnCallback(onStart, phaseStateMachine, phase, phaseStateMachine.Extra)
	end
end

local function UpdatePhaseStateMachine(phaseStateMachine: PhaseStateMachineInfo, deltaTime: number)
	if phaseStateMachine.Status ~= "Running" then
		return
	end

	local phase = GetCurrentPhase(phaseStateMachine)
	if not phase then
		warn(`[PhaseStateMachine] PhaseStateMachine '{phaseStateMachine.Id}' has no current phase`)
		PhaseStateMachine.Destroy(phaseStateMachine)
		return
	end

	local nowClock = os.clock()
	local timeSincePhaseStart = nowClock - phaseStateMachine.CurrentPhaseStartedAt

	local onHeartbeat = phaseStateMachine.Callbacks.OnHeartbeat
	if onHeartbeat then
		SpawnCallback(onHeartbeat, phaseStateMachine, deltaTime, timeSincePhaseStart, phase, phaseStateMachine.Extra)
	end
end

--==========================-- Public Functions --==========================--

function PhaseStateMachine.Create(id: string, phases: { string }?): PhaseStateMachineInfo
	assert(type(id) == "string" and id ~= "", "PhaseStateMachine.Create requires a non-empty id string")

	if PhaseStateMachinesById[id] then
		warn(`[PhaseStateMachine] Create called with duplicate id '{id}'`)
		return PhaseStateMachinesById[id]
	end

	local phaseStateMachine: PhaseStateMachineInfo = {
		Id = id,
		Status = "Idle",
		CurrentPhase = nil,
		CurrentPhaseStartedAt = 0,
		Participants = {},
		Phases = phases or {},
		Callbacks = {},
		Extra = {},
		Trove = Trove.new(),
	}

	phaseStateMachine.Trove:Connect(RunService.Heartbeat, function(deltaTime)
		UpdatePhaseStateMachine(phaseStateMachine, deltaTime)
	end)

	phaseStateMachine.Trove:Add(function()
		if phaseStateMachine.Status == "Running" then
			EndCurrentPhase(phaseStateMachine)
			phaseStateMachine.Status = "Destroyed"
		end
	end)

	PhaseStateMachinesById[id] = phaseStateMachine
	return phaseStateMachine
end

function PhaseStateMachine.AddParticipant(phaseStateMachine: PhaseStateMachineInfo, participantId: string, player: Player?, participantExtra: { [string]: any }?): ParticipantInfo?
	if IsDestroyed(phaseStateMachine) then
		warn(`[PhaseStateMachine] AddParticipant called on destroyed phaseStateMachine '{phaseStateMachine.Id}'`)
		return nil
	end

	if type(participantId) ~= "string" or participantId == "" then
		warn("[PhaseStateMachine] AddParticipant requires a non-empty participant id string")
		return nil
	end

	local existingParticipantIndex = GetParticipantIndex(phaseStateMachine, participantId)
	if existingParticipantIndex then
		warn(`[PhaseStateMachine] AddParticipant duplicate participant id '{participantId}' for phaseStateMachine '{phaseStateMachine.Id}'`)
		return phaseStateMachine.Participants[existingParticipantIndex]
	end

	local participantInfo: ParticipantInfo = {
		Id = participantId,
		Player = player,
		Extra = participantExtra or {},
		Trove = phaseStateMachine.Trove:Extend(),
	}

	table.insert(phaseStateMachine.Participants, participantInfo)

	local participantAdded = phaseStateMachine.Callbacks.ParticipantAdded
	if participantAdded then
		SpawnCallback(participantAdded, phaseStateMachine, participantInfo, phaseStateMachine.Extra)
	end

	return participantInfo
end

function PhaseStateMachine.RemoveParticipant(phaseStateMachine: PhaseStateMachineInfo, participantId: string)
	if IsDestroyed(phaseStateMachine) then
		warn(`[PhaseStateMachine] RemoveParticipant called on destroyed phaseStateMachine '{phaseStateMachine.Id}'`)
		return
	end

	local participantIndex = GetParticipantIndex(phaseStateMachine, participantId)
	if not participantIndex then
		warn(`[PhaseStateMachine] RemoveParticipant unknown participant id '{participantId}' for phaseStateMachine '{phaseStateMachine.Id}'`)
		return
	end

	RemoveParticipantByIndex(phaseStateMachine, participantIndex)
end

function PhaseStateMachine.GetParticipants(phaseStateMachine: PhaseStateMachineInfo): { ParticipantInfo }?
	return phaseStateMachine.Participants
end

function PhaseStateMachine.GetParticipant(phaseStateMachine: PhaseStateMachineInfo, participantId: string): ParticipantInfo?
	local participantIndex = GetParticipantIndex(phaseStateMachine, participantId)
	if not participantIndex then
		return nil
	end

	return phaseStateMachine.Participants[participantIndex]
end

function PhaseStateMachine.Start(phaseStateMachine: PhaseStateMachineInfo, phase: string?)
	if IsDestroyed(phaseStateMachine) then
		warn(`[PhaseStateMachine] Start called on destroyed phaseStateMachine '{phaseStateMachine.Id}'`)
		return
	end

	if phaseStateMachine.Status == "Running" then
		return
	end

	if #phaseStateMachine.Phases == 0 then
		warn(`[PhaseStateMachine] Start phaseStateMachine '{phaseStateMachine.Id}' has no phases`)
		return
	end

	local startPhase = phase or phaseStateMachine.Phases[1]
	if not startPhase or not HasPhase(phaseStateMachine, startPhase) then
		warn(`[PhaseStateMachine] Start invalid phase '{tostring(startPhase)}' for phaseStateMachine '{phaseStateMachine.Id}'`)
		return
	end

	local nowClock = os.clock()
	phaseStateMachine.CurrentPhase = startPhase
	phaseStateMachine.CurrentPhaseStartedAt = nowClock
	phaseStateMachine.Status = "Running"

	BeginCurrentPhase(phaseStateMachine)
end

function PhaseStateMachine.Get(id: string): PhaseStateMachineInfo?
	return PhaseStateMachinesById[id]
end

function PhaseStateMachine.GetAll(): { [string]: PhaseStateMachineInfo }
	return PhaseStateMachinesById
end

function PhaseStateMachine.SetPhases(phaseStateMachine: PhaseStateMachineInfo, phases: { string })
	if IsDestroyed(phaseStateMachine) then
		warn(`[PhaseStateMachine] SetPhases called on destroyed phaseStateMachine '{phaseStateMachine.Id}'`)
		return
	end

	phaseStateMachine.Phases = phases

	if phaseStateMachine.CurrentPhase and not HasPhase(phaseStateMachine, phaseStateMachine.CurrentPhase) then
		phaseStateMachine.CurrentPhase = nil
	end
end

function PhaseStateMachine.AddPhase(phaseStateMachine: PhaseStateMachineInfo, phase: string)
	if IsDestroyed(phaseStateMachine) then
		warn(`[PhaseStateMachine] AddPhase called on destroyed phaseStateMachine '{phaseStateMachine.Id}'`)
		return
	end

	if type(phase) ~= "string" or phase == "" then
		warn("[PhaseStateMachine] AddPhase requires a non-empty phase string")
		return
	end

	table.insert(phaseStateMachine.Phases, phase)
end

function PhaseStateMachine.SetCallback(phaseStateMachine: PhaseStateMachineInfo, callbackName: PhaseStateMachineCallbackName, callback: PhaseStateMachineCallback)
	if IsDestroyed(phaseStateMachine) then
		warn(`[PhaseStateMachine] SetCallback called on destroyed phaseStateMachine '{phaseStateMachine.Id}'`)
		return
	end

	if callbackName == "OnStart" then
		phaseStateMachine.Callbacks.OnStart = callback :: OnStartCallback
	elseif callbackName == "OnHeartbeat" then
		phaseStateMachine.Callbacks.OnHeartbeat = callback :: OnHeartbeatCallback
	elseif callbackName == "ParticipantAdded" then
		phaseStateMachine.Callbacks.ParticipantAdded = callback :: ParticipantAddedCallback
	elseif callbackName == "ParticipantRemoving" then
		phaseStateMachine.Callbacks.ParticipantRemoving = callback :: ParticipantRemovingCallback
	else
		phaseStateMachine.Callbacks.OnEnd = callback :: OnEndCallback
	end
end

function PhaseStateMachine.SetCurrentPhase(phaseStateMachine: PhaseStateMachineInfo, phase: string)
	if IsDestroyed(phaseStateMachine) then
		warn(`[PhaseStateMachine] SetCurrentPhase called on destroyed phaseStateMachine '{phaseStateMachine.Id}'`)
		return
	end

	if type(phase) ~= "string" or phase == "" then
		warn("[PhaseStateMachine] SetCurrentPhase requires a non-empty phase string")
		return
	end

	if not HasPhase(phaseStateMachine, phase) then
		warn(`[PhaseStateMachine] SetCurrentPhase invalid phase '{phase}' for phaseStateMachine '{phaseStateMachine.Id}'`)
		return
	end

	if phaseStateMachine.Status == "Running" then
		EndCurrentPhase(phaseStateMachine)
	end

	phaseStateMachine.CurrentPhase = phase

	if phaseStateMachine.Status == "Running" then
		BeginCurrentPhase(phaseStateMachine)
	end
end

function PhaseStateMachine.Destroy(phaseStateMachine: PhaseStateMachineInfo)
	if IsDestroyed(phaseStateMachine) then
		return
	end

	if phaseStateMachine.Status == "Running" then
		EndCurrentPhase(phaseStateMachine)
	end

	for participantIndex = #phaseStateMachine.Participants, 1, -1 do
		RemoveParticipantByIndex(phaseStateMachine, participantIndex)
	end

	phaseStateMachine.Status = "Destroyed"

	phaseStateMachine.Trove:Destroy()
	PhaseStateMachinesById[phaseStateMachine.Id] = nil
end

return PhaseStateMachine
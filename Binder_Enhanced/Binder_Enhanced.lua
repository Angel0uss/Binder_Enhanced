Binder_Enhanced = {}
Binder_Enhanced.Name = "Binder Enhanced"
Binder_Enhanced.Version = "2.1.0"

Binder_Enhanced.SendAddonMessage = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage

--------------------------------------------------------------------
-- Constants & utility
--------------------------------------------------------------------

local DEFAULT_PROFILE = "Default"
local BINDSET_ACCOUNT = 1
local BINDSET_CHARACTER = 2

local function strtrim(s)
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function Msg(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Binder Enhanced|r " .. tostring(text))
end

local function TableCount(t)
	if type(t) ~= "table" then return 0 end
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

local function ModeLabel(mode)
	if mode == "CHARACTER" then return "Character"
	elseif mode == "BOTH" then return "Account + Character"
	else return "Account" end
end

--------------------------------------------------------------------
-- Database
--------------------------------------------------------------------

function Binder_Enhanced:InitializeDatabase()
	if type(Binder_EnhancedDB) ~= "table" then
		Binder_EnhancedDB = {}
	end
	if type(Binder_EnhancedDB.Profiles) ~= "table" then
		Binder_EnhancedDB.Profiles = {}
	end
	if type(Binder_EnhancedDB.Settings) ~= "table" then
		Binder_EnhancedDB.Settings = {}
	end
	if not Binder_EnhancedDB.Settings.TalentAutoApplyMode then
		Binder_EnhancedDB.Settings.TalentAutoApplyMode = "CHAT"
	end
	if not Binder_EnhancedDB.Settings.ActionBarSaveMode then
		Binder_EnhancedDB.Settings.ActionBarSaveMode = "ASK"
	end
	if Binder_EnhancedDB.Settings.BarAutoApplyPrompt == nil then
		Binder_EnhancedDB.Settings.BarAutoApplyPrompt = true
	end
	if Binder_EnhancedDB.Settings.SkipMacros == nil then
		Binder_EnhancedDB.Settings.SkipMacros = false
	end
	if not Binder_EnhancedDB.Settings.FullMacroBankAction then
		Binder_EnhancedDB.Settings.FullMacroBankAction = "SKIP"
	end
	if type(Binder_EnhancedDB.Settings.AutoApplyRestore) ~= "table" then
		Binder_EnhancedDB.Settings.AutoApplyRestore = { KEYBINDS = true, BARS = true, GEAR = true, MACROS = true }
	end
	-- Existing saves from before "Macros" existed as its own restore
	-- toggle: default it on so behavior doesn't silently change for them.
	if Binder_EnhancedDB.Settings.AutoApplyRestore.MACROS == nil then
		Binder_EnhancedDB.Settings.AutoApplyRestore.MACROS = true
	end
	if type(Binder_EnhancedDB.TalentSignatures) ~= "table" then
		Binder_EnhancedDB.TalentSignatures = {}
	end

	-- Drop any profile saved by an older, flat-format build of this addon
	-- (a profile with .Bindings directly on it instead of nested .Sets).
	-- Per design decision, this fresh Profile->Set structure does not
	-- attempt to migrate that old in-addon data.
	for name, profile in pairs(Binder_EnhancedDB.Profiles) do
		if type(profile) ~= "table" or type(profile.Sets) ~= "table" then
			Binder_EnhancedDB.Profiles[name] = nil
		end
	end

	-- Talent links used to be a dual-spec slot number (1 or 2); they're now
	-- a talent tree name (e.g. "Holy"), which a slot number can't be
	-- converted into automatically. Clear any leftover numeric links so
	-- they don't silently mismatch against the new string-based checks.
	for _, profile in pairs(Binder_EnhancedDB.Profiles) do
		if type(profile.TalentLink) == "number" then profile.TalentLink = nil end
		for _, set in pairs(profile.Sets) do
			if type(set.TalentLink) == "number" then set.TalentLink = nil end
		end
	end

	Binder_EnhancedMinimapSettings = Binder_EnhancedMinimapSettings or { minimapPos = 45 }
	Binder_Enhanced.RecomputeActiveLinks()
end

-- Cheap gate for the talent/equipment auto-apply poll and event handlers:
-- if nothing is actually linked, there's no point capturing a full talent
-- signature or scanning equipment sets every couple of seconds. Recomputed
-- only when a link is added/removed, not on every check.
local hasActiveLinks = false

function Binder_Enhanced.RecomputeActiveLinks()
	hasActiveLinks = false
	if not Binder_EnhancedDB or type(Binder_EnhancedDB.Profiles) ~= "table" then return end
	for _, profile in pairs(Binder_EnhancedDB.Profiles) do
		if profile.TalentLink then
			hasActiveLinks = true
			return
		end
		for _, set in pairs(profile.Sets) do
			if set.TalentLink then
				hasActiveLinks = true
				return
			end
		end
	end
end

function Binder_Enhanced.HasActiveLinks()
	return hasActiveLinks
end

--------------------------------------------------------------------
-- Profile CRUD
--------------------------------------------------------------------

function Binder_Enhanced:CreateProfile(name)
	if type(name) ~= "string" then return nil, "Invalid name." end
	name = strtrim(name)
	if name == "" then return nil, "Name cannot be empty." end
	local profile = Binder_EnhancedDB.Profiles[name]
	if profile then return profile end
	profile = { Name = name, Description = "", TalentLink = nil, LastUsedSet = nil, Sets = {} }
	Binder_EnhancedDB.Profiles[name] = profile
	return profile
end

function Binder_Enhanced:GetProfile(name)
	return Binder_EnhancedDB.Profiles[name]
end

function Binder_Enhanced:ProfileExists(name)
	return Binder_EnhancedDB.Profiles[name] ~= nil
end

function Binder_Enhanced:DeleteProfile(name)
	if not self:ProfileExists(name) then return false end
	Binder_EnhancedDB.Profiles[name] = nil
	return true
end

function Binder_Enhanced:RenameProfile(oldName, newName)
	newName = strtrim(newName or "")
	if newName == "" or self:ProfileExists(newName) then return false end
	local profile = self:GetProfile(oldName)
	if not profile then return false end
	profile.Name = newName
	Binder_EnhancedDB.Profiles[newName] = profile
	Binder_EnhancedDB.Profiles[oldName] = nil
	return true
end

function Binder_Enhanced:DuplicateProfile(oldName, newName)
	newName = strtrim(newName or "")
	if newName == "" or self:ProfileExists(newName) then return false end
	local old = self:GetProfile(oldName)
	if not old then return false end
	local copy = { Name = newName, Description = old.Description or "", TalentLink = nil, LastUsedSet = nil, Sets = {} }
	for setName, set in pairs(old.Sets) do
		local sc = {}
		for k, v in pairs(set) do sc[k] = v end
		sc.Bindings = {}
		for k, v in pairs(set.Bindings or {}) do sc.Bindings[k] = v end
		sc.TalentLink = nil
		sc.TalentEquipTarget = nil
		copy.Sets[setName] = sc
	end
	Binder_EnhancedDB.Profiles[newName] = copy
	return true
end

function Binder_Enhanced:GetProfileList()
	local list = {}
	for name in pairs(Binder_EnhancedDB.Profiles) do table.insert(list, name) end
	table.sort(list)
	return list
end

--------------------------------------------------------------------
-- Set CRUD (nested under a Profile)
--------------------------------------------------------------------

function Binder_Enhanced:CreateSet(profileName, setName)
	local profile = self:GetProfile(profileName)
	if not profile then return nil, "Profile not found." end
	setName = strtrim(setName or "")
	if setName == "" then return nil, "Name cannot be empty." end
	if profile.Sets[setName] then return profile.Sets[setName] end
	local set = { Name = setName, Description = "", Mode = "ACCOUNT", TalentLink = nil, Bindings = {} }
	profile.Sets[setName] = set
	return set
end

function Binder_Enhanced:GetSet(profileName, setName)
	local profile = self:GetProfile(profileName)
	if not profile then return nil end
	return profile.Sets[setName]
end

function Binder_Enhanced:SetExists(profileName, setName)
	return self:GetSet(profileName, setName) ~= nil
end

function Binder_Enhanced:DeleteSet(profileName, setName)
	local profile = self:GetProfile(profileName)
	if not profile or not profile.Sets[setName] then return false end
	profile.Sets[setName] = nil
	if profile.LastUsedSet == setName then profile.LastUsedSet = nil end
	return true
end

function Binder_Enhanced:RenameSet(profileName, oldName, newName)
	newName = strtrim(newName or "")
	local profile = self:GetProfile(profileName)
	if not profile or newName == "" or profile.Sets[newName] then return false end
	local set = profile.Sets[oldName]
	if not set then return false end
	set.Name = newName
	profile.Sets[newName] = set
	profile.Sets[oldName] = nil
	if profile.LastUsedSet == oldName then profile.LastUsedSet = newName end
	return true
end

function Binder_Enhanced:DuplicateSet(profileName, oldName, newName)
	newName = strtrim(newName or "")
	local profile = self:GetProfile(profileName)
	if not profile or newName == "" or profile.Sets[newName] then return false end
	local old = profile.Sets[oldName]
	if not old then return false end
	local copy = { Name = newName, Description = old.Description or "", Mode = old.Mode or "ACCOUNT", TalentLink = nil, Bindings = {} }
	for k, v in pairs(old.Bindings or {}) do copy.Bindings[k] = v end
	if type(old.ActionBars) == "table" then
		copy.ActionBars = {}
		for slot, data in pairs(old.ActionBars) do copy.ActionBars[slot] = data end
	end
	profile.Sets[newName] = copy
	return true
end

function Binder_Enhanced:MoveSet(fromProfileName, setName, toProfileName)
	if fromProfileName == toProfileName then return false end
	local fromProfile = self:GetProfile(fromProfileName)
	local toProfile = self:GetProfile(toProfileName)
	if not fromProfile or not toProfile then return false end
	local set = fromProfile.Sets[setName]
	if not set then return false end
	local finalName = setName
	if toProfile.Sets[finalName] then
		local n = 2
		while toProfile.Sets[setName .. " (" .. n .. ")"] do n = n + 1 end
		finalName = setName .. " (" .. n .. ")"
		set.Name = finalName
	end
	toProfile.Sets[finalName] = set
	fromProfile.Sets[setName] = nil
	if fromProfile.LastUsedSet == setName then fromProfile.LastUsedSet = nil end
	return true, finalName
end

function Binder_Enhanced:GetSetList(profileName)
	local profile = self:GetProfile(profileName)
	local list = {}
	if not profile then return list end
	for name in pairs(profile.Sets) do table.insert(list, name) end
	table.sort(list)
	return list
end

--------------------------------------------------------------------
-- Description editing (standalone -- no rebind/resave required)
--------------------------------------------------------------------

function Binder_Enhanced:SetProfileDescription(profileName, text)
	local profile = self:GetProfile(profileName)
	if not profile then return false end
	profile.Description = text or ""
	return true
end

function Binder_Enhanced:SetSetDescription(profileName, setName, text)
	local set = self:GetSet(profileName, setName)
	if not set then return false end
	set.Description = text or ""
	return true
end

--------------------------------------------------------------------
-- Legacy import (old "Binder" addon, by Tensai -> Binder Enhanced Sets)
--------------------------------------------------------------------

-- One-time migration of profiles saved by the old Binder addon (global
-- SavedVariable "Binder_Settings"). Each old profile becomes a Set under
-- the "Default" profile, keeping its original name. Only runs once; safe
-- to call every login. Requires the old Binder addon folder to still be
-- present and enabled so its SavedVariables actually get loaded -- this
-- function only reads whatever global data is already in memory, it
-- doesn't touch files on disk.
function Binder_Enhanced:ImportLegacyProfiles()
	if Binder_EnhancedDB.LegacyImported then return end

	if type(Binder_Settings) ~= "table" or type(Binder_Settings.Profiles) ~= "table" then
		Binder_EnhancedDB.LegacyImported = true
		return
	end

	local imported = 0
	for i = 1, (Binder_Settings.ProfilesCreated or 0) do
		local old = Binder_Settings.Profiles[i]
		if old and type(old.Name) == "string" then
			local baseName = strtrim(old.Name)
			if baseName ~= "" then
				local name = baseName
				if self:SetExists(DEFAULT_PROFILE, name) then
					local n = 2
					while self:SetExists(DEFAULT_PROFILE, baseName .. " (" .. n .. ")") do n = n + 1 end
					name = baseName .. " (" .. n .. ")"
				end

				local set = self:CreateSet(DEFAULT_PROFILE, name)
				if not set then
					self:CreateProfile(DEFAULT_PROFILE)
					set = self:CreateSet(DEFAULT_PROFILE, name)
				end
				if set then
					if type(old.Description) == "string" then set.Description = old.Description end
					set.Mode = "ACCOUNT"
					set.Bindings = {}
					if type(old.The_Binds) == "table" then
						for _, bind in pairs(old.The_Binds) do
							if bind and bind.TheAction then
								if bind.BindingOne and bind.BindingOne ~= "" then
									set.Bindings[bind.BindingOne] = bind.TheAction
								end
								if bind.BindingTwo and bind.BindingTwo ~= "" then
									set.Bindings[bind.BindingTwo] = bind.TheAction
								end
							end
						end
					end
					imported = imported + 1
				end
			end
		end
	end

	Binder_EnhancedDB.LegacyImported = true
	if imported > 0 then
		Msg(string.format("Imported %d set(s) from the old Binder addon into your Default profile.", imported))
	end
end

--------------------------------------------------------------------
-- Binding capture / apply helpers
--------------------------------------------------------------------

local function CaptureCurrentBindings()
	local snap = {}
	for i = 1, GetNumBindings() do
		local action, key1, key2 = GetBinding(i)
		if action then
			if key1 and key1 ~= "" then snap[key1] = action end
			if key2 and key2 ~= "" then snap[key2] = action end
		end
	end
	return snap
end

-- Loads the given binding set (1=account, 2=character) into the active
-- keybind table, captures a snapshot of what was there, clears it, applies
-- the new bindings table, and saves back to that same binding set.
local function CaptureAndApplyToTarget(bindSetId, bindingsTable)
	LoadBindings(bindSetId)
	local snapshot = CaptureCurrentBindings()

	for i = 1, GetNumBindings() do
		local _, key1, key2 = GetBinding(i)
		if key1 and key1 ~= "" then SetBinding(key1) end
		if key2 and key2 ~= "" then SetBinding(key2) end
	end
	for key, action in pairs(bindingsTable) do
		if key and action then SetBinding(key, action) end
	end
	SaveBindings(bindSetId)

	return snapshot
end

local function RestoreToTarget(bindSetId, bindingsTable)
	LoadBindings(bindSetId)
	for i = 1, GetNumBindings() do
		local _, key1, key2 = GetBinding(i)
		if key1 and key1 ~= "" then SetBinding(key1) end
		if key2 and key2 ~= "" then SetBinding(key2) end
	end
	for key, action in pairs(bindingsTable) do
		if key and action then SetBinding(key, action) end
	end
	SaveBindings(bindSetId)
end

--------------------------------------------------------------------
-- Action bar capture / apply (spells, items, macros, mounts & pets)
--------------------------------------------------------------------

-- Covers the main bar plus the standard bonus/multi bars used in this
-- client version. Best-effort: most slot types restore reliably, but a
-- few edge cases may not carry over perfectly across characters --
-- that's expected and called out in the UI.
local ACTIONBAR_SLOT_MAX = 120

-- IMPORTANT: on this server/client, GetActionInfo() returns a *spellbook
-- index* for a spell action, not a real spell ID -- so it can't be saved
-- as-is and reused later (spellbook order can change between save and
-- restore, and it's not a valid input to spell-ID-based API calls like
-- GetSpellInfo). It has to be resolved to the spell's name+rank right
-- away, at save time, and then re-resolved back to whatever index that
-- name+rank currently sits at when restoring.
local function CaptureActionBars(skipMacros)
	local bars = {}
	for slot = 1, ACTIONBAR_SLOT_MAX do
		local actionType, id, subType = GetActionInfo(slot)
		if actionType and id then
			if actionType == "spell" and id > 0 and GetSpellName then
				local spellName, spellRank = GetSpellName(id, BOOKTYPE_SPELL)
				if spellName then
					bars[slot] = { t = "spell", name = spellName, rank = spellRank or "" }
				end
			elseif actionType == "item" then
				bars[slot] = { t = "item", id = id }
			elseif actionType == "macro" and GetMacroInfo and not skipMacros then
				local mName, mIcon, mBody = GetMacroInfo(id)
				-- Macro IDs 1-36 are the General (account-wide) bank, 37-54
				-- are the Character-specific bank in WotLK 3.3.5 (the
				-- General bank was expanded from 18 to 36 slots back in
				-- patch 3.0 -- 18 is only the Character-bank cap) --
				-- remember which one this came from so restore recreates it
				-- in the same bank instead of guessing based on whatever
				-- has free space at apply time.
				bars[slot] = { t = "macro", id = id, name = mName, icon = mIcon, body = mBody, per = id > 36 }
			elseif actionType == "companion" then
				-- Blizzard's own docs are explicit: companion list indices
				-- are UNSTABLE -- not guaranteed to map to the same
				-- companion even on the same character over time, let
				-- alone across different characters/accounts (order is
				-- roughly alphabetical but can shift on zoning/reload).
				-- Capturing the raw index alone (as this used to) meant
				-- restoring could silently summon the wrong mount, or
				-- nothing at all on a character with a different-length
				-- list. Capture the creature name too, as a stable
				-- identifier to re-resolve the current index by at apply
				-- time -- same fix already applied to spells and macros.
				local cName
				if GetCompanionInfo then
					local _, foundName = GetCompanionInfo(subType, id)
					cName = foundName
				end
				bars[slot] = { t = "companion", id = id, sub = subType, name = cName }
			end
			-- equipment sets intentionally not handled
		end
	end
	return bars
end

-- Counts how many action bar slots differ between a saved set and what's
-- currently on the bars, so the Apply confirmation can tell you about
-- pending action bar changes even when the keybinds themselves match
-- (e.g. you moved a spell to a different button without changing any key).
local function CountActionBarChanges(setBars)
	if type(setBars) ~= "table" or next(setBars) == nil then return 0 end
	local current = CaptureActionBars()
	local function SlotKey(d)
		if d.t == "spell" then return d.t .. "|" .. tostring(d.name) .. "|" .. tostring(d.rank or "") end
		return d.t .. "|" .. tostring(d.id) .. "|" .. tostring(d.sub or "")
	end
	local count = 0
	local seen = {}
	for slot, data in pairs(setBars) do
		seen[slot] = true
		local currentData = current[slot]
		if not currentData or SlotKey(currentData) ~= SlotKey(data) then count = count + 1 end
	end
	for slot in pairs(current) do
		if not seen[slot] then count = count + 1 end
	end
	return count
end

-- Applies a captured action bar layout. Builds a fresh spellbook-name and
-- macro-name lookup once per call (not per slot -- that was the freeze
-- bug), then for each slot: pick up the matching spell/item/macro/
-- companion, verify the cursor actually picked up the right thing via
-- GetCursorInfo() before placing it (this mirrors a known-working
-- restore addon for this server), then place it and clear the cursor.
-- Simple delayed-call helper (no C_Timer in this client). Originally lived
-- right before ApplyLinkedSetForTrigger (talent-switch auto-apply), which
-- only needed it for a post-auto-apply verification pass -- but
-- ApplyActionBars below (used by manual Apply too) now also needs it, for
-- the fresh-macro placement retry, so it has to be defined up here: it's a
-- local, and a local isn't visible to code that runs before its own
-- declaration.
local DelayFrame = CreateFrame("Frame")
DelayFrame:Hide()
local delayQueue = {}
DelayFrame:SetScript("OnUpdate", function(self, elapsed)
	local i = 1
	while i <= #delayQueue do
		local item = delayQueue[i]
		item.remaining = item.remaining - elapsed
		if item.remaining <= 0 then
			table.remove(delayQueue, i)
			pcall(item.fn)
		else
			i = i + 1
		end
	end
	if #delayQueue == 0 then self:Hide() end
end)
local function ScheduleDelayedCall(seconds, fn)
	table.insert(delayQueue, { remaining = seconds, fn = fn })
	DelayFrame:Show()
end

-- A macro named " " (or any other whitespace-only string) is a common
-- convention for making a macro look nameless in the UI while still
-- technically having a non-empty name -- but `name == ""` checks don't
-- catch it, so it was falling through to the NAMED-macro path everywhere:
-- matched/cached by that literal name string instead of by body content,
-- and shown as a blank, indistinguishable row in the bank-full replace
-- list instead of getting the body-preview treatment true blank names
-- get. Since many different macros can share that same whitespace name,
-- name-based matching/caching collapses them into "the same macro" the
-- same way plain blank names would without body-based matching -- and in
-- the replace list, indistinguishable rows mean the player can end up
-- clicking the wrong one and overwriting a macro they didn't mean to.
local function IsBlankMacroName(name)
	return not name or name:match("^%s*$") ~= nil
end

local function ApplyActionBars(bars, skipMacros)
	if type(bars) ~= "table" then return 0, 0, nil end

	-- skipMacros is passed in explicitly by the caller (the Apply dialog's
	-- own "Macros" checkbox, or the Auto-Apply setting's own "Macros"
	-- checkbox) so each context's choice is respected precisely. Only when
	-- a caller has no dialog of its own to ask (Undo/Rescue) does this fall
	-- back to the Options tab's general default.
	if skipMacros == nil then
		skipMacros = Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.SkipMacros
	end

	if UnitAffectingCombat and UnitAffectingCombat("player") then
		return 0, 0, "Can't restore action bars while in combat."
	end

	if not (PickupAction and ClearCursor and PlaceAction and GetActionInfo) then
		return 0, 0, "Action bar API not available on this client."
	end

	local spellCache = {}
	if GetSpellName then
		local i = 1
		while i <= 1024 do
			local sName, sRank = GetSpellName(i, BOOKTYPE_SPELL)
			if not sName then break end
			spellCache[sName] = i -- last occurrence wins: highest known rank
			if sRank and sRank ~= "" then spellCache[sName .. "\1" .. sRank] = i end
			i = i + 1
		end
	end

	-- Companion list indices are unstable (Blizzard's own docs), so build
	-- a name -> CURRENT index lookup fresh here, same pattern as spells
	-- above -- resolving by name at apply time instead of trusting the
	-- raw index captured at save time is what makes this portable across
	-- characters/accounts (and robust to the list simply reordering on
	-- the SAME character over time).
	local companionCache = {}
	if GetCompanionInfo and GetNumCompanions then
		for _, ctype in ipairs({ "MOUNT", "CRITTER" }) do
			local n = GetNumCompanions(ctype) or 0
			for i = 1, n do
				local _, cName = GetCompanionInfo(ctype, i)
				if cName then companionCache[ctype .. "\1" .. cName] = i end
			end
		end
	end

	-- Force-load the macro UI module -- like Equipment Manager, it's
	-- lazy-loaded, so GetMacroIconInfo/CreateMacro/EditMacro may not exist
	-- until this has been opened at least once in the session otherwise.
	if not (CreateMacro and GetMacroIconInfo) then
		if UIParentLoadAddOn then UIParentLoadAddOn("Blizzard_MacroUI")
		elseif LoadAddOn then LoadAddOn("Blizzard_MacroUI") end
	end

	local macroByName, macroBodyByIdx, macroByBlankBody = {}, {}, {}
	if GetMacroInfo then
		-- 54 total slots (36 General + 18 Character in WotLK 3.3.5) --
		-- scanning only to 36 would silently skip the entire Character
		-- bank, so name-matching would NEVER find an existing
		-- character-specific macro and CreateMacro would fire every
		-- single time one gets applied, guaranteeing a fresh duplicate
		-- on every apply.
		--
		-- Blank-named macros (name == "") can't be told apart by name at
		-- all -- every unnamed macro shares the same "" key. Matching them
		-- by name alone would make the SECOND unnamed macro found here
		-- look like "the same macro, just needs its body updated" as the
		-- FIRST one, silently overwriting it -- repeat for a third and the
		-- first two are gone, with the third one now showing in every slot
		-- that pointed to any of them. macroByBlankBody matches these by
		-- their exact body content instead, so different unnamed macros
		-- stay distinct.
		for i = 1, 54 do
			local mName, _, mBody = GetMacroInfo(i)
			if mName then
				macroByName[mName] = i
				macroBodyByIdx[i] = mBody
				if IsBlankMacroName(mName) and mBody then
					macroByBlankBody[mBody] = i
				end
			end
		end
	end

	-- Macros on this server are stored server-side, so a macro this addon
	-- just created via CreateMacro may not show up in a fresh GetMacroInfo
	-- scan yet if Apply is clicked again quickly (round-trip lag) -- the
	-- live scan above would then miss it and create ANOTHER duplicate.
	-- Binder_Enhanced.KnownMacros remembers what WE created, for as long
	-- as this session lasts, and fills that gap: trust our own record
	-- whenever the live scan doesn't (yet) show that name, as long as the
	-- slot we remember hasn't since been reassigned to something else.
	Binder_Enhanced.KnownMacros = Binder_Enhanced.KnownMacros or {}
	if GetMacroInfo then
		for name, knownIdx in pairs(Binder_Enhanced.KnownMacros) do
			if not IsBlankMacroName(name) and not macroByName[name] then
				local liveName, _, liveBody = GetMacroInfo(knownIdx)
				if liveName == nil or liveName == name then
					macroByName[name] = knownIdx
					macroBodyByIdx[knownIdx] = liveBody or macroBodyByIdx[knownIdx]
				else
					-- That slot now holds something else -- our record is
					-- stale (deleted and the id got reused), drop it.
					Binder_Enhanced.KnownMacros[name] = nil
				end
			end
		end
	end

	-- Same server-lag protection, extended to blank-named macros -- these
	-- were originally left out of the cache above over a collision
	-- worry that doesn't actually apply here: keying by exact BODY
	-- content (rather than the shared "" name) is already how
	-- macroByBlankBody itself tells different unnamed macros apart, so
	-- there's nothing extra to collide. Leaving them out meant unnamed
	-- macros stayed exposed to the exact duplicate-on-quick-reapply bug
	-- this cache exists to prevent.
	Binder_Enhanced.KnownBlankMacros = Binder_Enhanced.KnownBlankMacros or {}
	if GetMacroInfo then
		for body, knownIdx in pairs(Binder_Enhanced.KnownBlankMacros) do
			if not macroByBlankBody[body] then
				local liveName, _, liveBody = GetMacroInfo(knownIdx)
				if liveName == nil or (liveName == "" and liveBody == body) then
					macroByBlankBody[body] = knownIdx
					macroBodyByIdx[knownIdx] = body
				else
					Binder_Enhanced.KnownBlankMacros[body] = nil
				end
			end
		end
	end

	-- CreateMacro/EditMacro want an icon INDEX, not the texture path
	-- GetMacroInfo returns, so build that lookup once here too.
	local iconToIndex = {}
	if GetNumMacroIcons and GetMacroIconInfo then
		for i = 1, GetNumMacroIcons() do
			local path = GetMacroIconInfo(i)
			if path then iconToIndex[path] = i end
		end
	end

	ClearCursor()

	-- Wipe every slot first. Without this, any slot holding something that
	-- isn't part of the saved layout (e.g. a spell you moved after saving,
	-- or a slot that was empty when you saved) keeps its old content --
	-- so a spell can end up visible in both its old spot and its newly
	-- restored spot at once. pcall-wrapped so one bad slot can't silently
	-- abort the rest (WoW hides Lua errors from players by default, so an
	-- unguarded error here would look exactly like "nothing happened").
	local wipeErrors = 0
	for slot = 1, ACTIONBAR_SLOT_MAX do
		local ok, actionType, id = pcall(GetActionInfo, slot)
		if ok and (actionType or id) then
			local pOk = pcall(PickupAction, slot)
			pcall(ClearCursor)
			if not pOk then wipeErrors = wipeErrors + 1 end
		elseif not ok then
			wipeErrors = wipeErrors + 1
		end
	end

	local restored, skipped, applyErrors = 0, 0, 0
	local fullBankMacros = {}
	local pendingFullBank = {}
	local pendingFreshMacros = {}
	local fullBankAction = (Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.FullMacroBankAction) or "SKIP"

	for slot, data in pairs(bars) do
		local picked = false

		local ok = pcall(function()
			if data.t == "spell" and PickupSpell and data.name then
				local idx = spellCache[data.name .. "\1" .. (data.rank or "")] or spellCache[data.name]
				if idx then PickupSpell(idx, BOOKTYPE_SPELL); picked = true end
			elseif data.t == "item" and PickupItem and data.id then
				PickupItem(data.id); picked = true
			elseif data.t == "macro" and PickupMacro and not skipMacros then
				-- Exact match only, on name+body together (or body alone
				-- for a blank name, since name can't distinguish those at
				-- all) -- simpler and safer than trying to track
				-- ownership: if the body doesn't match exactly, this
				-- isn't treated as "the same macro that needs updating",
				-- it's just a different macro, and a fresh one gets
				-- created instead. WoW allows duplicate names, so the
				-- only cost of a false non-match is a harmless extra
				-- macro sitting alongside the old one -- never overwriting
				-- or losing anything that was already there, whether it's
				-- your own older macro or someone else's entirely
				-- unrelated one.
				local idx
				if not IsBlankMacroName(data.name) then
					local candidate = macroByName[data.name]
					if candidate and macroBodyByIdx[candidate] == data.body then
						idx = candidate
					end
				elseif data.body then
					idx = macroByBlankBody[data.body]
				end
				local bankFull = false
				local freshlyCreated = false
				if not idx and data.name and data.body and CreateMacro then
					-- Macro bank: this macro doesn't exist anymore (deleted
					-- or renamed) -- recreate it from what was saved, in the
					-- SAME bank (General/account vs Character) it was saved
					-- from. CreateMacro's real signature is (name, icon,
					-- body, perCharacter) -- perCharacter must be true for
					-- the Character bank and false/nil for the General
					-- bank. (Previously this always passed a truthy 4th
					-- argument here, which silently forced every recreated
					-- macro into the Character bank no matter which branch
					-- ran -- the 5th true/false argument had no effect.)
					--
					-- Deliberately NOT pre-checking GetNumMacros() against a
					-- hardcoded slot cap here -- the General bank's cap has
					-- differed across patches (18 pre-3.0, 36 from 3.0 on),
					-- and a private server's own implementation may not
					-- match either number exactly. Just attempt the create
					-- and react to whether the server actually granted it --
					-- correct regardless of what the real cap is.
					--
					-- CreateMacro is wrapped in its OWN pcall here (not just
					-- relying on the outer per-slot pcall) because this
					-- server throws a real Lua error when the bank is full
					-- rather than returning nil (confirmed: an uncaught
					-- error here was escaping straight to the generic
					-- "error(s) while restoring action bars" handler,
					-- skipping the bank-full detection below entirely --
					-- that, not the detection logic itself, was why neither
					-- the popup nor the skip message ever appeared).
					local iconIdx = (data.icon and iconToIndex[data.icon]) or 1
					local wantChar = data.per and true or false
					local createOk, createResult = pcall(CreateMacro, data.name, iconIdx, data.body, wantChar)
					idx = createOk and createResult or nil
					if not idx then
						if fullBankAction == "PICK" or fullBankAction == "AUTO" then
							-- Player has opted in to resolving this
							-- themselves -- queue it instead of just
							-- reporting it, so a follow-up dialog can offer
							-- to replace an existing macro in that bank.
							-- Left unfilled on THIS bar for now; the resolve
							-- dialog places it once resolved.
							bankFull = true
							table.insert(pendingFullBank, {
								slot = slot, name = data.name, body = data.body,
								icon = data.icon, iconIdx = iconIdx, wantChar = wantChar,
							})
						else
							-- Full bank: don't fall back to the stale saved
							-- id below (it may now belong to a totally
							-- different macro, or nothing) -- report it by
							-- name instead so the player knows to free up a
							-- slot, same as any other "couldn't restore
							-- this" case in this addon.
							bankFull = true
							local label = (not IsBlankMacroName(data.name) and data.name) or "(unnamed macro)"
							table.insert(fullBankMacros, label .. (wantChar and " (Character)" or " (General)"))
						end
					end
					if idx then
						freshlyCreated = true
						if not IsBlankMacroName(data.name) then
							macroByName[data.name] = idx
							Binder_Enhanced.KnownMacros[data.name] = idx
						elseif data.body then
							macroByBlankBody[data.body] = idx
							Binder_Enhanced.KnownBlankMacros[data.body] = idx
						end
						macroBodyByIdx[idx] = data.body
					end
				end
				if not idx and not bankFull then idx = data.id end
				if idx and not IsBlankMacroName(data.name) then Binder_Enhanced.KnownMacros[data.name] = idx end
				if idx and freshlyCreated then
					-- Just created server-side this same pass -- PickupMacro
					-- right now can grab nothing yet (see the round-trip-lag
					-- note above GetMacroInfo). Don't place it this pass;
					-- queue it and retry shortly, once it's actually synced,
					-- instead of leaving it unplaced until the player notices
					-- and clicks Apply again.
					table.insert(pendingFreshMacros, { slot = slot, idx = idx })
				elseif idx then
					PickupMacro(idx); picked = true
				end
			elseif data.t == "companion" and PickupCompanion and data.id then
				local ctype = data.sub or "MOUNT"
				-- Resolve by name against the CURRENT list first (portable
				-- across characters/accounts, and correct even if the
				-- list simply reordered on this same character) -- only
				-- fall back to the raw saved index for older data saved
				-- before this fix existed, which has no name to match by.
				local idx = (data.name and companionCache[ctype .. "\1" .. data.name]) or data.id
				PickupCompanion(ctype, idx); picked = true
			end
		end)

		if not ok then
			applyErrors = applyErrors + 1
			pcall(ClearCursor)
			skipped = skipped + 1
		elseif picked then
			local placeOk = pcall(function()
				local cursorType = GetCursorInfo and GetCursorInfo()
				-- Verified against Blizzard's own GetCursorInfo docs:
				-- cursorType for a companion pickup is literally
				-- "companion" (the MOUNT/CRITTER distinction only shows
				-- up in a separate subType return value) -- so this
				-- actually needs no special-casing at all; data.t already
				-- says "companion" for these. An earlier attempt here
				-- assumed cursorType would come back as "mount"/"pet"
				-- without verifying that against the docs first, which
				-- was wrong and silently broke companion placement.
				if not GetCursorInfo or cursorType == data.t then
					PlaceAction(slot)
					restored = restored + 1
				else
					skipped = skipped + 1
				end
			end)
			if not placeOk then applyErrors = applyErrors + 1; skipped = skipped + 1 end
			pcall(ClearCursor)
		else
			skipped = skipped + 1
		end
	end

	local errMsg = nil
	if wipeErrors > 0 or applyErrors > 0 then
		errMsg = string.format("%d error(s) while restoring action bars (see /console scriptErrors 1 for details).", wipeErrors + applyErrors)
	end
	if #fullBankMacros > 0 then
		local list = table.concat(fullBankMacros, ", ")
		local full = string.format("Macro bank full, couldn't recreate: %s. Delete a macro to free a slot.", list)
		errMsg = errMsg and (errMsg .. " " .. full) or full
	end

	if #pendingFreshMacros > 0 and ScheduleDelayedCall then
		local retryList = pendingFreshMacros
		local function retryFreshMacros()
			for _, item in ipairs(retryList) do
				pcall(function()
					PickupMacro(item.idx)
					local cursorType = GetCursorInfo and GetCursorInfo()
					if not GetCursorInfo or cursorType == "macro" then
						PlaceAction(item.slot)
					end
				end)
				pcall(ClearCursor)
			end
		end
		-- Two staggered attempts (same spacing used elsewhere in this file
		-- for other server round-trip-lag retries) -- redundant if the
		-- first one already worked, since re-placing the same macro on the
		-- same slot is harmless.
		ScheduleDelayedCall(0.3, retryFreshMacros)
		ScheduleDelayedCall(0.8, retryFreshMacros)
	end

	return restored, skipped, errMsg, pendingFullBank
end

--------------------------------------------------------------------
-- Save / Apply
--------------------------------------------------------------------

-- targets = { ACCOUNT = bool, CHARACTER = bool }
function Binder_Enhanced:SaveSetKeybinds(profileName, setName, target)
	local set = self:GetSet(profileName, setName)
	if not set then return false, "Set not found.", 0 end

	set.Bindings = CaptureCurrentBindings()
	set.Mode = (target == "CHARACTER") and "CHARACTER" or "ACCOUNT"
	set.BindingsTarget = set.Mode
	set.BindingsSavedAt = time()

	return true, nil, TableCount(set.Bindings)
end

function Binder_Enhanced:SaveSetBars(profileName, setName, skipMacros)
	local set = self:GetSet(profileName, setName)
	if not set then return false, "Set not found.", 0 end

	set.ActionBars = CaptureActionBars(skipMacros)
	set.ActionBarsSavedAt = time()

	return true, nil, TableCount(set.ActionBars)
end

function Binder_Enhanced:ApplySetKeybinds(profileName, setName, target)
	local set = self:GetSet(profileName, setName)
	if not set then return false, "Set not found.", 0 end

	Binder_EnhancedDB.Failsafe = Binder_EnhancedDB.Failsafe or {}
	local count = TableCount(set.Bindings)
	if target == "CHARACTER" then
		Binder_EnhancedDB.Failsafe.Character = CaptureAndApplyToTarget(BINDSET_CHARACTER, set.Bindings)
	else
		Binder_EnhancedDB.Failsafe.Account = CaptureAndApplyToTarget(BINDSET_ACCOUNT, set.Bindings)
	end

	set.LastAppliedAt = time()
	local profile = self:GetProfile(profileName)
	if profile then profile.LastUsedSet = setName end

	return true, nil, count
end

function Binder_Enhanced:ApplySetBars(profileName, setName, skipMacros)
	local set = self:GetSet(profileName, setName)
	if not set or type(set.ActionBars) ~= "table" or TableCount(set.ActionBars) == 0 then
		return false, "No action bars saved for this set.", 0, 0
	end

	Binder_EnhancedDB.Failsafe = Binder_EnhancedDB.Failsafe or {}
	Binder_EnhancedDB.Failsafe.ActionBars = CaptureActionBars()
	local restored, skipped, barErr, pendingFullBank = ApplyActionBars(set.ActionBars, skipMacros)

	set.LastAppliedAt = time()
	local profile = self:GetProfile(profileName)
	if profile then profile.LastUsedSet = setName end

	return true, barErr, restored, skipped, pendingFullBank
end

-- Combined apply, used by talent-spec auto-apply: it isn't interactive, so
-- it applies whatever the Set has (keybinds per its saved target, plus
-- action bars if any were saved) in one go rather than asking the player.
function Binder_Enhanced:ApplySet(profileName, setName, targets, skipBars, skipMacros)
	local set = self:GetSet(profileName, setName)
	if not set then return false, "Set not found.", 0 end

	Binder_EnhancedDB.Failsafe = Binder_EnhancedDB.Failsafe or {}
	local count = 0

	if targets.ACCOUNT then
		Binder_EnhancedDB.Failsafe.Account = CaptureAndApplyToTarget(BINDSET_ACCOUNT, set.Bindings)
		count = count + TableCount(set.Bindings)
	end
	if targets.CHARACTER then
		Binder_EnhancedDB.Failsafe.Character = CaptureAndApplyToTarget(BINDSET_CHARACTER, set.Bindings)
		count = count + TableCount(set.Bindings)
	end

	local barCount, barSkipped, barErr, pendingFullBank = 0, 0, nil, nil
	if not skipBars and type(set.ActionBars) == "table" and TableCount(set.ActionBars) > 0 then
		Binder_EnhancedDB.Failsafe.ActionBars = CaptureActionBars()
		barCount, barSkipped, barErr, pendingFullBank = ApplyActionBars(set.ActionBars, skipMacros)
	end

	set.LastAppliedAt = time()
	local profile = self:GetProfile(profileName)
	if profile then profile.LastUsedSet = setName end

	return true, barErr, count, barCount, barSkipped, pendingFullBank
end

function Binder_Enhanced:RestoreFailsafe()
	local fs = Binder_EnhancedDB.Failsafe
	if not fs or (not fs.Account and not fs.Character and not fs.ActionBars) then return false end
	if fs.Account then RestoreToTarget(BINDSET_ACCOUNT, fs.Account) end
	if fs.Character then RestoreToTarget(BINDSET_CHARACTER, fs.Character) end
	if fs.ActionBars then
		local _, _, barErr = ApplyActionBars(fs.ActionBars)
		if barErr then Msg(barErr) end
	end
	return true
end

--------------------------------------------------------------------
-- Share (send/receive a single Set via addon message)
--------------------------------------------------------------------

function Binder_Enhanced:SendSetToPlayer(profileName, setName, targetPlayer)
	local set = self:GetSet(profileName, setName)
	if not set then return end
	targetPlayer = strtrim(targetPlayer or "")
	if targetPlayer == "" then return end

	local dataString = setName .. "::" .. (set.Mode or "ACCOUNT") .. "::"
	for key, action in pairs(set.Bindings) do
		dataString = dataString .. key .. ":" .. action .. ";"
	end
	Binder_Enhanced.SendAddonMessage("Binder_EnhancedShare", dataString, "WHISPER", targetPlayer)
	Msg("Set '" .. setName .. "' sent to " .. targetPlayer .. ".")
end

function Binder_Enhanced:ReceiveSetFromPlayer(setName, mode, bindData, sender)
	local profileName = setName .. " (from " .. sender .. ")"
	local profile = self:CreateProfile(profileName)
	if not profile then return 0 end

	local finalSetName = setName
	local set = self:CreateSet(profileName, finalSetName)
	if not set then return 0 end

	set.Mode = mode == "CHARACTER" and "CHARACTER" or (mode == "BOTH" and "BOTH" or "ACCOUNT")
	set.Bindings = {}
	local count = 0
	for item in string.gmatch(bindData, "([^;]+)") do
		local k, a = string.match(item, "([^:]+):([^:]+)")
		if k and a then set.Bindings[k] = a; count = count + 1 end
	end
	return count, profileName, finalSetName
end

--------------------------------------------------------------------
-- Export / Import (a full Set, as one paste-able string -- unlike
-- SendSetToPlayer above, this includes ActionBars too, and doesn't
-- require both people to be online at once: LibSerialize turns the Set
-- into a flat string, LibDeflate compresses it and re-encodes it into a
-- form safe to paste into chat, Discord, or a forum post.
--------------------------------------------------------------------

local EXPORT_PREFIX = "!BE1!"

-- LibDeflate and LibSerialize register themselves ONLY inside LibStub's
-- own internal registry when loaded via .toc -- they do NOT become plain
-- globals named LibDeflate/LibSerialize just by being loaded. Referencing
-- those bare names directly (as earlier code here mistakenly did) is
-- always nil regardless of whether the libraries loaded fine -- has to
-- go through LibStub:GetLibrary explicitly.
local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
local LibSerialize = LibStub and LibStub:GetLibrary("LibSerialize", true)

-- Only the fields that matter for re-creating the Set elsewhere -- not
-- timestamps (meaningless once transferred) or TalentLink (a deprecated
-- field the rest of the addon is already migrating away from).
function Binder_Enhanced:ExportSet(profileName, setName)
	local set = self:GetSet(profileName, setName)
	if not set then return nil, "Set not found." end
	if not (LibSerialize and LibDeflate) then
		return nil, "Export requires LibSerialize and LibDeflate (missing -- check the addon's Libs folder)."
	end

	local payload = {
		Name = set.Name,
		Description = set.Description,
		Mode = set.Mode,
		Bindings = set.Bindings,
		BindingsTarget = set.BindingsTarget,
		ActionBars = set.ActionBars,
		TalentEquipTarget = set.TalentEquipTarget,
	}

	local ok, serialized = pcall(function() return LibSerialize:Serialize(payload) end)
	if not ok or not serialized then return nil, "Couldn't serialize this set." end

	local compressed = LibDeflate:CompressDeflate(serialized)
	if not compressed then return nil, "Couldn't compress this set." end

	local printable = LibDeflate:EncodeForPrint(compressed)
	if not printable then return nil, "Couldn't encode this set for export." end

	return EXPORT_PREFIX .. printable
end

-- Reverses ExportSet: decode -> decompress -> deserialize -> new Set.
-- targetProfileName is optional -- when omitted, mirrors ReceiveSetFromPlayer's
-- naming convention so imported and whisper-received sets look consistent.
function Binder_Enhanced:ImportSetString(str, targetProfileName)
	if not (LibSerialize and LibDeflate) then
		return nil, "Import requires LibSerialize and LibDeflate (missing -- check the addon's Libs folder)."
	end
	str = strtrim(str or "")
	if str == "" then return nil, "Nothing to import." end

	local body = string.match(str, "^" .. EXPORT_PREFIX .. "(.+)$")
	if not body then
		return nil, "Doesn't look like a Binder Enhanced export string (missing or wrong " .. EXPORT_PREFIX .. " prefix)."
	end

	local compressed = LibDeflate:DecodeForPrint(body)
	if not compressed then return nil, "Couldn't decode this string -- it may be incomplete or corrupted." end

	local serialized = LibDeflate:DecompressDeflate(compressed)
	if not serialized then return nil, "Couldn't decompress this string -- it may be incomplete or corrupted." end

	local ok, payload = LibSerialize:Deserialize(serialized)
	if not ok or type(payload) ~= "table" then
		return nil, "Couldn't read this set's data -- it may be corrupted or from an incompatible version."
	end

	local setName = (type(payload.Name) == "string" and payload.Name ~= "") and payload.Name or "Imported Set"
	local profileName = targetProfileName or (setName .. " (imported)")
	local profile = self:CreateProfile(profileName)
	if not profile then return nil, "Couldn't create a profile for this import." end

	local set = self:CreateSet(profileName, setName)
	if not set then return nil, "Couldn't create this set (name may already exist in that profile)." end

	set.Description = type(payload.Description) == "string" and payload.Description or ""
	set.Mode = payload.Mode == "CHARACTER" and "CHARACTER" or (payload.Mode == "BOTH" and "BOTH" or "ACCOUNT")
	set.Bindings = type(payload.Bindings) == "table" and payload.Bindings or {}
	set.BindingsTarget = payload.BindingsTarget
	set.ActionBars = type(payload.ActionBars) == "table" and payload.ActionBars or nil
	set.TalentEquipTarget = type(payload.TalentEquipTarget) == "string" and payload.TalentEquipTarget or nil

	local bindCount = TableCount(set.Bindings)
	local barCount = set.ActionBars and TableCount(set.ActionBars) or 0
	local macroCount = 0
	if set.ActionBars then
		for _, data in pairs(set.ActionBars) do
			if data.t == "macro" then macroCount = macroCount + 1 end
		end
	end
	return true, profileName, setName, bindCount, barCount, macroCount
end

--------------------------------------------------------------------
-- UI: Main frame + tabs
--------------------------------------------------------------------

local UI = CreateFrame("Frame", "Binder_EnhancedFrame", UIParent)
UI:SetWidth(520); UI:SetHeight(560); UI:SetPoint("CENTER")
UI:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
UI:SetMovable(true); UI:EnableMouse(true); UI:RegisterForDrag("LeftButton")
UI:SetScript("OnDragStart", function(self) self:StartMoving() end)
UI:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
UI:SetResizable(true)
-- Min size must fit the widest tab content (Options tab notes/checkboxes
-- are fixed at 460px wide, positioned ~5px from the panel edge) and the
-- tallest tab content (Options tab's full stacked list, which has no
-- scroll frame) -- otherwise shrinking the window pushes that content
-- past the frame border instead of actually reflowing it.
-- Options tab content now scrolls internally, so the window's own min
-- size only needs to fit that tab's fixed content WIDTH (460px notes +
-- margins + the scrollbar) -- height can go back down to something
-- reasonable since the Options tab no longer needs to physically contain
-- all of its content at once.
UI:SetMinResize(520, 420)
UI:SetMaxResize(900, 700)
UI:Hide()
tinsert(UISpecialFrames, "Binder_EnhancedFrame")

local ResizeGrip = CreateFrame("Button", nil, UI)
ResizeGrip:SetWidth(16); ResizeGrip:SetHeight(16)
ResizeGrip:SetPoint("BOTTOMRIGHT", -4, 4)
ResizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
ResizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
ResizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
ResizeGrip:SetScript("OnMouseDown", function() UI:StartSizing("BOTTOMRIGHT") end)
ResizeGrip:SetScript("OnMouseUp", function() UI:StopMovingOrSizing() end)

UI.Selected = { profile = nil, set = nil }
UI.Expanded = {}

local Title = UI:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
Title:SetPoint("TOP", 0, -14); Title:SetText("Binder Enhanced")

local VersionText = UI:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
VersionText:SetPoint("TOP", Title, "BOTTOM", 0, -2)
VersionText:SetText("v" .. Binder_Enhanced.Version)

local Close = CreateFrame("Button", nil, UI, "UIPanelCloseButton")
Close:SetPoint("TOPRIGHT", -5, -5)
Close:SetScript("OnClick", function() UI:Hide() end)

-- Tabs
local TabProfiles = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
TabProfiles:SetWidth(115); TabProfiles:SetHeight(22)
TabProfiles:SetPoint("TOPLEFT", 15, -48)
TabProfiles:SetText("Profiles & Sets")

local TabLinks = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
TabLinks:SetWidth(90); TabLinks:SetHeight(22)
TabLinks:SetPoint("LEFT", TabProfiles, "RIGHT", 4, 0)
TabLinks:SetText("Links")

local TabSettings = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
TabSettings:SetWidth(90); TabSettings:SetHeight(22)
TabSettings:SetPoint("LEFT", TabLinks, "RIGHT", 4, 0)
TabSettings:SetText("Settings")

local Divider = UI:CreateTexture(nil, "ARTWORK")
Divider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
Divider:SetHeight(2)
Divider:SetPoint("TOPLEFT", 15, -76)
Divider:SetPoint("TOPRIGHT", -15, -76)

local PanelProfiles = CreateFrame("Frame", nil, UI)
PanelProfiles:SetPoint("TOPLEFT", 10, -86)
PanelProfiles:SetPoint("BOTTOMRIGHT", -10, 10)

local PanelSettings = CreateFrame("Frame", nil, UI)
PanelSettings:SetPoint("TOPLEFT", 10, -86)
PanelSettings:SetPoint("BOTTOMRIGHT", -10, 10)
PanelSettings:Hide()

local PanelOptions = CreateFrame("Frame", nil, UI)
PanelOptions:SetPoint("TOPLEFT", 10, -86)
PanelOptions:SetPoint("BOTTOMRIGHT", -10, 10)
PanelOptions:Hide()

local function ShowTab(which)
	PanelProfiles:Hide(); PanelSettings:Hide(); PanelOptions:Hide()
	TabProfiles:Enable(); TabLinks:Enable(); TabSettings:Enable()
	if which == "profiles" then
		PanelProfiles:Show(); TabProfiles:Disable()
	elseif which == "links" then
		PanelSettings:Show(); TabLinks:Disable()
		Binder_Enhanced:RefreshSettingsTab()
	else
		PanelOptions:Show(); TabSettings:Disable()
		Binder_Enhanced:RefreshOptionsTab()
	end
end
TabProfiles:SetScript("OnClick", function() ShowTab("profiles") end)
TabLinks:SetScript("OnClick", function() ShowTab("links") end)
TabSettings:SetScript("OnClick", function() ShowTab("settings") end)

--------------------------------------------------------------------
-- Panel: Profiles & Sets tree list
--------------------------------------------------------------------

local FilterBox = CreateFrame("EditBox", nil, PanelProfiles, "InputBoxTemplate")
FilterBox:SetPoint("TOPLEFT", 10, -6)
FilterBox:SetWidth(150); FilterBox:SetHeight(20)
FilterBox:SetAutoFocus(false)
FilterBox:SetMaxLetters(50)

local FilterBoxLabel = PanelProfiles:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
FilterBoxLabel:SetPoint("BOTTOMLEFT", FilterBox, "TOPLEFT", 2, 1)
FilterBoxLabel:SetText("Search")

UI.Filter = { text = "", mode = "ALL", sort = "NAME" }

FilterBox:SetScript("OnTextChanged", function(s)
	UI.Filter.text = string.lower(s:GetText() or "")
	Binder_Enhanced:RefreshList()
end)
FilterBox:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus() end)
FilterBox:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)

local UpdateFilterButtonStates

local function MakeFilterToggle(label, value, x)
	local b = CreateFrame("Button", nil, PanelProfiles, "UIPanelButtonTemplate")
	b:SetWidth(64); b:SetHeight(18); b:SetPoint("TOPLEFT", x, -30)
	b:SetText(label)
	b:SetScript("OnClick", function()
		UI.Filter.mode = value
		UpdateFilterButtonStates()
		Binder_Enhanced:RefreshList()
	end)
	return b
end
local FilterAllBtn = MakeFilterToggle("All", "ALL", 6)
local FilterKBBtn = MakeFilterToggle("Keybinds", "KEYBINDS", 72)
local FilterABBtn = MakeFilterToggle("Bars", "BARS", 148)

local SortToggleBtn = CreateFrame("Button", nil, PanelProfiles, "UIPanelButtonTemplate")
SortToggleBtn:SetWidth(70); SortToggleBtn:SetHeight(18); SortToggleBtn:SetPoint("TOPLEFT", 208, -30)
SortToggleBtn:SetText("Sort: Name")
SortToggleBtn:SetScript("OnClick", function(s)
	UI.Filter.sort = (UI.Filter.sort == "NAME") and "DATE" or "NAME"
	s:SetText(UI.Filter.sort == "NAME" and "Sort: Name" or "Sort: Date")
	Binder_Enhanced:RefreshList()
end)

UpdateFilterButtonStates = function()
	if UI.Filter.mode == "ALL" then FilterAllBtn:Disable() else FilterAllBtn:Enable() end
	if UI.Filter.mode == "KEYBINDS" then FilterKBBtn:Disable() else FilterKBBtn:Enable() end
	if UI.Filter.mode == "BARS" then FilterABBtn:Disable() else FilterABBtn:Enable() end
end
UpdateFilterButtonStates()

local Scroll = CreateFrame("ScrollFrame", "Binder_EnhancedScrollFrame", PanelProfiles, "UIPanelScrollFrameTemplate")
Scroll:SetPoint("TOPLEFT", 0, -52); Scroll:SetWidth(280); Scroll:SetHeight(228)

local Content = CreateFrame("Frame")
Content:SetWidth(260); Content:SetHeight(310)
Scroll:SetScrollChild(Content)
PanelProfiles.Rows = {}

--------------------------------------------------------------------
-- Dedicated, directly-editable description box (used for both
-- creating a new Profile/Set and editing an existing one).
--------------------------------------------------------------------

local DescFrame = CreateFrame("Frame", nil, PanelProfiles)
DescFrame:SetPoint("BOTTOMLEFT", 0, 0)
DescFrame:SetWidth(280); DescFrame:SetHeight(64)
DescFrame:SetBackdrop({
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 8, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
DescFrame:SetBackdropColor(0, 0, 0, 0.35)

local DescLabel = DescFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
DescLabel:SetPoint("TOPLEFT", 5, -4)
DescLabel:SetText("Description:")

local DescEditBox = CreateFrame("EditBox", nil, DescFrame)
DescEditBox:SetPoint("TOPLEFT", 6, -17)
DescEditBox:SetPoint("BOTTOMRIGHT", -6, 4)
DescEditBox:SetMultiLine(true)
DescEditBox:SetAutoFocus(false)
DescEditBox:SetFontObject(GameFontHighlightSmall)
DescEditBox:SetMaxLetters(500)
DescEditBox:EnableMouse(true)
DescEditBox:SetJustifyH("LEFT")
DescEditBox:SetJustifyV("TOP")
DescEditBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
DescEditBox:SetScript("OnEditFocusLost", function(s)
	local sel = UI.Selected
	if not sel.profile then return end
	local text = s:GetText()
	if sel.set then
		Binder_Enhanced:SetSetDescription(sel.profile, sel.set, text)
	else
		Binder_Enhanced:SetProfileDescription(sel.profile, text)
	end
end)
DescEditBox:EnableMouse(false)
DescEditBox:EnableKeyboard(false)

-- Loads the currently selected Profile/Set's description into the box.
-- Skipped while the box has focus so it never clobbers active typing.
local function SyncDescriptionBox()
	if DescEditBox:HasFocus() then return end
	local sel = UI.Selected
	if not sel.profile then
		DescEditBox:SetText("")
		DescEditBox:EnableMouse(false); DescEditBox:EnableKeyboard(false)
		DescLabel:SetText("|cff888888Select a profile or set to add a description.|r")
		return
	end
	DescEditBox:EnableMouse(true); DescEditBox:EnableKeyboard(true)
	local text
	if sel.set then
		local set = Binder_Enhanced:GetSet(sel.profile, sel.set)
		text = set and set.Description or ""
		DescLabel:SetText("Description for '" .. sel.set .. "':")
	else
		local profile = Binder_Enhanced:GetProfile(sel.profile)
		text = profile and profile.Description or ""
		DescLabel:SetText("Description for '" .. sel.profile .. "':")
	end
	DescEditBox:SetText(text or "")
end
Binder_Enhanced.SyncDescriptionBox = SyncDescriptionBox

UI:SetScript("OnSizeChanged", function(self, w, h)
	local panelW, panelH = PanelProfiles:GetWidth(), PanelProfiles:GetHeight()
	local scrollW = math.max(200, panelW - 165)
	Scroll:SetWidth(scrollW)
	Scroll:SetHeight(math.max(100, panelH - 52 - 64))
	Content:SetWidth(math.max(180, scrollW - 20))
	DescFrame:SetWidth(panelW)
end)

--------------------------------------------------------------------
-- Panel: Confirm / diff popup (used for Apply)
--------------------------------------------------------------------

local ConfirmFrame = CreateFrame("Frame", "Binder_EnhancedConfirmFrame", UIParent)
ConfirmFrame:SetWidth(280); ConfirmFrame:SetHeight(480)
ConfirmFrame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
ConfirmFrame:SetFrameStrata("DIALOG")
ConfirmFrame:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
ConfirmFrame:SetMovable(true)
ConfirmFrame:EnableMouse(true)
ConfirmFrame:RegisterForDrag("LeftButton")
ConfirmFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
ConfirmFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
ConfirmFrame:Hide()

local ConfirmTitle = ConfirmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
ConfirmTitle:SetPoint("TOP", 0, -15); ConfirmTitle:SetText("Apply Set")

local function MakeCheckButton(parent, label, x, y)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetWidth(22); cb:SetHeight(22)
	cb:SetPoint("TOPLEFT", x, y)
	local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
	text:SetText(label)
	cb.text = text
	return cb
end

local ApplyKeybindsCB = MakeCheckButton(ConfirmFrame, "Keybinds", 15, -40)
local ApplyBarsCB = MakeCheckButton(ConfirmFrame, "Bars", 105, -40)
local ApplyBothCB = MakeCheckButton(ConfirmFrame, "Both", 185, -40)

-- Sits right under Bars (its sibling, not the Keybind-target section below)
-- since it's a sub-option of Bars, not related to Account/Character at all.
local ApplyMacrosCB = MakeCheckButton(ConfirmFrame, "Include Macros", 15, -64)

local ApplyTargetLabel = ConfirmFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ApplyTargetLabel:SetPoint("TOPLEFT", 15, -88)
ApplyTargetLabel:SetText("Keybind target:")

local ApplyAccountRadio = MakeCheckButton(ConfirmFrame, "Account", 15, -106)
local ApplyCharacterRadio = MakeCheckButton(ConfirmFrame, "Character", 115, -106)

local UpdateApplyFrameVisibility
UpdateApplyFrameVisibility = function()
	local showTarget = ApplyKeybindsCB:GetChecked() and true or false
	if showTarget then ApplyTargetLabel:Show(); ApplyAccountRadio:Show(); ApplyCharacterRadio:Show()
	else ApplyTargetLabel:Hide(); ApplyAccountRadio:Hide(); ApplyCharacterRadio:Hide() end
	local barsChecked = ApplyBarsCB:GetChecked() and true or false
	if barsChecked then ApplyMacrosCB:Show(); ApplyMacrosCB:Enable()
	else ApplyMacrosCB:Hide(); ApplyMacrosCB:Disable() end
end

ApplyBothCB:SetScript("OnClick", function(self)
	if self:GetChecked() then
		if ConfirmFrame.KeybindsAvailable then ApplyKeybindsCB:SetChecked(true) end
		ApplyKeybindsCB:Disable()
		if ConfirmFrame.BarsAvailable then ApplyBarsCB:SetChecked(true) end
		ApplyBarsCB:Disable()
	else
		if ConfirmFrame.KeybindsAvailable then ApplyKeybindsCB:Enable() end
		if ConfirmFrame.BarsAvailable then ApplyBarsCB:Enable() end
	end
	UpdateApplyFrameVisibility()
end)
ApplyKeybindsCB:SetScript("OnClick", function(self)
	if not self:GetChecked() and ApplyBothCB:GetChecked() then
		ApplyBothCB:SetChecked(false)
		if ConfirmFrame.BarsAvailable then ApplyBarsCB:Enable() end
	end
	UpdateApplyFrameVisibility()
end)
ApplyBarsCB:SetScript("OnClick", function(self)
	if not self:GetChecked() and ApplyBothCB:GetChecked() then
		ApplyBothCB:SetChecked(false)
		if ConfirmFrame.KeybindsAvailable then ApplyKeybindsCB:Enable() end
	end
	UpdateApplyFrameVisibility()
end)
ApplyAccountRadio:SetScript("OnClick", function(self)
	if self:GetChecked() then ApplyCharacterRadio:SetChecked(false) else self:SetChecked(true) end
end)
ApplyCharacterRadio:SetScript("OnClick", function(self)
	if self:GetChecked() then ApplyAccountRadio:SetChecked(false) else self:SetChecked(true) end
end)

local ConfirmScroll = CreateFrame("ScrollFrame", "Binder_EnhancedConfirmScrollFrame", ConfirmFrame, "UIPanelScrollFrameTemplate")
ConfirmScroll:SetPoint("TOPLEFT", 15, -136); ConfirmScroll:SetWidth(230); ConfirmScroll:SetHeight(282)

local ConfirmContent = CreateFrame("Frame")
ConfirmContent:SetWidth(210); ConfirmContent:SetHeight(1)
ConfirmScroll:SetScrollChild(ConfirmContent)
ConfirmFrame.Rows = {}
ConfirmFrame.PendingProfile = nil
ConfirmFrame.PendingSet = nil

local function ClearConfirmRows()
	for _, row in ipairs(ConfirmFrame.Rows) do row:Hide() end
end

local function PopulateChanges(profileName, setName)
	ClearConfirmRows()
	local set = Binder_Enhanced:GetSet(profileName, setName)
	if not set then return false end

	local currentBinds = CaptureCurrentBindings()

	local changes = {}
	for key, action in pairs(set.Bindings) do
		if currentBinds[key] ~= action then
			table.insert(changes, { key = key, oldAction = currentBinds[key] or "EMPTY", newAction = action })
		end
		currentBinds[key] = nil
	end
	for key, oldAction in pairs(currentBinds) do
		table.insert(changes, { key = key, oldAction = oldAction, newAction = "EMPTY" })
	end

	local barChangeCount = CountActionBarChanges(set.ActionBars)
	local hasActionBarData = type(set.ActionBars) == "table" and next(set.ActionBars) ~= nil

	if #changes == 0 and barChangeCount == 0 then
		if hasActionBarData then
			Msg("Set already matches your current keybinds and action bars.")
		else
			Msg("Set already matches your current keybinds.")
		end
		return false
	end

	if barChangeCount > 0 then
		table.insert(changes, 1, { isBarSummary = true, count = barChangeCount })
	end

	local offset = -5
	for index, data in ipairs(changes) do
		local row = ConfirmFrame.Rows[index]
		if not row then
			row = ConfirmContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row:SetWidth(210); row:SetJustifyH("LEFT")
			ConfirmFrame.Rows[index] = row
		end
		row:SetPoint("TOPLEFT", 5, offset)
		if data.isBarSummary then
			row:SetText(string.format("|cffff9900[Action Bars]|r\n%d slot(s) will be updated", data.count))
		else
			local cleanOld = string.gsub(data.oldAction, "MULTIACTIONBAR%dBUTTON", "ActionBtn")
			local cleanNew = string.gsub(data.newAction, "MULTIACTIONBAR%dBUTTON", "ActionBtn")
			row:SetText(string.format("|cff33ff99[%s]|r\n%s -> %s", data.key, cleanOld, cleanNew))
		end
		row:Show()
		offset = offset - 32
	end
	ConfirmContent:SetHeight(math.abs(offset))
	return true
end

local function OpenApplyConfirm(profileName, setName)
	local set = Binder_Enhanced:GetSet(profileName, setName)
	if not set then return end
	ConfirmFrame.PendingProfile = profileName
	ConfirmFrame.PendingSet = setName
	ConfirmTitle:SetText("Apply: " .. setName)

	local hasKeybinds = type(set.Bindings) == "table" and TableCount(set.Bindings) > 0
	local hasBars = type(set.ActionBars) == "table" and TableCount(set.ActionBars) > 0
	ConfirmFrame.KeybindsAvailable = hasKeybinds
	ConfirmFrame.BarsAvailable = hasBars

	local restoreFlags = (Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.AutoApplyRestore) or {}

	ApplyBothCB:SetChecked(false)

	if hasKeybinds then
		ApplyKeybindsCB:Enable(); ApplyKeybindsCB:SetChecked(restoreFlags.KEYBINDS ~= false)
		ApplyAccountRadio:Enable(); ApplyCharacterRadio:Enable()
		if set.Mode == "CHARACTER" then
			ApplyCharacterRadio:SetChecked(true); ApplyAccountRadio:SetChecked(false)
		else
			ApplyAccountRadio:SetChecked(true); ApplyCharacterRadio:SetChecked(false)
		end
	else
		ApplyKeybindsCB:SetChecked(false); ApplyKeybindsCB:Disable()
	end

	if hasBars then
		ApplyBarsCB:Enable(); ApplyBarsCB:SetChecked(restoreFlags.BARS ~= false)
	else
		ApplyBarsCB:SetChecked(false); ApplyBarsCB:Disable()
	end
	ApplyMacrosCB:SetChecked(restoreFlags.MACROS ~= false)

	UpdateApplyFrameVisibility()

	if PopulateChanges(profileName, setName) then
		ConfirmFrame:Show()
	else
		ConfirmFrame:Hide()
	end
end
Binder_Enhanced.OpenApplyConfirm = OpenApplyConfirm

local ApplyConfirmBtn = CreateFrame("Button", nil, ConfirmFrame, "UIPanelButtonTemplate")
ApplyConfirmBtn:SetWidth(110); ApplyConfirmBtn:SetHeight(22)
ApplyConfirmBtn:SetPoint("BOTTOMLEFT", 15, 15)
ApplyConfirmBtn:SetText("Apply")
ApplyConfirmBtn:SetScript("OnClick", function()
	local profileName, setName = ConfirmFrame.PendingProfile, ConfirmFrame.PendingSet
	if not profileName or not setName then return end

	local doKeybinds = ConfirmFrame.KeybindsAvailable and ApplyKeybindsCB:GetChecked()
	local doBars = ConfirmFrame.BarsAvailable and ApplyBarsCB:GetChecked()
	if not doKeybinds and not doBars then
		Msg("Select Keybinds, Bars, or Both.")
		return
	end

	local parts = {}

	local set = Binder_Enhanced:GetSet(profileName, setName)
	local restoreFlags = (Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.AutoApplyRestore) or {}
	if set and set.TalentEquipTarget and restoreFlags.GEAR ~= false then
		local eqOk, eqMsg = Binder_Enhanced.EquipGearSetByName(set.TalentEquipTarget)
		if eqOk then
			table.insert(parts, "equipped '" .. set.TalentEquipTarget .. "'")
		elseif eqMsg then
			Msg(eqMsg)
		end
	end
	if doKeybinds then
		local target = ApplyCharacterRadio:GetChecked() and "CHARACTER" or "ACCOUNT"
		local ok, msg, count = Binder_Enhanced:ApplySetKeybinds(profileName, setName, target)
		if ok then
			table.insert(parts, string.format("%d keybinds (%s)", count, target == "CHARACTER" and "Character" or "Account"))
		elseif msg then
			Msg(msg)
		end
	end
	if doBars then
		local skipMacros = not (ApplyMacrosCB:GetChecked() and true or false)
		local ok, msg, restored, skipped, pendingFullBank = Binder_Enhanced:ApplySetBars(profileName, setName, skipMacros)
		if ok then
			if skipped and skipped > 0 then
				table.insert(parts, string.format("%d action bar slots (%d skipped)", restored, skipped))
			else
				table.insert(parts, string.format("%d action bar slots", restored))
			end
			if msg then Msg(msg) end
			if pendingFullBank and #pendingFullBank > 0 then
				Binder_Enhanced:ResolveFullMacroBank(pendingFullBank)
			end
		elseif msg then
			Msg(msg)
		end
	end

	if #parts > 0 then
		Msg(string.format("Set '%s' applied: %s. Use 'Undo / Rescue' if something breaks.", setName, table.concat(parts, ", ")))
		if Binder_Enhanced.RollbackButton then Binder_Enhanced.RollbackButton:Enable() end
	end
	ConfirmFrame:Hide()
	Binder_Enhanced:RefreshList()
end)

local CancelConfirmBtn = CreateFrame("Button", nil, ConfirmFrame, "UIPanelButtonTemplate")
CancelConfirmBtn:SetWidth(110); CancelConfirmBtn:SetHeight(22)
CancelConfirmBtn:SetPoint("BOTTOMRIGHT", -35, 15)
CancelConfirmBtn:SetText("Cancel")
CancelConfirmBtn:SetScript("OnClick", function() ConfirmFrame:Hide() end)

UI:HookScript("OnHide", function() ConfirmFrame:Hide() end)

--------------------------------------------------------------------
-- Save-target popup (used by the Save button)
--------------------------------------------------------------------

local SaveFrame = CreateFrame("Frame", nil, UI)
SaveFrame:SetWidth(320); SaveFrame:SetHeight(280)
SaveFrame:SetPoint("CENTER", UI, "CENTER", 0, 0)
SaveFrame:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
SaveFrame:SetFrameStrata("DIALOG")
SaveFrame:Hide()

local SaveFrameTitle = SaveFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
SaveFrameTitle:SetPoint("TOP", 0, -15)
SaveFrameTitle:SetText("Save:")

-- Stacked vertically (not side-by-side) since the Bars label's text can
-- grow quite long (e.g. "Bars (always on, see settings)"), which broke a
-- fixed horizontal gap to whatever sat next to it.
local SaveKeybindsCB = MakeCheckButton(SaveFrame, "Keybinds", 20, -40)
local SaveBarsCB = MakeCheckButton(SaveFrame, "Bars", 20, 0)
SaveBarsCB:SetPoint("TOPLEFT", SaveKeybindsCB, "BOTTOMLEFT", 0, -6)
local SaveMacrosCB = MakeCheckButton(SaveFrame, "Include Macros", 40, 0)
SaveMacrosCB:SetPoint("TOPLEFT", SaveBarsCB, "BOTTOMLEFT", 20, -4)
local SaveBothCB = MakeCheckButton(SaveFrame, "Both", 20, 0)
SaveBothCB:SetPoint("TOPLEFT", SaveMacrosCB, "BOTTOMLEFT", -20, -6)

local SaveTargetLabel = SaveFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
SaveTargetLabel:SetPoint("TOPLEFT", SaveBothCB, "BOTTOMLEFT", 0, -10)
SaveTargetLabel:SetText("Keybind target:")

local SaveAccountRadio = MakeCheckButton(SaveFrame, "Account", 20, 0)
SaveAccountRadio:SetPoint("TOPLEFT", SaveTargetLabel, "BOTTOMLEFT", 0, -6)
local SaveCharacterRadio = MakeCheckButton(SaveFrame, "Character", 0, 0)
-- Must be the SAME point type ("TOPLEFT") as the one MakeCheckButton set,
-- so this call REPLACES it instead of adding a second, competing anchor.
-- ("LEFT" vs "TOPLEFT" are different point types, so WoW kept both
-- anchors active at once, which pinned this checkbox to SaveFrame's
-- literal top-left corner as well as near SaveAccountRadio -- the
-- "floating in the wrong spot" bug.)
SaveCharacterRadio:SetPoint("TOPLEFT", SaveAccountRadio, "TOPRIGHT", 100, 0)

local SaveBarsNote = SaveFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
SaveBarsNote:SetPoint("TOPLEFT", SaveAccountRadio, "BOTTOMLEFT", 0, -10)
SaveBarsNote:SetWidth(280); SaveBarsNote:SetJustifyH("LEFT")
SaveBarsNote:SetText("Spells, items, macros, mounts/pets. Macros and mounts/pets can be less reliable if your list order changes.")

local UpdateSaveFrameVisibility
UpdateSaveFrameVisibility = function()
	local showTarget = SaveKeybindsCB:GetChecked() and true or false
	if showTarget then SaveTargetLabel:Show(); SaveAccountRadio:Show(); SaveCharacterRadio:Show()
	else SaveTargetLabel:Hide(); SaveAccountRadio:Hide(); SaveCharacterRadio:Hide() end
	local barsChecked = SaveBarsCB:GetChecked() and true or false
	if barsChecked then SaveBarsNote:Show() else SaveBarsNote:Hide() end
	-- Macros is a sub-option of Bars -- nothing to include/exclude when
	-- Bars itself isn't being saved at all.
	if barsChecked then SaveMacrosCB:Enable() else SaveMacrosCB:Disable(); SaveMacrosCB:SetChecked(false) end
end

SaveBothCB:SetScript("OnClick", function(self)
	if self:GetChecked() then
		SaveKeybindsCB:SetChecked(true); SaveKeybindsCB:Disable()
		SaveBarsCB:SetChecked(true); SaveBarsCB:Disable()
	else
		SaveKeybindsCB:Enable(); SaveBarsCB:Enable()
	end
	UpdateSaveFrameVisibility()
end)
SaveKeybindsCB:SetScript("OnClick", function(self)
	if not self:GetChecked() and SaveBothCB:GetChecked() then SaveBothCB:SetChecked(false); SaveBarsCB:Enable() end
	UpdateSaveFrameVisibility()
end)
SaveBarsCB:SetScript("OnClick", function(self)
	if not self:GetChecked() and SaveBothCB:GetChecked() then SaveBothCB:SetChecked(false); SaveKeybindsCB:Enable() end
	UpdateSaveFrameVisibility()
end)
SaveAccountRadio:SetScript("OnClick", function(self)
	if self:GetChecked() then SaveCharacterRadio:SetChecked(false) else self:SetChecked(true) end
end)
SaveCharacterRadio:SetScript("OnClick", function(self)
	if self:GetChecked() then SaveAccountRadio:SetChecked(false) else self:SetChecked(true) end
end)

local SaveConfirmBtn = CreateFrame("Button", nil, SaveFrame, "UIPanelButtonTemplate")
SaveConfirmBtn:SetWidth(85); SaveConfirmBtn:SetHeight(22)
SaveConfirmBtn:SetPoint("BOTTOMLEFT", 15, 12)
SaveConfirmBtn:SetText("Save")

local SaveCancelBtn = CreateFrame("Button", nil, SaveFrame, "UIPanelButtonTemplate")
SaveCancelBtn:SetWidth(85); SaveCancelBtn:SetHeight(22)
SaveCancelBtn:SetPoint("BOTTOMRIGHT", -15, 12)
SaveCancelBtn:SetText("Cancel")
SaveCancelBtn:SetScript("OnClick", function() SaveFrame:Hide() end)

local function OpenSavePrompt(profileName, setName)
	SaveFrame.ProfileName = profileName
	SaveFrame.SetName = setName
	SaveFrameTitle:SetText("Save '" .. setName .. "':")

	SaveBothCB:SetChecked(false)
	SaveKeybindsCB:Enable(); SaveKeybindsCB:SetChecked(true)
	SaveAccountRadio:Enable(); SaveCharacterRadio:Enable()
	local currentBindSet = GetCurrentBindingSet and GetCurrentBindingSet()
	if currentBindSet == BINDSET_CHARACTER then
		SaveCharacterRadio:SetChecked(true); SaveAccountRadio:SetChecked(false)
	else
		SaveAccountRadio:SetChecked(true); SaveCharacterRadio:SetChecked(false)
	end

	local barMode = (Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.ActionBarSaveMode) or "ASK"
	if barMode == "NEVER" then
		SaveBarsCB:SetChecked(false); SaveBarsCB:Disable()
		SaveBarsCB.text:SetText("Bars |cff888888(off in settings)|r")
	elseif barMode == "ALWAYS" then
		SaveBarsCB:SetChecked(true); SaveBarsCB:Disable()
		SaveBarsCB.text:SetText("Bars |cff888888(always on, see settings)|r")
	else
		SaveBarsCB:Enable(); SaveBarsCB:SetChecked(false)
		SaveBarsCB.text:SetText("Bars")
	end
	-- Default to including macros whenever Bars is checked -- matches the
	-- old behavior (macros were always part of Bars, no opt-out existed).
	SaveMacrosCB:SetChecked(SaveBarsCB:GetChecked() and true or false)

	UpdateSaveFrameVisibility()
	SaveFrame:Show()
end

SaveConfirmBtn:SetScript("OnClick", function()
	local doKeybinds = SaveKeybindsCB:GetChecked()
	local doBars = SaveBarsCB:GetChecked()
	if not doKeybinds and not doBars then
		Msg("Select Keybinds, Bars, or Both.")
		return
	end

	local parts = {}
	if doKeybinds then
		local target = SaveCharacterRadio:GetChecked() and "CHARACTER" or "ACCOUNT"
		local ok, msg, count = Binder_Enhanced:SaveSetKeybinds(SaveFrame.ProfileName, SaveFrame.SetName, target)
		if ok then
			table.insert(parts, string.format("%d keybinds (%s)", count, target == "CHARACTER" and "Character" or "Account"))
		else
			Msg(msg)
		end
	end
	if doBars then
		local skipMacros = not (SaveMacrosCB:GetChecked() and true or false)
		local ok, msg, count = Binder_Enhanced:SaveSetBars(SaveFrame.ProfileName, SaveFrame.SetName, skipMacros)
		if ok then
			table.insert(parts, string.format("%d action bar slots", count))
		else
			Msg(msg)
		end
	end

	if #parts > 0 then
		Msg(string.format("Set '%s' saved: %s.", SaveFrame.SetName, table.concat(parts, ", ")))
		Binder_Enhanced:RefreshList()
	end
	SaveFrame:Hide()
end)

--------------------------------------------------------------------
-- Tree list rendering
--------------------------------------------------------------------

function Binder_Enhanced:RefreshList()
	for _, row in ipairs(PanelProfiles.Rows) do row:Hide() end
	local index = 0
	local offset = -5

	for _, profileName in ipairs(self:GetProfileList()) do
		index = index + 1
		local row = PanelProfiles.Rows[index]
		if not row then
			row = CreateFrame("Button", nil, Content)
			row.SelectedBG = row:CreateTexture(nil, "BACKGROUND")
			row.SelectedBG:SetAllPoints()
			row.SelectedBG:SetTexture(0.35, 0.6, 1, 0.28)
			row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			row.Text:SetAllPoints(); row.Text:SetJustifyH("LEFT")
			row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
			PanelProfiles.Rows[index] = row
		end
		row:SetWidth(255); row:SetHeight(18)
		row:SetPoint("TOPLEFT", 0, offset)

		local profile = self:GetProfile(profileName)
		local expanded = UI.Expanded[profileName]
		local marker = expanded and "[-]" or "[+]"
		local talentTag = profile.TalentLink and (" |cffff9900[" .. profile.TalentLink .. "]|r") or ""
		local equipTag = profile.TalentEquipTarget and (" |cff66ccff[" .. profile.TalentEquipTarget .. "]|r") or ""
		row.Text:SetText(marker .. " " .. profileName .. " |cff888888(" .. TableCount(profile.Sets) .. " sets)|r" .. talentTag .. equipTag)
		row.ProfileName = profileName
		row.SetName = nil
		if UI.Selected.profile == profileName and not UI.Selected.set then row.SelectedBG:Show() else row.SelectedBG:Hide() end
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(s, button)
			if button == "RightButton" then
				Binder_Enhanced.ShowRowContextMenu(profileName, nil)
				return
			end
			UI.Expanded[profileName] = not UI.Expanded[profileName]
			UI.Selected.profile = profileName
			UI.Selected.set = nil
			ConfirmFrame:Hide()
			Binder_Enhanced:RefreshList()
		end)
		row:SetScript("OnEnter", function(s)
			GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
			GameTooltip:SetText(profileName, 1, 1, 1)
			if profile.Description and profile.Description ~= "" then
				GameTooltip:AddLine(profile.Description, 0.8, 0.8, 0.8, true)
			end
			GameTooltip:AddLine(TableCount(profile.Sets) .. " set(s)", 0.7, 0.7, 0.7)
			if profile.TalentLink then
				GameTooltip:AddLine("Talent Link: " .. profile.TalentLink, 1, 0.6, 0)
			end
			if profile.TalentEquipTarget then
				GameTooltip:AddLine("Auto-Equip Gear: " .. profile.TalentEquipTarget, 0.4, 0.8, 1)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:Show()
		offset = offset - 20

		if expanded then
			local visibleSets = {}
			for _, setName in ipairs(self:GetSetList(profileName)) do
				local set = self:GetSet(profileName, setName)
				local hasKB = type(set.Bindings) == "table" and TableCount(set.Bindings) > 0
				local hasAB = type(set.ActionBars) == "table" and TableCount(set.ActionBars) > 0
				local matchesType = (UI.Filter.mode == "ALL")
					or (UI.Filter.mode == "KEYBINDS" and hasKB)
					or (UI.Filter.mode == "BARS" and hasAB)
				local matchesText = UI.Filter.text == "" or string.find(string.lower(setName), UI.Filter.text, 1, true)
				if matchesType and matchesText then
					table.insert(visibleSets, setName)
				end
			end
			if UI.Filter.sort == "DATE" then
				table.sort(visibleSets, function(a, b)
					local sa, sb = self:GetSet(profileName, a), self:GetSet(profileName, b)
					local da = math.max(sa.BindingsSavedAt or 0, sa.ActionBarsSavedAt or 0)
					local db = math.max(sb.BindingsSavedAt or 0, sb.ActionBarsSavedAt or 0)
					if da ~= db then return da > db end
					return a < b
				end)
			end
			for _, setName in ipairs(visibleSets) do
				index = index + 1
				local srow = PanelProfiles.Rows[index]
				if not srow then
					srow = CreateFrame("Button", nil, Content)
					srow.SelectedBG = srow:CreateTexture(nil, "BACKGROUND")
					srow.SelectedBG:SetAllPoints()
					srow.SelectedBG:SetTexture(0.35, 0.6, 1, 0.28)
					srow.Text = srow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
					srow.Text:SetAllPoints(); srow.Text:SetJustifyH("LEFT")
					srow:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
					PanelProfiles.Rows[index] = srow
				end
				srow:SetWidth(240); srow:SetHeight(16)
				srow:SetPoint("TOPLEFT", 18, offset)

				local set = self:GetSet(profileName, setName)
				local setTalentTag = set.TalentLink and (" |cffff9900[" .. set.TalentLink .. "]|r") or ""
				local setEquipTag = set.TalentEquipTarget and (" |cff66ccff[" .. set.TalentEquipTarget .. "]|r") or ""
				local hasKB = type(set.Bindings) == "table" and TableCount(set.Bindings) > 0
				local hasAB = type(set.ActionBars) == "table" and TableCount(set.ActionBars) > 0
				local kbBadge = hasKB and "|cff33ff99KB|r" or "|cff555555KB|r"
				local abBadge = hasAB and "|cff33ff99Bars|r" or "|cff555555Bars|r"
				local isActive = profile.LastUsedSet == setName
				local nameColor = isActive and "|cffffd200" or "|cffffffff"
				srow.Text:SetText("- " .. nameColor .. setName .. "|r " .. kbBadge .. " " .. abBadge .. " |cff88ccff[" .. ModeLabel(set.Mode) .. "]|r" .. setTalentTag .. setEquipTag)
				srow.ProfileName = profileName
				srow.SetName = setName
				if UI.Selected.profile == profileName and UI.Selected.set == setName then srow.SelectedBG:Show() else srow.SelectedBG:Hide() end
				srow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				srow:SetScript("OnClick", function(s, button)
					if button == "RightButton" then
						Binder_Enhanced.ShowRowContextMenu(profileName, setName)
						return
					end
					UI.Selected.profile = profileName
					UI.Selected.set = setName
					ConfirmFrame:Hide()
					Binder_Enhanced:RefreshList()
				end)
				srow:SetScript("OnEnter", function(s)
					GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
					GameTooltip:SetText(setName, 1, 1, 1)
					if set.Description and set.Description ~= "" then
						GameTooltip:AddLine(set.Description, 0.8, 0.8, 0.8, true)
					end
					if hasKB then
						GameTooltip:AddLine(string.format("Keybinds: %d bound (%s)%s", TableCount(set.Bindings),
							set.BindingsTarget == "CHARACTER" and "Character" or "Account",
							set.BindingsSavedAt and (" -- saved " .. date("%b %d", set.BindingsSavedAt)) or ""), 0.4, 1, 0.6)
					else
						GameTooltip:AddLine("Keybinds: none saved", 0.6, 0.6, 0.6)
					end
					if hasAB then
						GameTooltip:AddLine(string.format("Action Bars: %d slot(s)%s", TableCount(set.ActionBars),
							set.ActionBarsSavedAt and (" -- saved " .. date("%b %d", set.ActionBarsSavedAt)) or ""), 0.4, 1, 0.6)
					else
						GameTooltip:AddLine("Action Bars: none saved", 0.6, 0.6, 0.6)
					end
					if set.TalentLink then
						GameTooltip:AddLine("Talent Link: " .. set.TalentLink, 1, 0.6, 0)
					end
					if set.TalentEquipTarget then
						GameTooltip:AddLine("Auto-Equip Gear: " .. set.TalentEquipTarget, 0.4, 0.8, 1)
					end
					if isActive then
						GameTooltip:AddLine("Last applied Set for this profile", 1, 0.82, 0)
					end
					GameTooltip:Show()
				end)
				srow:SetScript("OnLeave", function() GameTooltip:Hide() end)
				srow:Show()
				offset = offset - 16
			end
		end
	end
	Content:SetHeight(math.abs(offset) + 10)

	SyncDescriptionBox()
end

function Binder_Enhanced:ToggleUI()
	if UI:IsShown() then
		UI:Hide()
	else
		UI.Expanded[DEFAULT_PROFILE] = true
		self:RefreshList()
		ShowTab("profiles")
		UI:Show()
	end
end

--------------------------------------------------------------------
-- Action buttons
--------------------------------------------------------------------

local function CreateSideButton(txt, y, handler)
	local b = CreateFrame("Button", nil, PanelProfiles, "UIPanelButtonTemplate")
	b:SetWidth(150); b:SetHeight(20); b:SetPoint("TOPRIGHT", -5, y)
	b:SetText(txt); b:SetScript("OnClick", handler)
	return b
end

local NewMenu = CreateFrame("Frame", "Binder_EnhancedNewMenu", UI, "UIDropDownMenuTemplate")
UIDropDownMenu_SetWidth(NewMenu, 150)

local function OpenNewProfilePopup()
	StaticPopupDialogs["BINDER_ENHANCED_NEWPROFILE"] = {
		text = "New profile name:", button1 = "OK", button2 = "Cancel",
		hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
		OnAccept = function(s)
			local n = s.editBox:GetText()
			local profile, msg = Binder_Enhanced:CreateProfile(n)
			if profile then
				UI.Expanded[profile.Name] = true
				UI.Selected.profile = profile.Name; UI.Selected.set = nil
				Binder_Enhanced:RefreshList()
				SyncDescriptionBox()
				DescEditBox:SetFocus()
			else
				Msg(msg)
			end
		end,
	}
	StaticPopup_Show("BINDER_ENHANCED_NEWPROFILE")
end

local function PromptCreateSetThenSave(profileName)
	StaticPopupDialogs["BINDER_ENHANCED_NEWSET"] = {
		text = "New set name (in '" .. profileName .. "'):", button1 = "OK", button2 = "Cancel",
		hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
		OnAccept = function(s)
			local n = strtrim(s.editBox:GetText())
			local set, msg = Binder_Enhanced:CreateSet(profileName, n)
			if not set and not Binder_Enhanced:ProfileExists(profileName) then
				-- No profile to hold this Set (e.g. Default was deleted and
				-- no longer auto-recreates) -- make one using the Set's own
				-- name instead of just failing.
				local newProfile, pmsg = Binder_Enhanced:CreateProfile(n)
				if newProfile then
					profileName = newProfile.Name
					set, msg = Binder_Enhanced:CreateSet(profileName, n)
				end
			end
			if set then
				UI.Expanded[profileName] = true
				UI.Selected.profile = profileName; UI.Selected.set = set.Name
				Binder_Enhanced:RefreshList()
				SyncDescriptionBox()
				OpenSavePrompt(profileName, set.Name)
			else
				Msg(msg)
			end
		end,
	}
	StaticPopup_Show("BINDER_ENHANCED_NEWSET")
end

CreateSideButton("+ New...", 0, function()
	UIDropDownMenu_Initialize(NewMenu, function()
		local info = UIDropDownMenu_CreateInfo()
		info.text = "New Profile"
		info.notCheckable = true
		info.func = OpenNewProfilePopup
		UIDropDownMenu_AddButton(info)

		local targetProfile = UI.Selected.profile or DEFAULT_PROFILE
		info = UIDropDownMenu_CreateInfo()
		info.text = "New Set (in " .. targetProfile .. ")"
		info.notCheckable = true
		info.func = function() PromptCreateSetThenSave(targetProfile) end
		UIDropDownMenu_AddButton(info)
	end, "MENU")
	ToggleDropDownMenu(1, nil, NewMenu, "cursor", 0, 0)
end)

CreateSideButton("Save", -30, function()
	if not UI.Selected.set then
		PromptCreateSetThenSave(UI.Selected.profile or DEFAULT_PROFILE)
		return
	end
	OpenSavePrompt(UI.Selected.profile, UI.Selected.set)
end)

CreateSideButton("Apply", -52, function()
	if not UI.Selected.profile or not UI.Selected.set then
		Msg("Select a Set first.")
		return
	end
	OpenApplyConfirm(UI.Selected.profile, UI.Selected.set)
end)

local function OpenRenamePopup()
	local sel = UI.Selected
	if not sel.profile then Msg("Select a profile or set first."); return end
	local isSet = sel.set ~= nil
	StaticPopupDialogs["BINDER_ENHANCED_RENAME"] = {
		text = isSet and ("New name for set '" .. sel.set .. "':") or ("New name for profile '" .. sel.profile .. "':"),
		button1 = "OK", button2 = "Cancel",
		hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
		OnShow = function(s) s.editBox:SetText(isSet and sel.set or sel.profile); s.editBox:HighlightText() end,
		OnAccept = function(s)
			local n = strtrim(s.editBox:GetText())
			local ok
			if isSet then
				ok = Binder_Enhanced:RenameSet(sel.profile, sel.set, n)
				if ok then sel.set = n end
			else
				ok = Binder_Enhanced:RenameProfile(sel.profile, n)
				if ok then
					UI.Expanded[n] = UI.Expanded[sel.profile]
					UI.Expanded[sel.profile] = nil
					sel.profile = n
				end
			end
			if ok then Binder_Enhanced:RefreshList() else Msg("Could not rename -- name may already be in use.") end
		end,
	}
	StaticPopup_Show("BINDER_ENHANCED_RENAME")
end

local function OpenDuplicatePopup()
	local sel = UI.Selected
	if not sel.profile then Msg("Select a profile or set first."); return end
	local isSet = sel.set ~= nil
	StaticPopupDialogs["BINDER_ENHANCED_DUPLICATE"] = {
		text = isSet and ("Copy of set '" .. sel.set .. "' -- new name:") or ("Copy of profile '" .. sel.profile .. "' -- new name:"),
		button1 = "OK", button2 = "Cancel",
		hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
		OnAccept = function(s)
			local n = strtrim(s.editBox:GetText())
			local ok
			if isSet then
				ok = Binder_Enhanced:DuplicateSet(sel.profile, sel.set, n)
				if ok then sel.set = n end
			else
				ok = Binder_Enhanced:DuplicateProfile(sel.profile, n)
				if ok then UI.Expanded[n] = true; sel.profile = n; sel.set = nil end
			end
			if ok then Binder_Enhanced:RefreshList() else Msg("Could not duplicate -- name may already be in use.") end
		end,
	}
	StaticPopup_Show("BINDER_ENHANCED_DUPLICATE")
end

local function OpenDeletePopup()
	local sel = UI.Selected
	if not sel.profile then Msg("Select a profile or set first."); return end
	local isSet = sel.set ~= nil
	StaticPopupDialogs["BINDER_ENHANCED_DELETE"] = {
		text = isSet and ("Delete set '" .. sel.set .. "'?") or ("Delete profile '" .. sel.profile .. "' and all its sets?"),
		button1 = "Delete", button2 = "Cancel",
		timeout = 0, whileDead = true, hideOnEscape = true,
		OnAccept = function()
			if isSet then
				Binder_Enhanced:DeleteSet(sel.profile, sel.set)
				sel.set = nil
			else
				Binder_Enhanced:DeleteProfile(sel.profile)
				sel.profile = nil
			end
			ConfirmFrame:Hide()
			Binder_Enhanced.RecomputeActiveLinks()
			Binder_Enhanced:RefreshList()
		end,
	}
	StaticPopup_Show("BINDER_ENHANCED_DELETE")
end

-- Right-click context menu, shown from a row's OnClick handler. Bundles
-- Rename/Duplicate/Delete/Move so those don't need their own buttons.
local RowContextMenu = CreateFrame("Frame", "Binder_EnhancedRowContextMenu", UI, "UIDropDownMenuTemplate")
UIDropDownMenu_SetWidth(RowContextMenu, 170)

local function ShowRowContextMenu(profileName, setName)
	UI.Selected.profile = profileName
	UI.Selected.set = setName
	Binder_Enhanced:RefreshList()

	local isSet = setName ~= nil
	UIDropDownMenu_Initialize(RowContextMenu, function()
		local info = UIDropDownMenu_CreateInfo()
		info.text = isSet and setName or profileName
		info.isTitle = true
		info.notCheckable = true
		UIDropDownMenu_AddButton(info)

		info = UIDropDownMenu_CreateInfo()
		info.text = "Rename"; info.notCheckable = true
		info.func = OpenRenamePopup
		UIDropDownMenu_AddButton(info)

		info = UIDropDownMenu_CreateInfo()
		info.text = "Duplicate"; info.notCheckable = true
		info.func = OpenDuplicatePopup
		UIDropDownMenu_AddButton(info)

		if isSet then
			for _, pname in ipairs(Binder_Enhanced:GetProfileList()) do
				if pname ~= profileName then
					info = UIDropDownMenu_CreateInfo()
					info.text = "Move to: " .. pname
					info.notCheckable = true
					info.func = function()
						local ok, finalName = Binder_Enhanced:MoveSet(profileName, setName, pname)
						if ok then
							UI.Expanded[pname] = true
							UI.Selected.profile = pname; UI.Selected.set = finalName
							Binder_Enhanced:RefreshList()
							Msg("Set moved to '" .. pname .. "'.")
						end
					end
					UIDropDownMenu_AddButton(info)
				end
			end
		end

		info = UIDropDownMenu_CreateInfo()
		info.text = "Delete"; info.notCheckable = true
		info.func = OpenDeletePopup
		UIDropDownMenu_AddButton(info)
	end, "MENU")
	ToggleDropDownMenu(1, nil, RowContextMenu, "cursor", 0, 0)
end
Binder_Enhanced.ShowRowContextMenu = ShowRowContextMenu

CreateSideButton("Share Set", -82, function()
	local sel = UI.Selected
	if not sel.profile or not sel.set then Msg("Select a Set to share."); return end
	StaticPopupDialogs["BINDER_ENHANCED_SHARE"] = {
		text = "Recipient:", button1 = "Send", button2 = "Cancel",
		hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
		OnAccept = function(s) Binder_Enhanced:SendSetToPlayer(sel.profile, sel.set, s.editBox:GetText()) end,
	}
	StaticPopup_Show("BINDER_ENHANCED_SHARE")
end)

local RollbackBtn = CreateSideButton("Undo / Rescue", -104, function()
	if Binder_Enhanced:RestoreFailsafe() then
		Msg("Keybinds restored!")
	else
		Msg("No backup available.")
	end
end)
Binder_Enhanced.RollbackButton = RollbackBtn

--------------------------------------------------------------------
-- Export / Import dialogs (Set as a full paste-able string -- unlike
-- Share Set above, includes action bars/macros too and doesn't need the
-- other person online at the same time)
--------------------------------------------------------------------

local function MakeCopyBoxFrame(name, title)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetWidth(420); f:SetHeight(260)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	f:Hide()

	local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	titleText:SetPoint("TOP", 0, -14)
	titleText:SetText(title)

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOP", 0, -34)
	f.hint = hint

	local scroll = CreateFrame("ScrollFrame", name .. "Scroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 15, -54)
	scroll:SetWidth(370); scroll:SetHeight(150)

	local editBox = CreateFrame("EditBox", name .. "EditBox", scroll)
	editBox:SetMultiLine(true)
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetWidth(360)
	editBox:SetAutoFocus(false)
	editBox:SetScript("OnEscapePressed", function() f:Hide() end)
	scroll:SetScrollChild(editBox)
	f.editBox = editBox

	local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	closeBtn:SetWidth(90); closeBtn:SetHeight(22)
	closeBtn:SetPoint("BOTTOMRIGHT", -15, 12)
	closeBtn:SetText("Close")
	closeBtn:SetScript("OnClick", function() f:Hide() end)
	f.closeBtn = closeBtn

	return f
end

local ExportFrame = MakeCopyBoxFrame("Binder_EnhancedExportFrame", "Export Set")

-- WoW's addon API has no way to write to the OS clipboard -- there's no
-- such function exposed to Lua in this client. This button can't
-- literally "copy" for the player; what it CAN do is refocus the edit
-- box and re-select all the text, in case they'd clicked elsewhere in
-- the frame and lost the selection, so Ctrl+C is always one press away
-- without having to hunt for the text again.
local ExportCopyBtn = CreateFrame("Button", nil, ExportFrame, "UIPanelButtonTemplate")
ExportCopyBtn:SetWidth(90); ExportCopyBtn:SetHeight(22)
ExportCopyBtn:SetPoint("BOTTOMLEFT", 15, 12)
ExportCopyBtn:SetText("Select All")
ExportCopyBtn:SetScript("OnClick", function()
	local text = ExportFrame.editBox:GetText() or ""
	ExportFrame.editBox:SetFocus()
	ExportFrame.editBox:HighlightText(0, string.len(text))
	ExportFrame.hint:SetText("Text re-selected -- press |cffffd200Ctrl+C|r now to copy it.")
end)

local function ShowExportedString(setName, str, macroCount)
	ExportFrame.hint:SetText(string.format("Text is already selected -- press |cffffd200Ctrl+C|r now to copy '%s' (%d macro%s included).",
		setName, macroCount, macroCount == 1 and "" or "s"))
	ExportFrame.editBox:SetText(str)
	ExportFrame.editBox:SetFocus()
	ExportFrame.editBox:HighlightText(0, string.len(str or ""))
	ExportFrame:Show()
end

CreateSideButton("Export Set", -134, function()
	local sel = UI.Selected
	if not sel.profile or not sel.set then Msg("Select a Set to export."); return end
	local str, err = Binder_Enhanced:ExportSet(sel.profile, sel.set)
	if str then
		local set = Binder_Enhanced:GetSet(sel.profile, sel.set)
		local macroCount = 0
		if set and set.ActionBars then
			for _, data in pairs(set.ActionBars) do
				if data.t == "macro" then macroCount = macroCount + 1 end
			end
		end
		ShowExportedString(sel.set, str, macroCount)
	else
		Msg(err or "Export failed.")
	end
end)

local ImportFrame = MakeCopyBoxFrame("Binder_EnhancedImportFrame", "Import Set")
ImportFrame.hint:SetText("Paste an exported set string below, then click Import.")
ImportFrame.editBox:SetScript("OnEscapePressed", function() ImportFrame:Hide() end)

local ImportBtn = CreateFrame("Button", nil, ImportFrame, "UIPanelButtonTemplate")
ImportBtn:SetWidth(90); ImportBtn:SetHeight(22)
ImportBtn:SetPoint("BOTTOMLEFT", 15, 12)
ImportBtn:SetText("Import")
ImportBtn:SetScript("OnClick", function()
	local text = ImportFrame.editBox:GetText()
	local ok, profileName, setName, bindCount, barCount, macroCount = Binder_Enhanced:ImportSetString(text)
	if ok then
		Msg(string.format("Imported '%s' -> profile '%s' (%d keybinds, %d action bar slots, %d of them macros).",
			setName, profileName, bindCount, barCount, macroCount or 0))
		ImportFrame:Hide()
		ImportFrame.editBox:SetText("")
		UI.Expanded[profileName] = true
		UI.Selected.profile = profileName; UI.Selected.set = setName
		if UI:IsShown() then Binder_Enhanced:RefreshList() end
	else
		Msg(profileName or "Import failed.")
	end
end)

CreateSideButton("Import Set", -156, function()
	ImportFrame.editBox:SetText("")
	ImportFrame:Show()
	ImportFrame.editBox:SetFocus()
end)

--------------------------------------------------------------------
-- Panel: Talent Link & Settings
--------------------------------------------------------------------

local SettingsHeader = PanelSettings:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
SettingsHeader:SetPoint("TOPLEFT", 5, -5)
SettingsHeader:SetText("Talent Spec Link")

local SettingsSelLabel = PanelSettings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
SettingsSelLabel:SetPoint("TOPLEFT", SettingsHeader, "BOTTOMLEFT", 0, -8)
SettingsSelLabel:SetWidth(460); SettingsSelLabel:SetJustifyH("LEFT")

local BuildStatusLabel = PanelSettings:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
BuildStatusLabel:SetPoint("TOPLEFT", SettingsSelLabel, "BOTTOMLEFT", 0, -4)
BuildStatusLabel:SetWidth(460); BuildStatusLabel:SetJustifyH("LEFT")

local function TalentLinkButton(txt, x, y, handler)
	local b = CreateFrame("Button", nil, PanelSettings, "UIPanelButtonTemplate")
	b:SetWidth(140); b:SetHeight(22); b:SetPoint("TOPLEFT", x, y)
	b:SetText(txt); b:SetScript("OnClick", handler)
	return b
end

local function GetSelectedLinkable()
	local sel = UI.Selected
	if not sel.profile then return nil end
	if sel.set then
		return Binder_Enhanced:GetSet(sel.profile, sel.set), "Set '" .. sel.set .. "' (in '" .. sel.profile .. "')"
	else
		return Binder_Enhanced:GetProfile(sel.profile), "Profile '" .. sel.profile .. "'"
	end
end

-- Saved Talent Builds: an exact snapshot of every talent's rank, not just
-- which tree has the most points -- so two builds that share a dominant
-- tree but spend their points differently can be told apart and linked
-- separately.
local function CaptureTalentSignature()
	if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return nil end
	local parts = {}
	local numTabs = GetNumTalentTabs() or 3
	for tab = 1, numTabs do
		local numTalents = GetNumTalents(tab) or 0
		for ti = 1, numTalents do
			local _, _, _, _, rank = GetTalentInfo(tab, ti)
			table.insert(parts, tostring(rank or 0))
		end
	end
	if #parts == 0 then return nil end
	return table.concat(parts, ",")
end

-- Every class has exactly 3 talent tabs; pulling their real names straight
-- from the game (rather than showing 3 separate always-visible buttons)
-- keeps this to one dropdown covering both tree links and saved builds.
local TalentLinkDropdown = CreateFrame("Frame", "Binder_EnhancedTalentLinkDropdown", PanelSettings, "UIDropDownMenuTemplate")
UIDropDownMenu_SetWidth(TalentLinkDropdown, 180)

local TalentLinkBtn = TalentLinkButton("Link Talent...", 0, 0, function()
	local obj = GetSelectedLinkable()
	if not obj then return end
	UIDropDownMenu_Initialize(TalentLinkDropdown, function()
		if GetTalentTabInfo then
			for i = 1, 3 do
				local tname = select(1, GetTalentTabInfo(i))
				if tname then
					local info = UIDropDownMenu_CreateInfo()
					info.text = tname
					info.notCheckable = true
					info.func = function()
						obj.TalentLink = tname
						Binder_Enhanced.RecomputeActiveLinks()
						Binder_Enhanced:RefreshSettingsTab()
						Binder_Enhanced:RefreshList()
					end
					UIDropDownMenu_AddButton(info)
				end
			end
		end
		local names = {}
		for n in pairs(Binder_EnhancedDB.TalentSignatures or {}) do table.insert(names, n) end
		table.sort(names)
		if #names > 0 then
			local title = UIDropDownMenu_CreateInfo()
			title.text = "Saved Builds"; title.isTitle = true; title.notCheckable = true
			UIDropDownMenu_AddButton(title)
			for _, n in ipairs(names) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = n
				info.notCheckable = true
				info.func = function()
					obj.TalentLink = n
					Binder_Enhanced.RecomputeActiveLinks()
					Binder_Enhanced:RefreshSettingsTab()
					Binder_Enhanced:RefreshList()
				end
				UIDropDownMenu_AddButton(info)
			end
		end
	end, "MENU")
	ToggleDropDownMenu(1, nil, TalentLinkDropdown, "cursor", 0, 0)
end)
TalentLinkBtn:SetWidth(150)
TalentLinkBtn:ClearAllPoints()
TalentLinkBtn:SetPoint("TOPLEFT", BuildStatusLabel, "BOTTOMLEFT", 0, -10)

local SaveBuildBtn = TalentLinkButton("Save Build...", 0, 0, function()
	StaticPopupDialogs["BINDER_ENHANCED_SAVEBUILD"] = {
		text = "Name this talent build:", button1 = "Save", button2 = "Cancel",
		hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
		OnAccept = function(s)
			local n = strtrim(s.editBox:GetText())
			if n == "" then return end
			local sig = CaptureTalentSignature()
			if not sig then
				Msg("Could not read your talents.")
				return
			end
			Binder_EnhancedDB.TalentSignatures = Binder_EnhancedDB.TalentSignatures or {}
			Binder_EnhancedDB.TalentSignatures[n] = sig
			Msg("Saved current talent build as '" .. n .. "'.")
			Binder_Enhanced:RefreshSettingsTab()
		end,
	}
	StaticPopup_Show("BINDER_ENHANCED_SAVEBUILD")
end)
SaveBuildBtn:SetWidth(110)
SaveBuildBtn:ClearAllPoints()
SaveBuildBtn:SetPoint("LEFT", TalentLinkBtn, "RIGHT", 6, 0)

local BuildDeleteDropdown = CreateFrame("Frame", "Binder_EnhancedBuildDeleteDropdown", PanelSettings, "UIDropDownMenuTemplate")
UIDropDownMenu_SetWidth(BuildDeleteDropdown, 170)

local DeleteBuildBtn = TalentLinkButton("Delete Build...", 0, 0, function()
	local names = {}
	for n in pairs(Binder_EnhancedDB.TalentSignatures or {}) do table.insert(names, n) end
	table.sort(names)
	if #names == 0 then
		Msg("No saved talent builds to delete.")
		return
	end
	UIDropDownMenu_Initialize(BuildDeleteDropdown, function()
		for _, n in ipairs(names) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = n
			info.notCheckable = true
			info.func = function()
				Binder_EnhancedDB.TalentSignatures[n] = nil
				Msg("Deleted saved talent build '" .. n .. "'.")
				Binder_Enhanced:RefreshSettingsTab()
			end
			UIDropDownMenu_AddButton(info)
		end
	end, "MENU")
	ToggleDropDownMenu(1, nil, BuildDeleteDropdown, "cursor", 0, 0)
end)
DeleteBuildBtn:SetWidth(110)
DeleteBuildBtn:ClearAllPoints()
DeleteBuildBtn:SetPoint("LEFT", SaveBuildBtn, "RIGHT", 6, 0)

local UnlinkBtn = TalentLinkButton("Unlink", 0, 0, function()
	local obj = GetSelectedLinkable()
	if obj then
		obj.TalentLink = nil
		Binder_Enhanced.RecomputeActiveLinks()
		Binder_Enhanced:RefreshSettingsTab()
		Binder_Enhanced:RefreshList()
	end
end)
UnlinkBtn:SetWidth(70)
UnlinkBtn:ClearAllPoints()
UnlinkBtn:SetPoint("LEFT", DeleteBuildBtn, "RIGHT", 6, 0)

local TalentNote = PanelSettings:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
TalentNote:SetPoint("TOPLEFT", TalentLinkBtn, "BOTTOMLEFT", 0, -8)
TalentNote:SetWidth(460); TalentNote:SetJustifyH("LEFT")
TalentNote:SetText("An exact saved build wins over a tree-only link. A Set's own link wins over its Profile's.")

local EquipHeader = PanelSettings:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
EquipHeader:SetPoint("TOPLEFT", TalentNote, "BOTTOMLEFT", 0, -16)
EquipHeader:SetText("Auto-Equip Gear on Talent Link")

local AutoEquipRow2Label = PanelSettings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
AutoEquipRow2Label:SetPoint("TOPLEFT", EquipHeader, "BOTTOMLEFT", 0, -8)
AutoEquipRow2Label:SetWidth(460); AutoEquipRow2Label:SetJustifyH("LEFT")

local AutoEquipDropdown = CreateFrame("Frame", "Binder_EnhancedAutoEquipDropdown", PanelSettings, "UIDropDownMenuTemplate")
UIDropDownMenu_SetWidth(AutoEquipDropdown, 170)

local AutoEquipLinkBtn = TalentLinkButton("Link Gear Set...", 0, 0, function()
	local obj = GetSelectedLinkable()
	if not obj then return end
	if not (GetNumEquipmentSets and GetEquipmentSetInfo) then
		LoadAddOn("Blizzard_EquipmentManager")
	end
	if not (GetNumEquipmentSets and GetEquipmentSetInfo) then
		Msg("Equipment Manager not available.")
		return
	end
	local n = GetNumEquipmentSets() or 0
	if n == 0 then
		Msg("You don't have any Equipment Manager sets saved yet.")
		return
	end
	UIDropDownMenu_Initialize(AutoEquipDropdown, function()
		for i = 1, n do
			local setName = GetEquipmentSetInfo(i)
			if setName then
				local info = UIDropDownMenu_CreateInfo()
				info.text = setName
				info.notCheckable = true
				info.func = function()
					obj.TalentEquipTarget = setName
					Binder_Enhanced:RefreshSettingsTab()
					Binder_Enhanced:RefreshList()
				end
				UIDropDownMenu_AddButton(info)
			end
		end
	end, "MENU")
	ToggleDropDownMenu(1, nil, AutoEquipDropdown, "cursor", 0, 0)
end)
AutoEquipLinkBtn:SetWidth(175)
AutoEquipLinkBtn:ClearAllPoints()
AutoEquipLinkBtn:SetPoint("TOPLEFT", AutoEquipRow2Label, "BOTTOMLEFT", 0, -6)
local AutoEquipUnlinkBtn = TalentLinkButton("Unlink", 0, 0, function()
	local obj = GetSelectedLinkable()
	if obj then obj.TalentEquipTarget = nil; Binder_Enhanced:RefreshSettingsTab(); Binder_Enhanced:RefreshList() end
end)
AutoEquipUnlinkBtn:SetWidth(70)
AutoEquipUnlinkBtn:ClearAllPoints()
AutoEquipUnlinkBtn:SetPoint("LEFT", AutoEquipLinkBtn, "RIGHT", 6, 0)

local EquipNote = PanelSettings:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
EquipNote:SetPoint("TOPLEFT", AutoEquipLinkBtn, "BOTTOMLEFT", 0, -8)
EquipNote:SetWidth(460); EquipNote:SetJustifyH("LEFT")
EquipNote:SetText("Requires an Equipment Manager set (character pane). When this Set's Talent Link triggers (spec change), this gear gets equipped too.")

-- Options tab content lives in a scroll frame rather than requiring the
-- whole window to grow to fit it -- keeps manual resizing free to go back
-- down to a small minimum size regardless of how much this tab's content
-- grows in the future.
local OptionsScroll = CreateFrame("ScrollFrame", "Binder_EnhancedOptionsScroll", PanelOptions, "UIPanelScrollFrameTemplate")
OptionsScroll:SetPoint("TOPLEFT", 0, 0)
OptionsScroll:SetPoint("BOTTOMRIGHT", -22, 0)
local OptionsContent = CreateFrame("Frame", nil, OptionsScroll)
OptionsContent:SetWidth(480); OptionsContent:SetHeight(750)
OptionsScroll:SetScrollChild(OptionsContent)

local AutoApplyHeader = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
AutoApplyHeader:SetPoint("TOPLEFT", 5, -5)
AutoApplyHeader:SetText("Auto-Apply Behavior (Talent & Equipment)")

local function MakeRadio(label, value, x, y)
	local cb = CreateFrame("CheckButton", nil, OptionsContent, "UICheckButtonTemplate")
	cb:SetWidth(22); cb:SetHeight(22); cb:SetPoint("TOPLEFT", x, y)
	local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
	text:SetText(label)
	cb.value = value
	return cb
end

local RadioSilent = MakeRadio("Silent (no message)", "SILENT", 0, -30)
local RadioChat = MakeRadio("Chat message", "CHAT", 0, -55)
local RadioConfirm = MakeRadio("Full confirmation popup", "CONFIRM", 0, -80)

local function SetAutoApplyMode(mode)
	Binder_EnhancedDB.Settings.TalentAutoApplyMode = mode
	RadioSilent:SetChecked(mode == "SILENT")
	RadioChat:SetChecked(mode == "CHAT")
	RadioConfirm:SetChecked(mode == "CONFIRM")
	Binder_Enhanced:RefreshOptionsTab()
end
RadioSilent:SetScript("OnClick", function() SetAutoApplyMode("SILENT") end)
RadioChat:SetScript("OnClick", function() SetAutoApplyMode("CHAT") end)
RadioConfirm:SetScript("OnClick", function() SetAutoApplyMode("CONFIRM") end)

local ActionBarHeader = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
ActionBarHeader:SetPoint("TOPLEFT", RadioConfirm, "BOTTOMLEFT", 5, -16)
ActionBarHeader:SetText("Saving Action Bars With a Set")

local ActionBarNote = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ActionBarNote:SetPoint("TOPLEFT", ActionBarHeader, "BOTTOMLEFT", 0, -6)
ActionBarNote:SetWidth(460); ActionBarNote:SetJustifyH("LEFT")
ActionBarNote:SetText("Controls whether saving a Set also offers to include your action bars (spells, items, macros, mounts/pets).")

local RadioBarAsk = MakeRadio("Ask me every time I save", "ASK", 0, 0)
RadioBarAsk:SetPoint("TOPLEFT", ActionBarNote, "BOTTOMLEFT", -5, -10)
local RadioBarAlways = MakeRadio("Always include action bars", "ALWAYS", 0, 0)
RadioBarAlways:SetPoint("TOPLEFT", RadioBarAsk, "BOTTOMLEFT", 0, -4)
local RadioBarNever = MakeRadio("Never include action bars", "NEVER", 0, 0)
RadioBarNever:SetPoint("TOPLEFT", RadioBarAlways, "BOTTOMLEFT", 0, -4)

local function SetActionBarSaveMode(mode)
	Binder_EnhancedDB.Settings.ActionBarSaveMode = mode
	RadioBarAsk:SetChecked(mode == "ASK")
	RadioBarAlways:SetChecked(mode == "ALWAYS")
	RadioBarNever:SetChecked(mode == "NEVER")
end
RadioBarAsk:SetScript("OnClick", function() SetActionBarSaveMode("ASK") end)
RadioBarAlways:SetScript("OnClick", function() SetActionBarSaveMode("ALWAYS") end)
RadioBarNever:SetScript("OnClick", function() SetActionBarSaveMode("NEVER") end)

local BarPromptHeader = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
BarPromptHeader:SetPoint("TOPLEFT", RadioBarNever, "BOTTOMLEFT", 5, -16)
BarPromptHeader:SetText("Action Bar Fallback Prompt")

local BarPromptNote = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
BarPromptNote:SetPoint("TOPLEFT", BarPromptHeader, "BOTTOMLEFT", 0, -6)
BarPromptNote:SetWidth(460); BarPromptNote:SetJustifyH("LEFT")
BarPromptNote:SetText("Action bars are applied automatically along with keybinds. If that silently fails for some reason, this shows a manual click-to-apply prompt as a fallback. Off: no fallback prompt, bars just get skipped if the automatic attempt fails.")

local BarPromptToggle = CreateFrame("CheckButton", nil, OptionsContent, "UICheckButtonTemplate")
BarPromptToggle:SetWidth(22); BarPromptToggle:SetHeight(22)
BarPromptToggle:SetPoint("TOPLEFT", BarPromptNote, "BOTTOMLEFT", 0, -6)
local BarPromptToggleText = BarPromptToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
BarPromptToggleText:SetPoint("LEFT", BarPromptToggle, "RIGHT", 2, 1)
BarPromptToggleText:SetText("Show a fallback click prompt if bars fail to auto-apply (recommended)")
BarPromptToggle:SetScript("OnClick", function(self)
	Binder_EnhancedDB.Settings.BarAutoApplyPrompt = self:GetChecked() and true or false
end)

local SkipMacrosToggle = CreateFrame("CheckButton", nil, OptionsContent, "UICheckButtonTemplate")
SkipMacrosToggle:SetWidth(22); SkipMacrosToggle:SetHeight(22)
SkipMacrosToggle:SetPoint("TOPLEFT", BarPromptToggle, "BOTTOMLEFT", 0, -6)
local SkipMacrosToggleText = SkipMacrosToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
SkipMacrosToggleText:SetPoint("LEFT", SkipMacrosToggle, "RIGHT", 2, 1)
SkipMacrosToggleText:SetText("Skip macros when applying action bars (leave those slots untouched)")
SkipMacrosToggle:SetScript("OnClick", function(self)
	Binder_EnhancedDB.Settings.SkipMacros = self:GetChecked() and true or false
end)

local FullBankLabel = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
FullBankLabel:SetPoint("TOPLEFT", SkipMacrosToggle, "BOTTOMLEFT", 5, -12)
FullBankLabel:SetText("When a macro's bank is full and it needs to be recreated:")

local RadioFullSkip = MakeRadio("Skip it, just tell me (safest)", "SKIP", 0, 0)
RadioFullSkip:ClearAllPoints()
RadioFullSkip:SetPoint("TOPLEFT", FullBankLabel, "BOTTOMLEFT", -5, -6)
local RadioFullPick = MakeRadio("Let me choose which macro to replace", "PICK", 0, 0)
RadioFullPick:ClearAllPoints()
RadioFullPick:SetPoint("TOPLEFT", RadioFullSkip, "BOTTOMLEFT", 0, -4)
local RadioFullAuto = MakeRadio("Auto-pick one, but ask me to confirm", "AUTO", 0, 0)
RadioFullAuto:ClearAllPoints()
RadioFullAuto:SetPoint("TOPLEFT", RadioFullPick, "BOTTOMLEFT", 0, -4)

local function SetFullMacroBankAction(mode)
	Binder_EnhancedDB.Settings.FullMacroBankAction = mode
	RadioFullSkip:SetChecked(mode == "SKIP")
	RadioFullPick:SetChecked(mode == "PICK")
	RadioFullAuto:SetChecked(mode == "AUTO")
end
RadioFullSkip:SetScript("OnClick", function() SetFullMacroBankAction("SKIP") end)
RadioFullPick:SetScript("OnClick", function() SetFullMacroBankAction("PICK") end)
RadioFullAuto:SetScript("OnClick", function() SetFullMacroBankAction("AUTO") end)

local RestoreHeader = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
RestoreHeader:SetPoint("TOPLEFT", RadioFullAuto, "BOTTOMLEFT", 5, -16)
RestoreHeader:SetText("Auto-Apply Restore Content")

local RestoreNote = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
RestoreNote:SetPoint("TOPLEFT", RestoreHeader, "BOTTOMLEFT", 0, -6)
RestoreNote:SetWidth(460); RestoreNote:SetJustifyH("LEFT")
RestoreNote:SetText("What a talent auto-trigger restores from the linked Set. Check any combination -- checking all three is the same as \"All\".")

local RestoreKeybindsCB = MakeRadio("Keybinds", "KEYBINDS", 0, 0)
RestoreKeybindsCB:ClearAllPoints()
RestoreKeybindsCB:SetPoint("TOPLEFT", RestoreNote, "BOTTOMLEFT", -5, -10)
local RestoreBarsCB = MakeRadio("Bars", "BARS", 0, 0)
RestoreBarsCB:ClearAllPoints()
RestoreBarsCB:SetPoint("LEFT", RestoreKeybindsCB, "RIGHT", 130, 0)
local RestoreGearCB = MakeRadio("Gear", "GEAR", 0, 0)
RestoreGearCB:ClearAllPoints()
RestoreGearCB:SetPoint("LEFT", RestoreBarsCB, "RIGHT", 130, 0)
-- On its own row rather than a 4th item on the same line -- three items at
-- this spacing already reach close to the panel's width, and a 4th would
-- risk running past the edge on some resolutions.
local RestoreMacrosCB = MakeRadio("Macros", "MACROS", 0, 0)
RestoreMacrosCB:ClearAllPoints()
RestoreMacrosCB:SetPoint("TOPLEFT", RestoreKeybindsCB, "BOTTOMLEFT", 0, -8)

local function SetAutoApplyRestoreFlag(flag, value)
	Binder_EnhancedDB.Settings.AutoApplyRestore = Binder_EnhancedDB.Settings.AutoApplyRestore or {}
	Binder_EnhancedDB.Settings.AutoApplyRestore[flag] = value
end
RestoreKeybindsCB:SetScript("OnClick", function(self) SetAutoApplyRestoreFlag("KEYBINDS", self:GetChecked() and true or false) end)
RestoreBarsCB:SetScript("OnClick", function(self) SetAutoApplyRestoreFlag("BARS", self:GetChecked() and true or false) end)
RestoreGearCB:SetScript("OnClick", function(self) SetAutoApplyRestoreFlag("GEAR", self:GetChecked() and true or false) end)
RestoreMacrosCB:SetScript("OnClick", function(self) SetAutoApplyRestoreFlag("MACROS", self:GetChecked() and true or false) end)

local AboutText = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
AboutText:SetPoint("TOPLEFT", RestoreMacrosCB, "BOTTOMLEFT", -5, -16)
AboutText:SetWidth(460); AboutText:SetJustifyH("LEFT")
AboutText:SetText("Binder Enhanced v" .. Binder_Enhanced.Version .. " by Angelouss. See the Changelog.txt included with this addon for release notes.")

function Binder_Enhanced:RefreshSettingsTab()
	local obj, label = GetSelectedLinkable()
	if obj then
		local linkText = obj.TalentLink and ("currently linked to |cffff9900" .. obj.TalentLink .. "|r") or "not linked"
		SettingsSelLabel:SetText("Selected: " .. label .. " -- " .. linkText)
		TalentLinkBtn:Enable(); SaveBuildBtn:Enable(); DeleteBuildBtn:Enable(); UnlinkBtn:Enable()

		local autoEquipText = obj.TalentEquipTarget and ("|cffff9900" .. obj.TalentEquipTarget .. "|r") or "|cff888888not linked|r"
		AutoEquipRow2Label:SetText("Spec change -> equip this gear: " .. autoEquipText)
		AutoEquipLinkBtn:Enable(); AutoEquipUnlinkBtn:Enable()
	else
		SettingsSelLabel:SetText("|cff888888Select a Profile or Set in the Profiles & Sets tab first.|r")
		TalentLinkBtn:Disable(); SaveBuildBtn:Disable(); DeleteBuildBtn:Disable(); UnlinkBtn:Disable()
		AutoEquipRow2Label:SetText("|cff888888Spec change -> equip this gear: select a Profile or Set first.|r")
		AutoEquipLinkBtn:Disable(); AutoEquipUnlinkBtn:Disable()
	end

	local currentSig = CaptureTalentSignature()
	local matchedName = nil
	if currentSig then
		for n, sig in pairs(Binder_EnhancedDB.TalentSignatures or {}) do
			if sig == currentSig then matchedName = n; break end
		end
	end
	local savedCount = TableCount(Binder_EnhancedDB.TalentSignatures or {})
	if matchedName then
		BuildStatusLabel:SetText("Current build matches saved build |cffff9900" .. matchedName .. "|r. (" .. savedCount .. " saved)")
	elseif savedCount > 0 then
		BuildStatusLabel:SetText("|cff888888Current build doesn't match any of your " .. savedCount .. " saved build(s).|r")
	else
		BuildStatusLabel:SetText("|cff888888No talent builds saved yet.|r")
	end
end

function Binder_Enhanced:RefreshOptionsTab()
	local mode = (Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.TalentAutoApplyMode) or "CHAT"
	RadioSilent:SetChecked(mode == "SILENT")
	RadioChat:SetChecked(mode == "CHAT")
	RadioConfirm:SetChecked(mode == "CONFIRM")

	local barMode = (Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.ActionBarSaveMode) or "ASK"
	RadioBarAsk:SetChecked(barMode == "ASK")
	RadioBarAlways:SetChecked(barMode == "ALWAYS")
	RadioBarNever:SetChecked(barMode == "NEVER")

	local barPrompt = Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.BarAutoApplyPrompt
	if barPrompt == nil then barPrompt = true end
	BarPromptToggle:SetChecked(barPrompt)

	SkipMacrosToggle:SetChecked(Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.SkipMacros and true or false)
	local fullBankMode = (Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.FullMacroBankAction) or "SKIP"
	RadioFullSkip:SetChecked(fullBankMode == "SKIP")
	RadioFullPick:SetChecked(fullBankMode == "PICK")
	RadioFullAuto:SetChecked(fullBankMode == "AUTO")

	if mode == "CONFIRM" then
		BarPromptToggle:Disable()
		BarPromptToggleText:SetText("|cff888888Show a fallback click prompt if bars fail to auto-apply (not used in Confirm mode)|r")
	else
		BarPromptToggle:Enable()
		BarPromptToggleText:SetText("Show a fallback click prompt if bars fail to auto-apply (recommended)")
	end

	local restoreFlags = (Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.AutoApplyRestore) or {}
	RestoreKeybindsCB:SetChecked(restoreFlags.KEYBINDS ~= false)
	RestoreBarsCB:SetChecked(restoreFlags.BARS ~= false)
	RestoreGearCB:SetChecked(restoreFlags.GEAR ~= false)
	RestoreMacrosCB:SetChecked(restoreFlags.MACROS ~= false)
end

--------------------------------------------------------------------
-- Standalone action-bar apply prompt (used by auto-apply triggers)
--------------------------------------------------------------------

-- Action bar changes (PickupSpell/PickupItem/PlaceAction/etc.) are
-- protected by the game and silently ignored unless triggered by a real
-- click -- a background event or timer can't do it, no matter how it's
-- written. So instead of a silent (and doomed) auto-apply attempt, this
-- shows a small standalone prompt; clicking its Apply button is a real
-- click, which is what actually lets the restore succeed.
local BarApplyPrompt = CreateFrame("Frame", "Binder_EnhancedBarApplyPrompt", UIParent)
BarApplyPrompt:SetWidth(320); BarApplyPrompt:SetHeight(80)
BarApplyPrompt:SetPoint("TOP", 0, -150)
BarApplyPrompt:SetFrameStrata("DIALOG")
BarApplyPrompt:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
BarApplyPrompt:SetMovable(true)
BarApplyPrompt:EnableMouse(true)
BarApplyPrompt:RegisterForDrag("LeftButton")
BarApplyPrompt:SetScript("OnDragStart", function(self) self:StartMoving() end)
BarApplyPrompt:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
BarApplyPrompt:Hide()

local BarApplyText = BarApplyPrompt:CreateFontString(nil, "OVERLAY", "GameFontNormal")
BarApplyText:SetPoint("TOP", 0, -14)
BarApplyText:SetWidth(290); BarApplyText:SetJustifyH("CENTER")

local BarApplyBtn = CreateFrame("Button", nil, BarApplyPrompt, "UIPanelButtonTemplate")
BarApplyBtn:SetWidth(110); BarApplyBtn:SetHeight(22)
BarApplyBtn:SetPoint("BOTTOMLEFT", 25, 12)
BarApplyBtn:SetText("Apply Bars")
BarApplyBtn:SetScript("OnClick", function()
	local profileName, setName = BarApplyPrompt.ProfileName, BarApplyPrompt.SetName
	BarApplyPrompt:Hide()
	if not profileName or not setName then return end
	local ok, msg, restored, skipped, pendingFullBank = Binder_Enhanced:ApplySetBars(profileName, setName)
	if ok then
		if skipped and skipped > 0 then
			Msg(string.format("Action bars applied for '%s' (%d slots, %d skipped).", setName, restored, skipped))
		else
			Msg(string.format("Action bars applied for '%s' (%d slots).", setName, restored))
		end
		if msg then Msg(msg) end
		if Binder_Enhanced.RollbackButton then Binder_Enhanced.RollbackButton:Enable() end
		if UI:IsShown() then Binder_Enhanced:RefreshList() end
		if pendingFullBank and #pendingFullBank > 0 then
			Binder_Enhanced:ResolveFullMacroBank(pendingFullBank)
		end
	elseif msg then
		Msg(msg)
	end
end)

local BarDismissBtn = CreateFrame("Button", nil, BarApplyPrompt, "UIPanelButtonTemplate")
BarDismissBtn:SetWidth(110); BarDismissBtn:SetHeight(22)
BarDismissBtn:SetPoint("BOTTOMRIGHT", -25, 12)
BarDismissBtn:SetText("Dismiss")
BarDismissBtn:SetScript("OnClick", function() BarApplyPrompt:Hide() end)

function Binder_Enhanced.ShowBarApplyPrompt(profileName, setName)
	BarApplyPrompt.ProfileName = profileName
	BarApplyPrompt.SetName = setName
	BarApplyText:SetText("Action bars ready for |cffffd200" .. setName .. "|r.\nWoW requires a real click to place spells/items, so click Apply below.")
	BarApplyPrompt:Show()
end

--------------------------------------------------------------------
-- Full macro bank resolve dialog
--------------------------------------------------------------------
-- Shown when a macro can't be recreated because its bank (General or
-- Character) is full and the player has opted (in Options) to resolve
-- this themselves rather than just skip it. Works through a queue one
-- item at a time: "Let me choose" starts with nothing pre-selected,
-- "Auto-pick, but confirm" pre-selects a candidate but still lets the
-- player click a different row instead -- same dialog, same flow, just a
-- different starting selection, matching the Options setting either way.
local FullBankFrame = CreateFrame("Frame", "Binder_EnhancedFullBankFrame", UIParent)
FullBankFrame:SetWidth(320); FullBankFrame:SetHeight(360)
FullBankFrame:SetPoint("CENTER")
FullBankFrame:SetFrameStrata("DIALOG")
FullBankFrame:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
FullBankFrame:SetMovable(true)
FullBankFrame:EnableMouse(true)
FullBankFrame:RegisterForDrag("LeftButton")
FullBankFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
FullBankFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
FullBankFrame:Hide()

local FullBankTitle = FullBankFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
FullBankTitle:SetPoint("TOP", 0, -14)
FullBankTitle:SetText("Macro Bank Full")

local FullBankInfo = FullBankFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
FullBankInfo:SetPoint("TOP", 0, -36)
FullBankInfo:SetWidth(290); FullBankInfo:SetJustifyH("CENTER")

local FullBankHint = FullBankFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
FullBankHint:SetPoint("TOP", FullBankInfo, "BOTTOM", 0, -10)
FullBankHint:SetWidth(290); FullBankHint:SetJustifyH("CENTER")
FullBankHint:SetText("Pick a macro below to overwrite with the new one, or Skip.")

local FullBankScroll = CreateFrame("ScrollFrame", "Binder_EnhancedFullBankScroll", FullBankFrame, "UIPanelScrollFrameTemplate")
FullBankScroll:SetPoint("TOPLEFT", 15, -100)
FullBankScroll:SetWidth(270); FullBankScroll:SetHeight(190)
local FullBankContent = CreateFrame("Frame", nil, FullBankScroll)
FullBankContent:SetWidth(250); FullBankContent:SetHeight(190)
FullBankScroll:SetScrollChild(FullBankContent)

FullBankFrame.rows = {}
FullBankFrame.selectedIdx = nil
FullBankFrame.queue = {}
FullBankFrame.queueIndex = 0

local function FullBankSelectRow(idx)
	FullBankFrame.selectedIdx = idx
	for _, row in ipairs(FullBankFrame.rows) do
		if row.macroIdx == idx then row.bg:Show() else row.bg:Hide() end
	end
end

local function FullBankGetRow(i)
	local row = FullBankFrame.rows[i]
	if not row then
		row = CreateFrame("Button", nil, FullBankContent)
		row:SetWidth(250); row:SetHeight(20)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.bg:SetTexture(1, 1, 1, 0.15)
		row.bg:Hide()
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 4, 0)
		row:SetScript("OnClick", function(self) FullBankSelectRow(self.macroIdx) end)
		FullBankFrame.rows[i] = row
	end
	return row
end

local function FullBankShowCurrent()
	local item = FullBankFrame.queue[FullBankFrame.queueIndex]
	if not item then
		FullBankFrame:Hide()
		return
	end

	FullBankInfo:SetText(string.format("Recreating |cffffd200%s|r (%s bank is full).",
		(not IsBlankMacroName(item.name) and item.name) or "(unnamed macro)", item.wantChar and "Character" or "General"))
	FullBankSelectRow(nil)

	-- List every macro currently in the SAME bank this one needs to go
	-- into -- the General/Character banks are separate slot ranges, so
	-- only offering choices from the right one avoids replacing something
	-- in the wrong bank entirely.
	local lo, hi = 1, 36
	if item.wantChar then lo, hi = 37, 54 end
	local n = 0
	for i = lo, hi do
		local mName, mIcon, mBody = GetMacroInfo(i)
		if mName then
			n = n + 1
			local row = FullBankGetRow(n)
			row.macroIdx = i
			if not IsBlankMacroName(mName) then
				row.text:SetText(mName)
			else
				-- Multiple unnamed macros can exist in the same bank and
				-- would otherwise all show the identical "(unnamed
				-- macro)" label with no way to tell them apart when
				-- choosing which one to replace -- show a short preview
				-- of the body instead, which is the only thing that
				-- actually distinguishes them.
				local preview = (mBody or ""):gsub("\n", " ")
				if #preview > 40 then preview = preview:sub(1, 40) .. "..." end
				if preview == "" then preview = "(empty)" end
				row.text:SetText("|cff888888(unnamed)|r " .. preview)
			end
			row:SetPoint("TOPLEFT", 0, -(n - 1) * 20)
			row:Show()
		end
	end
	for i = n + 1, #FullBankFrame.rows do FullBankFrame.rows[i]:Hide() end
	FullBankContent:SetHeight(math.max(190, n * 20))

	local mode = (Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.FullMacroBankAction) or "SKIP"
	if mode == "AUTO" and n > 0 then
		-- Pre-select a candidate -- the first (lowest-index) macro in that
		-- bank -- but the player can still click a different row instead.
		FullBankSelectRow(FullBankFrame.rows[1].macroIdx)
	end

	FullBankFrame:Show()
end

function Binder_Enhanced:ResolveFullMacroBank(pendingList)
	if type(pendingList) ~= "table" or #pendingList == 0 then return end
	FullBankFrame.queue = pendingList
	FullBankFrame.queueIndex = 1
	FullBankShowCurrent()
end

local FullBankReplaceBtn = CreateFrame("Button", nil, FullBankFrame, "UIPanelButtonTemplate")
FullBankReplaceBtn:SetWidth(90); FullBankReplaceBtn:SetHeight(22)
FullBankReplaceBtn:SetPoint("BOTTOMLEFT", 15, 12)
FullBankReplaceBtn:SetText("Replace")
FullBankReplaceBtn:SetScript("OnClick", function()
	local item = FullBankFrame.queue[FullBankFrame.queueIndex]
	local chosenIdx = FullBankFrame.selectedIdx
	if item and chosenIdx and EditMacro then
		local ok = pcall(function()
			EditMacro(chosenIdx, item.name, item.iconIdx, item.body)
			Binder_Enhanced.KnownMacros[item.name] = chosenIdx
			ClearCursor()
			PickupMacro(chosenIdx)
			local cursorType = GetCursorInfo and GetCursorInfo()
			if not GetCursorInfo or cursorType == "macro" then
				PlaceAction(item.slot)
			end
			ClearCursor()
		end)
		if not ok then Msg("Couldn't replace that macro -- see /console scriptErrors 1 for details.") end
	end
	FullBankFrame.queueIndex = FullBankFrame.queueIndex + 1
	FullBankShowCurrent()
end)

local FullBankSkipBtn = CreateFrame("Button", nil, FullBankFrame, "UIPanelButtonTemplate")
FullBankSkipBtn:SetWidth(90); FullBankSkipBtn:SetHeight(22)
FullBankSkipBtn:SetPoint("BOTTOM", 0, 12)
FullBankSkipBtn:SetText("Skip")
FullBankSkipBtn:SetScript("OnClick", function()
	FullBankFrame.queueIndex = FullBankFrame.queueIndex + 1
	FullBankShowCurrent()
end)

local FullBankCancelBtn = CreateFrame("Button", nil, FullBankFrame, "UIPanelButtonTemplate")
FullBankCancelBtn:SetWidth(110); FullBankCancelBtn:SetHeight(22)
FullBankCancelBtn:SetPoint("BOTTOMRIGHT", -15, 12)
FullBankCancelBtn:SetText("Skip Remaining")
FullBankCancelBtn:SetScript("OnClick", function()
	FullBankFrame.queue = {}
	FullBankFrame:Hide()
end)

--------------------------------------------------------------------
-- Talent-switch auto-apply
--------------------------------------------------------------------

-- Shared by both talent-link and equipment-link triggers: searches Sets

-- first (most specific), then falls back to a Profile-level link using
-- its most recently applied Set (or first alphabetically).
local function FindLinkedSet(newValue, linkField)
	local targetProfileName, targetSetName, targetSetObj

	for pname, profile in pairs(Binder_EnhancedDB.Profiles) do
		for sname, set in pairs(profile.Sets) do
			if set[linkField] == newValue then
				targetProfileName, targetSetName, targetSetObj = pname, sname, set
				break
			end
		end
		if targetSetObj then break end
	end

	if not targetSetObj then
		for pname, profile in pairs(Binder_EnhancedDB.Profiles) do
			if profile[linkField] == newValue then
				local sname = profile.LastUsedSet
				if not (sname and profile.Sets[sname]) then
					local names = {}
					for n in pairs(profile.Sets) do table.insert(names, n) end
					table.sort(names)
					sname = names[1]
				end
				if sname and profile.Sets[sname] then
					targetProfileName, targetSetName, targetSetObj = pname, sname, profile.Sets[sname]
				end
				break
			end
		end
	end

	return targetProfileName, targetSetName, targetSetObj
end

local function ApplyLinkedSetForTrigger(targetProfileName, targetSetName, targetSetObj, triggerLabel)
	if not targetSetObj then return end

	local restoreFlags = (Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.AutoApplyRestore) or {}
	local doKeybinds = restoreFlags.KEYBINDS ~= false
	local doBars = restoreFlags.BARS ~= false
	local doGear = restoreFlags.GEAR ~= false
	local doMacros = restoreFlags.MACROS ~= false

	local mode = targetSetObj.Mode or "ACCOUNT"
	local targets = { ACCOUNT = (mode == "ACCOUNT" or mode == "BOTH"), CHARACTER = (mode == "CHARACTER" or mode == "BOTH") }
	local behavior = (Binder_EnhancedDB.Settings and Binder_EnhancedDB.Settings.TalentAutoApplyMode) or "CHAT"
	local hasBars = type(targetSetObj.ActionBars) == "table" and TableCount(targetSetObj.ActionBars) > 0

	if behavior == "CONFIRM" then
		-- Reverse direction of Auto-Equip Gear: still equips directly here
		-- (a real click on the confirm popup's Apply button covers keybinds
		-- and bars, but gear equips immediately since it's a simple direct
		-- action with its own in-game error feedback).
		if triggerLabel == "Talent spec changed" and doGear and targetSetObj.TalentEquipTarget then
			local eqOk, eqMsg = Binder_Enhanced.EquipGearSetByName(targetSetObj.TalentEquipTarget)
			if eqOk then
				Msg("Equipped gear set '" .. targetSetObj.TalentEquipTarget .. "'.")
			elseif eqMsg then
				Msg(eqMsg)
			end
		end
		-- Never force the main browser window open for an automatic
		-- trigger -- only update it if it's already open. The confirm
		-- popup itself shows on its own (it's independent of the main
		-- window now), and clicking its Apply button is a real click, so
		-- it can restore action bars too, unlike the paths below.
		UI.Selected.profile = targetProfileName
		UI.Selected.set = targetSetName
		UI.Expanded[targetProfileName] = true
		if UI:IsShown() then Binder_Enhanced:RefreshList() end
		OpenApplyConfirm(targetProfileName, targetSetName)
	else
		-- A reference addon (Outfitter) confirms item/equipment pickup
		-- functions work fine from event-driven code -- the only real
		-- restriction is combat (which can't apply here anyway, since
		-- talent changes are themselves blocked in combat), not a
		-- hardware-event requirement. So bars and gear are attempted
		-- directly, same as keybinds; the bars click-prompt is now just a
		-- fallback for if that silent attempt actually reports nothing
		-- restored.
		local summary = {}
		local barsFailed = false

		if triggerLabel == "Talent spec changed" and doGear and targetSetObj.TalentEquipTarget then
			local eqOk, eqMsg = Binder_Enhanced.EquipGearSetByName(targetSetObj.TalentEquipTarget)
			if eqOk then
				table.insert(summary, "equipped '" .. targetSetObj.TalentEquipTarget .. "'")
			elseif eqMsg then
				Msg(eqMsg)
			end
		end

		local applyTargets = doKeybinds and targets or { ACCOUNT = false, CHARACTER = false }
		local ok, msg, count, barCount, barSkipped, pendingFullBank = Binder_Enhanced:ApplySet(targetProfileName, targetSetName, applyTargets, not doBars, not doMacros)
		if msg then Msg(msg) end
		if ok then
			if doKeybinds and count and count > 0 then
				table.insert(summary, count .. " keybinds")
			end
			if doBars and hasBars then
				if barCount and barCount > 0 then
					local barsLine = barCount .. " action bar slots"
					if barSkipped and barSkipped > 0 then
						barsLine = barsLine .. string.format(" (%d skipped)", barSkipped)
					end
					table.insert(summary, barsLine)
					-- Silent verification pass: something outside our own
					-- code has been observed reverting a slot shortly
					-- after an auto-triggered apply, even when this first
					-- pass reports a clean success -- re-apply once more
					-- a moment later to correct it if it happens again.
					-- No message either way; this is just a safety net.
					ScheduleDelayedCall(0.75, function()
						Binder_Enhanced:ApplySetBars(targetProfileName, targetSetName, not doMacros)
					end)
				else
					barsFailed = true
				end
			end
			-- Talent switches can't happen in combat, so there's no
			-- combat-safety concern in showing this dialog here too --
			-- same resolve flow as a manual Apply, just also offered after
			-- an automatic one.
			if pendingFullBank and #pendingFullBank > 0 then
				Binder_Enhanced:ResolveFullMacroBank(pendingFullBank)
			end
		end

		if behavior == "CHAT" and #summary > 0 then
			Msg(string.format("%s -> applied '%s / %s': %s.", triggerLabel, targetProfileName, targetSetName, table.concat(summary, ", ")))
		end

		if ok and barsFailed then
			local barPromptEnabled = Binder_EnhancedDB.Settings.BarAutoApplyPrompt
			if barPromptEnabled == nil then barPromptEnabled = true end
			if barPromptEnabled then
				Msg("Action bars didn't apply automatically -- use the prompt below to apply them manually.")
				Binder_Enhanced.ShowBarApplyPrompt(targetProfileName, targetSetName)
			end
		end
		if UI:IsShown() then Binder_Enhanced:RefreshList() end
	end
end

function Binder_Enhanced:HandleTalentSwitch(newTreeName)
	local p, s, obj = FindLinkedSet(newTreeName, "TalentLink")
	ApplyLinkedSetForTrigger(p, s, obj, "Talent spec changed")
end

--------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------

local MinimapButton = CreateFrame("Button", "Binder_EnhancedMinimapButton", Minimap)
MinimapButton:SetSize(31, 31); MinimapButton:SetFrameStrata("MEDIUM"); MinimapButton:SetFrameLevel(8)

local icon = MinimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\MacroFrame\\MacroFrame-Icon")
icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 0)

local border = MinimapButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53); border:SetPoint("TOPLEFT", 0, 0)

MinimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local function UpdateMinimapButtonPosition()
	if MinimapButton:GetParent() ~= Minimap then return end
	local a = Binder_EnhancedMinimapSettings.minimapPos or 45
	MinimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(math.rad(a)) * 80, math.sin(math.rad(a)) * 80)
end

MinimapButton:RegisterForDrag("RightButton")
MinimapButton:SetScript("OnDragStart", function(s)
	if MinimapButton:GetParent() ~= Minimap then return end
	s:SetScript("OnUpdate", function()
		local x, y = GetCursorPosition()
		local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
		local scale = Minimap:GetEffectiveScale()
		x = xmin - x / scale + 70
		y = y / scale - ymin - 70
		local a = math.deg(math.atan2(y, x))
		if a < 0 then a = a + 360 end
		Binder_EnhancedMinimapSettings.minimapPos = a
		UpdateMinimapButtonPosition()
	end)
end)
MinimapButton:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
MinimapButton:SetScript("OnClick", function(s, b)
	if b == "LeftButton" then Binder_Enhanced:ToggleUI() end
end)
MinimapButton:SetScript("OnEnter", function(s)
	GameTooltip:SetOwner(s, "ANCHOR_LEFT")
	GameTooltip:SetText("|cff33ff99Binder Enhanced|r")
	GameTooltip:AddLine("Left Click: Open", 1, 1, 1)
	GameTooltip:AddLine("Right Click + Drag: Move", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
MinimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

--------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------

SLASH_BINDER_ENHANCED1 = "/binder"
SLASH_BINDER_ENHANCED2 = "/bde"
SlashCmdList["BINDER_ENHANCED"] = function(msg)
	if msg == "debug" then
		if Binder_Enhanced.DebugTalentState then Binder_Enhanced.DebugTalentState() end
	else
		Binder_Enhanced:ToggleUI()
	end
end

--------------------------------------------------------------------
-- Interface Options panel (Interface -> AddOns)
--------------------------------------------------------------------
-- Binder Enhanced's actual settings live in its own window (there are
-- more of them, and richer controls, than fit comfortably in a standard
-- options canvas) -- this panel just makes the addon show up where
-- players expect to find it (Interface -> AddOns) and jumps straight
-- into the real Settings tab, rather than duplicating every checkbox
-- and radio button in two places that would need to be kept in sync.
local InterfaceOptionsPanel = CreateFrame("Frame", "Binder_EnhancedInterfaceOptionsPanel", UIParent)
InterfaceOptionsPanel.name = "Binder Enhanced"
InterfaceOptionsPanel:Hide()

local IOPTitle = InterfaceOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
IOPTitle:SetPoint("TOPLEFT", 16, -16)
IOPTitle:SetText("Binder Enhanced")

local IOPDesc = InterfaceOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
IOPDesc:SetPoint("TOPLEFT", IOPTitle, "BOTTOMLEFT", 0, -10)
IOPDesc:SetWidth(480); IOPDesc:SetJustifyH("LEFT")
IOPDesc:SetText("Binder Enhanced's Settings (talent auto-apply, action bar behavior, macro bank handling, and more) live in its own window for room to work with. Click below to open it, or type /binder any time.")

local IOPOpenBtn = CreateFrame("Button", nil, InterfaceOptionsPanel, "UIPanelButtonTemplate")
IOPOpenBtn:SetWidth(220); IOPOpenBtn:SetHeight(24)
IOPOpenBtn:SetPoint("TOPLEFT", IOPDesc, "BOTTOMLEFT", 0, -16)
IOPOpenBtn:SetText("Open Binder Enhanced Settings")
IOPOpenBtn:SetScript("OnClick", function()
	if not UI:IsShown() then Binder_Enhanced:ToggleUI() end
	ShowTab("settings")
	HideUIPanel(InterfaceOptionsFrame)
end)

if InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(InterfaceOptionsPanel)
end

--------------------------------------------------------------------
-- Events
--------------------------------------------------------------------

-- Determines your "current spec" as whichever talent tree has the most
-- points spent, rather than which dual-spec slot you're in -- so this
-- reflects your actual build even if you unlearn/respec talents without
-- ever touching dual spec. Returns nil if there's no clear leader (e.g.
-- a tie, or no points spent anywhere yet), so we don't guess wrong.
local function GetDominantTalentTab()
	if not GetTalentTabInfo then return nil end
	local bestName, bestPoints, isTie = nil, 0, false
	for i = 1, 3 do
		local name, _, pointsSpent = GetTalentTabInfo(i)
		if name and pointsSpent then
			if pointsSpent > bestPoints then
				bestName, bestPoints, isTie = name, pointsSpent, false
			elseif pointsSpent == bestPoints and pointsSpent > 0 then
				isTie = true
			end
		end
	end
	if isTie or bestPoints == 0 then return nil end
	return bestName
end

-- Resolves "what spec am I currently in" for link-matching purposes.
-- An exact match against a saved, named build is more specific than a
-- dominant-tree match, so it's tried first; if your current build was
-- never saved under a name, this falls back to the tree-name match.
local function GetCurrentTalentIdentifier()
	local sig = CaptureTalentSignature()
	if sig and Binder_EnhancedDB.TalentSignatures then
		for name, savedSig in pairs(Binder_EnhancedDB.TalentSignatures) do
			if savedSig == sig then return name end
		end
	end
	return GetDominantTalentTab()
end

-- Talent/equipment/item data can keep changing for several seconds after
-- login as it loads in from the server -- not just the very first read --
-- so a plain "first read = baseline" isn't quite enough to rule out a
-- false trigger. During this window, every read just re-baselines
-- silently; only after it ends do real changes get compared and acted on.
local LOGIN_GRACE_PERIOD = 8
local addonLoadedAt = nil

local function InLoginGracePeriod()
	if not addonLoadedAt then return true end
	return (GetTime() - addonLoadedAt) < LOGIN_GRACE_PERIOD
end

local lastDominantTab = nil
local talentBaselineSet = false

local function CheckTalentTreeChange()
	if not hasActiveLinks then return end
	local current = GetCurrentTalentIdentifier()
	if not current then return end
	if InLoginGracePeriod() or not talentBaselineSet then
		lastDominantTab = current
		talentBaselineSet = true
		return
	end
	if current ~= lastDominantTab then
		lastDominantTab = current
		Binder_Enhanced:HandleTalentSwitch(current)
	end
end

-- On-demand diagnostic (/binder debug) for the talent-switch trigger --
-- deliberately NOT a Msg() print inside CheckTalentTreeChange itself,
-- since that function runs on a 3-second poll and would spam chat
-- constantly. Run this once before a spec change and once right after to
-- compare -- if "current" doesn't actually change between the two, that
-- points at GetCurrentTalentIdentifier itself rather than the gating
-- logic around it.
function Binder_Enhanced.DebugTalentState()
	Msg(string.format(
		"|cff00ff00[DEBUG]|r hasActiveLinks=%s current=%s inGracePeriod=%s baselineSet=%s lastDominantTab=%s addonLoadedAt=%s now=%s",
		tostring(hasActiveLinks), tostring(GetCurrentTalentIdentifier()), tostring(InLoginGracePeriod()),
		tostring(talentBaselineSet), tostring(lastDominantTab), tostring(addonLoadedAt), tostring(GetTime())))
end

-- Confirmed via decompiled 3.3.5 client source: EquipmentManager_EquipSet
-- takes a plain equipment set name (not an ID) and calls UseEquipmentSet
-- internally, giving proper in-game error feedback if it fails (e.g.
-- locked items, casting). Falls back to UseEquipmentSet directly if the
-- wrapper isn't available for some reason.
local function EquipGearSetByName(name)
	if not name then return false, "No gear set specified." end
	if UnitAffectingCombat and UnitAffectingCombat("player") then
		return false, "Can't auto-equip gear while in combat."
	end

	local function tryEquip()
		if EquipmentManager_EquipSet then
			return pcall(EquipmentManager_EquipSet, name)
		elseif UseEquipmentSet then
			local ok, result = pcall(UseEquipmentSet, name)
			return ok and result
		end
		return false
	end

	if not EquipmentManager_EquipSet and not UseEquipmentSet then
		return false, "No equip function available on this client."
	end
	local ok = tryEquip()
	if not ok then return false, "Failed to equip gear set '" .. name .. "'." end

	-- Known WoW client quirk (not this addon): some gear sets -- reported
	-- specifically for ones involving Jewelcrafting items -- don't fully
	-- swap on a single EquipSet call; clicking Apply again in the actual
	-- Equipment Manager window reliably finishes the job. Three delayed
	-- passes, close together, does the same thing automatically -- same
	-- pattern already used elsewhere in this addon for other "needs to
	-- run twice" client quirks, just with an extra pass for margin.
	ScheduleDelayedCall(0.2, tryEquip)
	ScheduleDelayedCall(0.4, tryEquip)
	ScheduleDelayedCall(0.6, tryEquip)

	return true
end
Binder_Enhanced.EquipGearSetByName = EquipGearSetByName

local InitFrame = CreateFrame("Frame")
InitFrame:RegisterEvent("ADDON_LOADED")
InitFrame:RegisterEvent("CHAT_MSG_ADDON")
-- These talent/equipment events cover most cases, but naming/behavior can
-- vary across client builds, so none of them are relied on exclusively --
-- see the OnUpdate poll below, which is the real safety net.
pcall(InitFrame.RegisterEvent, InitFrame, "PLAYER_TALENT_UPDATE")
pcall(InitFrame.RegisterEvent, InitFrame, "CHARACTER_POINTS_CHANGED")
pcall(InitFrame.RegisterEvent, InitFrame, "ACTIVE_TALENT_GROUP_CHANGED")
InitFrame:SetScript("OnEvent", function(s, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= "Binder_Enhanced" then return end
		Binder_Enhanced:InitializeDatabase()
		Binder_Enhanced:ImportLegacyProfiles()
		UpdateMinimapButtonPosition()
		addonLoadedAt = GetTime()
		if not (Binder_EnhancedDB.Failsafe and (Binder_EnhancedDB.Failsafe.Account or Binder_EnhancedDB.Failsafe.Character or Binder_EnhancedDB.Failsafe.ActionBars)) then
			RollbackBtn:Disable()
		end
		if not (GetNumEquipmentSets and GetEquipmentSetInfo) then
			LoadAddOn("Blizzard_EquipmentManager")
		end
		Msg("Loaded. Use /binder or the minimap button.")
	elseif event == "CHAT_MSG_ADDON" then
		local pre, message, chan, sender = ...
		if pre ~= "Binder_EnhancedShare" then return end
		local setName, mode, bData = string.match(message, "^([^:]+)::([^:]+)::(.+)$")
		if not setName or not mode or not bData then return end
		local count, profileName = Binder_Enhanced:ReceiveSetFromPlayer(setName, mode, bData, sender)
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Binder Enhanced|r: Set '" .. setName .. "' received from " .. sender .. " (" .. count .. " keybinds) -> profile '" .. profileName .. "'.")
		if UI:IsShown() then Binder_Enhanced:RefreshList() end
	elseif event == "PLAYER_TALENT_UPDATE" or event == "CHARACTER_POINTS_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
		CheckTalentTreeChange()
	end
end)

-- Guaranteed fallback: whatever the events above do or don't catch, this
-- polls every couple of seconds and catches it anyway. Slightly slower
-- than an instant event, but it can't silently fail to fire.
local PollFrame = CreateFrame("Frame")
local pollElapsed = 0
PollFrame:SetScript("OnUpdate", function(self, elapsed)
	pollElapsed = pollElapsed + elapsed
	if pollElapsed < 3 then return end
	pollElapsed = 0
	if Binder_EnhancedDB then
		CheckTalentTreeChange()
	end
end)

local RSA = RSA or LibStub('AceAddon-3.0'):GetAddon('RSA')
local uClass = string.lower(select(2, UnitClass('player')))

local running = {}
local messageCache = {}
local cacheTagSpellName = {}
local cacheTagSpellLink = {}
local replacements = {}
local missTypes = {
	'ABSORB',
	'BLOCK',
	'DEFLECT',
	'DODGE',
	'EVADE',
	'IMMUNE',
	'MISS',
	'PARRY',
	'REFLECT',
	'RESIST',
}

local function CommCheck(currentSpell)
	-- Track group announced spells using RSA.Comm (AddonMessages)
	local CommCanAnnounce = true
	if currentSpell.comm then
		if RSA.Comm.GroupAnnouncer then
			CommCanAnnounce = true
			if RSA.Comm.GroupAnnouncer == tonumber(RSA.db.global.ID) then -- This is us, continue as normal.
				CommCanAnnounce = true
			else -- Someone else is announcing.
				CommCanAnnounce = false
			end
		else -- No Group, continue as normal.
			CommCanAnnounce = true
		end
	end
	return CommCanAnnounce
end

local function BuildMessageCache(currentSpell, currentSpellProfile, currentSpellData)
	-- Build Cache of valid messages
	-- We store empty strings when users blank a default message so we know not to use the default. An empty string can also be stored when a user deletes extra messages.
	-- We need to validate the list of messages so when we pick a message at random, we don't accidentally pick the blanked message.
	local messageCacheProfile = messageCache[currentSpellProfile]
	if not messageCacheProfile then
		messageCacheProfile = {}
		messageCache[currentSpellProfile] = {}
	end
	local validMessages = messageCacheProfile[currentSpellData]
	if not validMessages then
		validMessages = {}
		print('messageCache events:')

		local numEvents = 0
		for _ in pairs(currentSpell.events) do
			numEvents = numEvents + 1
		end
		print(numEvents)
		for i = 1, numEvents do
			if currentSpellData.messages[i] ~= '' then
				validMessages[i] = currentSpellData.messages[i]
			end
		end
		messageCache[currentSpellProfile][currentSpellData] = validMessages
	end
	if #validMessages == 0 then return end
	local message = validMessages[math.random(#validMessages)]
	if not message then return end
	message = gsub(message,'%%','%%%%')
	return message
end

local function HandleEvents()
	local timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlag, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool, ex1, ex2, ex3, ex4, ex5, ex6, ex7, ex8 = CombatLogGetCurrentEventInfo()

	--local spellData = RSA.SpellData
	local spellData = RSA.db.profile
	local classData = spellData[uClass]
					  -- RSA.db.profile.paladin
	print('before')
	if not classData then return end --print('NO CLASS DATA') end
	--local utilityData = spellData['utilities']
	--if not utilityData then return end --print('NO UTILITY DATA') end
	--local racialData = spellData['racials']
	--if not racialData then return end --print('NO Racial Data DATA') end
	print('after returns')

	local extraSpellID, extraSpellName, extraSchool = ex1, ex2, ex3
	local missType = ex1


	local currentSpellProfile = RSA.monitorData[uClass][spellID]
	if not currentSpellProfile then
		print('NO SPELL DATA')
		return end
	--currentSpellProfile = currentSpellProfile.profile
								-- RSA.monitorData.paladin.ardentDefender.ardentDefender = 'ardentDefender'

	if event == 'SPELL_DISPEL' or event == 'SPELL_STOLEN' then
		if not currentSpellProfile then
			spellID, extraSpellID = extraSpellID, spellID
			spellName, extraSpellName = extraSpellName, spellName
			spellSchool, extraSchool = extraSchool, spellSchool
			currentSpellProfile = RSA.monitorData[uClass][spellID]
		end
	end
	if not currentSpellProfile then print('NO SPELL PROFILE') return end
	local currentSpell = classData[currentSpellProfile]
						 -- RSA.db.profile.paladin['ardentDefender']



	if not currentSpell then print('NO SPELL DATA') return end
	if not currentSpell.events[event] then print('NO EVENT DATA') return end
	local currentSpellData = currentSpell.events[event]
							 -- RSA.db.profile.paladin['ardentDefender'].events[SPELL_HEAL] where SPELL_HEAL is the currently triggered event.
							 print('we have event data')


	if currentSpellData.targetIsMe and not RSA.IsMe(destFlags) then return end
	if currentSpellData.targetNotMe and RSA.IsMe(destFlags) then return end
	if currentSpellData.sourceIsMe and not RSA.IsMe(sourceFlags) then return end
	print('it is me')

	-- Track multiple occurences of the same spell to more accurately detect it's real end point.
	local spell_tracker = currentSpellProfile
	local tracker = currentSpellData.tracker or -1 -- Tracks spells like AoE Taunts to prevent multiple messages playing.
	if tracker == 1 and running[spell_tracker] == nil then return end -- Prevent announcement if we didn't start the tracker (i.e Tank Metamorphosis random procs from Artifact)
	if tracker == 1 and running[spell_tracker] >= 500 then return end -- Prevent multiple announcements of buff/debuff removal.
	if tracker == 2 then
		if running[spell_tracker] ~= nil then
			if running[spell_tracker] >= 0 and running[spell_tracker] < 500 then -- Prevent multiple announcements of buff/debuff application.
				running[spell_tracker] = running[spell_tracker] + 1
				return
			end
		end
		running[spell_tracker] = 0
	end
	if tracker == 1 and running[spell_tracker] == 0 then
		running[spell_tracker] = running[spell_tracker] + 500
	end
	if tracker == 1 and running[spell_tracker] > 0 and running[spell_tracker] < 500 then
		running[spell_tracker] = running[spell_tracker] - 1
		return
	end
	print('passed tracker')

	local message = BuildMessageCache(currentSpell, currentSpellProfile, currentSpellData)
	if not message then return end
	print('we have a message')


	-- Build Spell Name and Link Cache
	local tagSpellName = cacheTagSpellName[spellID]
	if not tagSpellName then
		tagSpellName = GetSpellInfo(spellID)
		cacheTagSpellName = tagSpellName
	end

	local tagSpellLink = cacheTagSpellLink[spellID]
	if not tagSpellLink then
		tagSpellLink = GetSpellLink(spellID)
		cacheTagSpellLink = tagSpellLink
	end

	if currentSpellData.uniqueSpellID then -- Replace cached data with 'real' spell data to announce the expected spell.
		local parentSpell = currentSpell.spellID

		tagSpellName = GetSpellInfo(parentSpell)
		cacheTagSpellName[spellID] = tagSpellName

		tagSpellLink = GetSpellLink(parentSpell)
		cacheTagSpellLink[spellID] = tagSpellLink
	end

	-- Trim Server Names
	local longName = destName
	if RSA.db.profile.general.globalAnnouncements.removeServerNames == true then
		if destName and destGUID then
			local realmName = select(7,GetPlayerInfoByGUID(destGUID))
			if realmName then
					destName = gsub(destName, '-'..realmName, '')
			end
		end
	end

	-- Build Tag replacements
	wipe(replacements)
	replacements['[SPELL]'] = tagSpellName
	replacements['[LINK]'] = tagSpellLink
	local tagReplacements = currentSpellData.tags or {}
	if tagReplacements.TARGET then replacements['[TARGET]'] = destName end
	if tagReplacements.SOURCE then replacements['[TARGET]'] = sourceName end
	if tagReplacements.AMOUNT then replacements['[AMOUNT]'] = ex1 end
	if tagReplacements.EXTRA then
		local name = cacheTagSpellName[extraSpellID]
		if not name then
			name = GetSpellInfo(extraSpellID)
			cacheTagSpellName[extraSpellID] = name
			replacements[tagReplacements.EXTRA] = name
		end
		local link = cacheTagSpellLink[extraSpellID]
		if not link then
			link = GetSpellLink(extraSpellID)
			cacheTagSpellLink[extraSpellID] = link
			replacements[tagReplacements.EXTRA] = link
		end
	end

	if tagReplacements.MISSTYPE then
		if RSA.db.profile.general.replacements.missType.useGenericReplacement == true then
			for i = 1,#missTypes do
				if missType == missTypes[i] then
					replacements['[MISSTYPE]'] = RSA.db.profile.general.replacements.missType.genericReplacementString
				end
			end
		else
			if missType == 'IMMUNE' then
				replacements['[MISSTYPE]'] = RSA.db.profile.general.replacements.missType.immune
				local validMessages = messageCache[currentSpellProfile][currentSpell.events].immuneMessages or nil
				if not validMessages then
					validMessages = {}
					for i = 1, #currentSpell.events[event].immuneMessages do
						if currentSpellData.immuneMessages[i] ~= '' then
							validMessages[i] = currentSpellData.immuneMessages[i]
						end
						messageCache[currentSpellProfile][currentSpell.events].immuneMessages = validMessages
						if #validMessages == 0 then return end
						message = validMessages[math.random(#validMessages)]
						if not message then return end
						message = gsub(message,'%%','%%%%')
					end
				end
			else
				replacements['MISSTYPE'] = RSA.db.profile.general.replacements.missType[string.lower(missType)]
			end
		end
	end

	if currentSpellData.channels.personal == true then
		if currentSpellData.groupRequired then -- Used in Mage Teleports, only locally announces if you are in a group.
			if not (GetNumSubgroupMembers() > 0 or GetNumGroupMembers() > 0) then return end
		end
		RSA.SendMessage.LibSink(gsub(message, ".%a+.", replacements))
	end

	if currentSpell.comm then -- Track group announced spells using RSA.Comm (AddonMessages)
		if not CommCheck(currentSpell) then return end
		--Local messages can always go through, so only check this after sending the local message.
	end

	if currentSpellData.channels.yell == true then
		RSA.SendMessage.Yell(gsub(message, ".%a+.", replacements))
	end
	if currentSpellData.channels.whisper == true and UnitExists(longName) and RSA.Whisperable(destFlags) then
		RSA.SendMessage.Whisper(message, longName, replacements, destName)
	end
	if currentSpellData.channels.say == true then
		RSA.SendMessage.Say(gsub(message, ".%a+.", replacements))
	end
	if currentSpellData.channels.emote == true then
		RSA.SendMessage.Emote(gsub(message, ".%a+.", replacements))
	end

	local Announced = false
	if currentSpellData.channels.party == true then
		if RSA.SendMessage.Party(gsub(message, ".%a+.", replacements)) == true then Announced = true end
	end
	if currentSpellData.channels.raid == true then
		if RSA.SendMessage.Raid(gsub(message, ".%a+.", replacements)) == true then Announced = true end
	end
	if currentSpellData.channels.instance == true then
		if RSA.SendMessage.Instance(gsub(message, ".%a+.", replacements)) == true then Announced = true end
	end
	if currentSpellData.channels.smartGroup == true then
		if Announced == false then
			RSA.SendMessage.SmartGroup(gsub(message, ".%a+.", replacements))
		end
	end

end

RSA.Monitor:SetScript('OnEvent', HandleEvents)
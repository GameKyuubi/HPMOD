--hpmod
--yes i tried making this before but never finished
--by Callmore

--object stuff
freeslot(
	"SPR_HPWN",
	"S_HPWARNING1", "S_HPWARNING2",
	"MT_HPWARNING",
	"sfx_hpelmn", "sfx_hpeati"
)

states[S_HPWARNING1] = {SPR_HPWN, FF_FULLBRIGHT|A, 8, nil, 0, 0, S_HPWARNING2}
states[S_HPWARNING2] = {SPR_HPWN, FF_FULLBRIGHT|B, 8, nil, 0, 0, S_HPWARNING1}

mobjinfo[MT_HPWARNING] = {
	spawnstate = S_HPWARNING1,
	spawnhealth = 1000,
	radius = FRACUNIT,
	height = FRACUNIT,
	flags = MF_NOBLOCKMAP|MF_DONTENCOREMAP
}

local cv_maxhp = CV_RegisterVar{
	name = "hpmod_maxhp",
	defaultvalue = 50,
	flags = CV_NETVAR,
	PossibleValue = {MIN = 1, MAX = INT32_MAX}
}
local cv_maxhpperplayer = CV_RegisterVar{
	name = "hpmod_maxhpperplayer",
	defaultvalue = 3,
	flags = CV_NETVAR,
	PossibleValue = {MIN = 0, MAX = INT32_MAX}
}
local cv_maxhpperplayerminplayers = CV_RegisterVar{
	name = "hpmod_maxhpperplayerminplayers",
	defaultvalue = 8,
	flags = CV_NETVAR,
	PossibleValue = {MIN = 0, MAX = 15}
}
local cv_hpheal = CV_RegisterVar{
	name = "hpmod_hpheal",
	defaultvalue = 20,
	flags = CV_NETVAR,
	PossibleValue = CV_Unsigned
}
local cv_hphealmode = CV_RegisterVar{
	name = "hpmod_hphealmode",
	defaultvalue = "Off",
	flags = CV_NETVAR,
	PossibleValue = {Off=0, On=1, Limited=2}
}
local cv_enabled = CV_RegisterVar{
	name = "hpmod_enabled",
	defaultvalue = "On",
	flags = CV_NETVAR,
	PossibleValue = CV_OnOff
}
local cv_enabledinbattle = CV_RegisterVar{
	name = "hpmod_enabledinbattle",
	defaultvalue = "On",
	flags = CV_NETVAR,
	PossibleValue = CV_OnOff
}
local cv_combatdamage = CV_RegisterVar{
	name = "hpmod_combatdamage",
	defaultvalue = "On",
	flags = CV_NETVAR,
	PossibleValue = CV_OnOff
}
local cv_bumpdamage = CV_RegisterVar{
	name = "hpmod_bumpdamage",
	defaultvalue = "On",
	flags = CV_NETVAR,
	PossibleValue = CV_OnOff
}
local cv_wallbonkdamage = CV_RegisterVar{
	name = "hpmod_wallbonkdamage",
	defaultvalue = "Off",
	flags = CV_NETVAR,
	PossibleValue = CV_OnOff
}
local cv_killhealenabled = CV_RegisterVar{
	name = "hpmod_killhealenabled",
	defaultvalue = "On",
	flags = CV_NETVAR,
	PossibleValue = CV_OnOff
}
local cv_killhealamount = CV_RegisterVar{
	name = "hpmod_killhealamount",
	defaultvalue = 25,
	flags = CV_NETVAR,
	PossibleValue = {MIN = 1, MAX = INT32_MAX}
}
local cv_itemabosrb = CV_RegisterVar{
	name = "hpmod_itemabsorb",
	defaultvalue = "Off",
	flags = CV_NETVAR,
	PossibleValue = CV_OnOff
}
local cv_deathdelay = CV_RegisterVar{
	name = "hpmod_deathdelay",
	defaultvalue = TICRATE/2,
	flags = CV_NETVAR,
	PossibleValue = {MIN=1, MAX=TICRATE*10}
}
local cv_healamount = CV_RegisterVar{
	name = "hpmod_healamount",
	defaultvalue = 12,
	flags = CV_NETVAR,
	PossibleValue = {MIN = 1, MAX = INT32_MAX}
}

local LOW_HP_LEVEL = 20
local LAG_HP_DRAIN = 3

local HPBARWIDTH = 100

local starttime = 6*TICRATE + (3*TICRATE/4)
local everyoneDeadTimer = 0
local exitTimer = 0
local lowHpSoundTimer = 0
local lowHpNumberFlashTimer = 0

local deadPlayers = {}

local retirestr = "ELIMINATED"
local retirelen = nil

local elimMode = false

local bargfx = nil
local barbggfx = nil
local barlinegfx = nil

--local running = false

rawset(_G, "hpmod", {
	running = false,
	maxhp = 100
})

rawset(_G, "hpmod_showbar", true)

rawset(_G, "hpmod_damagehp", function (p, dmg, source, force)
	if not hpmod.running then return end

	if leveltime <= starttime then return end

	if not (type(p) == "userdata") then error("arg1 expected type userdata, got " .. type(p), 2) end
	if not (p and p.valid) then error("arg1 is not a valid target", 2) end
	if not (type(dmg) == "number") then error("arg2 expected type number, got " .. type(dmg), 2) end
	if source and not (type(source) == "userdata" or type(source) == "table") then
		error("arg3 expected type userdata or table, got " .. type(dmg), 2)
	end --this ones too long for a inline
	if not p.hpmod then resetHp(p) end
	
	if p.hpmod.deathtimer > 0 then return end
	if p.exiting then return end --ignore damage if the player has finished
	
	if dmg >= p.hpmod.hp or force then
		if p.pflags & PF_TIMEOVER then return end --stop this from happening twice

		--add this player to a list, we need to check if they die later
		--print(source)
		deadPlayers[#deadPlayers+1] = {p, source, dmg, force}
	else
		p.hpmod.hp = $-dmg
		local lastlap = p.laps == numlaps-1
		if cv_hphealmode.value == 1 and not lastlap then --always heal
			p.hpmod.minhp = min(hpmod.maxhp, p.hpmod.hp+cv_hpheal.value)
		elseif cv_hphealmode.value == 2 and not lastlap then --limited heal
			p.hpmod.minhp = min($, min(hpmod.maxhp, p.hpmod.hp+cv_hpheal.value))
		else --no heal
			p.hpmod.minhp = p.hpmod.hp
		end
	end
end)

rawset(_G, "hpmod_healhp", function (p, heal)
	if not hpmod.running then return end

	if leveltime <= starttime then return end

	if not (type(p) == "userdata") then error("arg1 expected type userdata, got " .. type(p), 2) end
	if not (p and p.valid) then error("arg1 is not a valid target", 2) end
	if not (type(heal) == "number") then error("arg2 expected type number, got " .. type(heal), 2) end
	if not p.hpmod then resetHp(p) end
	
	if p.hpmod.deathtimer > 0 then return end
	if p.exiting then return end --ignore damage if the player has finished
	
	p.hpmod.hp = min($+heal, hpmod.maxhp)
	local lastlap = p.laps == numlaps-1
	if cv_hphealmode.value == 1 and not lastlap then --always heal
		p.hpmod.minhp = min(hpmod.maxhp, p.hpmod.hp+cv_hpheal.value)
	elseif cv_hphealmode.value == 2 and not lastlap then --limited heal
		-- lol nah do nothing
		--p.hpmod.minhp = min($, min(hpmod.maxhp, p.hpmod.hp+cv_hpheal.value))
	else --no heal
		p.hpmod.minhp = p.hpmod.hp
	end
end)

local function generateHFForPlayer(p)
	if p and p.valid and p.mo and p.mo.valid then
		return {{p.name, p.mo.hf_overridenamecolor or p.skincolor}, {skins[p.mo.skin].facemmap, p.skincolor}, p}
	else
		return {{}, {}}
	end
end

local function countPlayersInGame()
	local out = 0
	for p in players.iterate do
		if not (p and p.valid and not p.spectator) then continue end
		out = $+1
	end
	return out
end

local function killPlayer(p)
	if not hpmod.running then return end

	if not (p and p.valid and p.mo) then return end
	p.lives = 0
	p.pflags = $ | PF_TIMEOVER
	p.kartstuff[k_position] = countPlayersInGame()
	--P_RestoreMusic(p)
	S_ChangeMusic("KRFAIL", true, p)
	P_DamageMobj(p.mo, nil, nil, 10000)
	
	if p.mo and p.mo.valid then
		p.mo.momx = 0
		p.mo.momy = 0
		p.mo.momz = 0
	end
	
	p.kartstuff[k_sneakertimer] = 0
end

local function resetMaxHp()
	local mhp = cv_maxhp.value

	if cv_maxhpperplayer.value then
		local mhpmp = max(countPlayersInGame()-cv_maxhpperplayerminplayers.value, 0)
		mhp = $+(mhpmp*cv_maxhpperplayer.value)
	end

	hpmod.maxhp = max(mhp, 1)
end

local function resetHp(p)
	p.hpmod = {
		hp = hpmod.maxhp,
		minhp = hpmod.maxhp,
		laghp = hpmod.maxhp,
		deathtimer = 0,
		lastlap = 0,
		bumper = nil,
		bumpertimer = 0
	}
end



local function shouldHurt(p)
	return not (p.powers[pw_flashing] > 0 or p.kartstuff[k_squishedtimer] > 0 or p.kartstuff[k_spinouttimer] > 0
		or p.kartstuff[k_invincibilitytimer] > 0 or p.kartstuff[k_growshrinktimer] > 0 or p.kartstuff[k_hyudorotimer] > 0 
		or (G_BattleGametype() and ((p.kartstuff[k_bumper] <= 0 and p.kartstuff[k_comebacktimer]) or p.kartstuff[k_comebackmode] == 1)))
end

local function getBumpSpeed(p)
	return FixedMul(p.speed, p.kartweight*(FRACUNIT/16)+FRACUNIT)
end



local function hpmodNet(net)
	hpmod = net($)
	everyoneDeadTimer = net($)
	exitTimer = net($)
	deadPlayers = net($)
	elimMode = net($)
end

local function hpmodChange()
	resetMaxHp()
	for p in players.iterate do
		if not (p and p.valid) then continue end
		resetHp(p)
	end
	everyoneDeadTimer = 0
	
	hpmod.running = cv_enabled.value
	if not hpmod.running then return end
	if G_BattleGametype() and not cv_enabledinbattle.value then
		hpmod.running = false
		return
	end

	for i = 0, 15 do
		for p = 0, 3 do
			local obj = P_SpawnMobj(0, 0, 0, MT_HPWARNING)
			obj.eflags = $|MFE_DRAWONLYFORP1<<p
			--obj.flags2 = $|MF2_DONTDRAW
			obj.targetplayern = i
			obj.displayplayern = p
			obj.colorized = true
			obj.color = SKINCOLOR_BLUE
		end
	end

	local cv_elim = CV_FindVar("elimination")
	if cv_elim and cv_elim.value then
		elimMode = true
		--print("HPMOD Elim mode enabled!")
	else
		elimMode = false
	end
	
	if G_BattleGametype() then
		hud.disable("battlerankingsbumpers")
		hud.disable("gametypeinfo")
	end
end

local function hpmodThink()
	
	if leveltime < 1 then return end
	if leveltime == 1 then hpmodChange() end

	if leveltime == starttime then
		resetMaxHp()
		for p in players.iterate do
			if not (p and p.valid) then return end
			resetHp(p)
		end
	end

	if not hpmod.running then return end
	
	if G_BattleGametype() then
		if hud.enabled("battlerankingsbumpers") then
			hud.disable("battlerankingsbumpers")
		end
		if hud.enabled("gametypeinfo") then
			hud.disable("gametypeinfo")
		end
	end

	--first we gotta check if everyone is somehow dead
	if everyoneDeadTimer then --GGS IDIOTS, YOU ALL KILLED EACHOTHER AND NOW NOONE SHALL WIN
		for p in players.iterate do
			if p.hpmod.laghp > p.hpmod.hp then
				if not (leveltime%LAG_HP_DRAIN) then
					p.hpmod.laghp = $-1
				end
			elseif p.hpmod.laghp < p.hpmod.hp then
				p.hpmod.laghp = p.hpmod.hp
			end

			p.marescore = p.hpmod.hp
		end
		
		if everyoneDeadTimer == 1 then
			S_StopMusic()
		elseif everyoneDeadTimer == (TICRATE*1)+(TICRATE/2) then
			S_ChangeMusic("GOVER", false, nil)
		elseif everyoneDeadTimer > (TICRATE*10)+(TICRATE/2) then
			S_ChangeMusic("KRFAIL", true, nil, 0, 3*MUSICRATE)
			G_ExitLevel()
		end
		everyoneDeadTimer = $+1
		return
	end
	
	--check if someone has exited
	do
		local someoneExit = false
		for p in players.iterate do
			if p.exiting then
				someoneExit = true
				exitTimer = $+1
				break
			end
		end

		if not someoneExit then
			exitTimer = 0
		end
	end

	--main game stuff
	for p in players.iterate do
		if not (p and p.valid) then continue end
		if not p.hpmod then
			resetHp(p)
		end
		
		if p.hpmod.bumpertimer then
			p.hpmod.bumpertimer = $-1
		else
			p.hpmod.bumper = nil
		end
		
		if p.spectator then continue end
		
		if p.hpmod.laghp > p.hpmod.hp then
			if not (leveltime%LAG_HP_DRAIN) then
				p.hpmod.laghp = $-1
			end
		elseif p.hpmod.laghp < p.hpmod.hp then
			p.hpmod.laghp = p.hpmod.hp
		end

		p.marescore = p.hpmod.hp
		p.kartstuff[k_bumper] = 3

		if elimMode and p.hpmod.deathtimer then
			-- first check if elim has started, otherwise just do regular death
			local cv_elimstart = CV_FindVar("elim_starttime")
			if leveltime > starttime + (cv_elimstart.value * TICRATE) then
				-- yo cool, time to see what elim does and mimic it
				-- since it seems to like that

				--p.spectator = true
				p.elim_rejoinEnd = true
				continue
			end
		end

		if p.hpmod.deathtimer and p.hpmod.deathtimer < cv_deathdelay.value then
			-- do funny spin into boom
			p.hpmod.deathtimer = $+1
			if p.playerstate == PST_DEAD then
				p.hpmod.deathtimer = cv_deathdelay.value
			end
		elseif p.hpmod.deathtimer == cv_deathdelay.value then
			killPlayer(p)
			S_StartSound(nil, sfx_hpelmn)
			p.hpmod.deathtimer = $+1
		end

		if p.pflags & PF_TIMEOVER then continue end
		
		if p.laps > p.hpmod.lastlap then
			p.hpmod.lastlap = p.laps
			local lastlap = p.laps == numlaps
			if cv_hphealmode.value and not lastlap then
				CONS_Printf(p, "Lap complete! HP regained.")
				p.hpmod.hp = p.hpmod.minhp
			end

			lastlap = p.laps == numlaps-1
			if cv_hphealmode.value == 1 and not lastlap then
				p.hpmod.minhp = min(p.hpmod.hp+cv_hpheal.value, hpmod.maxhp)
			end
		end

		if (p.mo.eflags & MFE_JUSTBOUNCEDWALL) and shouldHurt(p) and cv_wallbonkdamage.value then
			local dmg = FixedInt(FixedDiv(p.speed, FRACUNIT*9))
			if p.kartstuff[k_sneakertimer] then
				dmg = $/2 --damage you less during sneaker state
			end
			hpmod_damagehp(p, dmg, {{"A wall", 0}, {"K_HSWALL", 0}})
		end

		if exitTimer >= 20*TICRATE and (exitTimer%TICRATE) == 0
		and not p.exiting and not p.hpmod.deathtimer then
			local dmg = exitTimer/(20*TICRATE)
			hpmod_damagehp(p, dmg)
		end

		if cv_itemabosrb.value
		and p.cmd.buttons & BT_CUSTOM2
		and p.kartstuff[k_itemtype] ~= 0
		and p.kartstuff[k_itemheld] ~= 1 then
			K_StripItems(p)
			hpmod_healhp(p, cv_healamount.value)
			local mo = nil
			if p.mo and p.mo.valid then
				mo = p.mo
			end
			S_StartSound(mo, sfx_hpeati)
		end

	end

	-- funny sound effect to annoy people
	if lowHpSoundTimer then
		lowHpSoundTimer = $-1
	end

	if lowHpNumberFlashTimer then
		lowHpNumberFlashTimer = $-1
	end

	local p = displayplayers[0]
	if p and p.valid
	and p.hpmod.hp <= LOW_HP_LEVEL
	and not p.exiting
	and not p.hpmod.deathtimer
	and not (p.pflags & PF_TIMEOVER)
	and not lowHpSoundTimer then
		S_StartSound(nil, sfx_s3k75)
		lowHpNumberFlashTimer = TICRATE/4
		lowHpSoundTimer = max(TICRATE/2, (TICRATE*p.hpmod.hp)/7)
	end

	-- wipe the variable after we are done with it
	p = nil

	if #deadPlayers then
		local deltWith = {}
		for i, k in ipairs(deadPlayers) do
			local p = k[1]
			local source = k[2]
			if type(source) == "table" then continue end
			if p and p.valid and ((p.pflags & PF_TIMEOVER) or p.hpmod.deathtimer) then continue end --dont heal if they are already dead :(
			if deltWith[p] then continue end -- we already delt with this player, skip
			if source and source.valid then
				if source.hpmod and cv_killhealenabled.value
				and not source.hpmod.deathtimer
				and p ~= source then --dont heal if you killed yourself!
					source.hpmod.hp = min($+cv_killhealamount.value, hpmod.maxhp)
					if cv_hphealmode.value == 1 then --always heal
						source.hpmod.minhp = min(hpmod.maxhp, source.hpmod.hp+cv_hpheal.value)
					elseif cv_hphealmode.value == 2 then --limited heal
						source.hpmod.minhp = min($, min(hpmod.maxhp, source.hpmod.hp+cv_hpheal.value))
					else --no heal
						source.hpmod.minhp = source.hpmod.hp
					end
					CONS_Printf(source, "Eliminated " .. p.name .. "! +" .. cv_killhealamount.value .. "HP")
					deltWith[p] = true -- mark that this player was delt with
				end
			else
				k[2] = nil
			end
		end

		for i, k in ipairs(deadPlayers) do
			--deal with each death here instead
			local p, source, damage, force = unpack(k, 1, 4)
			
			if not (p and p.valid and p.hpmod) then continue end
			if p.pflags & PF_TIMEOVER then continue end --dont kill someone twice
			if p.hpmod.deathtimer then continue end --dont kill someone twice
			
			--lololol no u
			if p.spectator then continue end

			if damage >= p.hpmod.hp or force then
				p.hpmod.hp = 0
				p.hpmod.minhp = 0
			else
				--they where saved from death!
				continue
			end
			
			if hitfeed then --snu why you gotta make it so hard to make a custom HF now :(
				local v = generateHFForPlayer(p)
				local s = {{}, {}}
				if type(source) == "table" then --they sent in a custom text
					s = source
				elseif source then --there is a source
					s = generateHFForPlayer(source)
				end

				HF_SendHitMessage(s, v, "K_HMEXPL") --HITFEED HAS A BUILD-IN EXPLODE ICON! v2 doesent (f) also thx snu
			else
				print(p.name .. " eliminated!")
			end

			if elimMode then
				-- first check if elim has started, otherwise just do regular death
				local cv_elimstart = CV_FindVar("elim_starttime")
				if leveltime >= starttime + (cv_elimstart.value * TICRATE) then
					-- yo cool, time to see what elim does and mimic it
					-- since it seems to like that
					
					--taken from source to help give the illution that it works
					local boom = P_SpawnMobj(p.mo.x, p.mo.y, p.mo.z, MT_FZEROBOOM)
					boom.scale = p.mo.scale
					boom.angle = p.mo.angle
					boom.target = p.mo

					--p.spectator = true
					p.elim_rejoinEnd = true
					S_StartSound(nil, sfx_hpelmn)
					continue
				end
			end

			p.hpmod.deathtimer = 1
		end

		deadPlayers = {}
	end

	do --check if everyone in-game is dead
		local aliveCount = 0
		local winner = nil
		local pInGame = 0
		for p in players.iterate do
			if not (p and p.valid) then continue end
			if p.spectator then continue end
			pInGame = $+1
			if p.pflags & PF_TIMEOVER then
				continue
			else
				aliveCount = $+1
				winner = p
				if aliveCount > 1 then break end
			end
		end
		
		if aliveCount == 0 and pInGame then
			everyoneDeadTimer = 1
		elseif aliveCount == 1 and pInGame > 1 then --someone won by being last standing, exitlevel
			for p in players.iterate do
				if not (p and p.valid) then continue end
				if p.spectator then continue end
				if p == winner then
					P_DoPlayerExit(winner)
				else
					S_ChangeMusic("KRFAIL", true, nil)
				end
			end
		end
	end
	
end

local function hpmodRespawn(p)
	if not p.hpmod then
		resetHp(p)
	end
end

local function hpmodDeath(pmo, mo, pmo2)
	if not hpmod.running then return end
	if not cv_combatdamage.value then return end

	if not (pmo and pmo.valid and pmo.player and pmo.player.valid) then return end
	if pmo.player.pflags&PF_TIMEOVER then return end

	if pmo.player.spectator then return end
	
	local attacker = nil
	if pmo2 and pmo2.valid and pmo2.player then
		attacker = pmo2.player
	end

	if mo and mo.valid and mo.type == MT_SINK then
		hpmod_damagehp(pmo.player, hpmod.maxhp, attacker, true)
		local boom = P_SpawnMobj(pmo.x, pmo.y, pmo.z, MT_FZEROBOOM)
		boom.scale = pmo.scale
		boom.angle = pmo.angle
		boom.target = pmo
		return
	end
	
	if pmo.player.kartstuff[k_eggmanexplode] then
		hpmod_damagehp(pmo.player, 20, attacker)
	end

	if pmo.player and pmo.player.hpmod.bumper and pmo.player.hpmod.bumper.valid then
		attacker = pmo.player.hpmod.bumper
	else
		attacker = nil
	end

	hpmod_damagehp(pmo.player, 15, attacker)
end

local SPINDMG = {
	[MT_ORBINAUT] = 15,
	[MT_ORBINAUT_SHIELD] = 15,
	[MT_JAWZ] = 15,
	[MT_JAWZ_DUD] = 15,
	[MT_JAWZ_SHIELD] = 15,
	[MT_BALLHOG] = 15,
}

local function hpmodSpin(p, mo, pmo)
	if not hpmod.running then return end
	if not cv_combatdamage.value then return end

	if not (p and p.valid) then return end

	if mo and mo.valid and SPINDMG[mo.type] then
		local plr = (pmo and pmo.valid) and pmo.player or nil
		hpmod_damagehp(p, SPINDMG[mo.type], plr)
	elseif mo and mo.valid and mo.player and mo.player.valid and mo.player.kartstuff[k_invincibilitytimer] then
		hpmod_damagehp(p, 20, mo.player)
	else
		local plr = (pmo and pmo.valid) and pmo.player or nil
		if mo and mo.valid and mo.type == MT_BANANA and mo.health then
			hpmod_damagehp(p, 5, plr) -- yooo crit
		end
		hpmod_damagehp(p, 10, plr)
	end
end

local function hpmodExplode(p, mo, pmo)
	if not hpmod.running then return end
	if not cv_combatdamage.value then return end

	if not (p and p.valid) then return end
	local plr = (pmo and pmo.valid) and pmo.player or nil
	if mo and mo.valid and mo.type == MT_SPBEXPLOSION and mo.extravalue1 then
		-- spb boom
		hpmod_damagehp(p, 30, plr)
		-- A HA HA YOU HAVE UNOOOOOOOOOOOOOOOO
		-- +4 to face
		return
	end
	-- regular boom
	hpmod_damagehp(p, 20, plr)
end

local function hpmodSquish(p, mo, pmo)
	if not hpmod.running then return end
	if not cv_combatdamage.value then return end

	if not (p and p.valid) then return end
	local plr = (pmo and pmo.valid) and pmo.player or nil
	hpmod_damagehp(p, 20, plr)
end

local function hpmodBumpFight(mobj1, mobj2)
    if not hpmod.running then return end
	
	if mobj1.valid and mobj1.player
	and mobj2 and mobj2.valid and mobj2.player then
		local p1, p2 = mobj1.player, mobj2.player
		p1.hpmod.bumper = p2
		p1.hpmod.bumpertimer = TICRATE*5
		
		p2.hpmod.bumper = p1
		p2.hpmod.bumpertimer = TICRATE*5
	end
	
	if not (cv_bumpdamage.value) then return end
    
    if leveltime < starttime+TICRATE*3 then return end

    if not mobj2.valid then return end
	local p1, p2 = mobj1.player, mobj2.player

    if mobj2.player then

        if not (shouldHurt(p1) and shouldHurt(p2)) then return end

        if not ((mobj1.z >= mobj2.z and mobj1.z < mobj2.z + mobj2.height)
        or (mobj2.z >= mobj1.z and mobj2.z < mobj1.z + mobj1.height)) then
            return
        end

		if p1.kartstuff[k_sneakertimer] and p1.kartstuff[k_sneakertimer]
		or not (p1.kartstuff[k_sneakertimer] or p2.kartstuff[k_sneakertimer]) then
			return
		end

        local attacker, victim
        --detect who wins fight
        if p1.kartstuff[k_sneakertimer] > p2.kartstuff[k_sneakertimer] then
            attacker = mobj1
            victim = p2
        else
            attacker = mobj2
            victim = p1
        end
        hpmod_damagehp(victim, 10, attacker.player)
        K_SpinPlayer(victim, attacker, 1, attacker, false)
        
    end
    
end

local function hpmodIntermission()
	hud.enable("battlerankingsbumpers")
	hud.enable("gametypeinfo")
end

addHook("NetVars", hpmodNet)
addHook("ThinkFrame", hpmodThink)
addHook("PlayerSpawn", hpmodRespawn)
addHook("MobjDeath", hpmodDeath, MT_PLAYER)
addHook("MobjCollide", hpmodBumpFight, MT_PLAYER)
addHook("PlayerSpin", hpmodSpin)
addHook("PlayerExplode", hpmodExplode)
addHook("PlayerSquish", hpmodSquish)
addHook("IntermissionThinker", hpmodIntermission)

local WARNITEMDAMAGETABLE = {
	[KITEM_BANANA] = 10,
	[KITEM_THUNDERSHIELD] = 10,
	[KITEM_ORBINAUT] = 15,
	[KITEM_JAWZ] = 15,
	[KITEM_BALLHOG] = 15,
	[KITEM_INVINCIBILITY] = 20,
	[KITEM_SNEAKER] = 20,
	[KITEM_EGGMAN] = 20,
	[KITEM_MINE] = 20,
	[KITEM_GROW] = 20,
	[KITEM_SPB] = 30,
	[KITEM_KITCHENSINK] = 30,
}

--Thinker for the health waring indicator
local function hpmodHpwarnThink(mo)
	local dp = displayplayers[mo.displayplayern]
	local tp = players[mo.targetplayern]
	if mo.displayplayern <= splitscreen
	and dp and dp.valid and not dp.spectator
	and tp and tp.valid and not (dp == tp) and not tp.spectator
	and tp.hpmod and tp.hpmod.hp <= LOW_HP_LEVEL
	and not (tp.pflags&PF_TIMEOVER) then
		mo.flags2 = $&~MF2_DONTDRAW
		P_TeleportMove(mo, tp.mo.x, tp.mo.y, tp.mo.z + FixedMul(48*FRACUNIT, tp.mo.scale))
		mo.momx = tp.mo.momx
		mo.momy = tp.mo.momy
		mo.momz = tp.mo.momz
		mo.scale = tp.mo.scale
		if ((WARNITEMDAMAGETABLE[dp.kartstuff[k_itemtype]]
		and tp.hpmod.hp <= WARNITEMDAMAGETABLE[dp.kartstuff[k_itemtype]])
		or (dp.kartstuff[k_invincibilitytimer] and tp.hpmod.hp <= 20)
		or (dp.mo.scale>tp.mo.scale and tp.hpmod.hp <= 20)
		or (dp.kartstuff[k_eggmanexplode] and tp.hpmod.hp <= 20)
		or (dp.kartstuff[k_sneakertimer] and not tp.kartstuff[k_sneakertimer] and tp.hpmod.hp <= 20))
		and leveltime&4 and cv_combatdamage.value then
			mo.color = SKINCOLOR_CRIMSON
		else
			mo.color = SKINCOLOR_BLUE
		end
	else
		mo.flags2 = $|MF2_DONTDRAW
	end
end

addHook("MobjThinker", hpmodHpwarnThink, MT_HPWARNING)

--thinker for battle bumpers to not draw
local function hpmodBumperThink(mo)
	if leveltime > 1 and hpmod.running then
		P_RemoveMobj(mo)
	end
end

addHook("MobjThinker", hpmodBumperThink, MT_BATTLEBUMPER)

local function hpmodHud(v, p)

	if not bargfx then
		bargfx = {}
		for i = 1, 7 do
			bargfx[2^(i-1)] = {}
			for k = 1, 3 do
				bargfx[2^(i-1)][k] = v.cachePatch("HPBAR" .. i .. k)
			end
		end
	end
	
	if not barbggfx then
		barbggfx = {}
		for k = 1, 3 do
			barbggfx[k] = v.cachePatch("HPBG" .. k)
		end
	end
	
	if not barlinegfx then
		barlinegfx = {}
		for k = 1, 3 do
			barlinegfx[k] = v.cachePatch("HPLINE" .. k)
		end
	end

	--calculate RETIRE string width
	if not retirelen then
		retirelen = 0
		for i = 1, retirestr:len() do
			local let = retirestr:sub(i, i)
			local patch = v.cachePatch(string.format("MKFNT%03d", let:byte()))
			retirelen = $+patch.width
		end
	end
	
	if not hpmod.running then return end

	if not (p and p.valid and not p.spectator) then return end
	if not p.hpmod then return end
	
	local pdisp = nil
	for i = 0, splitscreen do
		if displayplayers[i] == p then
			pdisp = i
		end
	end
	if pdisp == nil then return end
	
	local barwidth = splitscreen&2 and HPBARWIDTH/2 or HPBARWIDTH
	local barx = splitscreen&2 and (80-barwidth/2) + (160*(pdisp&1)) or 160-barwidth/2
	local bary = 180
	local gfxset = 1
	local vflags = V_HUDTRANS
	local centerx = splitscreen&2 and 80 + (160*(pdisp&1)) or 160
	local centery = 100
	
	if splitscreen then
		--oh good lets go figgure out what y to put this bar on
		--its either 80 or 180
		if splitscreen == 1 then --2 player
			bary = pdisp and 190 or 90
			centery = pdisp and 150 or 50
			gfxset = 2
			if pdisp == 1 then
				vflags = $|V_SNAPTOBOTTOM
			end
		else --3 or 4 player (they work the same for our purpiaies
			bary = pdisp&2 and 190 or 90
			centery = pdisp&2 and 150 or 50

			gfxset = 3
			if pdisp&1 then
				vflags = $|V_SNAPTORIGHT
			else
				vflags = $|V_SNAPTOLEFT
			end
			if pdisp&2 then
				vflags = $|V_SNAPTOBOTTOM
			end
		end
	else
		vflags = $|V_SNAPTOBOTTOM
	end
	
	--do this first so we can hide the bar if needed
	if p.hpmod.deathtimer >= cv_deathdelay.value then
		v.drawKartString(centerx-(retirelen/2), centery-6, retirestr, V_HUDTRANS)
	end

	if not (hpmod_showbar) then return end
	
	--calculate bar length (for lower or higher hp games)
	
	--draw bar bg
	v.draw(barx - 2, bary-1, barbggfx[gfxset], vflags)

	if p.hpmod.minhp > p.hpmod.hp then --regainable hp
		local barlen = FixedInt(FixedDiv(p.hpmod.minhp, hpmod.maxhp)*barwidth)
		local barLenght = max(min(barlen, barwidth), 0)
		local xoff = 0
		local s = 1
		while barLenght ~= 0 do
			local bit = barLenght&s
			barLenght = barLenght&!s
			if bit then
				v.draw(barx + xoff, bary+1, bargfx[bit][gfxset], (vflags&~V_HUDTRANS)|V_HUDTRANSHALF, v.getColormap(0, SKINCOLOR_BLUEBERRY))
				xoff = $+(bargfx[bit][gfxset].width)
			end
			s = $<<1
		end
	end
	
	if p.hpmod.laghp > p.hpmod.hp then --latent hp
		local barlen = FixedInt(FixedDiv(p.hpmod.laghp, hpmod.maxhp)*barwidth)
		local barLenght = max(min(barlen, barwidth), 0)
		local xoff = 0
		local s = 1
		while barLenght ~= 0 do
			local bit = barLenght&s
			barLenght = barLenght&!s
			if bit then
				v.draw(barx + xoff, bary+1, bargfx[bit][gfxset], vflags, v.getColormap(0, SKINCOLOR_CRIMSON))
				xoff = $+(bargfx[bit][gfxset].width)
			end
			s = $<<1
		end
	end

	do --current hp
		local barlen = FixedInt(FixedDiv(p.hpmod.hp, hpmod.maxhp)*barwidth)
		local barLenght = max(min(barlen, barwidth), 0)
		local xoff = 0
		local s = 1
		while barLenght ~= 0 do
			local bit = barLenght&s
			barLenght = barLenght&!s
			if bit then
				v.draw(barx + xoff, bary+1, bargfx[bit][gfxset], vflags, v.getColormap(0, p.skincolor))
				xoff = $+(bargfx[bit][gfxset].width)
			end
			s = $<<1
		end
	end
	
	local fnt = "left"
	if splitscreen then
		bary = $+5
		fnt = "small"
	end
	
	--draw hp number + line
	local barlen = FixedInt(FixedDiv(p.hpmod.hp, hpmod.maxhp)*barwidth)
	do
		local extravflags = 0
		if lowHpNumberFlashTimer
		and not p.exiting
		and not p.hpmod.deathtimer
		and not (p.pflags & PF_TIMEOVER) then
			extravflags = V_REDMAP
		end
		v.drawString(barx + barlen + 1, bary-10, p.hpmod.hp, vflags|extravflags, fnt)
	end
	v.draw(barx + barlen - 1, bary-12, barlinegfx[gfxset], vflags)

	if ((exitTimer > 15*TICRATE and exitTimer < 20*TICRATE
	and (exitTimer&2))
	or exitTimer > 20*TICRATE)
	and not (p.exiting or p.hpmod.deathtimer) then
		local voff = 11
		if splitscreen then
			voff = 0
		end
		v.drawString(barx + 1 , bary+voff, "HURRY UP!", vflags, fnt)
	end
	
	if not splitscreen and cv_itemabosrb.value and p.kartstuff[k_itemtype] ~= 0 and p.kartstuff[k_itemheld] ~= 1 then
		v.drawString(10, 56, "Custom 2 - Absorb item " + cv_healamount.value + "hp", V_ALLOWLOWERCASE|V_SNAPTOTOP|V_SNAPTOLEFT, "small")
	end

end
hud.add(hpmodHud, "game")

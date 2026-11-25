skillsWindow = nil
skillsButton = nil
REGEN_OPCODE = 131
regenStatus = nil
regenEvent = nil

function init()
  connect(LocalPlayer, {
    onExperienceChange = onExperienceChange,
    onLevelChange = onLevelChange,
    onHealthChange = onHealthChange,
    onManaChange = onManaChange,
    onSoulChange = onSoulChange,
    onFreeCapacityChange = onFreeCapacityChange,
    onTotalCapacityChange = onTotalCapacityChange,
    onRegenerationChange = onRegenerationChange,
    onSpeedChange = onSpeedChange,
    onBaseSpeedChange = onBaseSpeedChange,
	onOfflineTrainingChange = onOfflineTrainingChange,
    onMagicLevelChange = onMagicLevelChange,
    onBaseMagicLevelChange = onBaseMagicLevelChange,
    onSkillChange = onSkillChange,
    onBaseSkillChange = onBaseSkillChange
  })
  connect(g_game, {
    onGameStart = refresh,
    onGameEnd = offline
  })
  ProtocolGame.registerExtendedOpcode(REGEN_OPCODE, onRegenStatus, true)

  -- skillsButton = modules.client_topmenu.addRightGameToggleButton('skillsButton', tr('Skills'), '/images/topbuttons/skills', toggle)
  skillsButton = modules.game_playerbars.skillsButton
  skillsButton:setOn(true)
  skillsWindow = g_ui.loadUI('skills', modules.game_interface.getRightPanel())
  
  refresh()
  skillsWindow:setup()
  modules.game_playerbars.bindPanel('skills', skillsWindow)
end

function terminate()
  disconnect(LocalPlayer, {
    onExperienceChange = onExperienceChange,
    onLevelChange = onLevelChange,
    onHealthChange = onHealthChange,
    onManaChange = onManaChange,
    onSoulChange = onSoulChange,
    onFreeCapacityChange = onFreeCapacityChange,
    onTotalCapacityChange = onTotalCapacityChange,
    onRegenerationChange = onRegenerationChange,
    onSpeedChange = onSpeedChange,
    onBaseSpeedChange = onBaseSpeedChange,
	onOfflineTrainingChange = onOfflineTrainingChange,
    onMagicLevelChange = onMagicLevelChange,
    onBaseMagicLevelChange = onBaseMagicLevelChange,
    onSkillChange = onSkillChange,
    onBaseSkillChange = onBaseSkillChange
  })
  disconnect(g_game, {
    onGameStart = refresh,
    onGameEnd = offline
  })
  ProtocolGame.unregisterExtendedOpcode(REGEN_OPCODE)
  if regenEvent then regenEvent:cancel() regenEvent = nil end

  modules.game_playerbars.unbindPanel('skills')
  skillsWindow:destroy()
end

function expForLevel(level)
  return math.floor((50*level*level*level)/3 - 100*level*level + (850*level)/3 - 200)
end

function expToAdvance(currentLevel, currentExp)
  return expForLevel(currentLevel+1) - currentExp
end

function resetSkillColor(id)
  local skill = skillsWindow:recursiveGetChildById(id)
  local widget = skill:getChildById('value')
  widget:setColor('#bbbbbb')
end

function toggleSkill(id, state)
  local skill = skillsWindow:recursiveGetChildById(id)
  if id == 'skillId' .. Skill.CriticalChance or id == 'skillId' .. Skill.CriticalDamage then
    state = false
  end
  skill:setVisible(state)
end

function setSkillBase(id, value, baseValue)
  if baseValue <= 0 or value < 0 then
    return
  end
  local skill = skillsWindow:recursiveGetChildById(id)
  local widget = skill:getChildById('value')

  if value > baseValue then
    widget:setColor('#008b00') -- green
    skill:setTooltip(baseValue .. ' +' .. (value - baseValue))
  elseif value < baseValue then
    widget:setColor('#b22222') -- red
    skill:setTooltip(baseValue .. ' ' .. (value - baseValue))
  else
    widget:setColor('#bbbbbb') -- default
    skill:removeTooltip()
  end
end

function setSkillValue(id, value)
  local skill = skillsWindow:recursiveGetChildById(id)
  local widget = skill:getChildById('value')
  widget:setText(value)
end

function setSkillColor(id, value)
  local skill = skillsWindow:recursiveGetChildById(id)
  local widget = skill:getChildById('value')
  widget:setColor(value)
end

function setSkillTooltip(id, value)
  local skill = skillsWindow:recursiveGetChildById(id)
  local widget = skill:getChildById('value')
  widget:setTooltip(value)
end

-- fill color of each bar, kept so the bar can be emptied at 0%
local fillColors = {}

function setSkillPercent(id, percent, tooltip, color)
  local skill = skillsWindow:recursiveGetChildById(id)
  local widget = skill:getChildById('percent')
  if widget then
    local value = math.floor(percent)
    widget:setPercent(value)

    if tooltip then
      widget:setTooltip(tooltip)
    end

    if color then
      fillColors[id] = color
    elseif not fillColors[id] then
      fillColors[id] = widget:getBackgroundColor()
    end
    -- the progress bar always draws at least 1 px of fill; hide it at 0%
    widget:setBackgroundColor(value > 0 and fillColors[id] or '#00000000')
  end
end

function checkAlert(id, value, maxValue, threshold, greaterThan)
  if greaterThan == nil then greaterThan = false end
  local alert = false

  -- maxValue can be set to false to check value and threshold
  -- used for regeneration checking
  if type(maxValue) == 'boolean' then
    if maxValue then
      return
    end

    if greaterThan then
      if value > threshold then
        alert = true
      end
    else
      if value < threshold then
        alert = true
      end
    end
  elseif type(maxValue) == 'number' then
    if maxValue < 0 then
      return
    end

    local percent = math.floor((value / maxValue) * 100)
    if greaterThan then
      if percent > threshold then
        alert = true
      end
    else
      if percent < threshold then
        alert = true
      end
    end
  end

  if alert then
    setSkillColor(id, '#b22222') -- red
  else
    resetSkillColor(id)
  end
end

function update()
  local soulPoints = skillsWindow:recursiveGetChildById('soul')
  soulPoints:hide()
  
  local speedPoints = skillsWindow:recursiveGetChildById('speed')
  speedPoints:show()
  
  local regenerationTime = skillsWindow:recursiveGetChildById('regenerationTime')
  if not g_game.getFeature(GamePlayerRegenerationTime) then
    regenerationTime:hide()
  else
	regenerationTime:show()
  end
end

function refresh()
  local player = g_game.getLocalPlayer()
  if not player then return end

  if expSpeedEvent then expSpeedEvent:cancel() end
  expSpeedEvent = cycleEvent(checkExpSpeed, 30*1000)
  startRegen()

  onExperienceChange(player, player:getExperience())
  onLevelChange(player, player:getLevel(), player:getLevelPercent())
  onHealthChange(player, player:getHealth(), player:getMaxHealth())
  onManaChange(player, player:getMana(), player:getMaxMana())
  onSoulChange(player, player:getSoul())
  onFreeCapacityChange(player, player:getFreeCapacity())
  onMagicLevelChange(player, player:getMagicLevel(), player:getMagicLevelPercent())
  onOfflineTrainingChange(player, player:getOfflineTrainingTime())
  onRegenerationChange(player, player:getRegenerationTime())
  onSpeedChange(player, player:getSpeed())

  local hasAdditionalSkills = g_game.getFeature(GameAdditionalSkills)
  for i = Skill.Fist, Skill.ManaLeechAmount do
    onSkillChange(player, i, player:getSkillLevel(i), player:getSkillLevelPercent(i))
    onBaseSkillChange(player, i, player:getSkillBaseLevel(i))

    if i > Skill.Fishing then
      toggleSkill('skillId'..i, hasAdditionalSkills)
    end
  end

  update()

  local contentsPanel = skillsWindow:getChildById('contentsPanel')
  skillsWindow:setContentMinimumHeight(44)
  if hasAdditionalSkills then
    skillsWindow:setContentMaximumHeight(514)
  else
    skillsWindow:setContentMaximumHeight(424)
  end
end

function offline()
  if expSpeedEvent then expSpeedEvent:cancel() expSpeedEvent = nil end
  if regenEvent then regenEvent:cancel() regenEvent = nil end
  regenStatus = nil
end

-- Food and water time left, sent by the server on opcode 131 and counted down here.
local function formatRegen(seconds)
  if seconds <= 0 then return '-' end
  local minutes = math.floor(seconds / 60)
  local rest = seconds % 60
  return minutes .. ':' .. (rest < 10 and '0' .. rest or rest)
end

function updateRegen()
  if not skillsWindow then return end
  local food, water = 0, 0
  if regenStatus then
    local elapsed = os.time() - regenStatus.time
    food = math.max(0, regenStatus.food - elapsed)
    water = math.max(0, regenStatus.water - elapsed)
  end
  setSkillValue('food', formatRegen(food))
  checkAlert('food', food, false, 60)
  setSkillValue('water', formatRegen(water))
  checkAlert('water', water, false, 60)
  updateRegenRates(food, water)
end

-- Health and mana regeneration, from the sources the server sends on opcode 131:
-- food (vocation), water (mana only) and the exploration chest bonuses.
local function formatAmount(value)
  if math.abs(value - math.floor(value + 0.5)) < 0.05 then
    return tostring(math.floor(value + 0.5))
  end
  return string.format('%.1f', value)
end

local function readSource(source)
  if type(source) ~= 'table' then return nil end
  local amount, seconds = tonumber(source[1]) or 0, tonumber(source[2]) or 0
  if amount <= 0 or seconds <= 0 then return nil end
  return {amount = amount, seconds = seconds}
end

local function showRate(id, label, sources)
  local list = {}
  for _, entry in ipairs(sources) do
    local source = readSource(entry.source)
    if source then
      source.name = entry.name
      table.insert(list, source)
    end
  end
  local skill = skillsWindow:recursiveGetChildById(id)
  local text, tooltip = '-', label .. ': none (eat food to regenerate).'
  if #list > 0 then
    -- shown over the period of the first source (food when fed)
    local period, total = list[1].seconds, 0
    local lines = {}
    for _, source in ipairs(list) do
      total = total + source.amount * period / source.seconds
      table.insert(lines, source.name .. ': ' .. formatAmount(source.amount) .. ' every ' .. formatAmount(source.seconds) .. 's')
    end
    text = formatAmount(total) .. ' / ' .. formatAmount(period) .. 's'
    tooltip = label .. ' ' .. text .. '\n' .. table.concat(lines, '\n') ..
      '\nNo regeneration inside protection zones.'
  end
  setSkillValue(id, text)
  skill:setTooltip(tooltip)
  skill:getChildById('value'):setTooltip(tooltip)
end

function updateRegenRates(food, water)
  local regen = regenStatus and regenStatus.regen or {}
  local fed, chests = type(regen.food) == 'table' and regen.food or {}, type(regen.chests) == 'table' and regen.chests or {}
  local drink = type(regen.water) == 'table' and regen.water or {}
  local hp, mana = {}, {}
  if food > 0 then
    table.insert(hp, {name = 'Food', source = fed.hp})
    table.insert(mana, {name = 'Food', source = fed.mana})
  end
  if water > 0 then
    table.insert(mana, {name = 'Water', source = drink.mana})
  end
  table.insert(hp, {name = 'Treasure chests', source = chests.hp})
  table.insert(mana, {name = 'Treasure chests', source = chests.mana})
  showRate('hpRegen', 'HP regen', hp)
  showRate('manaRegen', 'Mana regen', mana)
end

local regenTicks = 0
local function requestRegen()
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() and g_game.getFeature(GameExtendedOpcode) then
    protocol:sendExtendedOpcode(REGEN_OPCODE, '{"action":"sync"}')
  end
end

local function regenTick()
  updateRegen()
  regenTicks = regenTicks + 1
  if regenTicks % 30 == 0 then requestRegen() end
end

function onRegenStatus(protocol, opcode, buffer)
  local ok, data = pcall(function() return json.decode(buffer) end)
  if not ok or type(data) ~= 'table' or data.action ~= 'status' then return end
  regenStatus = {food = math.max(0, math.floor(tonumber(data.food) or 0)),
    water = math.max(0, math.floor(tonumber(data.water) or 0)), time = os.time(),
    regen = type(data.regen) == 'table' and data.regen or nil}
  updateRegen()
end

function startRegen()
  if regenEvent then regenEvent:cancel() end
  regenTicks = 0
  regenEvent = cycleEvent(regenTick, 1000)
  updateRegen()
  scheduleEvent(requestRegen, 1000)
end

function toggle()
	if skillsWindow:isVisible() then
		if not modules.game_playerbars.skillsButton:isChecked() then
			skillsWindow:close()
		end
	else
		if modules.game_playerbars.skillsButton:isChecked() then
			skillsWindow:open()
		end
	end
end

function checkExpSpeed()
  local player = g_game.getLocalPlayer()
  if not player then return end

  local currentExp = player:getExperience()
  local currentTime = g_clock.seconds()
  if player.lastExps ~= nil then
    player.expSpeed = (currentExp - player.lastExps[1][1])/(currentTime - player.lastExps[1][2])
    onLevelChange(player, player:getLevel(), player:getLevelPercent())
  else
    player.lastExps = {}
  end
  table.insert(player.lastExps, {currentExp, currentTime})
  if #player.lastExps > 30 then
    table.remove(player.lastExps, 1)
  end
end

function onMiniWindowClose()
	modules.game_playerbars.skillsButton:setChecked(false)
end

function onSkillButtonClick(button)
  local percentBar = button:getChildById('percent')
  if percentBar then
    percentBar:setVisible(not percentBar:isVisible())
    if percentBar:isVisible() then
      button:setHeight(21)
    else
      button:setHeight(21 - 6)
    end
  end
end

function onExperienceChange(localPlayer, value)
  local postFix = ""
  if value > 1e15 then
	postFix = "B"
	value = math.floor(value / 1e9)
  elseif value > 1e12 then
	postFix = "M"
	value = math.floor(value / 1e6)
  elseif value > 1e9 then
	postFix = "K"
	value = math.floor(value / 1e3)
  end
  setSkillValue('experience', comma_value(value) .. postFix)
end

function onLevelChange(localPlayer, value, percent)
  setSkillValue('level', value)
  local text = tr('You have %s percent to go', 100 - percent) .. '\n' ..
               tr('%s of experience left', expToAdvance(localPlayer:getLevel(), localPlayer:getExperience()))

  if localPlayer.expSpeed ~= nil then
     local expPerHour = math.floor(localPlayer.expSpeed * 3600)
     if expPerHour > 0 then
        local nextLevelExp = expForLevel(localPlayer:getLevel()+1)
        local hoursLeft = (nextLevelExp - localPlayer:getExperience()) / expPerHour
        local minutesLeft = math.floor((hoursLeft - math.floor(hoursLeft))*60)
        hoursLeft = math.floor(hoursLeft)
        text = text .. '\n' .. tr('%d of experience per hour', expPerHour)
        text = text .. '\n' .. tr('Next level in %d hours and %d minutes', hoursLeft, minutesLeft)
     end
  end

  setSkillPercent('level', percent, text)
end

function onHealthChange(localPlayer, health, maxHealth)
  setSkillValue('health', health)
  checkAlert('health', health, maxHealth, 30)
end

function onManaChange(localPlayer, mana, maxMana)
  setSkillValue('mana', mana)
  checkAlert('mana', mana, maxMana, 30)
end

function onSoulChange(localPlayer, soul)
  setSkillValue('soul', soul)
end

function onFreeCapacityChange(localPlayer, freeCapacity)
  setSkillValue('capacity', freeCapacity * 100)
  checkAlert('capacity', freeCapacity, localPlayer:getTotalCapacity(), 20)
end

function onTotalCapacityChange(localPlayer, totalCapacity)
  checkAlert('capacity', localPlayer:getFreeCapacity(), totalCapacity, 20)
end

function onRegenerationChange(localPlayer, regenerationTime)
  if not g_game.getFeature(GamePlayerRegenerationTime) or regenerationTime < 0 then
    return
  end
  local minutes = math.floor(regenerationTime / 60)
  local seconds = regenerationTime % 60
  if seconds < 10 then
    seconds = '0' .. seconds
  end

  setSkillValue('regenerationTime', minutes .. ":" .. seconds)
  checkAlert('regenerationTime', regenerationTime, false, 300)
end

function onSpeedChange(localPlayer, speed)
  setSkillValue('speed', speed)

  onBaseSpeedChange(localPlayer, localPlayer:getBaseSpeed())
end

function onOfflineTrainingChange(localPlayer, offlineTrainingTime)
  if not g_game.getFeature(GameOfflineTrainingTime) then
    return
  end
  local hours = math.floor(offlineTrainingTime / 60)
  local minutes = offlineTrainingTime % 60
  if minutes < 10 then
    minutes = '0' .. minutes
  end
  local percent = 100 * offlineTrainingTime / (12 * 60) -- max is 12 hours

  setSkillValue('offlineTraining', hours .. ":" .. minutes)
  setSkillPercent('offlineTraining', percent, tr('You have %s percent', percent))
end

function onBaseSpeedChange(localPlayer, baseSpeed)
  setSkillBase('speed', localPlayer:getSpeed(), baseSpeed)
end

function onMagicLevelChange(localPlayer, magiclevel, percent)
  setSkillValue('magiclevel', magiclevel)
  setSkillPercent('magiclevel', percent, tr('You have %s percent to go', 100 - percent))

  onBaseMagicLevelChange(localPlayer, localPlayer:getBaseMagicLevel())
end

function onBaseMagicLevelChange(localPlayer, baseMagicLevel)
  setSkillBase('magiclevel', localPlayer:getMagicLevel(), baseMagicLevel)
end

function onSkillChange(localPlayer, id, level, percent)
  setSkillValue('skillId' .. id, level)
  setSkillPercent('skillId' .. id, percent, tr('You have %s percent to go', 100 - percent))

  onBaseSkillChange(localPlayer, id, localPlayer:getSkillBaseLevel(id))
end

function onBaseSkillChange(localPlayer, id, baseLevel)
  setSkillBase('skillId'..id, localPlayer:getSkillLevel(id), baseLevel)
end

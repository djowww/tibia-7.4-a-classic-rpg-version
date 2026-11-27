local function clientFile(relative)
	for _, prefix in ipairs({'client/', 'Servidor/TFS/client/', 'Cliente/', '../../Cliente/'}) do
		local path = prefix .. relative
		local file = io.open(path, 'r')
		if file then file:close(); return path end
	end
	error('Client file not found: ' .. relative)
end

dofile(clientFile('modules/corelib/json.lua'))

-- OTClient resolves sibling anchors as widget dependencies, even when the
-- edges affect different axes. A mutual dependency can prevent UI creation.
local function checkAnchorGraph(source)
	local root, stack, dependencyCount = {children={}}, {}, 0
	for line in source:gmatch('[^\r\n]+') do
		local whitespace, text = line:match('^(%s*)(.-)%s*$')
		local indent = #whitespace
		local widgetClass = text:match('^([%a_][%w_]*)$')
			or text:match('^([%a_][%w_]*)%s*<%s*[%w_]+$')
		if widgetClass then
			while #stack > 0 and stack[#stack].indent >= indent do table.remove(stack) end
			local parent = stack[#stack] or root
			local widget = {indent=indent,children={},anchors={},class=widgetClass}
			parent.children[#parent.children+1] = widget
			stack[#stack+1] = widget
		elseif #stack > 0 then
			local widget = stack[#stack]
			local id = text:match('^id:%s*([%w_]+)$')
			if id then widget.id=id end
			local target = text:match('^anchors%.[%w_]+:%s*([%w_]+)%.[%w_]+$')
			if target and target ~= 'parent' then widget.anchors[#widget.anchors+1]=target end
		end
	end
	local function checkScope(parent)
		local siblings, state = {}, {}
		for _, widget in ipairs(parent.children) do
			if widget.id then siblings[widget.id]=widget end
		end
		local function visit(widget)
			if state[widget] == 1 then return false, 'Anchor dependency cycle at ' .. (widget.id or widget.class) end
			if state[widget] == 2 then return true end
			state[widget]=1
			for _, target in ipairs(widget.anchors) do
				local dependency = siblings[target]
				if dependency then
					dependencyCount=dependencyCount+1
					local ok, reason=visit(dependency)
					if not ok then return false, reason end
				end
			end
			state[widget]=2
			return true
		end
		for _, widget in ipairs(parent.children) do
			local ok, reason=visit(widget)
			if not ok then return false, reason end
			ok, reason=checkScope(widget)
			if not ok then return false, reason end
		end
		return true
	end
	local ok, reason=checkScope(root)
	return ok, reason, dependencyCount
end

assert(not checkAnchorGraph([[Panel
  Panel
    id: list
    anchors.right: scroll.left
  Panel
    id: scroll
    anchors.top: list.bottom
]]), 'the checker must catch cycles across different coordinate axes')
assert(checkAnchorGraph([[Panel
  Panel
    id: list
    anchors.right: scroll.left
  Panel
    id: scroll
    anchors.top: parent.top
]]), 'ordinary sibling anchors must remain valid')
local otuiFile=assert(io.open(clientFile('modules/game_achievements/achievements.otui'), 'r'))
local otui=otuiFile:read('*a')
otuiFile:close()
local anchorsValid, anchorError, dependencies=checkAnchorGraph(otui)
assert(anchorsValid, anchorError)
assert(dependencies>0, 'the actual UI anchor dependencies must be inspected')

local callbacks, sent, events = {}, {}, {}
local unread, eventId, now, online, featureEnabled = 0, 0, 0, true, false
local gameEvents, windowEvents = {}, {}
local rootSize = {width=1024, height=640}

-- A widget that records what the module sets on it. Children named in the
-- OTUI are reachable as fields, like in the client.
local function widget(class)
	local self = {class=class, children={}, visible=true}
	function self:setText(value) self.text=value end
	function self:setTooltip(value) self.tooltip=value end
	function self:setEnabled(value) self.enabled=value end
	function self:setVisible(value) self.visible=value end
	function self:isVisible() return self.visible end
	function self:setColor(value) self.color=value end
	function self:setBackgroundColor(value) self.background=value end
	function self:setPercent(value) self.percent=value end
	function self:setWidth(value) self.width=value end
	function self:setSize(value) self.width,self.height=value.width,value.height end
	function self:setMarginLeft(value) self.marginLeft=value end
	function self:setMarginTop(value) self.marginTop=value end
	function self:setImageSource(value) self.image=value end
	function self:setImageClip(value) self.clip=value end
	function self:setBorderWidth(value) self.borderWidth=value end
	function self:destroyChildren() self.children={} end
	function self:show() self.visible=true end
	function self:hide() self.visible=false end
	function self:raise() end
	function self:focus() end
	function self:destroy() self.destroyed=true end
	return self
end
local window = widget('MainWindow')
window.visible=false
for _, id in ipairs({'hall','rankIcon','rankName','rankBar','message','bonuses','claimButton','plaque','tiers'}) do window[id]=widget(id) end
for _, id in ipairs({'speed','attack','pvp','death'}) do
	local chip=widget('HallBonus'); chip.icon=widget('icon'); chip.value=widget('value'); window.bonuses[id]=chip
end
window.plaque.bigFrame=widget('bigFrame'); window.plaque.bigFrame.bigItem=widget('bigItem')
for _, id in ipairs({'trackName','bar','reward'}) do window.plaque[id]=widget(id) end
window.tiers.tierRow = widget('tierRow')
for tier=1,5 do
	local box=widget('HallTier'); box.slot=widget('slot'); box.slot.item=widget('item'); box.caption=widget('caption')
	window.tiers.tierRow['tier'..tier]=box
end
for _, id in ipairs({'hall','rankIcon','rankName','rankBar','message','bonuses','speed','attack','pvp','death','icon','value','claimButton','plaque','tiers','bigFrame','bigItem',
	'trackName','bar','reward','tierRow','tier1','tier5','slot','item','caption'}) do
	assert(otui:find('id: '..id..'\n',1,true), 'the OTUI must declare '..id)
end

g_game = {
	isOnline=function() return online end,
	getFeature=function() return featureEnabled end,
	getProtocolGame=function() return {sendExtendedOpcode=function(_,opcode,message)
		assert(opcode==126 and type(message)=='string')
		sent[#sent+1]=json.decode(message)
	end} end
}
g_clock = {millis=function() return now end}
GameExtendedOpcode = 1
g_ui = {
	displayUI=function() return window end,
	getRootWidget=function() return {getSize=function() return rootSize end} end,
	createWidget=function(name,parent)
		assert(parent==window.hall and ('\n'..otui):find('\n'..name..' < ',1,true), 'hall widgets use the styles of the OTUI: '..tostring(name))
		local child=widget(name)
		parent.children[#parent.children+1]=child
		return child
	end
}
ProtocolGame = {
	registerExtendedOpcode=function(opcode,callback,raw) assert(raw==true); callbacks[opcode]=callback end,
	unregisterExtendedOpcode=function(opcode) callbacks[opcode]=nil end
}
modules = {game_playerbars={setAchievementsUnread=function(count) unread=count end}}
function connect(target,handlers)
	assert(target==g_game or target==window)
	local handlersByTarget=target==g_game and gameEvents or windowEvents
	for name,callback in pairs(handlers) do handlersByTarget[name]=callback end
end
function disconnect(target,handlers)
	assert(target==g_game or target==window)
	local handlersByTarget=target==g_game and gameEvents or windowEvents
	for name,callback in pairs(handlers) do assert(handlersByTarget[name]==callback); handlersByTarget[name]=nil end
end
function scheduleEvent(callback,delay)
	eventId=eventId+1
	events[eventId]={callback=callback,due=now+delay}
	return eventId
end
function removeEvent(id) events[id]=nil end
local function advance(milliseconds)
	local target, iterations = now+milliseconds, 0
	while true do
		local nextId, due
		for id,event in pairs(events) do
			if event.due<=target and (not due or event.due<due or (event.due==due and id<nextId)) then
				nextId,due=id,event.due
			end
		end
		if not nextId then break end
		local event=events[nextId]
		events[nextId]=nil; now=due
		event.callback()
		iterations=iterations+1
		assert(iterations<100, 'timer callbacks must settle')
	end
	now=target
end

-- The server catalog: 12 tracks of 5 objectives. `values` gives the live
-- counter of each track; a tier is completed once the counter reaches it.
local prefixes={'steps_','level_','monsterKills_','pvpKills_','deaths_','skill_7_','skill_0_','skill_1_','skill_2_','skill_3_','skill_4_','skill_5_'}
local targets={steps_={100,1000,10000,100000,1000000},monsterKills_={100,1000,10000,100000,1000000},
	pvpKills_={1,10,100,1000,10000},deaths_={1,10,100,1000,10000},level_={20,50,100,150,200}}
local function catalog(id, values, options)
	options=options or {}
	local entries={}
	for index, prefix in ipairs(prefixes) do
		for tier, target in ipairs(targets[prefix] or {40,60,80,100,120}) do
			local value=values[index] or 0
			entries[#entries+1]={id=prefix..tier,title=(options.title or 'Objective ')..prefix..tier,category=prefix,
				reward=prefix=='steps_' and '+'..tier..' speed' or (options.reward or 'Rank progress'),
				progress=math.min(value,target),target=target,completed=value>=target}
		end
	end
	local result={}
	for page=1,5 do
		local part={}
		for index=(page-1)*12+1,page*12 do part[#part+1]=entries[index] end
		result[page]={action='progress',snapshotId=id,page=page,pages=5,entries=part,
			unread=options.unread or 4,bonuses={speed=6,attack=0,pvp=0,deathReduction=0}}
	end
	return result
end
local function receive(payload)
	local encoded=json.encode(payload)
	assert(#encoded<=7000, 'real paginated JSON fits the server wire limit')
	callbacks[126](nil,126,encoded)
end
local function receiveAll(snapshot)
	for _,payload in ipairs(snapshot) do receive(payload) end
end
local function count(class)
	local total=0
	for _,child in ipairs(window.hall.children) do if child.class==class then total=total+1 end end
	return total
end
local function hallWidgets(image)
	local list={}
	for _,child in ipairs(window.hall.children) do if child.image==image then list[#list+1]=child end end
	return list
end
local function spots()
	local list={}
	for _,child in ipairs(window.hall.children) do if child.class=='HallSpot' and child.onClick then list[#list+1]=child end end
	return list
end

dofile(clientFile('modules/game_achievements/achievements.lua'))
modules.game_achievements={claimRewards=claimRewards}
local claimHandler=assert(otui:match('id: claimButton.-@onClick:%s*([^\r\n]+)'), 'claim button needs a real click binding')
window.claimButton.onClick=assert((loadstring or load)('return function() '..claimHandler..' end'))()
function window.claimButton:click() if self.enabled then self.onClick() end end
init()
assert(not window.visible and #sent==0, 'init must wait for the extended-opcode handshake')
assert(#spots()==12 and #hallWidgets('/images/achievements/hall_items')==12 and #hallWidgets('/images/achievements/hall_light')==12
	and #hallWidgets('/images/achievements/hall_ranks')==6 and count('HallFrame')==12, 'the hall has twelve pedestals and six rank trophies')
assert(window.width==614 and window.hall.width==600 and window.plaque.marginTop==326, 'small screens get the room at zoom 1 with the plaques below')
assert(window.rankName.text=='Novice' and not window.claimButton.visible and not window.claimButton.enabled)
advance(999)
assert(#sent==0)
featureEnabled=true
advance(1)
assert(#sent==1 and sent[1].action=='getProgress', 'request follows the startup delay')

-- Pagination: partial, duplicate and obsolete pages never repaint the hall.
local today=catalog(10,{14382,8,63,0,0,0,10,10,10,10,10,10})
receive(today[2]); receive(today[2]); receive(today[1])
assert(window.rankBar.text=='' and window.rankBar.percent==0 and not window.bonuses.visible and unread==0,
	'out-of-order and duplicate pages cannot expose a partial catalog')
receive(catalog(9,{})[1])
receiveAll({today[3],today[4],today[5]})
assert(window.rankBar.text=='3 / 6' and window.rankBar.percent==50 and window.rankBar.tooltip=='3 more to reach Adventurer' and unread==4)
assert(window.bonuses.visible and window.bonuses.speed.value.text=='+6' and window.bonuses.death.value.text=='-0%' and window.message.text==''
	and window.bonuses.pvp.icon.clip.x==64)

-- The room: lit items, silhouettes, light and dots follow the completed tiers.
local items, lights = hallWidgets('/images/achievements/hall_items'), hallWidgets('/images/achievements/hall_light')
assert(items[1].clip.x==64 and items[1].clip.y==0, 'three steps objectives put the third boots on the first pedestal')
assert(lights[1].visible and lights[1].clip.x==256 and lights[1].clip.y==0)
assert(items[3].clip.x==160 and items[3].clip.y==64 and not lights[3].visible, 'an empty pedestal shows the first item as a silhouette, unlit')
local dots={}
for _,child in ipairs(window.hall.children) do if child.class=='HallImage' and child.background then dots[#dots+1]=child end end
assert(#dots==60 and dots[3].background=='#e6b84a' and dots[4].background=='#0c0c0c' and dots[11].background=='#0c0c0c')
local trophies=hallWidgets('/images/achievements/hall_ranks')
assert(trophies[1].clip.y==0 and trophies[2].clip.y==32 and trophies[2].tooltip=='Adventurer\n6 / 60')

-- The plaque follows the closest goal until the player clicks a pedestal.
assert(window.plaque.trackName.text=='Monsters defeated' and window.plaque.bar.text=='63 / 100' and window.plaque.bar.percent==63)
assert(window.plaque.reward.text=='' and window.plaque.bigFrame.tooltip=='', 'rank progress needs no reward text')
spots()[1].onClick()
assert(window.plaque.trackName.text=='Steps walked' and window.plaque.bar.text=='14,382 / 100,000' and window.plaque.reward.text=='+4 speed'
	and window.plaque.bigFrame.tooltip=='Steel boots')
local row=window.tiers.tierRow
assert(row.tier1.caption.text=='100' and row.tier4.caption.text=='100k' and row.tier5.caption.text=='1M')
assert(row.tier3.caption.color=='#8fbf7a' and row.tier4.caption.color=='#DDD8C6' and row.tier5.caption.color=='#8f8e84')
assert(row.tier4.tooltip=='Walk 100,000 steps\nBoots of haste\n+4 speed\n85,618 to go' and row.tier5.tooltip:find('Locked',1,true))
assert(row.tier3.slot.item.clip.x==64 and row.tier4.slot.item.clip.x==256, 'earned tiers are lit, the others are silhouettes')
local frames={}
for _,child in ipairs(window.hall.children) do if child.class=='HallFrame' then frames[#frames+1]=child end end
assert(frames[1].visible and not frames[3].visible)

-- Opening: big screens get zoom 2 with the plaques over the lower wall.
show()
assert(window.visible and unread==0 and sent[#sent].action=='markSeen' and window.width==614)
hide()
rootSize={width=1366,height=768}
show()
assert(window.width==1214 and window.height==675 and window.hall.width==1200 and window.plaque.marginTop==526 and window.tiers.marginLeft==734)
assert(#spots()==12 and window.plaque.trackName.text=='Steps walked', 'rebuilding the room keeps the catalog and the chosen pedestal')
assert(hallWidgets('/images/achievements/hall_items')[1].width==64 and window.plaque.bigFrame.width==68)
local beforeRefresh=#sent
refresh(); refresh()
assert(#sent==beforeRefresh, 'rapid refresh requests share a delayed request')
advance(2100)
assert(sent[#sent].action=='getProgress' and window.plaque.trackName.text=='Steps walked', 'refresh never blanks the hall')

-- Newer snapshots replace the hall only when complete.
local later=catalog(11,{184220,74,12840,14,23,6,22,31,86,44,38,82},{unread=0})
receive(later[1])
assert(window.rankBar.text=='3 / 6', 'a newer incomplete response preserves the rendered snapshot')
receiveAll({later[2],later[3],later[4],later[5]})
assert(window.rankName.text=='Veteran' and window.rankBar.text=='20 / 30' and window.rankIcon.clip.x==128)
assert(sent[#sent].action=='markSeen' and unread==0)
receiveAll(today)
assert(window.rankName.text=='Veteran', 'obsolete and completed duplicate snapshots are ignored')
spots()[9].onClick()
assert(window.plaque.bar.text:find(' / 100',1,true) and window.plaque.bigFrame.tooltip=='Two handed sword')

-- Timeouts keep the last complete hall.
advance(10000)
advance(5900)
assert(window.message.text:find('could not be updated',1,true) and window.rankName.text=='Veteran')
local duplicate=catalog(12,{})
duplicate[2].entries[1].id=duplicate[1].entries[1].id
receiveAll(duplicate)
assert(window.rankName.text=='Veteran', 'duplicate achievement ids invalidate an entire snapshot')
local invalid=catalog(13,{})
invalid[1].entries[1].progress=101
receiveAll(invalid)
assert(window.rankName.text=='Veteran', 'out-of-range progress invalidates a snapshot')

-- A server from before the trophy hall still names the retired reward.
receiveAll(catalog(14,{184220,74,12840,14,23,6,22,31,86,44,38,82},{reward='Item reward retired',unread=0}))
assert(window.plaque.reward.text=='')

-- Everything completed: Legend, every pedestal glowing.
receiveAll(catalog(15,{1e6,200,1e6,1e4,1e4,120,120,120,120,120,120,120},{unread=0}))
assert(window.rankName.text=='Legend' and window.rankBar.text=='60 / 60' and window.rankBar.percent==100)
local glows=hallWidgets('/images/achievements/hall_glow')
assert(#glows==12 and glows[1].visible and glows[12].visible and window.plaque.bar.text=='120')
assert(window.plaque.bar.percent==100 and window.plaque.bigFrame.tooltip=='Magic sword')
assert(hallWidgets('/images/achievements/hall_ranks')[6].clip.y==0 and hallWidgets('/images/achievements/hall_statue')[1].clip.x==800)

-- Hidden updates highlight the menu button; pending item rewards can be claimed.
hide()
receiveAll(catalog(16,{1e6,200,1e6,1e4,1e4,120,120,120,120,120,120,120}))
assert(not window.visible and unread==4, 'hidden updates restore the unread button highlight')
local pending=catalog(17,{14382,20,63,0,0,0,10,10,10,10,10,10},{unread=0})
pending[1].entries[6].completed=false; pending[1].entries[6].ready=true
assert(pending[1].entries[6].id=='level_1')
receiveAll(pending)
assert(unread==1 and window.claimButton.visible and window.message.text:find('Claim rewards',1,true))
show()
for _,page in ipairs(pending) do page.snapshotId=18 end
receiveAll(pending)
advance(2100)
local beforeClaim=#sent
window.claimButton:click()
advance(2100)
assert(sent[#sent].action=='claimRewards' and #sent==beforeClaim+1 and not window.claimButton.enabled)
window.claimButton:click(); refresh()
advance(2100)
assert(#sent==beforeClaim+1, 'duplicate claims and refreshes cannot overlap an in-flight claim')
local paid=catalog(20,{14382,20,63,0,0,0,10,10,10,10,10,10},{unread=0})
receiveAll(paid)
assert(unread==0 and not window.claimButton.visible and not window.claimButton.enabled, 'paying the pending item removes its badge')
local wrongReady=catalog(21,{})
wrongReady[1].entries[1].ready='yes'
receiveAll(wrongReady)
assert(window.rankBar.text=='4 / 6', 'ready must be a boolean when provided')
callbacks[126](nil,126,json.encode({action='seen'}))
assert(unread==0)

online=false; gameEvents.onGameEnd()
assert(not window.visible and unread==0 and next(events)==nil and not window.claimButton.enabled
	and window.rankBar.text=='' and not window.bonuses.visible
	and window.message.text:find('Connect to the game',1,true), 'logout clears per-character state and all timers')
assert(window.plaque.bar.text=='' and not hallWidgets('/images/achievements/hall_light')[1].visible)

online=true; gameEvents.onGameStart()
local beforeStartup=#sent
show()
assert(next(events)~=nil, 'startup, polling and request timers are active for termination coverage')
terminate()
assert(window.destroyed and callbacks[126]==nil and next(events)==nil and next(gameEvents)==nil and next(windowEvents)==nil)
advance(20000)
assert(#sent==beforeStartup+1, 'terminated timers cannot send subsequent requests')

print('PASS Achievements UI: trophy hall with 12 pedestals, tiers, light, rank trophies, plaque selection, both zooms, pending claim/cooldown/timeouts, stable pagination, real OTUI anchors, old-server compatibility and timer cleanup')

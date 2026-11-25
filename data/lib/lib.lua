-- Core API functions implemented in Lua
dofile('data/lib/core/core.lua')
dofile('data/lib/lamp_states.lua')

-- Compatibility library for our old Lua API
dofile('data/lib/compat/compat.lua')

dofile('data/lib/modalwindow.lua')

-- Crash-safe inventory/SQL changes for purchases and currency exchange.
dofile('data/lib/custom/economy.lua')

-- Persistent online bonus and fixed-point fractional gain accounting.
dofile('data/lib/custom/onlineBonus.lua')
dofile('data/lib/custom/regenStatus.lua')

-- Persistent per-character Bestiary kill progress.
dofile('data/lib/custom/antigasBestiary.lua')
dofile('data/lib/custom/antigasAchievements.lua')

-- Hidden exploration chests: one per region, permanent per-character rewards.
dofile('data/lib/custom/explorationChests.lua')

-- Behaviour-based bot detection: scores and staff alerts, no punishment.
dofile('data/lib/custom/botDetector.lua')

-- Staff command list for the client F1 window, read from talkactions.xml.
dofile('data/lib/custom/gmCommands.lua')

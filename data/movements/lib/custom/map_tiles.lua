-- Data-driven map tiles, shared by scripts/custom/teleport.lua and
-- scripts/custom/storage_flag.lua. Each entry is keyed by the movement id set on
-- the map tile; movements.xml decides which events (StepIn/AddItem) reach it.
--
-- This file is loaded once with the movements interface. The thin scripts are
-- loaded once per XML registration, so the tables must not live in them.

MapTiles = {}

-- Teleport rules. Everything movable on the source tile is relocated.
--   to          destination.
--   from        source tile; defaults to the tile carrying the movement id.
--   effects     magic effects sent after the relocation; an effect without
--               pos is shown on the tile carrying the movement id.
--   playerOnly  when stepping, only players trigger the tile. Items dropped
--               on the tile are never filtered by this flag.
--   addItem     true: an item dropped on the tile follows the same rule.
--               table: an item dropped on the tile follows that rule instead.
local teleports = {
	[9] = {from = {x = 32267, y = 31898, z = 12}, to = {x = 32267, y = 31886, z = 12}, playerOnly = true},
	[12] = {from = {x = 32266, y = 31898, z = 12}, to = {x = 32266, y = 31886, z = 12}, playerOnly = true},
	[13] = {from = {x = 32266, y = 31899, z = 12}, to = {x = 32266, y = 31911, z = 12}, playerOnly = true},
	[14] = {from = {x = 32265, y = 31899, z = 12}, to = {x = 32265, y = 31911, z = 12}, playerOnly = true},
	[15] = {from = {x = 32265, y = 31898, z = 12}, to = {x = 32265, y = 31886, z = 12}, playerOnly = true},
	[22] = {to = {x = 33199, y = 32699, z = 14}, effects = {{effect = 11}, {effect = 11, pos = {x = 33199, y = 32699, z = 14}}}, addItem = true},
	[23] = {to = {x = 33225, y = 32699, z = 14}, effects = {{effect = 11}, {effect = 11, pos = {x = 33225, y = 32699, z = 14}}}, addItem = true},
	[61] = {to = {x = 32566, y = 31959, z = 1}, effects = {{effect = 3, pos = {x = 32487, y = 31928, z = 7}}}, playerOnly = true},
	[76] = {to = {x = 33280, y = 32740, z = 10}, effects = {{effect = 11}, {effect = 11, pos = {x = 33280, y = 32740, z = 10}}}, addItem = true},
	[77] = {to = {x = 33280, y = 32740, z = 10}, effects = {{effect = 11}, {effect = 11, pos = {x = 33280, y = 32740, z = 10}}}, addItem = true},
	[78] = {to = {x = 33265, y = 32678, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33265, y = 32678, z = 13}}}, addItem = true},
	[79] = {to = {x = 33264, y = 32671, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33264, y = 32671, z = 13}}}, addItem = true},
	[80] = {to = {x = 33267, y = 32685, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33267, y = 32685, z = 13}}}, addItem = true},
	[81] = {to = {x = 33264, y = 32695, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33264, y = 32695, z = 13}}}, addItem = true},
	[83] = {to = {x = 33260, y = 32700, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33260, y = 32700, z = 13}}}, addItem = true},
	[84] = {to = {x = 33231, y = 32705, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33231, y = 32705, z = 8}}}, addItem = true},
	[85] = {to = {x = 33259, y = 32681, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33259, y = 32681, z = 13}}}, addItem = true},
	[86] = {to = {x = 33257, y = 32691, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33257, y = 32691, z = 13}}}, addItem = true},
	[87] = {to = {x = 33256, y = 32673, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33256, y = 32673, z = 13}}}, addItem = true},
	[88] = {to = {x = 33254, y = 32685, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33254, y = 32685, z = 13}}}, addItem = true},
	[89] = {to = {x = 33254, y = 32704, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33254, y = 32704, z = 13}}}, addItem = true},
	[90] = {to = {x = 33254, y = 32698, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33254, y = 32698, z = 13}}}, addItem = true},
	[91] = {to = {x = 33247, y = 32679, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33247, y = 32679, z = 13}}}, addItem = true},
	[92] = {to = {x = 33249, y = 32693, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33249, y = 32693, z = 13}}}, addItem = true},
	[93] = {to = {x = 33247, y = 32671, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33247, y = 32671, z = 13}}}, addItem = true},
	[94] = {to = {x = 33258, y = 32708, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33258, y = 32708, z = 13}}}, addItem = true},
	[95] = {to = {x = 33211, y = 32700, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33211, y = 32700, z = 13}}}, addItem = true},
	[96] = {to = {x = 33211, y = 32699, z = 14}, effects = {{effect = 11}, {effect = 11, pos = {x = 33211, y = 32699, z = 14}}}, addItem = true},
	[97] = {to = {x = 33025, y = 32872, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33025, y = 32872, z = 8}}}, addItem = true},
	[98] = {to = {x = 33205, y = 33002, z = 14}, effects = {{effect = 11}, {effect = 11, pos = {x = 33205, y = 33002, z = 14}}}, addItem = true},
	[99] = {to = {x = 33159, y = 32838, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33159, y = 32838, z = 8}}}, addItem = true},
	[101] = {to = {x = 33206, y = 32592, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33206, y = 32592, z = 8}}}, addItem = true},
	[102] = {to = {x = 33179, y = 32880, z = 11}, effects = {{effect = 11}, {effect = 11, pos = {x = 33179, y = 32880, z = 11}}}, addItem = true},
	[104] = {to = {x = 33158, y = 32771, z = 15}, effects = {{effect = 11}, {effect = 11, pos = {x = 33158, y = 32771, z = 15}}}, addItem = true},
	[105] = {to = {x = 33190, y = 32947, z = 15}, effects = {{effect = 11, pos = {x = 33183, y = 32757, z = 15}}, {effect = 11, pos = {x = 33191, y = 32947, z = 15}}}, addItem = true},
	[106] = {to = {x = 33231, y = 32705, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33231, y = 32705, z = 8}}}, addItem = true},
	[107] = {to = {x = 33025, y = 32872, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33025, y = 32872, z = 8}}}, addItem = true},
	[110] = {to = {x = 33255, y = 32836, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33255, y = 32836, z = 8}}}, addItem = true},
	[112] = {to = {x = 33149, y = 32870, z = 11}, effects = {{effect = 11}, {effect = 11, pos = {x = 33149, y = 32870, z = 11}}}, addItem = true},
	[113] = {to = {x = 33255, y = 32839, z = 9}, effects = {{effect = 11}, {effect = 11, pos = {x = 33255, y = 32839, z = 9}}}, addItem = true},
	[114] = {to = {x = 33147, y = 32864, z = 7}, effects = {{effect = 15}, {effect = 15, pos = {x = 33147, y = 32864, z = 7}}}, addItem = true},
	[115] = {to = {x = 33159, y = 32838, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33159, y = 32838, z = 8}}}, addItem = true},
	[117] = {to = {x = 33206, y = 32592, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33206, y = 32592, z = 8}}}, addItem = true},
	[118] = {to = {x = 33125, y = 32760, z = 14}, effects = {{effect = 11}, {effect = 11, pos = {x = 33125, y = 32760, z = 14}}}, addItem = true},
	[119] = {to = {x = 33131, y = 32566, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33131, y = 32566, z = 8}}}, addItem = true},
	[120] = {to = {x = 33133, y = 32642, z = 8}, effects = {{effect = 11, pos = {x = 33124, y = 32759, z = 14}}, {effect = 11, pos = {x = 33133, y = 32642, z = 8}}}, addItem = true},
	[121] = {to = {x = 33085, y = 32781, z = 14}, effects = {{effect = 11}, {effect = 11, pos = {x = 33085, y = 32781, z = 14}}}, addItem = true},
	[122] = {to = {x = 33193, y = 32664, z = 15}, effects = {{effect = 11}, {effect = 11, pos = {x = 33193, y = 32664, z = 15}}}, addItem = true},
	[124] = {to = {x = 33204, y = 32956, z = 14}, effects = {{effect = 11}, {effect = 11, pos = {x = 33204, y = 32956, z = 14}}}, addItem = true},
	[126] = {to = {x = 33131, y = 32566, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33131, y = 32566, z = 8}}}, addItem = true},
	[128] = {to = {x = 33080, y = 32569, z = 13}, effects = {{effect = 11}, {effect = 11, pos = {x = 33080, y = 32569, z = 13}}}, addItem = true},
	[131] = {to = {x = 33083, y = 32610, z = 14}, effects = {{effect = 11}, {effect = 11, pos = {x = 33083, y = 32610, z = 14}}}, addItem = true},
	[132] = {to = {x = 33133, y = 32642, z = 8}, effects = {{effect = 15}, {effect = 15, pos = {x = 33133, y = 32642, z = 8}}}, addItem = true},
	[133] = {to = {x = 33280, y = 32744, z = 10}, effects = {{effect = 11}, {effect = 11, pos = {x = 33280, y = 32744, z = 10}}}, addItem = true},
	[136] = {to = {x = 33206, y = 32577, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33206, y = 32577, z = 8}}}, addItem = true},
	[141] = {to = {x = 33255, y = 32836, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33255, y = 32836, z = 8}}}, addItem = true},
	[143] = {to = {x = 33235, y = 32705, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33235, y = 32705, z = 8}}}, addItem = true},
	[144] = {to = {x = 33192, y = 32846, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33192, y = 32846, z = 8}}}, addItem = true},
	[145] = {to = {x = 33195, y = 32852, z = 4}, effects = {{effect = 11}, {effect = 11, pos = {x = 33195, y = 32852, z = 4}}}, addItem = true},
	[146] = {to = {x = 33157, y = 32834, z = 7}, effects = {{effect = 11}, {effect = 11, pos = {x = 33157, y = 32834, z = 7}}}, addItem = true},
	[147] = {to = {x = 33133, y = 32642, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33133, y = 32642, z = 8}}}, addItem = true},
	[148] = {to = {x = 33029, y = 32868, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33029, y = 32868, z = 8}}}, addItem = true},
	[149] = {to = {x = 33131, y = 32566, z = 8}, effects = {{effect = 11}, {effect = 11, pos = {x = 33131, y = 32566, z = 8}}}, addItem = true},
	[151] = {to = {x = 33021, y = 32605, z = 7}, effects = {{effect = 15}, {effect = 15, pos = {x = 33021, y = 32605, z = 7}}}, addItem = true},
	[152] = {to = {x = 32840, y = 32533, z = 9}, effects = {{effect = 15}, {effect = 15, pos = {x = 32840, y = 32533, z = 9}}}, addItem = true},
	[154] = {to = {x = 32839, y = 32532, z = 9}, effects = {{effect = 21}, {effect = 21, pos = {x = 32839, y = 32532, z = 9}}}, playerOnly = true},
	[156] = {to = {x = 32874, y = 31942, z = 11}, addItem = true},
	[157] = {to = {x = 32874, y = 31953, z = 12}, addItem = true},
	[159] = {to = {x = 32615, y = 32483, z = 9}, effects = {{effect = 13, pos = {x = 32615, y = 32483, z = 9}}}, playerOnly = true},
	[160] = {to = {x = 32660, y = 32113, z = 8}, addItem = true},
	[165] = {to = {x = 33324, y = 31592, z = 15}, addItem = true},
	[167] = {to = {x = 33277, y = 31592, z = 11}, effects = {{effect = 15}, {effect = 15, pos = {x = 33277, y = 31592, z = 11}}}, addItem = true},
	[168] = {to = {x = 33279, y = 31592, z = 12}, effects = {{effect = 15}, {effect = 15, pos = {x = 33279, y = 31592, z = 12}}}, addItem = true},
	[170] = {to = {x = 33070, y = 31620, z = 15}, addItem = true},
	[173] = {from = {x = 32274, y = 31847, z = 15}, to = {x = 32171, y = 31855, z = 15}, effects = {{effect = 11, pos = {x = 32171, y = 31855, z = 15}}}},
	[174] = {from = {x = 32274, y = 31858, z = 15}, to = {x = 32216, y = 31846, z = 15}, effects = {{effect = 11, pos = {x = 32216, y = 31846, z = 15}}}},
	[175] = {from = {x = 32267, y = 31847, z = 15}, to = {x = 32275, y = 31905, z = 13}, effects = {{effect = 11, pos = {x = 32275, y = 31905, z = 13}}}},
	[176] = {from = {x = 32267, y = 31858, z = 15}, to = {x = 32186, y = 31938, z = 14}, effects = {{effect = 11, pos = {x = 32186, y = 31938, z = 14}}}},
	[177] = {from = {x = 32266, y = 31857, z = 12}, to = {x = 32266, y = 31864, z = 12}, effects = {{effect = 11, pos = {x = 32266, y = 31864, z = 12}}}},
	[178] = {from = {x = 32266, y = 31863, z = 12}, to = {x = 32259, y = 31892, z = 10}, effects = {{effect = 11, pos = {x = 32259, y = 31892, z = 10}}}},
	[179] = {from = {x = 32262, y = 31889, z = 10}, to = {x = 32259, y = 31892, z = 10}, effects = {{effect = 11, pos = {x = 32259, y = 31892, z = 10}}}},
	[180] = {from = {x = 32259, y = 31858, z = 15}, to = {x = 32312, y = 31974, z = 13}, effects = {{effect = 11, pos = {x = 32312, y = 31974, z = 13}}}},
	[181] = {from = {x = 32259, y = 31847, z = 15}, to = {x = 32245, y = 31891, z = 14}, effects = {{effect = 11, pos = {x = 32245, y = 31891, z = 14}}}},
	[183] = {from = {x = 32177, y = 31864, z = 15}, to = {x = 32177, y = 31870, z = 15}, effects = {{effect = 11, pos = {x = 32177, y = 31870, z = 15}}}},
	[185] = {from = {x = 32176, y = 31864, z = 15}, to = {x = 32176, y = 31870, z = 15}, effects = {{effect = 11, pos = {x = 32176, y = 31870, z = 15}}}},
	[194] = {to = {x = 32794, y = 31577, z = 5}, effects = {{effect = 11, pos = {x = 32794, y = 31577, z = 5}}}},
	[195] = {to = {x = 32812, y = 31577, z = 5}, effects = {{effect = 11, pos = {x = 32812, y = 31577, z = 5}}}},
	[197] = {to = {x = 32725, y = 31589, z = 12}, addItem = true},
	[208] = {to = {x = 32569, y = 32110, z = 7}, effects = {{effect = 11}, {effect = 11, pos = {x = 32569, y = 32110, z = 7}}}, addItem = true},
	[209] = {to = {x = 32526, y = 32156, z = 12}},
	[210] = {to = {x = 32554, y = 32212, z = 11}},
	[211] = {to = {x = 32492, y = 31697, z = 7}, effects = {{effect = 13, pos = {x = 32492, y = 31697, z = 7}}}, addItem = true},
	[212] = {to = {x = 32167, y = 32438, z = 9}, effects = {{effect = 15}, {effect = 15, pos = {x = 32167, y = 32438, z = 9}}}, addItem = true},
	[213] = {to = {x = 32281, y = 32389, z = 10}, effects = {{effect = 15}, {effect = 15, pos = {x = 32281, y = 32389, z = 10}}}, addItem = true},
	[214] = {to = {x = 32167, y = 32438, z = 9}, effects = {{effect = 15}, {effect = 15, pos = {x = 32167, y = 32438, z = 9}}}, addItem = true},
	[217] = {to = {x = 32107, y = 31567, z = 9}, addItem = true},
	[219] = {to = {x = 32081, y = 32172, z = 9}, addItem = true},
	[220] = {to = {x = 32090, y = 32172, z = 9}, addItem = true},
	[221] = {from = {x = 32481, y = 31904, z = 4}, to = {x = 32481, y = 31904, z = 5}, effects = {{effect = 11, pos = {x = 32481, y = 31904, z = 5}}}, addItem = true},
	[222] = {from = {x = 32481, y = 31905, z = 1}, to = {x = 32480, y = 31905, z = 2}, effects = {{effect = 11, pos = {x = 32480, y = 31905, z = 2}}}, addItem = true},
	[223] = {from = {x = 32479, y = 31904, z = 2}, to = {x = 32479, y = 31904, z = 3}, effects = {{effect = 11, pos = {x = 32479, y = 31904, z = 3}}}, addItem = true},
	[224] = {from = {x = 32476, y = 31904, z = 5}, to = {x = 32476, y = 31904, z = 6}, effects = {{effect = 11, pos = {x = 32476, y = 31904, z = 6}}}, addItem = true},
	[225] = {from = {x = 32476, y = 31904, z = 3}, to = {x = 32476, y = 31904, z = 4}, effects = {{effect = 11, pos = {x = 32476, y = 31904, z = 4}}}, addItem = true},
	[226] = {to = {x = 32836, y = 32294, z = 7}, addItem = true},
	[228] = {to = {x = 32776, y = 32255, z = 11}, addItem = true},
	[229] = {to = {x = 32767, y = 32229, z = 7}, addItem = true},
	[231] = {to = {x = 32913, y = 32070, z = 12}, effects = {{effect = 13, pos = {x = 32913, y = 32070, z = 11}}}, playerOnly = true},
	[236] = {to = {x = 33293, y = 32481, z = 7}, effects = {{effect = 11, pos = {x = 33293, y = 32481, z = 7}}}, playerOnly = true, addItem = {to = {x = 33325, y = 32166, z = 5}, effects = {{effect = 13, pos = {x = 33325, y = 32166, z = 5}}}}},
	[239] = {to = {x = 32791, y = 32331, z = 10}, effects = {{effect = 15, pos = {x = 32791, y = 32331, z = 10}}}, addItem = {to = {x = 32791, y = 32331, z = 10}, effects = {{effect = 13, pos = {x = 32791, y = 32331, z = 10}}}}},
	[1000] = {to = {x = 32671, y = 32069, z = 8}},
	[1001] = {to = {x = 32942, y = 32708, z = 8}},
	[1105] = {to = {x = 32827, y = 32314, z = 9}, addItem = true},
	[1106] = {to = {x = 32842, y = 32323, z = 9}, addItem = true},
	[1107] = {to = {x = 32844, y = 32307, z = 9}, addItem = true},
	[1108] = {to = {x = 32855, y = 32296, z = 9}, addItem = true},
	[1109] = {to = {x = 32840, y = 32317, z = 9}, addItem = true},
	[1110] = {to = {x = 32854, y = 32323, z = 9}, addItem = true},
	[1111] = {to = {x = 32858, y = 32296, z = 9}, addItem = true},
	[1112] = {to = {x = 32856, y = 32289, z = 9}, addItem = true},
	[1113] = {to = {x = 32826, y = 32273, z = 12}, addItem = true},
	[1114] = {to = {x = 32824, y = 32242, z = 12}, addItem = true},
	[1115] = {to = {x = 32856, y = 32353, z = 15}, addItem = true},
	[1116] = {to = {x = 32876, y = 32226, z = 15}, addItem = true},
	[1117] = {to = {x = 32767, y = 32227, z = 15}, addItem = true},
	[1118] = {to = {x = 32859, y = 32278, z = 15}, addItem = true},
	[1119] = {to = {x = 32786, y = 32308, z = 15}, addItem = true},
	[1120] = {to = {x = 32806, y = 32327, z = 15}, addItem = true},
	[1121] = {to = {x = 32836, y = 32287, z = 15}, addItem = true},
	[2011] = {to = {x = 32689, y = 32299, z = 15}, effects = {{effect = 13, pos = {x = 32689, y = 32299, z = 15}}}, playerOnly = true, addItem = {to = {x = 32689, y = 32299, z = 15}, effects = {{effect = 14, pos = {x = 32689, y = 32299, z = 15}}}}},
	[2012] = {to = {x = 32834, y = 32275, z = 9}, effects = {{effect = 13, pos = {x = 32834, y = 32275, z = 9}}}, playerOnly = true, addItem = {to = {x = 32834, y = 32275, z = 9}, effects = {{effect = 14, pos = {x = 32834, y = 32275, z = 9}}}}},
}

-- Quest flags set when a player steps on the tile.
--   storage/value  storage written for the player.
--   onlyBelow      only act while the stored value is below this number.
--   effect         magic effect shown on effectPos, or on the tile itself.
local storageFlags = {
	[5] = {storage = 48, value = 1, onlyBelow = 1, effect = 15, effectPos = {x = 32549, y = 32142, z = 7}},
	[47] = {storage = 42, value = 1, onlyBelow = 1, effect = 7, effectPos = {x = 32478, y = 31900, z = 1}},
	[48] = {storage = 41, value = 1, onlyBelow = 1, effect = 7, effectPos = {x = 32477, y = 31900, z = 1}},
	[49] = {storage = 43, value = 1, onlyBelow = 1, effect = 7, effectPos = {x = 32479, y = 31900, z = 1}},
	[50] = {storage = 41, value = 1, onlyBelow = 1, effect = 7, effectPos = {x = 32477, y = 31900, z = 1}},
	[51] = {storage = 41, value = 1, onlyBelow = 1, effect = 7, effectPos = {x = 32477, y = 31900, z = 1}},
	[52] = {storage = 42, value = 1, onlyBelow = 1, effect = 7, effectPos = {x = 32478, y = 31900, z = 1}},
	[53] = {storage = 43, value = 1, onlyBelow = 1, effect = 7, effectPos = {x = 32479, y = 31900, z = 1}},
	[54] = {storage = 44, value = 1, onlyBelow = 1, effect = 7, effectPos = {x = 32480, y = 31900, z = 1}},
	[55] = {storage = 41, value = 1, onlyBelow = 1, effect = 7, effectPos = {x = 32477, y = 31900, z = 1}},
	[56] = {storage = 41, value = 1, onlyBelow = 1, effect = 7, effectPos = {x = 32477, y = 31900, z = 1}},
	[57] = {storage = 44, value = 1, onlyBelow = 1, effect = 7, effectPos = {x = 32480, y = 31900, z = 1}},
	[58] = {storage = 42, value = 1, onlyBelow = 1, effect = 7, effectPos = {x = 32478, y = 31900, z = 1}},
	[134] = {storage = 276, value = 1, effect = 13},
	[135] = {storage = 275, value = 1, effect = 13},
	[137] = {storage = 272, value = 1, effect = 13},
	[138] = {storage = 277, value = 1, effect = 13},
	[139] = {storage = 274, value = 1, effect = 13},
	[140] = {storage = 271, value = 1, effect = 13},
	[142] = {storage = 273, value = 1, effect = 13},
}

local function relocate(rule, tilePosition)
	doRelocate(rule.from or tilePosition, rule.to)
	if rule.effects then
		for _, entry in ipairs(rule.effects) do
			Game.sendMagicEffect(entry.pos or tilePosition, entry.effect)
		end
	end
end

function MapTiles.teleportOnStepIn(creature, item)
	local rule = teleports[item:getMovementId()]
	if not rule or (rule.playerOnly and not creature:isPlayer()) then
		return
	end
	relocate(rule, item:getPosition())
end

function MapTiles.teleportOnAddItem(tileItem)
	local rule = teleports[tileItem:getMovementId()]
	if not rule or not rule.addItem then
		return
	end
	relocate(rule.addItem == true and rule or rule.addItem, tileItem:getPosition())
end

function MapTiles.storageFlagOnStepIn(creature, item)
	local rule = storageFlags[item:getMovementId()]
	local player = rule and creature:getPlayer()
	if not player then
		return
	end
	if rule.onlyBelow and player:getStorageValue(rule.storage) >= rule.onlyBelow then
		return
	end
	player:setStorageValue(rule.storage, rule.value)
	Game.sendMagicEffect(rule.effectPos or item:getPosition(), rule.effect)
end

-- Exposed for tests and tooling; the game only uses the handlers above.
MapTiles.teleports = teleports
MapTiles.storageFlags = storageFlags

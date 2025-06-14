--[[
* Besieged - FFXI Ashita v4 Addon
* Author: Original: Dean James (Xurion of Bismarck), ported by Knautz
* License: GPLv3
* Description: Alerts when Besieged events are happening.
]]

require('common')

addon.name = 'Besieged'
addon.author  = 'Original: Dean James (Xurion of Bismarck), ported by Knautz'
addon.version = '1.0.0'
addon.desc    = 'Alerts when Besieged events are happening';
addon.link    = 'https://github.com/ThreeWordsLong/ffxi-besieged';
addon.aliases = T{'/bs', '/besieged'}
addon.commands = T{
    ['Help'] = 'Prints out available commands.',
    ['Debug'] = 'Toggles debug logging.',
    ['Interval'] = 'Sets the interval for checking Besieged status in seconds.',
    ['Show'] = 'Toggles the visibility of the Besieged Hex Packet Data.',
}

local ffi = require('ffi')
local bit = require('bit')
local imgui = require('imgui')
local settings = require('settings');
local ok, inspect_mod = pcall(require, 'inspect')
local inspect = ok and inspect_mod or function(t)
    return tostring(t)
end


ffi.cdef[[

typedef struct CONQUEST_PACKET {
    uint16_t id_size;  // lower 9 bits = id, upper 7 bits = size
    uint16_t sync;
    uint8_t balance_of_power;          // 0x04
    uint8_t alliance_indicator;        // 0x05
    uint8_t _unknown1[20];             // 0x06
    uint32_t ronfaure_info;            // 0x1A
    uint32_t zulkheim_info;            // 0x1E
    uint32_t norvallen_info;           // 0x22
    uint32_t gustaberg_info;           // 0x26
    uint32_t derfland_info;            // 0x2A
    uint32_t sarutabaruta_info;        // 0x2E
    uint32_t kolshushu_info;           // 0x32
    uint32_t aragoneu_info;            // 0x36
    uint32_t fauregandi_info;          // 0x3A
    uint32_t valdeaunia_info;          // 0x3E
    uint32_t qufim_info;               // 0x42
    uint32_t litelor_info;             // 0x46
    uint32_t kuzotz_info;              // 0x4A
    uint32_t vollbow_info;             // 0x4E
    uint32_t elshimo_lowlands_info;    // 0x52
    uint32_t elshimo_uplands_info;     // 0x56
    uint32_t tulia_info;               // 0x5A
    uint32_t movalpolos_info;          // 0x5E
    uint32_t tavnazian_info;           // 0x62
    uint8_t _unknown2[32];             // 0x66
    uint8_t sandoria_bar;              // 0x86
    uint8_t bastok_bar;                // 0x87
    uint8_t windurst_bar;              // 0x88
    uint8_t sandoria_bar_nobm;         // 0x89
    uint8_t bastok_bar_nobm;           // 0x8A
    uint8_t windurst_bar_nobm;         // 0x8B
    uint8_t days_to_tally;             // 0x8C
    uint8_t _unknown4[3];              // 0x8D
    int32_t conquest_points;           // 0x90
    uint8_t beastmen_bar;              // 0x94
    uint8_t _unknown5[11];             // 0x95
    uint8_t mmj_orders_level_ac;       // 0xA0
    uint8_t halvung_arrapago_level;    // 0xA1
    uint8_t beastman_status_1;         // 0xA2
    uint8_t beastman_status_2;         // 0xA3
    uint32_t mmj_info;                 // 0xA4
    uint32_t halvung_info;             // 0xA8
    uint32_t arrapago_info;            // 0xAC
    int32_t imperial_standing;         // 0xB0
} CONQUEST_PACKET;

]]

-- Default Settings
local default_settings = T{
    debug = true,
    interval = 300,
    show_window = false
};

-- Addon state
local besieged = {
    settings = settings.load(default_settings),
    last_update = 0,
    requesting = false,
    previous_attacker = nil,
    last_notification = '',
    last_status = nil,
    last_packet = nil,
};

besieged.verbose = besieged.settings.debug and 1 or 0
besieged.last_update = os.time() - besieged.settings.interval + 3

local minimum_interval = 125 --there is a client side cache for 2 mins, so we don't want to force request the server more than this allows

local logger = {}

local function safe_format(fmt, ...)
    local args = {...}
    for i = 1, select('#', ...) do
        local val = args[i]
        if type(val) == "table" then
            args[i] = inspect(val)
        elseif type(val) ~= "string" then
            args[i] = tostring(val)
        end
    end
    return string.format(fmt, table.unpack(args))
end

local function make_level(level, color, required_verbosity)
    return function(fmt, ...)
        if (besieged.verbose or 0) < required_verbosity then return end

        local tag = addon.name or 'Addon'
        local color_code = string.char(0x1E, tonumber(color))  -- \30\{color}
        local reset_code = string.char(0x1E, 0x01)             -- \30\01

        local prefix = string.format('[%s%s - %s%s] ', color_code, tag, level:upper(), reset_code)


        local message
        local arg_count = select('#', ...)
        if arg_count == 0 then
            -- Still wrap through safe_format to handle tables or placeholders
            message = safe_format("%s", fmt)
        else
            message = safe_format(fmt, ...)
        end

        print(prefix .. message)
    end
end

-- Verbosity scale: 0=warn/error/info, 1=debug
logger.error = make_level('error', '4', 0)
logger.warn  = make_level('warn',  '3', 0)
logger.info  = make_level('info',  '5', 0)
logger.debug = make_level('debug', '2', 1)

local log = logger.info
local debug = logger.debug

local function print_help()
    log("Usage: %s [command]", addon.aliases[1])
    log("Available commands:%s", addon.commands)
end

ffi.cdef[[
int __stdcall PlaySoundA(const char* pszSound, void* hmod, unsigned int fdwSound);
]]
local winmm = ffi.load("winmm")
local function play_sound(sound)
    local flags = 0x00020001  -- SND_FILENAME | SND_ASYNC
    winmm.PlaySoundA(string.format('%s\\sounds\\%s.wav', addon.path, sound), nil, flags)
end


local orders_map = {
    [0] = 'Defend Al Zahbi',
    [1] = 'Intercept Enemy',
    [2] = 'Invade Enemy Base',
    [3] = 'Recover the Orb'
}

local candescence_map = {
    [0] = 'Whitegate',
    [1] = 'Mamool',
    [2] = 'Trolls',
    [3] = 'Lamia'
}

local beastman_status_map = {
    [0] = 'Training',
    [1] = 'Advancing',
    [2] = 'Attacking',
    [3] = 'Retreating',
    [4] = 'Defending',
    [5] = 'Preparing',
}


-- Bitpacked region int (for the actual locations on the map, not the overview)
-- 3 Least Significant Bits -- Beastman Status for that region
-- 8 following bits -- Number of Forces
-- 4 following bits -- Level
-- 4 following bits -- Number of Archaic Mirrors
-- 4 following bits -- Number of Prisoners
-- 9 following bits -- No clear purpose
local function unpack_region_info(info)
    local status     = bit.band(info, 0x7)                        -- bits 0–2
    local forces     = bit.band(bit.rshift(info, 3), 0xFF)        -- bits 3–10
    local level      = bit.band(bit.rshift(info, 11), 0xF)        -- bits 11–14
    local mirrors    = bit.band(bit.rshift(info, 15), 0xF)        -- bits 15–18
    local prisoners  = bit.band(bit.rshift(info, 19), 0xF)        -- bits 19–22
    local unknown    = bit.rshift(info, 23)                       -- bits 23–31
    return {
        status = beastman_status_map[status],
        forces = forces,
        level = level,
        mirrors = mirrors,
        prisoners = prisoners,
        unknown = unknown
    }
end

local function debug_conquest_packet(data, raw)
    local function printb(label, offset, val, bytes)
        local raw_bytes = {}
        for i = bytes, 1, -1 do
            table.insert(raw_bytes, string.format("%02X", raw:byte(offset + i)))
        end

        local formatted_val = "N/A"
        if type(val) == "number" then
            if bytes == 1 then
                formatted_val = string.format("0x%02X", val)
            elseif bytes == 2 then
                formatted_val = string.format("0x%04X", val)
            elseif bytes == 4 then
                formatted_val = string.format("0x%08X", val)
            else
                formatted_val = tostring(val)
            end
        end

        debug("%-28s [0x%03X]: %-12s  (ffi: %s)", label, offset, table.concat(raw_bytes, " "), formatted_val)
    end

    printb("id_size",       0x00, data.id_size, 2)
    printb("sync",          0x02, data.sync, 2)
    printb("balance_of_power", 0x04, data.balance_of_power, 1)
    printb("alliance_indicator", 0x05, data.alliance_indicator, 1)

    printb("_unknown1",     0x06, "N/A", 20)

    printb("ronfaure_info", 0x1A, data.ronfaure_info, 4)
    printb("zulkheim_info", 0x1E, data.zulkheim_info, 4)
    printb("norvallen_info", 0x22, data.norvallen_info, 4)
    printb("gustaberg_info", 0x26, data.gustaberg_info, 4)
    printb("derfland_info", 0x2A, data.derfland_info, 4)
    printb("sarutabaruta_info", 0x2E, data.sarutabaruta_info, 4)
    printb("kolshushu_info", 0x32, data.kolshushu_info, 4)
    printb("aragoneu_info", 0x36, data.aragoneu_info, 4)
    printb("fauregandi_info", 0x3A, data.fauregandi_info, 4)
    printb("valdeaunia_info", 0x3E, data.valdeaunia_info, 4)
    printb("qufim_info", 0x42, data.qufim_info, 4)
    printb("litelor_info", 0x46, data.litelor_info, 4)
    printb("kuzotz_info", 0x4A, data.kuzotz_info, 4)
    printb("vollbow_info", 0x4E, data.vollbow_info, 4)
    printb("elshimo_lowlands_info", 0x52, data.elshimo_lowlands_info, 4)
    printb("elshimo_uplands_info", 0x56, data.elshimo_uplands_info, 4)
    printb("tulia_info", 0x5A, data.tulia_info, 4)
    printb("movalpolos_info", 0x5E, data.movalpolos_info, 4)
    printb("tavnazian_info", 0x62, data.tavnazian_info, 4)

    printb("_unknown2", 0x66, "N/A", 32)

    printb("sandoria_bar", 0x86, data.sandoria_bar, 1)
    printb("bastok_bar", 0x87, data.bastok_bar, 1)
    printb("windurst_bar", 0x88, data.windurst_bar, 1)
    printb("sandoria_bar_nobm", 0x89, data.sandoria_bar_nobm, 1)
    printb("bastok_bar_nobm", 0x8A, data.bastok_bar_nobm, 1)
    printb("windurst_bar_nobm", 0x8B, data.windurst_bar_nobm, 1)
    printb("days_to_tally", 0x8C, data.days_to_tally, 1)

    printb("_unknown4", 0x8D, "N/A", 3)

    printb("conquest_points", 0x90, data.conquest_points, 4)
    printb("beastmen_bar", 0x94, data.beastmen_bar, 1)
    printb("_unknown5", 0x95, "N/A", 12)

    printb("mmj_orders_level_ac", 0xA0, data.mmj_orders_level_ac, 1)
    printb("halvung_arrapago_level", 0xA1, data.halvung_arrapago_level, 1)
    printb("beastman_status_1", 0xA2, data.beastman_status_1, 1)
    printb("beastman_status_2", 0xA3, data.beastman_status_2, 1)

    printb("mmj_info", 0xA4, data.mmj_info, 4)
    printb("halvung_info", 0xA8, data.halvung_info, 4)
    printb("arrapago_info", 0xAC, data.arrapago_info, 4)

    printb("imperial_standing", 0xB0, data.imperial_standing, 4)
end


local function parse_besieged_packet(packet)
    local data = ffi.cast('const CONQUEST_PACKET*', packet.data_raw)

    local mmj_orders_level_ac = data.mmj_orders_level_ac
    local halvung_arrapago_level = data.halvung_arrapago_level
    local beastman_status_1 = data.beastman_status_1
    local beastman_status_2 = data.beastman_status_2

    -- AC owner: bits 0–1
    local ac_owner = bit.band(mmj_orders_level_ac, 0x03)

    -- Orders: bits 2–3
    local orders = bit.band(bit.rshift(mmj_orders_level_ac, 2), 0x03)

    -- MMJ level: bits 4–7
    local mmj_level = bit.rshift(mmj_orders_level_ac, 4)

    -- Halvung level: bits 0–3
    local halvung_level = bit.band(halvung_arrapago_level, 0x0F)

    -- Arrapago level: bits 4–7
    local arrapago_level = bit.rshift(halvung_arrapago_level, 4)

    -- MMJ Orders: bits 0–2
    local mmj_orders = bit.band(beastman_status_1, 0x07)

    -- Halvung Orders: bits 3–5
    local halvung_orders = bit.band(bit.rshift(beastman_status_1, 3), 0x07)

    -- Arrapago Orders: bit 6 of beastman_status_1 and bit 0 of beastman_status_2
    local arrapago_orders = bit.bor(
        bit.band(bit.rshift(beastman_status_1, 6), 0x03),  -- bits 6–7 as lower 2
        bit.lshift(bit.band(beastman_status_2, 0x01), 2)   -- bit 0 of status_2 as MSB
    )

    local mmj_info = unpack_region_info(data.mmj_info)
    local halvung_info = unpack_region_info(data.halvung_info)
    local arrapago_info = unpack_region_info(data.arrapago_info)

    return {
        candescence = candescence_map[ac_owner],
        orders = orders_map[orders],
        imperial_standing = data.imperial_standing,

        mamool = {
            level = mmj_level,
            status = beastman_status_map[mmj_orders],
            region = mmj_info
        },
        trolls = {
            level = halvung_level,
            status = beastman_status_map[halvung_orders],
            region = halvung_info
        },
        lamia = {
            level = arrapago_level,
            status = beastman_status_map[arrapago_orders],
            region = arrapago_info
        }
    }
end




local function handle_besieged_packet(packet)
    debug('Handling Besieged packet data')
    local notification = ''
    local besieged_status = parse_besieged_packet(packet)
    besieged.last_status = besieged_status

    if besieged.previous_attacker == 'Mamool Ja Savages' and besieged_status.mamool.status ~= 'Attacking' then
        notification = notification .. 'The Mamool Ja Savages have retreated.\n'
    end

    if besieged.previous_attacker == 'Troll Mercenaries' and besieged_status.trolls.status ~= 'Attacking' then
        notification = notification .. 'The Troll Mercenaries have retreated.\n'
    end

    if besieged.previous_attacker == 'Undead Swarm' and besieged_status.lamia.status ~= 'Attacking' then
        notification = notification .. 'The Undead Swarm have retreated.\n'
    end

    if besieged_status.mamool.status == 'Attacking' then
        besieged.previous_attacker = 'Mamool Ja Savages'
        notification = notification .. 'Level ' .. besieged_status.mamool.level .. ' Mamool Ja Savages are attacking Al Zahbi!\n'
    end

    if besieged_status.trolls.status == 'Attacking' then
        besieged.previous_attacker = 'Troll Mercenaries'
        notification = notification .. 'Level ' .. besieged_status.trolls.level .. ' Troll Mercenaries are attacking Al Zahbi!\n'
    end

    if besieged_status.lamia.status == 'Attacking' then
        besieged.previous_attacker = 'Undead Swarm'
        notification = notification .. 'Level ' .. besieged_status.lamia.level .. ' Undead Swarm are attacking Al Zahbi!\n'
    end

    if besieged_status.mamool.status == 'Advancing' then
        notification = notification .. 'Level ' .. besieged_status.mamool.level .. ' Mamool Ja Savages are advancing towards Al Zahbi!\n'
    end

    if besieged_status.trolls.status == 'Advancing' then
        notification = notification .. 'Level ' .. besieged_status.trolls.level .. ' Troll Mercenaries are advancing towards Al Zahbi!\n'
    end

    if besieged_status.lamia.status == 'Advancing' then
        notification = notification .. 'Level ' .. besieged_status.lamia.level .. ' Undead Swarm are advancing towards Al Zahbi!\n'
    end

    if notification ~= '' then
        notification = 'Besieged Update:' .. notification
        notification = notification:gsub('\n$', '')

        if notification ~= besieged.last_notification then
            besieged.last_notification = notification
            log(notification)
            play_sound('alert')
        end

    else
        debug('No notification this time')
        debug('Trolls [' .. besieged_status.trolls.level .. ']  Mamool Ja [' .. besieged_status.mamool.level .. ']  Lamia [' .. besieged_status.lamia.level .. ']')
    end
end

local function request_besieged_data()
    debug('Requesting Besieged data from server')
    AshitaCore:GetPacketManager():QueuePacket(
        0x005A,     -- opcode
        0x0004,     -- size
        2,          -- alignment (safe default)
        0x00,       -- pparam1
        0x00,       -- pparam2
        function(ptr)
            local p = ffi.cast('uint8_t*', ptr)
            local header = bit.bor(0x005A, bit.lshift(0x0004, 9)) -- id:9 + size:7
            local sync   = 0x0000
            p[0] = bit.band(header, 0xFF)
            p[1] = bit.rshift(header, 8)
            p[2] = bit.band(sync, 0xFF)
            p[3] = bit.rshift(sync, 8)
        end
    )
end

local function render_ui()
    if not besieged.settings.show_window or not besieged.last_status then return end

    local packet_data = besieged.last_packet
    local parsed = besieged.last_status
    local bytes_per_row = 16

    if imgui.Begin('Raw Packet Hex Viewer', true) then

        -- Section: Status Overview
        imgui.Text('Besieged Overview:')

        imgui.Text(string.format('Astral Candescence: %s', parsed.candescence))
        imgui.Text(string.format('Orders: %s', parsed.orders))
        imgui.Text(string.format('Imperial Standing: %d', parsed.imperial_standing))

        imgui.Separator()
        imgui.Text('Stronghold Status:')

        for name, info in pairs({
            Mamool = parsed.mamool,
            Trolls = parsed.trolls,
            Lamia  = parsed.lamia,
        }) do
            imgui.Text(string.format('%-8s Lv %d Forces: %-3d  Mirrors: %-2d  Prisoners: %-2d (%s)', 
                name, 
                info.level, 
                info.region.forces, 
                info.region.mirrors, 
                info.region.prisoners,
                info.region.status or "?"
            ))
        end

        imgui.Separator()

        -- Section: Hex Viewer

        if imgui.Button('Copy Hex to Clipboard') then
            local full_hex = {}

            for i = 1, #packet_data, 16 do
                local line = {}
                for j = 0, 15 do
                    local idx = i + j
                    if idx <= #packet_data then
                        table.insert(line, string.format('%02X', packet_data:byte(idx)))
                    else
                        table.insert(line, '  ')
                    end
                end
                table.insert(full_hex, string.format('%04X: %s', i - 1, table.concat(line, ' ')))
            end

            imgui.SetClipboardText(table.concat(full_hex, '\n'))
        end

        imgui.Text('Raw Packet:')
        imgui.BeginChild('##hex_scroll', { 0, 0 }, true)
        imgui.Text("        00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F     0123456789ABCDEF")
        imgui.Separator()

        local total_len = #packet_data

        for i = 1, total_len, bytes_per_row do
            -- Offset column
            imgui.Text(string.format('%04X:', i - 1))
            imgui.SameLine(80)

            local hex_parts = {}
            local ascii_parts = {}

            for j = 0, bytes_per_row - 1 do
                local idx = i + j
                if idx <= total_len then
                    local byte = packet_data:byte(idx)
                    table.insert(hex_parts, string.format('%02X', byte))

                    -- ASCII printable check
                    if byte >= 32 and byte <= 126 then
                        table.insert(ascii_parts, string.char(byte))
                    else
                        table.insert(ascii_parts, '.')
                    end
                else
                    table.insert(hex_parts, '  ')
                    table.insert(ascii_parts, ' ')
                end
            end

            imgui.Text(string.format('%-47s  |  %s', table.concat(hex_parts, ' '), table.concat(ascii_parts)))
        end

        imgui.EndChild()
        imgui.End()
    end
end






ashita.events.register('load', 'load_'..addon.name:lower(), function ()

    print(string.format('[\30\05%s - INFO\30\01] Loaded. Update interval: %d seconds.', addon.name, besieged.settings.interval))
    
end);

ashita.events.register('d3d_present', 'besieged_addon', function()
    if not besieged.last_update or besieged.last_update == 0 or (os.time() - besieged.last_update < besieged.settings.interval) then
        return
    elseif not besieged.requesting then
        besieged.requesting = true
        besieged.last_update = os.time()
        request_besieged_data()
    end
end)

ashita.events.register('packet_in', 'besieged_check', function(packet)
    if packet.id == 0x05E then
        besieged.last_update = os.time() --reset the timer to zero
        debug('Received Besieged data from server')
        if besieged.requesting then
            besieged.requesting = false
            handle_besieged_packet(packet)
            besieged.last_packet = packet.data
        end
    end
end)

ashita.events.register('command', 'command_' .. addon.name:lower(), function (e)
    local args = e.command:args()
    
    if (#args == 0 or not addon.aliases:contains(args[1]:lower())) then
        return
    end

    local cmd = args[2] and args[2]:lower()

    if not cmd or cmd == 'help' then
        print_help()
        return
    elseif cmd == 'debug' then
        besieged.settings.debug = not besieged.settings.debug
        if besieged.settings.debug then
            log('Debug logging enabled')
        else
            log('Debug logging disabled')
        end
        settings.save()
        return
    elseif cmd == 'interval' then
        local new_interval = tonumber(args[3])
        if not new_interval then
            log('Usage: %s interval <seconds>', addon.aliases[1])
            return
        end
        if new_interval == besieged.settings.interval then
            log('Interval is already set to %d seconds', new_interval)
            return
        end
        if new_interval < minimum_interval then
            log('Cannot set interval lower than %d seconds', minimum_interval)
            return
        end
        besieged.settings.interval = new_interval
        settings.save()
        log('Interval set to %d seconds', new_interval)
    elseif cmd == 'show' then
        if not besieged.settings.show_window then
            log('Besieged UI is now visible. Use %s show to toggle it off.', addon.aliases[1])
        else
            log('Besieged UI is now hidden. Use %s show to toggle it on.', addon.aliases[1])
        end
        besieged.settings.show_window = not besieged.settings.show_window
        settings.save()
    else
        log("Unknown command: %s", cmd)
        print_help()
        return
    end
end)


-- Render loop
ashita.events.register('d3d_present', 'beseiged_hex_ui', function()
    render_ui()
end)


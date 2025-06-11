--[[
* Besieged - FFXI Ashita v4 Addon
* Author: Original: Dean James (Xurion of Bismarck), ported by Knautz
* License: GPLv3
* Description: Alerts when Besieged events are happening.
]]

require('common')

addon.name = 'Besieged'
addon.author  = 'Original: Dean James (Xurion of Bismarck), ported by Knautz'
addon.version = '0.0.1'
addon.desc    = 'ChocoRun Addon';
addon.link    = 'https://github.com/ThreeWordsLong/ffxi-besieged';
addon.aliases = T{'/bs', '/besieged'}
addon.commands = T{
    ['Help'] = 'Prints out available commands.',
    ['Debug'] = 'Toggles debug logging.',
    ['Last'] = 'Reprocesses the last Besieged data received.',
    ['Interval'] = 'Sets the interval for checking Besieged status in seconds.',
    ['Show'] = 'Toggles the visibility of the Besieged Hex Packet Data.',
}

local ffi = require('ffi')
local bit = require('bit')
local imgui = require('imgui')
local settings = require('settings');
local inspect = require('inspect');

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
    last_packet = nil,
};

besieged.last_update = os.time() - besieged.settings.interval + 3

local minimum_interval = 125 --there is a client side cache for 2 mins, so we don't want to force request the server more than this allows

local beastman_status_map = {
    [0] = 'Training',
    [1] = 'Advancing',
    [2] = 'Attacking',
    [3] = 'Retreating',
    [4] = 'Defending',
    [5] = 'Preparing',
}

local function log(tag, fmt, ...)
    if select('#', ...) == 0 and fmt == nil then
        fmt = tag
        tag = (addon and addon.name)
            and string.format('[\30\05%s\30\01] ', addon.name)
            or ''
    else
        tag = tag or (addon and addon.name)
            and string.format('[\30\05%s\30\01] ', addon.name)
            or ''
    end

    local message = string.format(fmt, ...)
    print(tag .. message)
end


local function debug(fmt, ...)
    if not besieged.settings.debug then return end
    local tag = (addon and addon.name)
        and string.format('[\30\02DEBUG - %s\30\01] ', addon.name)
        or ''
    log(tag, fmt, ...)
end

local function print_help()
    log("Usage: %s [command]", addon.aliases[1])
    log("Available commands:%s", inspect(addon.commands))
end

local function parse_besieged_packet(packet)
    local data = packet.data
    local a2 = data:byte(0x00A2 + 1)
    local a3 = data:byte(0x00A3 + 1)

    -- Status bitfields (unchanged, correct offsets)
    local mamool_status = bit.rshift(bit.band(a2, 0xE0), 5)       -- bits 7–5
    local troll_status  = bit.rshift(bit.band(a2, 0x1C), 2)       -- bits 4–2
    local lamia_status  = bit.bor(
        bit.band(a2, 0x03),                      -- bits 1–0
        bit.lshift(bit.rshift(a3, 7), 2)         -- bit 7 from A3
    )

    -- Updated level offsets
    local mamool_level = data:byte(0x009E + 1)
    local troll_level  = data:byte(0x00A1 + 1)  
    local lamia_level  = data:byte(0x009F + 1)

    return {
        mamool = { status = beastman_status_map[mamool_status], level = mamool_level },
        trolls = { status = beastman_status_map[troll_status],  level = troll_level },
        lamia  = { status = beastman_status_map[lamia_status],  level = lamia_level },
    }
end



local function handle_besieged_packet(packet)
    debug('Handling Besieged packet data')
    besieged.last_packet = packet
    debug('Received Besieged data from server')



        if besieged.requesting then
            besieged.requesting = false
            handle_besieged_packet(packet)
        end
    local notification = ''
    local besieged_status = parse_besieged_packet(packet)

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


ashita.events.register('load', 'load_'..addon.name:lower(), function ()

    print(string.format('[\30\05%s Addon\30\01] Loaded. Update interval: %d seconds.', addon.name, besieged.settings.interval))
    
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
    elseif cmd == 'last' then
        if not besieged.last_packet then
            log('No previous Besieged data available.')
            return
        end
        handle_besieged_packet(besieged.last_packet)
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
            log('Besieged UI is now visible. Use /showhex to toggle it off.')
        else
            log('Besieged UI is now hidden. Use /showhex to toggle it on.')
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
    if not besieged.settings.show_window or not besieged.last_packet then return end

    local packet_data = besieged.last_packet.data
    local parsed = parse_besieged_packet({ data = packet_data })
    local bytes_per_row = 16

    if imgui.Begin('Raw Packet Hex Viewer', true) then

        -- Section: Status Overview
        imgui.Text('Besieged Status:')

        for name, info in pairs({
            Mamool = parsed.mamool,
            Trolls = parsed.trolls,
            Lamia = parsed.lamia,
        }) do
            imgui.Text(string.format('%-12s Lv %d  (%s)', name, info.level, info.status))
        end

        imgui.Separator()

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


        -- Section: Hex Viewer
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
end)


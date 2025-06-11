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
}

local ffi = require('ffi')
local bit = require('bit')
local settings = require('settings');
local inspect = require('inspect');

-- Default Settings
local default_settings = T{
    debug = true,
    interval = 300
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

besieged.last_update = os.now() - besieged.settings.interval + 10

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
        and string.format('[\30\02[DEBUG] %s\30\01] ', addon.name)
        or ''
    log(tag, fmt, ...)
end

local function print_help()
    log("Usage: %s [command]", addon.aliases[1])
    log("Available commands:%s", inspect(addon.commands))
end

local function parse_besieged_packet(packet)
    local data = packet.data_raw or packet.data

    local byteA0 = data:byte(0xA0 + 1)
    local byteA1 = data:byte(0xA1 + 1)
    local byteA2 = data:byte(0xA2 + 1)
    local byteA3 = data:byte(0xA3 + 1)

    -- byteA0: CCOOMMMM
    local candescense = bit.rshift(bit.band(byteA0, 0xC0), 6)
    local orders      = bit.rshift(bit.band(byteA0, 0x30), 4)
    local mamool_level = bit.band(byteA0, 0x0F)

    -- byteA1: TTTTLLLL
    local trolls_level = bit.rshift(byteA1, 4)
    local lamia_level  = bit.band(byteA1, 0x0F)

    -- byteA2: MMMTTTLL
    local mamool_status = bit.rshift(byteA2, 5)
    local trolls_status = bit.band(bit.rshift(byteA2, 2), 0x07)
    local lamia_status_part_1 = bit.band(byteA2, 0x03)

    -- byteA3: L-------
    local lamia_status_part_2 = bit.rshift(byteA3, 7)
    local lamia_status = bit.bor(lamia_status_part_1, bit.lshift(lamia_status_part_2, 2))

    return {
        mamool = {
            status = beastman_status_map[mamool_status],
            level = mamool_level,
        },
        trolls = {
            status = beastman_status_map[trolls_status],
            level = trolls_level,
        },
        lamia = {
            status = beastman_status_map[lamia_status],
            level = lamia_level,
        },
    }
end

local function handle_besieged_packet(packet)
    debug('Handling Besieged packet data')
    besieged.last_packet = packet
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
    log('Loaded. Update interval: %d seconds.', besieged.settings.interval)
end);

ashita.events.register('d3d_present', 'enable_chocorun', function()
    if os.time() - besieged.last_update < besieged.settings.interval then
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
        for i = 0xA0, 0xA3 do
            local b = packet.data:byte(i + 1)
            if b == nil then
                debug('byte[%X] is nil (packet too short?)', i)
            else
                debug('byte[%X] = 0x%02X (%d)', i, b, b)
            end
        end
        debug('packet.data size: %d', #packet.data)


        for i = 0xA0, 0xA3 do
            local b = packet.data:byte(i + 1)
            debug(string.format('byte[%X] = 0x%02X (%d)', i, b, b))
        end
        local hex_data = {}
        for i = 1, #packet.data do
            if (i - 1) % 16 == 0 then
                table.insert(hex_data, string.format('\n%04X: ', i - 1))
            end
            table.insert(hex_data, string.format('%02X ', packet.data:byte(i)))
        end
        log(inspect(table.concat(hex_data)))
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
    else
        log("Unknown command: %s", cmd)
        print_help()
        return
    end
end)



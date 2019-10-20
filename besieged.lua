_addon.name = 'Besieged'
_addon.author  = 'Dean James (Xurion of Bismarck)'
_addon.version = '0.0.1'
_addon.commands = {'besieged', 'bs'}

require('pack')
packets = require('packets')
timeit = require('timeit')
timer = timeit.new()
interval = 300 --5 mins
minimum_interval = 125 --there is a client side cache for 2 mins, so we don't want to force request the server more than this allows
previous_attacker = nil
requesting = false
debug_mode = true

function debug(msg)
    if not debug_mode then return end
    print('Besieged debug', msg)
end

function add_to_chat(msg)
    windower.add_to_chat(8, msg)
end

beastman_status_map = {
    [0] = 'Training',
    [1] = 'Advancing',
    [2] = 'Attacking',
    [3] = 'Retreating',
    [4] = 'Defending',
    [5] = 'Preparing',
}

windower.register_event('load', function()
    timer:start()
    debug('Loaded. Timer of ' .. interval .. ' seconds started')
end)

windower.register_event('prerender', function()
    if timer:check() >= interval and not requesting then
        debug('Interval reached')
        requesting = true
        timer:next() --start counting from zero
        debug('Time reset to zero')
        request_besieged_data()
    end
end)

windower.register_event('addon command', function(command, ...)
    if not command then return end
    local args = {...}
    if command == 'last' then
        local previous_packet = windower.packets.last_incoming(0x05E)
        handle_besieged_packet(previous_packet)
    elseif command == 'interval' and args[1] then
        if type(args[1]) ~= 'number' then return end
        if args[1] < minimum_interval then
            add_to_chat('Cannot set interval lower than ' .. minimum_interval)
            interval = minimum_interval
        else
            interval = args[1]
        end
        add_to_chat('Interval set to ' .. interval .. ' seconds')
    end
end)

windower.register_event('incoming chunk', function(id, packet)
    if id == 0x05E then
        timer:next() --force counting from zero just in case this was a manual /besiegedmap check from the player
        debug('Received Besieged data from server - Time reset to zero in case this is a manual /besiegedmap check')
        if requesting then
            requesting = false
            handle_besieged_packet(packet)
        end
    end
end)

function handle_besieged_packet(packet)
    debug('Handling Besieged packet data')
    local notification = ''
    local besieged_status = parse_besieged_packet(packet)

    if previous_attacker == 'Mamool Ja Savages' and besieged_status.mamool.status ~= 'Attacking' then
        notification = notification .. 'The Mamool Ja Savages have retreated.\n'
    end

    if previous_attacker == 'Troll Mercenaries' and besieged_status.trolls.status ~= 'Attacking' then
        notification = notification .. 'The Troll Mercenaries have retreated.\n'
    end

    if previous_attacker == 'Undead Swarm' and besieged_status.llamia.status ~= 'Attacking' then
        notification = notification .. 'The Undead Swarm have retreated.\n'
    end

    if besieged_status.mamool.status == 'Attacking' then
        previous_attacker = 'Mamool Ja Savages'
        notification = notification .. 'Level ' .. besieged_status.mamool.level .. ' Mamool Ja Savages are attacking Al Zahbi!\n'
    end

    if besieged_status.trolls.status == 'Attacking' then
        previous_attacker = 'Troll Mercenaries'
        notification = notification .. 'Level ' .. besieged_status.trolls.level .. ' Troll Mercenaries are attacking Al Zahbi!\n'
    end

    if besieged_status.llamia.status == 'Attacking' then
        previous_attacker = 'Undead Swarm'
        notification = notification .. 'Level ' .. besieged_status.llamia.level .. ' Undead Swarm are attacking Al Zahbi!\n'
    end

    if besieged_status.mamool.status == 'Advancing' then
        notification = notification .. 'Level ' .. besieged_status.mamool.level .. ' Mamool Ja Savages are advancing towards Al Zahbi!\n'
    end

    if besieged_status.trolls.status == 'Advancing' then
        notification = notification .. 'Level ' .. besieged_status.trolls.level .. ' Troll Mercenaries are advancing towards Al Zahbi!\n'
    end

    if besieged_status.llamia.status == 'Advancing' then
        notification = notification .. 'Level ' .. besieged_status.llamia.level .. ' Undead Swarm are advancing towards Al Zahbi!\n'
    end

    if notification ~= '' then
        notification = 'Besieged Update:\n' .. notification

        --remove last character to prevent extra line feed?

        --Maybe only alert the player if the notification is different from the previous?
        add_to_chat(notification)
    else
        debug('No notification this time')
        debug('Trolls [' .. besieged_status.trolls.level .. ']  Mamool Ja [' .. besieged_status.mamool.level .. ']  Llamia [' .. besieged_status.llamia.level .. ']')
    end
end

function request_besieged_data()
    debug('Requesting Besieged data from server')
    local packet = packets.new('outgoing', 0x05A, {})
    packets.inject(packet)
end

--LSB00MSB

function parse_besieged_packet(packet)
	local candescense, orders, mamool_level = packet:unpack('b2b2b4', 0xA0 + 1)
    local trolls_level, llamia_level = packet:unpack('b4b4', 0xA1 + 1)
    local mamool_status, trolls_status, llamia_status_part_1 = packet:unpack('b3b3b2', 0xA2 + 1)
    local llamia_status_part_2 = packet:unpack('b1', 0xA3 + 1)
    local llamia_status = llamia_status_part_1 + llamia_status_part_2

    local mamool_status = beastman_status_map[mamool_status]
    local trolls_status = beastman_status_map[trolls_status]
    local llamia_status = beastman_status_map[llamia_status]

    return {
        mamool = {
            status = mamool_status,
            level = mamool_level,
        },
        trolls = {
            status = trolls_status,
            level = trolls_level,
        },
        llamia = {
            status = llamia_status,
            level = llamia_level,
        },
    }
end

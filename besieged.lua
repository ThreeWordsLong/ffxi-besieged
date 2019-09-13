_addon.name = 'Besieged'
_addon.author  = 'Dean James (Xurion of Bismarck)'
_addon.version = '0.0.1'
_addon.commands = {'besieged', 'bs'}

timeit = require('timeit');
timer = timeit.new()
interval = 60
requesting = false
last_notification = nil

beastman_statuses_map = {
    0 = 'Training',
    1 = 'Advancing',
    2 = 'Attacking',
    3 = 'Retreating',
    4 = 'Defending',
    5 = 'Preparing',
}

windower.register_event('load', function()
    timer:start()
end)

windower.register_event('prerender', function()
    if timer:check() >= interval then
        requesting = true
        request_besieged_data()
        timer:next()
    end
end)

windower.register_event('addon command', function(...)
    if not ... then return end
    local args = {...}
    if args[0] == 'stop' then
        timer:stop()
        windower.add_to_chat(8, 'Besieged alerts stopped')
    else if args[0] == 'start' then
        timer:start()
        windower.add_to_chat(8, 'Besieged alerts resumed')
    end
end)

windower.register_event('incoming chunk', function(id, packet)
    if id == 0x05E && requesting then
        local notification = '';
        requesting = false
        local besieged_statuses = parse_besieged_packet(packet)

        if besieged_statuses.mamool == 'Attacking' then
            notification = 'The Mamool Ja Savages are attacking Al Zahbi!\n'
        end

        if besieged_statuses.trolls == 'Attacking' then
            notification = notification .. 'The Troll Mercenaries are attacking Al Zahbi!\n'
        end

        if besieged_statuses.llamia == 'Attacking' then
            notification = notification .. 'The Undead Swarm are attacking Al Zahbi!\n'
        end

        if besieged_statuses.mamool == 'Advancing' then
            notification = notification .. 'The Mamool Ja Savages are advancing towards Al Zahbi!\n'
        end

        if besieged_statuses.trolls == 'Advancing' then
            notification = notification .. 'The Troll Mercenaries are advancing towards Al Zahbi!\n'
        end

        if besieged_statuses.llamia == 'Advancing' then
            notification = notification .. 'The Undead Swarm are advancing towards Al Zahbi!\n'
        end

        if notification then
            notification = 'Besieged Update:\n' .. notification;
        end

        --remove last character to prevent extra line feed?

        --Only alert the player if the notification is different from the previous
        if last_notification != notification then
            last_notification = notification
            windower.add_to_chat(8, notification)
        end
    end
end)

function request_besieged_data()
    --send a 0x05A
end

function parse_besieged_packet(packet)
    local mamool_status_code = packet:byte(0) --define packet ID
    local mamool_status = beastman_status_map[mamool_status_code]
    local trolls_status_code = packet:byte(0) --define packet ID
    local trolls_status = beastman_status_map[trolls_status_code]
    local llamia_status_code = packet:byte(0) --define packet ID
    local llamia_status = beastman_status_map[llamia_status_code]

    return {
        mamool = mamool_status,
        trolls = trolls_status,
        llamia = llamia_status,
    }
end

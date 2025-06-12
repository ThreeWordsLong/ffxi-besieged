# ffxi-besieged

*Work in progress - This addon requests data from the server and has not been fully tested. Use at your own discretion.*

An Ashita4 port of Xurion's ffxi-beseiged addon.

Still trying to sort out the packet data, doesn't seem to be quite right.

## Running
Copy the addon to `addons/besieged/besieged.lua` in the Ashita install directory. Then run `/addon load besieged` in game.

## Commands

### interval
`/bs interval [interval]`
Sets the alert interval to the given interval in seconds.
Note: The FFXI client only allows you to request Besieged data from the server every two minutes, even if you use /bmap multiple times.
For this reason, the minimum interval you can set is 125s so we don't spam the servers with requests. The default interval is 300s.

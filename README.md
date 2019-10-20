# ffxi-besieged
An FFXI Windower 4 addon that alerts when Besieged events are happening.

## Running
Copy the addon to `addons/besieged/besieged.lua` in the Windower install directory. Then run `//lua load besieged` in game.

## Commands

### interval
`//bs interval [interval]`
Sets the alert interval to the given interval in seconds.
Note: The FFXI client only allows you to request Besieged data from the server every two minutes, even if you use /bmap multiple times.
For this reason, the minimum interval you can set is 125s so we don't spam the servers with requests. The default interval is 300s.

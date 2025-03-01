# Elden Ring PS5 Invasion Blocker
# PS5 Invasion Shield

A network monitoring and control tool for Elden Ring cooperative play on PlayStation 5. This tool allows you to play cooperatively while automatically blocking unwanted invasions after a configurable analysis period.

works fine - the host will see the invader struggling, while other coop-players must run until the invader is kicked.

This is a research project for network analysis purposes. Use at your own risk and responsibility. The tool does not modify any game files or the PlayStation 5 system.

### Hardware
- PlayStation 5
- GL.iNet Beryl (GL-MT1300) or similar OpenWrt router
- Network connection between PS5 and router

## Overview

PS5 Invasion Shield is a collection of shell scripts that analyze and control network traffic between your PlayStation 5 and the internet. When playing co-op modes in games like Elden Ring, it allows cooperative play while selectively blocking unwanted PvP invasion connections.

This is a network-level solution that works by:
1. Learning legitimate co-op connections during a learning phase
2. Monitoring all new connections during gameplay
3. Selectively blocking connections that aren't part of the co-op whitelist

## Key Features

- **Non-invasive**: Works at the network level without modifying your PS5 or games
- **Selective Blocking**: Preserves co-op functionality while blocking invasions
- **Configurable**: Multiple modes of operation with adjustable timing
- **Automatic Learning**: Auto-detects legitimate connections
- **Static Whitelist**: Permanently allow specific IPs
- **Live Monitoring**: Real-time view of all connections and their status

## Requirements

- A Linux-based router or computer acting as a gateway between your PS5 and internet
- Shell scripting environment (Bash/Dash/BusyBox)
- Administrative access (root) to configure iptables
- `iptables` and `conntrack` installed
- Your PS5 must be connected through this device

Tested on:
- OpenWRT routers
- GL.iNet travel routers
- Linux-based NAS devices
- Raspberry Pi as network bridge

## Installation

1. Clone this repository to your router/device:
   ```
   git clone https://github.com/yourusername/ps5-invasion-shield.git
   cd ps5-invasion-shield
   ```

2. Make scripts executable:
   ```
   chmod +x invasion-*.sh
   ```

3. Edit the configuration file to match your network setup:
   ```
   nano invasion-config.sh
   ```
   
   At minimum, update the PS5_IP variable to match your PlayStation's IP address.

## Usage

The system consists of several scripts that work together:

### 1. Learning Mode
Run this first to establish a whitelist of legitimate connections:

```
./invasion-learn.sh
```

The script will automatically monitor connections for 20 seconds and add them to the whitelist. You should run this when connected to friends in co-op mode.

### 2. Shield Mode
After establishing a whitelist, run the shield mode to protect against invasions:

```
./invasion-shield.sh
```

This monitors all connections and blocks any that aren't in the whitelist after a short observation period.

### 3. Monitor Mode
To view current connections and protection status:

```
./invasion-monitor.sh
```

### 4. Control Functions
Manage whitelist and perform maintenance tasks:

```
./invasion-control.sh
```

This opens a menu with various options to clean up the whitelist, remove inactive connections, or block all non-whitelisted connections.

## Technical Details

### How It Works

1. **Learning Phase**: The system monitors all connections to your PS5 and records the IP:Port combinations during co-op play
2. **Observation**: When running in shield mode, new connections not in the whitelist are observed for 30 seconds
3. **Decision**: If a connection persists beyond the observation period and isn't in the whitelist, it's blocked for 3 minutes
4. **Whitelist System**: Two types of whitelists are maintained:
   - Dynamic Whitelist: IP:Port combinations learned during the learning phase
   - Static Whitelist: IP addresses that are always permitted regardless of port

### Configuration Options

Edit `invasion-config.sh` to customize:

- `PS5_IP`: Your PlayStation 5's IP address
- `LOCAL_RANGE`: Your local network range (to exclude from filtering)
- `OBSERVATION_TIME`: How long to observe new connections before deciding (seconds)
- `BLOCK_DURATION`: How long to block unwanted connections (seconds)
- `REFRESH_INTERVAL`: Update interval for all scripts (seconds)

### Static Whitelist

To permanently allow specific IP addresses regardless of port:

1. Edit the `static_whitelist.txt` file
2. Add one IP address per line (no port numbers)
3. Lines starting with # are treated as comments

Example:
```
# FromSoftware matchmaking servers
65.52.64.250
52.226.139.180
```

## Troubleshooting

- **"No connections detected"**: Ensure your PS5 is actively communicating through the device running the scripts
- **"Learning mode captures no connections"**: Check if your PS5 has an active internet connection and is using the correct gateway
- **"Co-op doesn't work"**: Your whitelist may be incomplete. Run learning mode again during active co-op
- **"Invasions still occur"**: The invasion may be coming from a previously whitelisted connection. Try clearing and recreating your whitelist.


## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This tool is provided for research and educational purposes only. Use at your own risk. We are not responsible for any account suspensions or other consequences that may arise from using this software.

The authors do not encourage or condone cheating in online games. This tool is designed to enhance co-op play experience by filtering unwanted network connections, not to provide unfair advantages.

## Security Considerations

- The tool only monitors and manages network connections
- No game files or console system files are modified
- All changes are made at the network level through the router
- Emergency deactivation available at any time

## Acknowledgments

- Thanks to the OpenWrt community
- GL.iNet for their router firmware
- All contributors and testers
- No thanks to make intruders an integral part of the game design :-/

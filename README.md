# Elden Ring PS5 Invasion Blocker

A network monitoring and control tool for Elden Ring cooperative play on PlayStation 5. This tool allows you to play cooperatively while automatically blocking unwanted invasions after a configurable analysis period.

## ⚠️ Disclaimer

This is a research project for network analysis purposes. Use at your own risk and responsibility. The tool does not modify any game files or the PlayStation 5 system.

## Features

- Learning mode to identify and whitelist cooperative connections
- Protection mode to monitor and manage new connections
- Configurable analysis window for new connections (default: 30 seconds)
- Emergency deactivation of all blocking rules
- Detailed logging system
- Modular implementation for easy maintenance

## Requirements

### Hardware
- PlayStation 5
- GL.iNet Beryl (GL-MT1300) or similar OpenWrt router
- Network connection between PS5 and router

### Software
- Python 3.10+
- OpenWrt 22.03+
- IPTables with NFT backend
- Conntrack-tools

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/eldenring-ps5-invasion-blocker.git
cd eldenring-ps5-invasion-blocker
```

2. Install required Python packages:
```bash
pip install -r requirements.txt
```

3. Configure your settings in `config.py`:
```python
SETTINGS = {
    'ps5_ip': 'YOUR_PS5_IP',
    'whitelist_file': 'whitelist.json',
    'log_file': 'network_monitor.log',
    'analysis_time': 30  # seconds
}
```

## Usage

### 1. Learning Mode
First, run the learning mode to identify legitimate cooperative connections:

```bash
python lernmodus.py
```

Start a cooperative session in Elden Ring and play normally. The script will learn and save connection patterns. Press Ctrl+C to stop and save the whitelist.

### 2. Protection Mode
After creating a whitelist, run the protection mode:

```bash
python schutzmodus.py
```

This will:
- Monitor new network connections
- Allow whitelisted connections immediately
- Analyze new connections for the configured time window
- Block connections that don't match cooperative patterns

To stop monitoring and optionally remove all blocking rules, press Ctrl+C.

## How It Works

The tool uses three main components:

1. **Network Helper** (`netzwerk_helfer.py`):
   - Provides common utilities for network monitoring
   - Handles connection tracking and IP extraction
   - Manages logging

2. **Learning Mode** (`lernmodus.py`):
   - Observes and records legitimate cooperative connections
   - Creates a whitelist of trusted IPs

3. **Protection Mode** (`schutzmodus.py`):
   - Monitors new connections
   - Applies whitelist rules
   - Manages connection blocking

## Contributing

Contributions are welcome! Please feel free to submit pull requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Security Considerations

- The tool only monitors and manages network connections
- No game files or console system files are modified
- All changes are made at the network level through the router
- Emergency deactivation available at any time

## Acknowledgments

- Thanks to the OpenWrt community
- GL.iNet for their router firmware
- All contributors and testers

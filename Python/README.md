# Cisco Tunnel Gateway Checker — Python Edition

A cross-platform Python implementation of the Cisco Tunnel Gateway Checker for NOC and network-engineering workflows. It connects to Cisco devices over SSH with Paramiko, reads tunnel configuration, calculates gateway addresses, and performs Cisco-side reachability checks.

## Requirements

- Python 3.9 or newer recommended
- SSH access to the Cisco router
- A Cisco IOS/IOS-XE device with an accessible tunnel interface

Dependencies are listed in `requirements.txt`:

```text
paramiko>=3.4,<5
cryptography>=42,<47
```

## Installation

From the repository root:

```powershell
git clone https://github.com/alizarifi23/cisco-tunnel-gateway-checker.git
cd cisco-tunnel-gateway-checker
```

Create a virtual environment:

### Windows CMD

```cmd
python -m venv .venv
.venv\Scripts\activate
python -m pip install --upgrade pip
python -m pip install -r Python\requirements.txt
```

### Windows PowerShell

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r Python\requirements.txt
```

### Linux / macOS

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r Python/requirements.txt
```

## Run

From the repository root:

```powershell
python Python\Cisco-Tunnel-Gateway-Checker.py
```

Or, after changing into the Python directory:

```powershell
cd Python
python Cisco-Tunnel-Gateway-Checker.py
```

## First Run

The Python application creates local runtime files next to the Python script:

```text
Python/
├── Cisco-Tunnel-Gateway-Checker.py
├── config.json          # generated locally
├── routers.csv          # generated locally
└── .credentials.key    # generated locally when credentials are saved
```

Do not commit real versions of these local files.

## How It Works

1. Select a router from the CSV inventory.
2. Enter the Cisco tunnel number.
3. Establish an interactive SSH session with Paramiko.
4. Execute `show run interface tunnel <number>`.
5. Extract tunnel source and destination IPv4 addresses.
6. Apply the configured gateway offset.
7. Execute Cisco-side ping tests for the calculated gateways.
8. Display the results in the console.

## Configuration

The application manages configuration interactively. The main settings include:

- SSH username and password
- Optional Cisco enable password
- Gateway IPv4 offset
- Ping count and timeout
- Cisco SSH port and command timeout
- Router CSV location

## Credential Protection

When saved credentials are enabled, the Python edition encrypts password values with Fernet and stores the local key in `.credentials.key`.

This is local convenience protection, not a replacement for an enterprise secrets manager. Protect the workstation and never commit `.credentials.key`, `config.json`, or real router inventory data.

## Router Inventory

Example `Python/routers.csv`:

```csv
ID,Name,IP
1,R1,192.168.1.1
2,R2,192.168.1.2
```

The application provides router management for listing, adding, editing, and deleting routers.

## Gateway Offset Example

Given:

```text
Tunnel Source  : 10.10.10.10
Gateway Offset : -1
```

The calculated source gateway is:

```text
10.10.10.9
```

The same offset is applied to the tunnel destination.

## Troubleshooting

### `ModuleNotFoundError`

Make sure the virtual environment is active and install the dependencies:

```powershell
python -m pip install -r Python\requirements.txt
```

### SSH connection fails

Check the router IP, SSH port, credentials, reachability, and Cisco SSH configuration.

### Tunnel source/destination is not detected

Confirm that the selected tunnel exists and that Cisco returns `tunnel source` and `tunnel destination` lines for it.

## Related Editions

- [Repository](../README.md)
- [PowerShell Edition](../PowerShell/README.md)

© 2026 Cisco Tunnel Gateway Checker — Powered By Ali Zarifi

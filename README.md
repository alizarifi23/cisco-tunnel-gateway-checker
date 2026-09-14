# Cisco Tunnel Gateway Checker

> A practical NOC utility for Cisco network engineers to discover tunnel source/destination gateways and verify reachability directly from Cisco routers.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](PowerShell/README.md)
[![Python](https://img.shields.io/badge/Python-3.9%2B-3776AB?logo=python&logoColor=white)](Python/README.md)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Cisco Tunnel Gateway Checker is a lightweight network troubleshooting and automation tool designed for NOC engineers and Cisco administrators. It connects to a Cisco router over SSH, identifies the configured tunnel source and destination, calculates the corresponding gateway addresses using a configurable IPv4 offset, and runs Cisco-side ping tests.

The repository contains **two equivalent editions** so the tool can be used in Windows PowerShell environments or cross-platform Python environments.

## ✨ Highlights

- 🔐 SSH connectivity to Cisco routers
- 🔎 Automatic tunnel source and destination detection
- 🌐 Configurable gateway IP offset such as `-1`, `+1`, `-2`, or `+2`
- 📡 Cisco-side gateway ping verification
- 🔄 Persistent interactive SSH session during a tunnel check
- 📋 CSV-based router inventory
- ➕ Add, edit, list, and delete routers
- 🔑 Optional local credential protection
- 🖥️ Console-based NOC workflow
- 🧰 PowerShell implementation using PuTTY/Plink
- 🐍 Python implementation using Paramiko
- 📦 Separate documentation and dependencies for each edition

## 🧭 Choose an Edition

| Edition | Best for | Entry point |
|---|---|---|
| **PowerShell** | Windows NOC workstations and Plink-based Cisco SSH | [`PowerShell/Cisco-Tunnel-Gateway-Checker.ps1`](PowerShell/Cisco-Tunnel-Gateway-Checker.ps1) |
| **Python** | Cross-platform automation and Python environments | [`Python/Cisco-Tunnel-Gateway-Checker.py`](Python/Cisco-Tunnel-Gateway-Checker.py) |

### PowerShell

See the complete Windows installation, Plink setup, configuration, router inventory, credentials, and troubleshooting guide:

**[→ PowerShell README](PowerShell/README.md)**

Run from the repository root:

```powershell
.\PowerShell\Cisco-Tunnel-Gateway-Checker.ps1
```

### Python

See the complete Python virtual-environment installation, dependency setup, configuration, credential protection, router inventory, and troubleshooting guide:

**[→ Python README](Python/README.md)**

Install:

```powershell
python -m venv .venv
.\.venv\Scripts\activate
python -m pip install -r Python\requirements.txt
```

Run:

```powershell
python Python\Cisco-Tunnel-Gateway-Checker.py
```

## ⚙️ How It Works

```text
                         Cisco Router
                              │
                              │ SSH
                              ▼
               ┌────────────────────────────┐
               │ Cisco Tunnel Gateway       │
               │ Checker                    │
               └─────────────┬──────────────┘
                             │
                             │ show run interface tunnel X
                             ▼
                  ┌──────────────────────┐
                  │ Tunnel Source /      │
                  │ Tunnel Destination   │
                  └──────────┬───────────┘
                             │
                       IPv4 Offset
                             │
                             ▼
                  ┌──────────────────────┐
                  │ Source Gateway       │
                  │ Destination Gateway  │
                  └──────────┬───────────┘
                             │
                        Cisco Ping
                             │
                             ▼
                    Reachability Result
```

For a tunnel source of `10.10.10.10` and an offset of `-1`, the checker calculates `10.10.10.9`. The same logic is applied to the tunnel destination.

## 📁 Repository Structure

```text
cisco-tunnel-gateway-checker/
│
├── PowerShell/
│   ├── Cisco-Tunnel-Gateway-Checker.ps1
│   └── README.md
│
├── Python/
│   ├── Cisco-Tunnel-Gateway-Checker.py
│   ├── requirements.txt
│   └── README.md
│
├── .gitignore
├── LICENSE
└── README.md
```

Runtime files such as `config.json`, `routers.csv`, and the Python credential key are generated locally and are intentionally excluded from source control.

## 🖥️ Requirements

### PowerShell Edition

- Windows 10 / 11
- PowerShell 5.1 or newer
- PuTTY / `plink.exe`
- SSH connectivity to the Cisco router

### Python Edition

- Python 3.9 or newer recommended
- SSH connectivity to the Cisco router
- `paramiko`
- `cryptography`

## 📋 Typical NOC Workflow

```text
SSH → Select Router → Select Tunnel
        ↓
Read Tunnel Source / Destination
        ↓
Apply Gateway Offset
        ↓
Ping Source Gateway
        ↓
Ping Destination Gateway
        ↓
Display Reachability Results
```

This reduces repetitive manual work during tunnel troubleshooting, incident investigation, connectivity checks, and first-level Cisco network support.

## 🔐 Security Notes

Do not commit:

- Real Cisco usernames/passwords
- `config.json` containing saved credentials
- `routers.csv` containing confidential production inventory
- `.credentials.key`
- Private infrastructure information

Use dedicated Cisco accounts with appropriate privileges and follow your organization's credential-management policy.

## 🔎 Search / SEO Keywords

Cisco Tunnel Gateway Checker, Cisco tunnel checker, Cisco gateway checker, Cisco GRE tunnel troubleshooting, Cisco IP tunnel troubleshooting, Cisco NOC tool, Cisco network automation, Cisco network troubleshooting, Cisco SSH checker, Cisco IOS tunnel, Cisco IOS-XE tunnel, PowerShell Cisco automation, Python Cisco automation, Paramiko Cisco SSH, Plink Cisco SSH, tunnel source destination checker, gateway reachability checker, NOC network utility, network operations automation.

> Search visibility cannot be guaranteed by README text alone. GitHub indexing, repository activity, external links, search-engine crawling, and the quality/relevance of the project all affect discoverability. This README is structured with descriptive headings, natural technical keywords, clear links, and installation documentation to make the project easier to understand and index.

## 🛣️ Roadmap

Potential future improvements:

- [ ] Multi-router batch tunnel checks
- [ ] Parallel checks
- [ ] CSV/JSON result export
- [ ] HTML reporting
- [ ] Packet-loss and latency extraction
- [ ] Multiple tunnels per router
- [ ] Structured logging
- [ ] Monitoring-platform integration
- [ ] SNMP checks
- [ ] Optional GUI

## 🤝 Contributing

Bug reports, improvements, documentation updates, and pull requests are welcome. Never include passwords, private keys, or confidential production network information in issues or pull requests.

## 📄 License

Released under the MIT License. See [`LICENSE`](LICENSE).

## 👨‍💻 Author

**Ali Zarifi**

- GitHub: [@alizarifi23](https://github.com/alizarifi23)
- Email: alizarifi23@gmail.com

## ⭐ Support

If this project is useful for Cisco network troubleshooting, NOC operations, or network automation, consider starring the repository on GitHub.

---

**Cisco Tunnel Gateway Checker — practical Cisco tunnel and gateway verification for NOC engineers.**

# Cisco Tunnel Gateway Checker

A PowerShell-based NOC utility for Cisco network engineers to quickly identify tunnel source/destination gateways and verify their reachability through Cisco devices.

The tool establishes an SSH session to a Cisco router using **Plink**, retrieves the configured tunnel source and destination addresses, calculates the corresponding gateway addresses based on a configurable IP offset, and performs Cisco-side ping tests.

---

## 🚀 Features

* 🔐 SSH connection to Cisco routers using **Plink**
* 🔑 Optional encrypted credential storage
* 🔎 Automatic `plink.exe` detection
* 📁 Manual Plink path configuration
* ⚙️ JSON-based configuration
* 🌐 Configurable gateway IP offset (`+1`, `-1`, `+2`, etc.)
* 📋 Router management through CSV
* ➕ Add routers directly from the application
* ✏️ Edit router information
* 🗑️ Delete routers
* 🔢 Dynamic Cisco tunnel number input
* 🔍 Automatic detection of:

  * Tunnel Source IP
  * Tunnel Destination IP
* 📡 Cisco-side gateway ping
* 🔄 Persistent SSH session during the tunnel check
* 🖥️ Professional console-based interface
* 🛠️ Designed as a practical **NOC / Network Operations tool**
* 🧩 No tunnel host keys need to be stored in `routers.csv`
* 🔐 Uses PuTTY/Plink's SSH host-key mechanism

---

## 🏗️ Project Structure

```text
cisco-tunnel-gateway-checker/
│
├── PowerShell/
│   ├── Cisco-Tunnel-Gateway-Checker.ps1
│   ├── config.json
│   └── routers.csv
│
├── Python/
│   └── README.md
│
├── README.md
└── LICENSE
```

> The repository can be expanded with additional implementations, such as Python, in the future.

---

## ⚙️ How It Works

The general workflow is:

```text
                ┌──────────────────────┐
                │   Cisco Router       │
                └──────────┬───────────┘
                           │
                           │ SSH / Plink
                           ▼
                ┌──────────────────────┐
                │ Tunnel Gateway       │
                │      Checker         │
                └──────────┬───────────┘
                           │
                  show run int tu X
                           │
                           ▼
              ┌──────────────────────────┐
              │ Tunnel Source /          │
              │ Tunnel Destination       │
              └────────────┬─────────────┘
                           │
                     IP Offset
                           │
                           ▼
              ┌──────────────────────────┐
              │ Source Gateway           │
              │ Destination Gateway      │
              └────────────┬─────────────┘
                           │
                     Cisco Ping
                           │
                           ▼
                ┌──────────────────────┐
                │ Reachability Result  │
                └──────────────────────┘
```

---

# 🖥️ Requirements

### Operating System

* Windows 10 / 11
* PowerShell 5.1 or newer

### Network

The machine running the application must be able to establish SSH connectivity to the Cisco router.

### Required Software

**PuTTY / Plink**

The application requires:

```text
plink.exe
```

The program can automatically search common Windows locations for Plink.

If Plink is not found, the application provides an option to manually specify its location.

---

# 📦 Installation

## 1. Clone the Repository

```powershell
git clone https://github.com/alizarifi23/cisco-tunnel-gateway-checker.git
```

Then:

```powershell
cd cisco-tunnel-gateway-checker
```

---

## 2. Start the Application

Run the PowerShell script:

```powershell
.\PowerShell\Cisco-Tunnel-Gateway-Checker.ps1
```

If PowerShell execution policy prevents the script from running, you may need to adjust your execution policy according to your organization's security policy.

---

# 🔧 Configuration

The application automatically creates `config.json` if it does not exist.

Example:

```json
{
    "Credentials": {
        "SaveCredentials": false,
        "Username": "",
        "Password": ""
    },
    "Network": {
        "GatewayOffset": -1
    },
    "Ping": {
        "Count": 5,
        "Timeout": 2
    },
    "Cisco": {
        "SSHPort": 22,
        "CommandTimeout": 15
    },
    "Files": {
        "Routers": ".\\routers.csv",
        "Plink": ""
    }
}
```

---

# 🌐 Gateway Offset

Different organizations may use different IP addressing policies around tunnel endpoints.

For example, if the tunnel source is:

```text
10.10.10.10
```

and the configured offset is:

```text
-1
```

the application calculates:

```text
10.10.10.9
```

If the offset is:

```text
+1
```

the result becomes:

```text
10.10.10.11
```

The offset can be configured from the application:

```text
Configuration
    └── Gateway Offset
```

Examples:

```text
+1
-1
+2
-2
```

This allows the same tool to be used in environments with different IP addressing conventions.

---

# 📋 Router Management

Routers are stored in:

```text
routers.csv
```

Example:

```csv
ID,Name,IP
1,R1,192.168.1.1
2,R2,192.168.1.2
3,R3,192.168.1.3
```

The application provides a router management menu for:

* Show routers
* Add router
* Edit router
* Delete router

This removes the need to modify the PowerShell source code whenever a router needs to be added or changed.

---

# 🔐 Credentials

The application can operate in two modes.

### Temporary Credentials

The username and password are requested when needed and are not stored.

### Saved Credentials

If the user chooses to save the credentials, PowerShell's:

```powershell
ConvertFrom-SecureString
```

mechanism is used to store the encrypted password value in the local configuration.

> **Security Note:** This is intended for convenient use on a trusted Windows machine. It should not be treated as a portable password vault or enterprise credential-management system.

To remove saved credentials:

```text
Configuration
    └── Reset Saved Credentials
```

---

# 🔑 SSH Host Keys

The application does **not** require SSH host keys to be stored in `routers.csv`.

Plink uses the normal PuTTY SSH host-key mechanism.

Therefore, router information remains simple:

```csv
ID,Name,IP
1,R1,192.168.1.1
```

No additional host-key column is required.

---

# 📡 Tunnel Checking Process

When the user selects:

```text
Check Tunnel
```

the application:

### 1. Selects a router

```text
R1
192.168.1.1
```

### 2. Requests the tunnel number

The user can enter the Cisco tunnel interface number, for example:

```text
0
1
10
100
1000
```

### 3. Establishes an SSH session

Plink connects to the Cisco router.

### 4. Retrieves tunnel configuration

The application executes:

```cisco
show run int tu <tunnel-number>
```

### 5. Extracts tunnel addresses

It identifies:

```text
Tunnel Source
Tunnel Destination
```

### 6. Calculates gateways

The configured gateway offset is applied.

Example:

```text
Tunnel Source       : 10.10.10.10
Gateway Offset      : -1
Source Gateway      : 10.10.10.9
```

### 7. Performs Cisco-side ping

The application sends:

```cisco
ping <gateway> re 5
```

### 8. Displays the result

The result is presented in a formatted console interface.

---

# 🖥️ Example

```text
╔══════════════════════════════════════════════════════════════════════╗
║                       TUNNEL INFORMATION                            ║
╠══════════════════════════════════════════════════════════════════════╣

  Router Name          : R1
  Router IP            : 192.168.1.1
  Tunnel Number        : 100

  Tunnel Source        : 10.10.10.10
  Source Gateway       : 10.10.10.9

  Tunnel Destination   : 20.20.20.10
  Destination Gateway  : 20.20.20.9

  Gateway Offset       : -1

╚══════════════════════════════════════════════════════════════════════╝
```

---

# 🏢 NOC Use Case

This project was designed as a practical **Network Operations Center (NOC)** utility.

In environments with a large number of Cisco routers and GRE/IP tunnel configurations, manually performing the following tasks repeatedly can be time-consuming:

```text
SSH → Find Tunnel → Read Source → Read Destination
→ Calculate Gateway → Ping Source Gateway
→ Calculate Destination Gateway → Ping Destination Gateway
```

The tool automates this workflow into a single operation.

It can be useful for:

* Network monitoring
* Network troubleshooting
* Tunnel verification
* Connectivity testing
* Incident investigation
* NOC operations
* Cisco infrastructure support
* First-level network troubleshooting

---

# 🧠 Technical Concepts

This project demonstrates practical experience with:

* PowerShell
* Cisco IOS
* SSH
* Plink
* PuTTY
* IPv4 manipulation
* Regular expressions
* JSON configuration
* CSV data management
* Process management
* Standard input/output streams
* Persistent SSH sessions
* Network troubleshooting
* NOC automation

---

# 🔒 Security Considerations

This project is designed primarily for internal network administration and troubleshooting.

Recommended practices:

* Do not commit `config.json` containing saved credentials.
* Do not commit real production router IP addresses.
* Do not commit confidential infrastructure information.
* Use `.gitignore` for local configuration files.
* Use dedicated accounts with appropriate privileges.
* Follow your organization's credential-management policy.

Example `.gitignore`:

```gitignore
# Local configuration
config.json

# Router inventory
routers.csv

# PowerShell temporary files
*.tmp

# Logs
*.log
```

---

# 🛣️ Roadmap

Possible future improvements:

* [ ] Multi-router batch checking
* [ ] Parallel tunnel checks
* [ ] CSV result export
* [ ] HTML report generation
* [ ] Ping success/failure summary
* [ ] Packet-loss percentage extraction
* [ ] Response-time extraction
* [ ] Logging system
* [ ] Multiple tunnel checks per router
* [ ] Network topology visualization
* [ ] Python implementation
* [ ] GUI version
* [ ] Integration with monitoring platforms
* [ ] SNMP support
* [ ] API-based monitoring integration

---

# 🤝 Contributing

Contributions, bug reports and feature requests are welcome.

If you find an issue:

1. Open an Issue.
2. Describe the problem.
3. Include the PowerShell version.
4. Include relevant error messages.
5. Avoid posting passwords, private keys or production credentials.

Pull requests are welcome for improvements and new features.

---

# 📄 License

This project is provided for educational and network administration purposes.

Add an appropriate open-source license to the repository if you intend to accept and distribute contributions under a specific license.

---

# 👨‍💻 Author

**Ali Zarifi**

GitHub:

[github.com/alizarifi23](https://github.com/alizarifi23?utm_source=chatgpt.com)

Project:

[cisco-tunnel-gateway-checker](https://github.com/alizarifi23/cisco-tunnel-gateway-checker?utm_source=chatgpt.com)

---

## ⭐ Support

If you find this project useful for Cisco network troubleshooting or NOC automation, consider giving the repository a ⭐.

---

**Cisco Tunnel Gateway Checker — Automating repetitive Cisco tunnel troubleshooting tasks for NOC environments.**

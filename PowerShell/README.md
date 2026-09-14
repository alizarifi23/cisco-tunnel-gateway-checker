# Cisco Tunnel Gateway Checker — PowerShell Edition

A Windows PowerShell NOC utility for Cisco engineers to inspect tunnel source/destination addresses, calculate gateway IPs with a configurable offset, and test gateway reachability from the Cisco router.

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or newer
- PuTTY / `plink.exe`
- SSH connectivity to the Cisco router

## Installation

From the repository root:

```powershell
git clone https://github.com/alizarifi23/cisco-tunnel-gateway-checker.git
cd cisco-tunnel-gateway-checker
```

Run:

```powershell
.\PowerShell\Cisco-Tunnel-Gateway-Checker.ps1
```

If Windows blocks script execution, use your organization's approved execution-policy process. Do not weaken endpoint security just to run an untrusted script.

## Plink

The script automatically searches common PuTTY locations for `plink.exe`. If it cannot find Plink, choose the manual path option from the application.

## First Run

The application creates its local configuration and router inventory next to the PowerShell script:

```text
PowerShell/
├── Cisco-Tunnel-Gateway-Checker.ps1
├── config.json       # generated locally
└── routers.csv       # generated locally
```

`config.json` stores the selected gateway offset, ping settings, SSH settings, and optional locally encrypted PowerShell credential data.

## Router Inventory

Routers are stored in `PowerShell/routers.csv`:

```csv
ID,Name,IP
1,R1,192.168.1.1
2,R2,192.168.1.2
```

The application can add, edit, list, and delete routers from its menu.

## Tunnel Check

The workflow is:

1. Select a Cisco router.
2. Enter the tunnel number.
3. Connect through SSH/Plink.
4. Read `show run interface tunnel <number>`.
5. Detect tunnel source and destination IPv4 addresses.
6. Apply the configured gateway offset.
7. Run Cisco-side pings to the calculated gateways.
8. Display the tunnel and reachability results.

Example:

```text
Tunnel Source       : 10.10.10.10
Gateway Offset      : -1
Source Gateway      : 10.10.10.9
```

## Gateway Offset

Supported examples include:

```text
-2
-1
+1
+2
```

The offset is applied to both the tunnel source and tunnel destination IPv4 addresses.

## Credentials

Credentials may be entered for each session or saved locally using PowerShell's `ConvertFrom-SecureString` mechanism. Saved credentials are intended for a trusted Windows workstation, not as an enterprise password vault.

Never commit real credentials, production inventories, or generated local configuration files.

## Troubleshooting

### Plink not found

Install PuTTY and make sure `plink.exe` is available, or select its full path from the configuration menu.

### SSH connection fails

Verify:

- The router IP and SSH port are correct.
- The workstation can reach the router.
- SSH is enabled on the Cisco device.
- The supplied username/password is valid.
- The Cisco account has the required EXEC privileges.

### Tunnel addresses are not detected

Verify that the selected tunnel interface exists and contains `tunnel source` and `tunnel destination` IPv4 configuration.

## Security

Local files such as `config.json` and `routers.csv` can contain sensitive operational information. Keep them out of Git unless they contain sanitized example data.

## Related Editions

- [Repository](../README.md)
- [Python Edition](../Python/README.md)

© 2026 Cisco Tunnel Gateway Checker — Powered By Ali Zarifi

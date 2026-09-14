#!/usr/bin/env python3
# ============================================================
# Cisco Tunnel Gateway Checker - Python Edition
# Powered By Ali Zarifi
# ============================================================

import csv
import getpass
import ipaddress
import json
import os
import re
import socket
import sys
import time
from pathlib import Path

try:
    import paramiko
except ImportError:
    print("Missing dependency: paramiko")
    print("Install with: python -m pip install paramiko")
    sys.exit(1)

try:
    from cryptography.fernet import Fernet, InvalidToken
except ImportError:
    print("Missing dependency: cryptography")
    print("Install with: python -m pip install cryptography")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_PATH = SCRIPT_DIR / "config.json"
ROUTERS_PATH = SCRIPT_DIR / "routers.csv"
KEY_PATH = SCRIPT_DIR / ".credentials.key"

DEFAULT_CONFIG = {
    "Credentials": {
        "SaveCredentials": False,
        "Username": "",
        "Password": "",
        "EnablePassword": "",
    },
    "Network": {"GatewayOffset": ""},
    "Ping": {"Count": 5, "Timeout": 15},
    "Cisco": {"SSHPort": 22, "CommandTimeout": 15},
    "Files": {"Routers": "./routers.csv"},
}

# ----------------------------- UI -----------------------------

def clear():
    os.system("cls" if os.name == "nt" else "clear")


def header(title="CISCO TUNNEL GATEWAY CHECKER"):
    clear()
    print()
    print("╔══════════════════════════════════════════════════════════════════════╗")
    left = max(0, (70 - len(title)) // 2)
    right = max(0, 70 - len(title) - left)
    print("║" + " " * left + title + " " * right + "║")
    print("╠══════════════════════════════════════════════════════════════════════╣")


def pause():
    print()
    input("Press ENTER to continue")


def show_box(title, lines, title_color=None):
    print("╔══════════════════════════════════════════════════════════════════════╗")
    left = max(0, (70 - len(title)) // 2)
    right = max(0, 70 - len(title) - left)
    print("║" + " " * left + title + " " * right + "║")
    print("╠══════════════════════════════════════════════════════════════════════╣")
    if not lines:
        lines = [""]
    for line in lines:
        line = str(line) if line is not None else ""
        print("║ " + line[:68].ljust(68) + " ║")
    print("╚══════════════════════════════════════════════════════════════════════╝")

# -------------------------- config ----------------------------

def save_config(config):
    try:
        CONFIG_PATH.write_text(json.dumps(config, indent=4, ensure_ascii=False), encoding="utf-8")
        return True
    except Exception as exc:
        print(f"\nCould not save configuration.\n{exc}")
        return False


def deep_merge(default, current):
    changed = False
    for key, value in default.items():
        if key not in current:
            current[key] = json.loads(json.dumps(value))
            changed = True
        elif isinstance(value, dict) and isinstance(current[key], dict):
            if deep_merge(value, current[key]):
                changed = True
    return changed


def load_config():
    if not CONFIG_PATH.exists():
        config = json.loads(json.dumps(DEFAULT_CONFIG))
        save_config(config)
        return config
    try:
        config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        if not isinstance(config, dict):
            raise ValueError("Configuration root must be an object.")
        if deep_merge(DEFAULT_CONFIG, config):
            save_config(config)
        return config
    except Exception:
        print("\nconfig.json is invalid. Creating a new configuration...")
        config = json.loads(json.dumps(DEFAULT_CONFIG))
        save_config(config)
        return config

# -------------------- encrypted credentials ------------------

def get_key():
    if KEY_PATH.exists():
        return KEY_PATH.read_bytes()
    key = Fernet.generate_key()
    KEY_PATH.write_bytes(key)
    try:
        os.chmod(KEY_PATH, 0o600)
    except OSError:
        pass
    return key


def encrypt_secret(value):
    if not value:
        return ""
    return Fernet(get_key()).encrypt(value.encode()).decode()


def decrypt_secret(value):
    if not value:
        return ""
    try:
        return Fernet(get_key()).decrypt(value.encode()).decode()
    except (InvalidToken, ValueError, TypeError):
        return ""


def reset_credentials(config):
    config["Credentials"] = {
        "SaveCredentials": False,
        "Username": "",
        "Password": "",
        "EnablePassword": "",
    }
    save_config(config)


def get_credentials(config):
    saved = config["Credentials"]
    if saved.get("SaveCredentials") and saved.get("Username") and saved.get("Password"):
        password = decrypt_secret(saved["Password"])
        enable = decrypt_secret(saved.get("EnablePassword", ""))
        if password:
            return {"Username": saved["Username"], "Password": password, "EnablePassword": enable}
        print("\nSaved credentials could not be loaded. Please enter them again.")

    header("CREDENTIALS")
    username = input("\nSSH Username: ").strip()
    password = getpass.getpass("SSH Password: ")
    print("\nEnable password is optional.")
    print("If a router does not ask for it, it will not be used.\n")
    enable = getpass.getpass("Enable Password (leave empty if not required): ")

    save = input("\nSave credentials for future use? [Y/N]: ").strip().lower()
    if save == "y":
        saved["SaveCredentials"] = True
        saved["Username"] = username
        saved["Password"] = encrypt_secret(password)
        saved["EnablePassword"] = encrypt_secret(enable)
        save_config(config)
        print("\nCredentials saved successfully.")
    else:
        reset_credentials(config)

    return {"Username": username, "Password": password, "EnablePassword": enable}

# --------------------------- routers --------------------------

def ensure_router_file(config):
    path_value = config["Files"].get("Routers") or "./routers.csv"
    path = Path(path_value)
    if not path.is_absolute():
        path = SCRIPT_DIR / path
    if not path.exists():
        with path.open("w", newline="", encoding="utf-8-sig") as f:
            csv.DictWriter(f, fieldnames=["ID", "Name", "IP"]).writeheader()
    return path


def get_routers(config):
    path = ensure_router_file(config)
    try:
        with path.open("r", newline="", encoding="utf-8-sig") as f:
            return list(csv.DictReader(f))
    except Exception as exc:
        print(f"\nCould not read routers.csv.\n{exc}")
        return []


def save_routers(config, routers):
    path = ensure_router_file(config)
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=["ID", "Name", "IP"])
        writer.writeheader()
        writer.writerows(routers)


def show_router_list(config):
    routers = get_routers(config)
    print()
    print("╔══════╦════════════════════════════════╦══════════════════════════════╗")
    print("║ ID   ║ Name                           ║ IP                           ║")
    print("╠══════╬════════════════════════════════╬══════════════════════════════╣")
    for r in routers:
        rid = str(r.get("ID", ""))[:4].ljust(4)
        name = str(r.get("Name", ""))[:30].ljust(30)
        ip = str(r.get("IP", ""))[:28].ljust(28)
        print(f"║ {rid} ║ {name} ║ {ip} ║")
    if not routers:
        print("║      ║ No routers configured.        ║                              ║")
    print("╚══════╩════════════════════════════════╩══════════════════════════════╝")


def valid_ip(value):
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return False


def add_router(config):
    header("ADD ROUTER")
    routers = get_routers(config)
    name = input("\nRouter Name: ").strip()
    if not name:
        print("\nRouter name cannot be empty.")
        pause(); return
    ip = input("Router IP: ").strip()
    if not valid_ip(ip):
        print("\nInvalid IP address.")
        pause(); return
    ids = []
    for r in routers:
        try: ids.append(int(r.get("ID", 0)))
        except (ValueError, TypeError): pass
    routers.append({"ID": str(max(ids, default=0) + 1), "Name": name, "IP": ip})
    save_routers(config, routers)
    print("\nRouter added successfully.")
    pause()


def edit_router(config):
    header("EDIT ROUTER")
    routers = get_routers(config)
    show_router_list(config)
    rid = input("\nEnter Router ID to edit: ").strip()
    router = next((r for r in routers if str(r.get("ID")) == rid), None)
    if not router:
        print("\nRouter not found."); pause(); return
    name = input(f"New Name [{router.get('Name', '')}]: ").strip() or router.get("Name", "")
    ip = input(f"New IP [{router.get('IP', '')}]: ").strip() or router.get("IP", "")
    if not valid_ip(ip):
        print("\nInvalid IP address."); pause(); return
    router["Name"], router["IP"] = name, ip
    save_routers(config, routers)
    print("\nRouter updated successfully.")
    pause()


def remove_router(config):
    header("DELETE ROUTER")
    routers = get_routers(config)
    show_router_list(config)
    rid = input("\nEnter Router ID to delete: ").strip()
    router = next((r for r in routers if str(r.get("ID")) == rid), None)
    if not router:
        print("\nRouter not found."); pause(); return
    if input(f"Delete {router.get('Name', '')}? [Y/N]: ").strip().lower() != "y":
        print("\nOperation cancelled."); pause(); return
    save_routers(config, [r for r in routers if str(r.get("ID")) != rid])
    print("\nRouter deleted successfully.")
    pause()


def router_management(config):
    while True:
        header("ROUTER MANAGEMENT")
        print("║  [1] Show Routers                                                    ║")
        print("║  [2] Add Router                                                      ║")
        print("║  [3] Edit Router                                                     ║")
        print("║  [4] Delete Router                                                   ║")
        print("║  [5] Back                                                            ║")
        print("╚══════════════════════════════════════════════════════════════════════╝")
        choice = input("\nSelect option: ").strip()
        if choice == "1": clear(); show_router_list(config); pause()
        elif choice == "2": add_router(config)
        elif choice == "3": edit_router(config)
        elif choice == "4": remove_router(config)
        elif choice == "5": return
        else: print("\nInvalid option."); time.sleep(1)


def select_router(config):
    routers = get_routers(config)
    if not routers:
        print("\nNo routers found."); pause(); return None
    clear(); show_router_list(config)
    rid = input("\nEnter Router ID: ").strip()
    router = next((r for r in routers if str(r.get("ID")) == rid), None)
    if not router:
        print("\nInvalid router selection."); pause(); return None
    return router

# ------------------------ networking --------------------------

def gateway_offset(config):
    value = str(config["Network"].get("GatewayOffset", ""))
    if re.fullmatch(r"[+-]?\d+", value):
        return int(value)
    while True:
        header("GATEWAY OFFSET")
        print("\nExamples:")
        print("  -1 = one IP before Tunnel IP")
        print("  +1 = one IP after Tunnel IP")
        print("  -2 = two IPs before Tunnel IP")
        print("  +2 = two IPs after Tunnel IP\n")
        value = input("Gateway Offset: ").strip()
        if re.fullmatch(r"[+-]?\d+", value):
            config["Network"]["GatewayOffset"] = int(value)
            save_config(config)
            return int(value)
        print("\nInvalid offset.")


def add_ipv4_offset(address, offset):
    try:
        ip = ipaddress.IPv4Address(address)
        value = int(ip) + int(offset)
        if not 0 <= value <= 0xFFFFFFFF:
            return None
        return str(ipaddress.IPv4Address(value))
    except Exception:
        return None

# -------------------------- Cisco SSH -------------------------

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
PROMPT_RE = re.compile(r"^[^\s]+[>#]\s*$")


def clean_output(text):
    return ANSI_RE.sub("", text or "").replace("\x00", "")


def prompt_from(text):
    prompt = None
    for line in clean_output(text).splitlines():
        line = line.strip()
        if PROMPT_RE.fullmatch(line):
            prompt = line
    return prompt


class CiscoSession:
    def __init__(self, client, shell, timeout=15):
        self.client = client
        self.shell = shell
        self.timeout = timeout
        self.shell.settimeout(0.2)

    def close(self):
        try: self.shell.close()
        except Exception: pass
        try: self.client.close()
        except Exception: pass

    def read_available(self):
        chunks = []
        while True:
            try:
                if not self.shell.recv_ready(): break
                data = self.shell.recv(65535)
                if not data: break
                chunks.append(data.decode("utf-8", errors="replace"))
            except (socket.timeout, TimeoutError):
                break
            except Exception:
                break
        return clean_output("".join(chunks))

    def clear(self):
        self.read_available()

    def send(self, command):
        self.shell.send(command.rstrip("\r\n") + "\n")

    def read_until_prompt(self, timeout=None, password=False):
        timeout = timeout or self.timeout
        output = ""
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            chunk = self.read_available()
            if chunk:
                output += chunk
                if password and re.search(r"(?i)password\s*:", output):
                    return output
                if prompt_from(output):
                    return output
            time.sleep(0.05)
        output += self.read_available()
        return output

    def enable(self, enable_password=""):
        self.clear(); self.send("")
        output = self.read_until_prompt(5)
        prompt = prompt_from(output)
        if not prompt:
            raise RuntimeError("No Cisco prompt was received after SSH connection.")
        if prompt.endswith("#"):
            return
        if not prompt.endswith(">"):
            raise RuntimeError(f"Could not determine Cisco EXEC mode. Last prompt: {prompt}")

        self.clear(); self.send("enable")
        output = self.read_until_prompt(5, password=True)
        if re.search(r"(?i)(bad secrets|% ?bad|invalid password|authentication failed|incorrect password)", output):
            raise RuntimeError("Enable password was rejected by the Cisco router.")
        if re.search(r"(?i)password\s*:", output):
            if not enable_password:
                enable_password = getpass.getpass("Enable Password: ")
            if not enable_password:
                raise RuntimeError("Cisco requested an enable password, but no enable password was provided.")
            self.send(enable_password)
            output = self.read_until_prompt(5)
            if re.search(r"(?i)(bad secrets|% ?bad|invalid password|authentication failed|incorrect password)", output):
                raise RuntimeError("Enable password was rejected by the Cisco router.")
        prompt = prompt_from(output)
        if not prompt or not prompt.endswith("#"):
            raise RuntimeError(f"Could not confirm Cisco privileged EXEC mode. Last prompt: {prompt}")

    def command(self, command, timeout=None):
        self.clear(); self.send(command)
        return self.read_until_prompt(timeout or self.timeout)


def connect_cisco(router_ip, port, username, password, timeout=15):
    header("CONNECTING")
    print(f"\nRouter : {router_ip}")
    print(f"Port   : {port}\n")
    print("Establishing SSH connection...")
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(
            hostname=router_ip, port=int(port), username=username, password=password,
            timeout=timeout, banner_timeout=timeout, auth_timeout=timeout,
            look_for_keys=False, allow_agent=False,
        )
        shell = client.invoke_shell(width=200, height=1000)
        session = CiscoSession(client, shell, timeout)
        time.sleep(1.2)
        initial = session.read_available()
        if initial:
            print(initial)
        return session
    except (paramiko.AuthenticationException, paramiko.SSHException, socket.error) as exc:
        client.close()
        raise RuntimeError(f"SSH connection failed. {exc}") from exc


def get_tunnel_information(session, tunnel, enable_password):
    session.enable(enable_password)
    output = session.command(f"show run interface tunnel {tunnel}", 10)
    if not output.strip():
        raise RuntimeError("No response received from Cisco router.")
    source = re.search(r"(?im)^\s*tunnel\s+source\s+(\d+\.\d+\.\d+\.\d+)", output)
    destination = re.search(r"(?im)^\s*tunnel\s+destination\s+(\d+\.\d+\.\d+\.\d+)", output)
    if not source: raise RuntimeError("Could not find Tunnel Source IP.")
    if not destination: raise RuntimeError("Could not find Tunnel Destination IP.")
    return source.group(1), destination.group(1), output


def cisco_ping(session, address, count, timeout):
    return session.command(f"ping {address} repeat {count}", timeout)

# --------------------------- tunnel ---------------------------

def show_tunnel(router, tunnel, source, destination, source_gw, destination_gw, offset):
    show_box("TUNNEL INFORMATION", [
        f"Router Name         : {router['Name']}",
        f"Router IP           : {router['IP']}",
        f"Tunnel Number       : {tunnel}",
        "",
        f"Tunnel Source       : {source}",
        f"Source Gateway      : {source_gw}",
        "",
        f"Tunnel Destination  : {destination}",
        f"Destination Gateway : {destination_gw}",
        "",
        f"Gateway Offset      : {offset}",
    ])


def show_ping(title, address, output):
    lines = [f"Target : {address}", ""]
    lines += [line.strip()[:68] for line in clean_output(output).splitlines() if line.strip()]
    show_box(title, lines or ["No output received."])


def start_tunnel_check(config, credentials):
    router = select_router(config)
    if not router: return
    header("TUNNEL CHECK")
    print(f"\nSelected Router\n\nName : {router['Name']}\nIP   : {router['IP']}\n")
    while True:
        tunnel = input("Tunnel Number: ").strip()
        if tunnel.isdigit(): break
        print("\nInvalid Tunnel Number! Please enter a valid number.\n")

    session = None
    try:
        session = connect_cisco(
            router["IP"], config["Cisco"]["SSHPort"], credentials["Username"],
            credentials["Password"], config["Cisco"]["CommandTimeout"]
        )
        header("FETCHING TUNNEL INFORMATION")
        source, destination, _ = get_tunnel_information(session, tunnel, credentials.get("EnablePassword", ""))
        offset = int(config["Network"]["GatewayOffset"])
        source_gw = add_ipv4_offset(source, offset)
        destination_gw = add_ipv4_offset(destination, offset)
        if not source_gw: raise RuntimeError("Could not calculate Source Gateway.")
        if not destination_gw: raise RuntimeError("Could not calculate Destination Gateway.")
        clear()
        show_tunnel(router, tunnel, source, destination, source_gw, destination_gw, offset)
        source_ping = cisco_ping(session, source_gw, int(config["Ping"]["Count"]), int(config["Ping"]["Timeout"]))
        show_ping("SOURCE GATEWAY RESULT", source_gw, source_ping)
        destination_ping = cisco_ping(session, destination_gw, int(config["Ping"]["Count"]), int(config["Ping"]["Timeout"]))
        show_ping("DESTINATION GATEWAY RESULT", destination_gw, destination_ping)
        show_box("CHECK COMPLETE", [
            f"Router : {router['Name']}", f"Tunnel : {tunnel}", "",
            f"Source Gateway      : {source_gw}", f"Destination Gateway : {destination_gw}",
        ])
        pause()
    except Exception as exc:
        show_box("ERROR", [str(exc), "", f"Router : {router['Name']}", f"Tunnel : {tunnel}"])
        pause()
    finally:
        if session:
            try: session.send("exit")
            except Exception: pass
            session.close()

# ------------------------ configuration -----------------------

def configuration_menu(config):
    while True:
        header("CONFIGURATION")
        print("║  [1] Credentials                                                     ║")
        print("║  [2] Gateway Offset                                                  ║")
        print("║  [3] Ping Settings                                                   ║")
        print("║  [4] Cisco SSH Settings                                              ║")
        print("║  [5] Show Current Configuration                                      ║")
        print("║  [6] Reset Saved Credentials                                         ║")
        print("║  [7] Back                                                            ║")
        print("╚══════════════════════════════════════════════════════════════════════╝")
        choice = input("\nSelect option: ").strip()
        if choice == "1":
            reset_credentials(config); get_credentials(config)
        elif choice == "2":
            current = config["Network"]["GatewayOffset"]
            value = input(f"\nNew Gateway Offset [{current}]: ").strip() or str(current)
            if re.fullmatch(r"[+-]?\d+", value):
                config["Network"]["GatewayOffset"] = int(value); save_config(config); print("\nGateway Offset updated.")
            else: print("\nInvalid offset.")
            pause()
        elif choice == "3":
            count = input(f"\nPing Count [{config['Ping']['Count']}]: ").strip() or str(config['Ping']['Count'])
            timeout = input(f"Ping Timeout [{config['Ping']['Timeout']}]: ").strip() or str(config['Ping']['Timeout'])
            if count.isdigit() and timeout.isdigit() and int(count) > 0 and int(timeout) > 0:
                config["Ping"]["Count"], config["Ping"]["Timeout"] = int(count), int(timeout); save_config(config); print("\nPing settings updated.")
            else: print("\nInvalid value.")
            pause()
        elif choice == "4":
            port = input(f"\nSSH Port [{config['Cisco']['SSHPort']}]: ").strip() or str(config['Cisco']['SSHPort'])
            timeout = input(f"Command Timeout [{config['Cisco']['CommandTimeout']}]: ").strip() or str(config['Cisco']['CommandTimeout'])
            if port.isdigit() and timeout.isdigit() and int(port) > 0 and int(timeout) > 0:
                config["Cisco"]["SSHPort"], config["Cisco"]["CommandTimeout"] = int(port), int(timeout); save_config(config); print("\nCisco SSH settings updated.")
            else: print("\nInvalid value.")
            pause()
        elif choice == "5":
            header("CURRENT CONFIGURATION")
            print(f"\nCredentials:\n  Save Credentials : {config['Credentials']['SaveCredentials']}\n  Username         : {config['Credentials']['Username']}\n  SSH Password     : ********\n  Enable Password  : ********")
            print(f"\nNetwork:\n  Gateway Offset   : {config['Network']['GatewayOffset']}")
            print(f"\nPing:\n  Count            : {config['Ping']['Count']}\n  Timeout          : {config['Ping']['Timeout']}")
            print(f"\nCisco:\n  SSH Port         : {config['Cisco']['SSHPort']}\n  Command Timeout  : {config['Cisco']['CommandTimeout']}")
            print(f"\nFiles:\n  Routers          : {config['Files']['Routers']}\n  Credentials Key  : {KEY_PATH}")
            pause()
        elif choice == "6":
            reset_credentials(config); print("\nSaved credentials have been removed."); pause()
        elif choice == "7": return
        else: print("\nInvalid option."); time.sleep(1)

# --------------------------- main -----------------------------

def main_menu(config, credentials):
    while True:
        header()
        print("║  [1] Check Tunnel                                                    ║")
        print("║  [2] Router Management                                               ║")
        print("║  [3] Configuration                                                   ║")
        print("║  [4] Exit                                                            ║")
        print("╚══════════════════════════════════════════════════════════════════════╝")
        print(f"\n  SSH      : Paramiko\n  Offset   : {config['Network']['GatewayOffset']}\n  Routers  : {len(get_routers(config))}\n")
        choice = input("Select option: ").strip()
        if choice == "1": start_tunnel_check(config, credentials)
        elif choice == "2": router_management(config)
        elif choice == "3":
            configuration_menu(config)
            credentials = get_credentials(config)
        elif choice == "4":
            clear(); show_box("THANK YOU", ["Cisco Tunnel Gateway Checker", "", "Powered By Ali Zarifi"]); input("\nPress Enter To Exit..."); return
        else: print("\nInvalid option."); time.sleep(1)


def main():
    try:
        config = load_config()
        ensure_router_file(config)
        gateway_offset(config)
        credentials = get_credentials(config)
        main_menu(config, credentials)
    except KeyboardInterrupt:
        print("\n\nProgram interrupted by user.")
    except Exception as exc:
        clear(); show_box("FATAL ERROR", [str(exc), "", "Check the configuration and try again."]); pause()


if __name__ == "__main__":
    main()

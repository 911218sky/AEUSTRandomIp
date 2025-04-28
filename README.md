# 🚀 Random IP

Automatically rotates your IPv4 address on the first active physical interface at a configurable interval.

---

## ✨ Features

- 🛡️ Runs with Administrator/root privileges  
- 🔍 Selects the first active **physical** network adapter (excludes VMs)  
- 🎲 Picks a random unused IP in your subnet (up to 50 attempts)  
- ♻️ Flushes old IPv4 addresses and default routes, then applies new IP, gateway, and DNS  
- 🔄 Repeats every _Interval_ seconds (default: 60)

---

## 🖥️ Requirements

- **Windows**: PowerShell 5.1+ with Administrator privileges  
- **Linux**: Bash with `ip`, `ping`, `curl`, and root/sudo rights

---

## ⚙️ Parameters

| Name           | Type        | Default                         | Description                                    |
| -------------- | ----------- | ------------------------------- | ---------------------------------------------- |
| `Prefix`       | `string`    | `120.96.54`                     | Fixed leading octets (e.g. '192.168', '10.0') |
| `Interval`     | `int`       | `60`                            | Seconds between IP rotations                   |
| `PrefixLength` | `int`       | `24`                            | Subnet mask length (e.g. 24 for 255.255.255.0) |
| `Gateway`      | `string`    | `120.96.54.254`                 | Default gateway IP                             |
| `DnsServers`   | `string[]`  | `120.96.35.1,120.96.36.1`       | One or more DNS server IPs                     |

---

## 📝 Examples

### 🪟 Windows

Fetch and execute with optional parameters:

```powershell
$scriptContent = Invoke-RestMethod 'https://raw.githubusercontent.com/911218sky/AEUSTRandomIp/refs/heads/main/start.ps1'
$scriptBlock = [ScriptBlock]::Create($scriptContent)
& $scriptBlock -Interval 30 -Prefix '192.168.1' -PrefixLength 24 -Gateway '192.168.1.1' -DnsServers '8.8.8.8','8.8.4.4'
```

Or the shorter alias form:

```powershell
irm 'https://raw.githubusercontent.com/911218sky/AEUSTRandomIp/refs/heads/main/start.ps1' | iex
```

---

### 🐧 Linux

Use `curl` and pipe into `bash`; flags after `--` are passed to `start.sh`:

```bash
curl -sSL https://raw.githubusercontent.com/911218sky/AEUSTRandomIp/refs/heads/main/start.sh | \
    INTERVAL=30 \
    PREFIX="192.168.1" \
    PREFIX_LENGTH=24 \
    GATEWAY="192.168.1.1" \
    DNS_SERVERS="8.8.8.8 8.8.4.4" \
    bash
```

Or simply (defaults):

```bash
curl -sSL https://raw.githubusercontent.com/911218sky/AEUSTRandomIp/refs/heads/main/start.sh | sudo bash
```

**Flags:**

- `-i`: interval (seconds)  
- `-p`: prefix length  
- `-g`: gateway IP  
- `-d`: comma-separated DNS servers  

---

## 🛠️ Troubleshooting

- **Windows**: Ensure PowerShell is run as Administrator.  
- **Linux**: Run under root or with `sudo`, and verify your interface state.  
- Check script output for adapter selection or IP assignment errors.
# 🔄 Random IP Rotator 

**Automatically rotate IPv4 addresses** on your physical network adapter with configurable intervals & seamless restoration of original settings.

![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1+-blue?logo=powershell)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-lightgrey)

## 🚀 Key Features

### 🔄 IP Management
- **Random IP Generation**: Creates unused IPs within specified subnet (50-attempt collision check)
- **Auto-Restoration**: Perfectly restores original network config on exit (Ctrl+C)
- **Real-Time Countdown**: Progress bar shows time until next rotation

### 🛡️ Safety & Compatibility
- **Physical Adapter Detection**: Automatically skips virtual interfaces (Hyper-V/Tailscale)
- **Admin Privilege Handling**: Self-elevates to Administrator/Root when needed
- **Cross-Platform**: Works on both Windows (PowerShell) and Linux (Bash)

## ⚙️ Configuration Options

| Parameter              | Default Value       | Description                          |
|-----------------------|---------------------|--------------------------------------|
| `-Prefix`             | `120.96.54`         | Fixed IP segments (1-3 octets)       |
| `-Interval`           | `600` (10 mins)     | Rotation frequency in seconds        |
| `-PrefixLength`       | `24` (/24)          | Subnet mask length                   |
| `-Gateway`            | `120.96.54.254`     | Default gateway IP                   |
| `-DnsServers`         | `120.96.35.1, ...`  | Comma-separated DNS servers          |
| `-TestDnsServers`     | `8.8.8.8`           | IPs to test connectivity after change |
| `-ConnectivityWaitTime` | `10`              | Seconds to wait before testing        |

## 📥 Installation & Usage

### Windows (PowerShell)
```powershell
$scriptContent = Invoke-RestMethod 'https://raw.githubusercontent.com/911218sky/AEUSTRandomIp/refs/heads/main/start.ps1'
$scriptBlock = [ScriptBlock]::Create($scriptContent)
& $scriptBlock -Interval 1200 -Prefix '192.168.1' -PrefixLength 24 -Gateway '192.168.1.1' -DnsServers '8.8.8.8','8.8.4.4' -TestDnsServers '1.1.1.1','8.8.8.8' -ConnectivityWaitTime 15
```

Or simply (defaults):

```powershell
irm 'https://raw.githubusercontent.com/911218sky/AEUSTRandomIp/refs/heads/main/start.ps1' | iex
```

### Linux (Bash)
```bash
curl -sSL https://raw.githubusercontent.com/911218sky/AEUSTRandomIp/main/start.sh | sudo bash -s -- --interval 1200 --prefix "192.168.1" --prefix-length 24 --gateway "192.168.1.1" --dns-servers "8.8.8.8,8.8.4.4" --test-dns "1.1.1.1,8.8.8.8" --wait-time 15
```

Or simply (defaults):

```bash
curl -sSL https://raw.githubusercontent.com/911218sky/AEUSTRandomIp/refs/heads/main/start.sh | sudo bash
```
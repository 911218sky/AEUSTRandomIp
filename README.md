# AEUST Random Ip
- Runs with elevated (Administrator) privileges.  
- Automatically selects the first active **physical** network adapter (excludes Hyper-V, Tailscale, etc.).  
- Picks a random unused IP on your specified subnet (up to 50 attempts).  
- Clears existing IPv4 addresses and default routes, then assigns the new static IP, gateway, and DNS servers.  
- Repeats the switch at a user-defined interval (default: 60 seconds).

## Requirements

- Windows 10 / 11 or Windows Server  
- PowerShell 5.1 or newer  
- Administrator privileges  

## Parameters

| Name          | Type        | Default                         | Description                                          |
| ------------- | ----------- | ------------------------------- | ---------------------------------------------------- |
| `Interval`    | `[int]`     | `60`                            | Time (seconds) between IP rotations                  |
| `PrefixLength`| `[int]`     | `24`                            | Subnet prefix length (e.g. 24 for 255.255.255.0)     |
| `Gateway`     | `[string]`  | `'120.96.54.254'`               | Default gateway IP                                   |
| `DnsServers`  | `[string[]]`| `@('120.96.35.1','120.96.36.1')`| One or more DNS server IPs                           |

## Examples

1. **Every 30 seconds**, use gateway `192.168.1.1` and Google DNS:

   ```
   .\start.ps1 -Interval 30 -Gateway '192.168.1.1' -DnsServers '8.8.8.8','8.8.4.4'
   ```

2. **Remote one-liner** via RAW URL:

   ```
   irm 'https://raw.githubusercontent.com/911218sky/AEUSTRandomIp/refs/heads/main/start.ps1' | iex
   ```

## Troubleshooting

- Make sure you run PowerShell **as Administrator**.  
- Confirm you have an active **physical** network adapter up and connected.  
- If nothing happens, check the script output for errors regarding IP assignment or adapter selection.

## License

This project is licensed under the [MIT License](LICENSE).  
Feel free to fork, customize, and contribute back!
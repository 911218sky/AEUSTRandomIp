#!/bin/bash
#
# IP Rotator - Randomly switches the local network adapter IPv4 address
# at a configurable interval, saving and restoring original settings on exit,
# and displays a real-time countdown until the next switch.

# Default values
PREFIX="120.96.54"
INTERVAL=1200
PREFIX_LENGTH=24
GATEWAY="120.96.54.254"
DNS_SERVERS=("120.96.35.1" "120.96.36.1")

# Function to display usage
show_help() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -p, --prefix PREFIX        Fixed leading octets of IP (e.g. '192.168')"
  echo "                              Default: $PREFIX"
  echo "  -i, --interval SECONDS     Seconds between IP rotations"
  echo "                              Default: $INTERVAL"
  echo "  -l, --prefix-length LENGTH Subnet prefix length (e.g. 24 for 255.255.255.0)"
  echo "                              Default: $PREFIX_LENGTH"
  echo "  -g, --gateway IP           Default gateway IP address"
  echo "                              Default: $GATEWAY"
  echo "  -d, --dns-servers IPS      Comma-separated DNS server IPs"
  echo "                              Default: ${DNS_SERVERS[*]}"
  echo "  -h, --help                 Show this help message"
}

# Parse command line arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p|--prefix) PREFIX="$2"; shift 2 ;;
    -i|--interval) INTERVAL="$2"; shift 2 ;;
    -l|--prefix-length) PREFIX_LENGTH="$2"; shift 2 ;;
    -g|--gateway) GATEWAY="$2"; shift 2 ;;
    -d|--dns-servers) IFS=',' read -r -a DNS_SERVERS <<< "$2"; shift 2 ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
  esac
done

# Validate prefix format (1-3 octets)
if ! [[ "$PREFIX" =~ ^([0-9]{1,3}\.){0,2}[0-9]{1,3}$ ]]; then
  echo "Error: Prefix must consist of 1-3 octets separated by dots." >&2
  exit 1
fi

# Count number of octets in prefix
IFS='.' read -r -a FIXED_OCTETS <<< "$PREFIX"
DYNAMIC_COUNT=$((4 - ${#FIXED_OCTETS[@]}))

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "This script requires root privileges." >&2
  echo "Please run with sudo or as root." >&2
  exit 1
fi

# Detect OS
OS_TYPE=$(uname -s)
echo "Detected OS: $OS_TYPE"

# Select active network interface based on OS
case "$OS_TYPE" in
  Linux)
    INTERFACE=$(ip -o link show | grep 'state UP' | grep -v 'virbr\|docker\|veth\|lo\|tun\|tailscale' | head -n1 | awk -F': ' '{print $2}')
    
    # Detect network management tool
    if command -v nmcli >/dev/null 2>&1; then
      NETWORK_TOOL="NetworkManager"
    else
      NETWORK_TOOL="legacy"
    fi
    ;;
    
  Darwin)  # macOS
    INTERFACE=$(networksetup -listallhardwareports | grep -A1 "Wi-Fi\|Ethernet" | grep "Device" | head -1 | awk '{print $2}')
    NETWORK_TOOL="networksetup"
    SERVICE=$(networksetup -listallhardwareports | grep -B1 "Device: $INTERFACE" | head -1 | cut -d: -f2 | tr -d ' ')
    ;;
    
  *)
    echo "Unsupported operating system: $OS_TYPE" >&2
    exit 1
    ;;
esac

echo "Using interface: $INTERFACE"
echo "Using network tool: $NETWORK_TOOL"

# Save original network settings
save_original_settings() {
  case "$OS_TYPE" in
    Linux)
      if [ "$NETWORK_TOOL" = "NetworkManager" ]; then
        CONNECTION=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$INTERFACE" | cut -d: -f1)
        echo "Saving NetworkManager connection: $CONNECTION"
      fi
      
      ORIG_IP=$(ip -4 addr show dev "$INTERFACE" | grep 'inet ' | awk '{print $2}')
      ORIG_GATEWAY=$(ip route | grep default | grep "$INTERFACE" | awk '{print $3}')
      
      # Backup DNS configuration
      cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null
      ORIG_DNS=$(grep nameserver /etc/resolv.conf | awk '{print $2}')
      ;;
      
    Darwin)
      ORIG_IP=$(ifconfig "$INTERFACE" | grep 'inet ' | awk '{print $2}')
      ORIG_NETMASK=$(ifconfig "$INTERFACE" | grep 'inet ' | awk '{print $4}')
      ORIG_GATEWAY=$(route -n get default | grep gateway | awk '{print $2}')
      ORIG_DNS=$(networksetup -getdnsservers "$SERVICE")
      ;;
  esac
}

# Save original settings
save_original_settings

echo "Original settings:"
echo "  Interface: $INTERFACE"
echo "  IP: $ORIG_IP"
echo "  Gateway: $ORIG_GATEWAY"
echo "  DNS: ${ORIG_DNS[*]}"

# Function to restore original network settings
restore_original() {
  echo -e "\nRestoring original network settings..."

  case "$OS_TYPE" in
    Linux)
      if [ "$NETWORK_TOOL" = "NetworkManager" ] && [ -n "$CONNECTION" ]; then
        echo "  Reconnecting to original NetworkManager connection"
        nmcli connection up "$CONNECTION"
      else
        # Flush current IP configuration
        ip addr flush dev "$INTERFACE"
        
        # Restore original IP and route
        echo "  Restoring IP $ORIG_IP"
        ip addr add "$ORIG_IP" dev "$INTERFACE"
        ip route add default via "$ORIG_GATEWAY" dev "$INTERFACE"
      fi
      
      # Restore DNS
      if [ -f /etc/resolv.conf.bak ]; then
        echo "  Restoring DNS configuration"
        mv /etc/resolv.conf.bak /etc/resolv.conf
      fi
      ;;
      
    Darwin)
      echo "  Restoring IP configuration for $SERVICE"
      networksetup -setmanual "$SERVICE" "$ORIG_IP" "$ORIG_NETMASK" "$ORIG_GATEWAY"
      
      echo "  Restoring DNS configuration"
      if [[ "$ORIG_DNS" == *"There aren't any DNS Servers"* ]]; then
        networksetup -setdnsservers "$SERVICE" "Empty"
      else
        networksetup -setdnsservers "$SERVICE" "${ORIG_DNS[@]}"
      fi
      ;;
  esac
  
  echo "✅ Original settings restored."
}

# Trap CTRL+C and EXIT to restore settings
trap restore_original INT TERM EXIT

# Function to set network configuration
set_network_config() {
  local ip="$1"
  
  case "$OS_TYPE" in
    Linux)
      if [ "$NETWORK_TOOL" = "NetworkManager" ]; then
        # Create a temporary connection
        echo "Creating temporary NetworkManager connection..."
        nmcli connection delete "IP-Rotator" 2>/dev/null || true
        nmcli connection add type ethernet con-name "IP-Rotator" ifname "$INTERFACE" \
          ipv4.method manual ipv4.addresses "$ip/$PREFIX_LENGTH" \
          ipv4.gateway "$GATEWAY" ipv4.dns "$(IFS=,; echo "${DNS_SERVERS[*]}")"
        
        # Activate the new connection
        nmcli connection up "IP-Rotator"
      else
        # Traditional IP configuration
        echo "Setting new IP: $ip/$PREFIX_LENGTH"
        ip addr flush dev "$INTERFACE"
        ip addr add "$ip/$PREFIX_LENGTH" dev "$INTERFACE"
        
        echo "Setting default gateway: $GATEWAY"
        ip route add default via "$GATEWAY" dev "$INTERFACE"
        
        # Set DNS servers
        echo "Setting DNS servers: ${DNS_SERVERS[*]}"
        echo -n > /etc/resolv.conf
        for dns in "${DNS_SERVERS[@]}"; do
          echo "nameserver $dns" >> /etc/resolv.conf
        done
      fi
      ;;
      
    Darwin)
      # Convert CIDR prefix length to netmask
      netmask=""
      case $PREFIX_LENGTH in
        8) netmask="255.0.0.0" ;;
        16) netmask="255.255.0.0" ;;
        24) netmask="255.255.255.0" ;;
        *) echo "Converting prefix length $PREFIX_LENGTH to netmask"; netmask="255.255.255.0" ;;
      esac
      
      echo "Setting new IP: $ip/$PREFIX_LENGTH ($netmask)"
      networksetup -setmanual "$SERVICE" "$ip" "$netmask" "$GATEWAY"
      
      echo "Setting DNS servers: ${DNS_SERVERS[*]}"
      networksetup -setdnsservers "$SERVICE" "${DNS_SERVERS[@]}"
      ;;
  esac
}

# Main rotation loop
while true; do
  # Generate a candidate IP
  attempt=0
  while true; do
    ((attempt++))
    if [ "$attempt" -gt 50 ]; then
      echo "Error: Unable to find a free IP after 50 attempts." >&2
      exit 1
    fi
    
    # Generate random octets
    random_octets=""
    for ((i=1; i<=DYNAMIC_COUNT; i++)); do
      random_octet=$((RANDOM % 206 + 50))  # 50-255 range
      random_octets="$random_octets.$random_octet"
    done
    
    # Remove leading dot if present
    random_octets=${random_octets#.}
    
    # Combine prefix with random octets
    if [ "$DYNAMIC_COUNT" -eq 1 ]; then
      new_ip="$PREFIX.$random_octets"
    else
      new_ip="$PREFIX$random_octets"
    fi
    
    echo "Checking $new_ip..."
    if ! ping -c 1 -W 1 "$new_ip" &>/dev/null; then
      # IP is not in use, we can use it
      break
    fi
  done
  
  # Apply new network configuration
  set_network_config "$new_ip"
  echo "✅ Switched to $new_ip"
  
  # Countdown until next switch
  start_time=$(date +%s)
  end_time=$((start_time + INTERVAL))
  
  while true; do
    current_time=$(date +%s)
    remaining=$((end_time - current_time))
    
    if [ "$remaining" -le 0 ]; then
      break
    fi
    
    mins=$((remaining / 60))
    secs=$((remaining % 60))
    printf "\rNext switch in %02d:%02d...   " "$mins" "$secs"
    sleep 1
  done
  echo
done
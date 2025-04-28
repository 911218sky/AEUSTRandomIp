#!/usr/bin/env bash
#
# Randomly rotates the IPv4 address on the first active physical interface
# at a configurable interval. Requires root privileges.
#
# Usage: sudo ./random_ip.sh [ -i INTERVAL ] [ -p PREFIX ] [ -g GATEWAY ] [ -d DNS1,DNS2,... ]
#
#   -i INTERVAL   Seconds between IP rotations (default: 60)
#   -p PREFIX     Subnet prefix length (default: 24)
#   -g GATEWAY    Default gateway IP (default: 120.96.54.254)
#   -d DNS        Comma-separated DNS servers (default: 120.96.35.1,120.96.36.1)

INTERVAL=60
PREFIX=24
GATEWAY="120.96.54.254"
DNS="120.96.35.1,120.96.36.1"
SUBNET="120.96.54"

usage() {
  echo "Usage: $0 [ -i INTERVAL ] [ -p PREFIX ] [ -g GATEWAY ] [ -d DNS1,DNS2,... ]"
  exit 1
}

while getopts ":i:p:g:d:h" opt; do
  case $opt in
    i) INTERVAL=$OPTARG ;;
    p) PREFIX=$OPTARG ;;
    g) GATEWAY=$OPTARG ;;
    d) DNS=$OPTARG ;;
    h|\?) usage ;;
  esac
done

# Re-run with sudo if not root
if [[ $EUID -ne 0 ]]; then
  echo "Re-running as root..."
  exec sudo bash "$0" "$@"
fi

# Find first active physical interface
get_active_iface() {
  for iface in /sys/class/net/*; do
    name=$(basename "$iface")
    [[ "$name" == lo ]] && continue
    oper=$(<"$iface/operstate")
    [[ "$oper" != up ]] && continue
    # skip virtual interfaces
    [[ -d "$iface/device/virtual" ]] && continue
    echo "$name"
    return
  done
}

IFACE=$(get_active_iface)
[[ -z $IFACE ]] && { echo "No active physical interface found."; exit 1; }
echo "Using interface: $IFACE"

# Convert DNS string to array
IFS=',' read -r -a DNS_SERVERS <<< "$DNS"

while true; do
  attempt=0
  while true; do
    (( attempt++ ))
    [[ $attempt -gt 50 ]] && { echo "Failed to find free IP after 50 tries."; exit 1; }
    octet=$(( RANDOM % 254 + 1 ))
    NEW_IP="$SUBNET.$octet"
    echo "Checking $NEW_IP..."
    ping -c1 -W1 "$NEW_IP" &> /dev/null || break
  done

  echo "Flushing old IP on $IFACE..."
  ip addr flush dev "$IFACE"

  echo "Assigning $NEW_IP/$PREFIX via gateway $GATEWAY..."
  ip addr add "$NEW_IP"/"$PREFIX" dev "$IFACE"
  ip route add default via "$GATEWAY" dev "$IFACE" 2>/dev/null

  echo "Configuring DNS: ${DNS_SERVERS[*]}"
  cp /etc/resolv.conf /etc/resolv.conf.bak
  {
    for dns in "${DNS_SERVERS[@]}"; do
      echo "nameserver $dns"
    done
  } > /etc/resolv.conf

  echo "✅ Switched to $NEW_IP"
  sleep "$INTERVAL"
done
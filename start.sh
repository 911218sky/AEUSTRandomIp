#!/bin/bash

# Network IP Rotation Script
# Randomly switches the network adapter IPv4 address at a configurable interval

# Default configuration
PREFIX="192.168.1"
INTERVAL=600
PREFIX_LENGTH=24
GATEWAY="192.168.1.1"
DNS_SERVERS=("8.8.8.8" "8.8.4.4")
TEST_DNS_SERVERS=("8.8.8.8")
CONNECTIVITY_WAIT_TIME=10

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --prefix)
      PREFIX="$2"
      shift 2
      ;;
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --prefix-length)
      PREFIX_LENGTH="$2"
      shift 2
      ;;
    --gateway)
      GATEWAY="$2"
      shift 2
      ;;
    --dns-servers)
      IFS=',' read -ra DNS_SERVERS <<< "$2"
      shift 2
      ;;
    --test-dns)
      IFS=',' read -ra TEST_DNS_SERVERS <<< "$2"
      shift 2
      ;;
    --wait-time)
      CONNECTIVITY_WAIT_TIME="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Parse prefix
IFS='.' read -ra PREFIX_OCTETS <<< "$PREFIX"
if [[ ${#PREFIX_OCTETS[@]} -gt 3 ]]; then
  echo "Prefix may contain at most 3 octets."
  exit 1
fi

# Calculate dynamic octets needed
DYNAMIC_COUNT=$((4 - ${#PREFIX_OCTETS[@]}))

# Find the network interface
INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
if [[ -z "$INTERFACE" ]]; then
  echo "No active network interface found."
  exit 1
fi

echo "Using interface: $INTERFACE"

# Save original network settings
ORIG_IP=$(ip -o -4 addr show dev $INTERFACE | awk '{print $4}' | cut -d/ -f1)
ORIG_PREFIX=$(ip -o -4 addr show dev $INTERFACE | awk '{print $4}' | cut -d/ -f2)
ORIG_GATEWAY=$(ip -o -4 route show default | awk '{print $3}')
ORIG_DNS=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}')

echo "Original IP: $ORIG_IP/$ORIG_PREFIX"
echo "Original Gateway: $ORIG_GATEWAY"
echo "Original DNS: $ORIG_DNS"

# Function to restore original settings
restore_original() {
  echo -e "\nRestoring original network settings..."
  
  # Remove current IP configuration
  ip addr flush dev $INTERFACE
  
  # Restore original IP and route
  ip addr add $ORIG_IP/$ORIG_PREFIX dev $INTERFACE
  ip route add default via $ORIG_GATEWAY dev $INTERFACE
  
  # Restore DNS (this is distribution-dependent)
  if [[ -f /etc/resolv.conf.backup ]]; then
    mv /etc/resolv.conf.backup /etc/resolv.conf
  else
    echo "Warning: Could not restore original DNS configuration."
  fi
  
  echo "✅ Original settings restored."
}

# Trap for cleanup on exit
trap restore_original EXIT INT TERM

# Backup resolv.conf
cp /etc/resolv.conf /etc/resolv.conf.backup

# Main rotation loop
while true; do
  # Generate a candidate IP
  attempt=0
  while true; do
    ((attempt++))
    if [[ $attempt -gt 50 ]]; then
      echo "Unable to find a free IP after 50 attempts."
      exit 1
    fi
    
    # Generate random octets
    random_octets=()
    for ((i=1; i<=DYNAMIC_COUNT; i++)); do
      random_octets+=($((RANDOM % 205 + 50)))
    done
    
    # Combine octets
    new_ip="${PREFIX_OCTETS[*]}"
    for octet in "${random_octets[@]}"; do
      new_ip="$new_ip.$octet"
    done
    
    echo "Checking $new_ip..."
    if ! ping -c 1 -W 1 "$new_ip" &>/dev/null; then
      break # IP not in use
    fi
  done
  
  # Test connectivity after assigning new IP
  test_attempt=0
  connectivity_ok=false
  
  while [[ "$connectivity_ok" = false && $test_attempt -lt 50 ]]; do
    ((test_attempt++))
    
    echo "Configuring new IP $new_ip/$PREFIX_LENGTH..."
    
    # Remove current IP configuration
    ip addr flush dev $INTERFACE
    
    # Add new IP and route
    ip addr add $new_ip/$PREFIX_LENGTH dev $INTERFACE
    ip route add default via $GATEWAY dev $INTERFACE
    
    # Set DNS servers
    echo -n > /etc/resolv.conf
    for dns in "${DNS_SERVERS[@]}"; do
      echo "nameserver $dns" >> /etc/resolv.conf
    done
    
    echo "Waiting $CONNECTIVITY_WAIT_TIME seconds before testing connectivity..."
    sleep $CONNECTIVITY_WAIT_TIME
    
    echo "Testing connectivity to: ${TEST_DNS_SERVERS[*]}"
    connectivity_ok=true
    
    for dns in "${TEST_DNS_SERVERS[@]}"; do
      if ! ping -c 3 -W 1 "$dns" &>/dev/null; then
        echo "Failed to connect to $dns"
        connectivity_ok=false
        break
      fi
    done
    
    if [[ "$connectivity_ok" = false ]]; then
      echo "Connectivity test failed, trying a new IP..."
      
      # Generate new random octets
      random_octets=()
      for ((i=1; i<=DYNAMIC_COUNT; i++)); do
        random_octets+=($((RANDOM % 205 + 50)))
      done
      
      # Combine octets
      new_ip="${PREFIX_OCTETS[*]}"
      for octet in "${random_octets[@]}"; do
        new_ip="$new_ip.$octet"
      done
    fi
  done
  
  if [[ "$connectivity_ok" = false ]]; then
    echo "Unable to find a free IP with connectivity after 50 attempts."
    exit 1
  fi
  
  echo "✅ Switched to $new_ip"
  
  # Countdown until next switch
  for ((i=1; i<=INTERVAL; i++)); do
    percent=$((i * 100 / INTERVAL))
    echo -ne "\rNext IP rotation in $((INTERVAL - i)) seconds... ($percent%) "
    sleep 1
  done
  echo -e "\nRotating IP address..."
done
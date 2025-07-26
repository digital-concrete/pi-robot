#!/bin/bash

set -e

HOTSPOT_NAME="MyPiHotspot"
SSID="MyPiHotspot"
PASSWORD="123456789"
HOTSPOT_IP="192.168.40.1"
DHCP_RANGE_START="192.168.40.10"
DHCP_RANGE_END="192.168.40.100"
IFACE="wlan0"

echo "==> Checking prerequisites..."
sudo apt update
sudo apt install -y network-manager

echo "==> Disabling conflicting services..."
sudo systemctl stop hostapd dnsmasq 2>/dev/null || true
sudo systemctl disable hostapd dnsmasq 2>/dev/null || true
sudo systemctl mask dhcpcd 2>/dev/null || true

echo "==> Deleting old hotspot (if exists)..."
nmcli connection delete "$HOTSPOT_NAME" 2>/dev/null || true

echo "==> Creating hotspot..."
nmcli connection add type wifi ifname "$IFACE" con-name "$HOTSPOT_NAME" autoconnect yes ssid "$SSID"
nmcli connection modify "$HOTSPOT_NAME" 802-11-wireless.mode ap 802-11-wireless.band bg
nmcli connection modify "$HOTSPOT_NAME" wifi-sec.key-mgmt wpa-psk
nmcli connection modify "$HOTSPOT_NAME" wifi-sec.psk "$PASSWORD"

echo "==> Setting manual IP and shared method..."
nmcli connection modify "$HOTSPOT_NAME" ipv4.addresses "$HOTSPOT_IP/24"
nmcli connection modify "$HOTSPOT_NAME" ipv4.method shared
nmcli connection modify "$HOTSPOT_NAME" ipv6.method ignore

echo "==> Enabling autoconnect..."
nmcli connection modify "$HOTSPOT_NAME" connection.autoconnect yes

echo "==> Starting hotspot..."
nmcli connection up "$HOTSPOT_NAME"

echo "==> Done! Hotspot '$SSID' is now active on $IFACE with IP $HOTSPOT_IP"

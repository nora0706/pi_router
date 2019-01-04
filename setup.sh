#!/bin/bash
#
# This version uses September 2017 august stretch image, please use this image
#

if [ "$EUID" -ne 0 ]
	then echo "Must be root"
	exit
fi

if [[ $# -lt 1 ]]; 
	then echo "You need to pass a password!"
	echo "Usage:"
	echo "sudo $0 yourChosenPassword [apName]"
	exit
fi

APPASS="$1"
APSSID="PiRouter"

if [[ $# -eq 2 ]]; then
	APSSID=$2
fi

apt-get update -yqq
apt-get upgrade -yqq
apt-get install hostapd dnsmasq -yqq

sudo service hostapd stop
sudo service dnsmasq stop
sudo service dhcpcd stop


# Setup dnsmasq
# Listen only on the interface wlan0
# Specify IP address of Google DNS server
# Enable the DHCP server start from 192.168.168.11 to 192.168.168.50
#   netmask is 255.255.255.255, lease time is 24 hours
cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
server=8.8.8.8
dhcp-range=192.168.168.11,192.168.168.50,255.255.255.0,24h
EOF

# Setup hostapd
# Listen only on the interface wlan0
# Specify the bridge name
# Provide the driver for the network device
#
# hw_mode: a(5GHz) or g(2.4Ghz)
# channel: the channel to use
# wmm_enabled: QoS support
# auth_algs: 1=wpa, 2=wep, 3=both
# wpa: WPA2 only
# ieee80211n: 802.11n support
# ht_capab: 
cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
bridge=br0
driver=nl80211

hw_mode=g
channel=10
wmm_enabled=1
auth_algs=1
wpa=2
ieee80211n=1
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]

wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP

wpa_passphrase=$APPASS
ssid=$APSSID
EOF

# Specify the DAEMON_CONF to hostapd
sed -i -- 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/g' /etc/default/hostapd

# Enable the IPv4 forwarding
sed -i -- 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf

# Setup the iptable for outbound traffic
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# Save the rule
sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"
# Eable the rule on boot
sed -i -- 's/exit 0//g' /etc/rc.local
cat >> /etc/rc.local <<EOF
# Added by Access Point Setup
iptables-restore < /etc/iptables.ipv4.nat
exit 0
EOF

# Setup the dhcp service
# Listen only on the interface wlan0
# Specify IP address of Google DNS server
# Enable the DHCP server start from 192.168.168.11 to 192.168.168.50
cat >> /etc/dhcpcd.conf <<EOF
interface wlan0
static ip_address=192.168.168.10/24
nohook wpa_supplicant
denyinterfaces eth0
denyinterfaces wlan0
EOF

sudo apt-get install bridge-utils
sudo brctl addbr br0
sudo brctl addif br0 eth0


sed -i -- 's/allow-hotplug wlan0//g' /etc/network/interfaces
sed -i -- 's/iface wlan0 inet manual//g' /etc/network/interfaces
sed -i -- 's/    wpa-conf \/etc\/wpa_supplicant\/wpa_supplicant.conf//g' /etc/network/interfaces

cat >> /etc/network/interfaces <<EOF
# Added by Access Point Setup
auto eth0 wlan0

iface eth0 inet manual

allow-hotplug wlan0
iface wlan0 inet manual

iface br0 inet static
  address 192.168.168.10
  netmask 255.255.255.0
  bridge_ports eth0 wlan0
  bridge_stp on
  bridge_maxwait 10
  post-up iw dev $IFACE set power_save off
EOF

systemctl enable hostapd
systemctl enable dnsmasq
systemctl enable dhcpcd

sudo service hostapd start
sudo service dnsmasq start
sudo service dhcpcd start

echo "All done! Please reboot"

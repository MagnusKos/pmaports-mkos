#!/bin/sh

INTERFACE="usb0"
ROUTE="default via 172.16.42.2 dev $INTERFACE"


[ "$1" = "$INTERFACE" ] || exit 0

case "$2" in
  "carrier"|"up")
    #ip link show "$1" | grep -q "state UP" || exit 0
    echo "Carrier up." >> /var/log/dispatcher.log
    ip route add $ROUTE || exit 1
    #logger "Route added for $INTERFACE on cable connect"
    ;;
  "down"|"carrier-off")
    #ip link show "$1" | grep -q "state DOWN" || exit 0
    echo "Carrier down." >> /var/log/dispatcher.log   
    ip route del $ROUTE 2>/dev/null || true
    #logger "Route removed for $INTERFACE on disconnect"
    ;;
esac

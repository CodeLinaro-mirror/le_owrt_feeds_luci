#!/bin/sh

if [ -z "$1" -o -z "$2" ]; then
    exit 1
fi

WPA_IFACE="$1"
WPA_EVENT="$2"
echo "EVENT $WPA_EVENT on $WPA_IFACE" >/dev/console
case "$WPA_EVENT" in
    "CONNECTED")
        killall -q sam_countdown
        rm -f /tmp/sam_countdown.pid
        ;;
    "DISCONNECTED")
        sam_countdown &
        ;;
    *)
        echo "Unknown action: $WPA_ACTION" >/dev/console
        exit 1
        ;;
esac

exit 0

#!/data/adb/magisk/busybox sh

# Give the system some time to finish early boot
sleep 25

# Stop adbd
stop adbd

# Set ADB over TCP port
setprop service.adb.tcp.port 5555

# Set iptables to accept TCP 5555
iptables -I INPUT -p tcp --dport 5555 -j ACCEPT

# Restart adbd
start adbd

# Optional: log it
echo "[BOOT] adbd restarted on TCP port 5555 at $(date)" >> /data/adb/adb_tcp.log 2>&1
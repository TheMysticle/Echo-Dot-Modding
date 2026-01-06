# Amazon Echo Dot 2 (Biscuit) - MQTT LED Control & Root Mods

[🇵🇱 Polska wersja (Polish Version)](README.pl.md)

This repository contains the scripts and instructions demonstrated in my YouTube video regarding modding the **Amazon Echo Dot 2nd Gen (2016)**, codename **"biscuit"**.

By rooting this device and using these scripts, you can take full control over the LED ring via MQTT (perfect for Home Assistant) and enable ADB over Wi-Fi for wireless management.

<div align="center">
  <a href="https://www.youtube.com/watch?v=PwSRFhiGyJs">
    <img src="https://img.youtube.com/vi/PwSRFhiGyJs/0.jpg" alt="YouTube Video">
  </a>
  <br>
  <em>(Click the image to watch the tutorial)</em>
</div>

## ⚠️ Disclaimer
**I am not responsible for bricked devices.** This process involves hardware shorting and modifying system partitions. Proceed at your own risk.

## Prerequisites

1.  **Amazon Echo Dot 2nd Gen** (Model RS03QR).
2.  **Root Access:** You must first unlock and root your device using the method by `rortiz2` on XDA.
    *   🔗 [XDA Thread: Unlock/Root/TWRP/Unbrick Amazon Echo Dot 2nd Gen](https://xdaforums.com/t/unlock-root-twrp-unbrick-amazon-echo-dot-2nd-gen-2016-biscuit.4761416/)
3.  **Latest Magisk:** The XDA guide installs Magisk 17.1. **You must update to a newer Magisk version** (v24+) for these scripts to work correctly (for the `service.d` support).
4.  **Mosquitto Binaries:** Included in this repo (ARM64 builds of `mosquitto_sub` and `mosquitto_pub`).

## Repository Contents

*   `led_mqtt.sh`: The main service script. Connects to your MQTT broker, listens for JSON commands, and controls the LEDs (with flicker-free static colors and animations).
*   `adb_tcp.sh`: A simple script to enable ADB over Wi-Fi on boot (Port 5555).
*   `mosquitto_sub` / `mosquitto_pub`: Required binaries for MQTT communication.

## Installation Guide

### Step 1: Prepare the Scripts
Open `led_mqtt.sh` in a text editor on your computer and **edit the configuration section** to match your network:

```bash
# MQTT Settings
MQTT_HOST="192.168.1.XX"      # Your Home Assistant/Broker IP
MQTT_USER="YourUser"          # Your MQTT Username
MQTT_PASS="YourPassword"      # Your MQTT Password
```

### Step 2: Transfer Files to the Echo Dot
You cannot push files directly to system folders. We must push to `/sdcard/` first, then move them using Root.

1.  Connect your Echo Dot via USB.
2.  Push the files:
    ```bash
    adb push led_mqtt.sh /sdcard/
    adb push adb_tcp.sh /sdcard/
    adb push mosquitto_pub /sdcard/
    adb push mosquitto_sub /sdcard/
    ```

### Step 3: Install scripts to `service.d`
Enter the device shell and move the files to the Magisk service directory so they run on boot.

```bash
adb shell
su
```

*Grant root access on the device if prompted (or if auto-granted).*

Now, move the binaries and scripts:

```bash
# 1. Install Mosquitto Binaries
mv /sdcard/mosquitto_pub /data/adb/
mv /sdcard/mosquitto_sub /data/adb/
chmod 755 /data/adb/mosquitto_pub
chmod 755 /data/adb/mosquitto_sub

# 2. Install Service Scripts
mv /sdcard/led_mqtt.sh /data/adb/service.d/
mv /sdcard/adb_tcp.sh /data/adb/service.d/
chmod 755 /data/adb/service.d/led_mqtt.sh
chmod 755 /data/adb/service.d/adb_tcp.sh
```

### Step 4: Reboot
Reboot the device. The LEDs should turn on (if configured) or connect to your broker. ADB over Wi-Fi will be active on port 5555.

```bash
reboot
```

## Home Assistant Configuration

Add the following to your `configuration.yaml`. This configuration uses the JSON schema and supports brightness, RGB colors, and effects.

```yaml
mqtt:
  light:
    - name: "Echo Dot LED"
      unique_id: "echo_dot_mqtt_led"
      schema: json
      command_topic: "echodot/light/set"
      state_topic: "echodot/light/state"
      brightness: true
      supported_color_modes: ["rgb"]
      effect: true
      effect_list:
        - "Stop Effect"
        - "rainbow"
        - "notification"
        - "pulse_blue"
      optimistic: false
      qos: 0
```

## Troubleshooting

If the LEDs are not working:

1.  **Check the logs:**
    ```bash
    adb shell cat /data/adb/led_mqtt.log
    ```
2.  **Verify permissions:** Ensure all files in `/data/adb/service.d/` and `/data/adb/` are executable (`chmod 755`).
3.  **Manual Test:** Try running the script manually to see errors:
    ```bash
    adb shell
    su
    /data/adb/service.d/led_mqtt.sh
    ```
#!/data/adb/magisk/busybox sh

# --- Configuration ---
SCRIPT_PATH="/data/adb/service.d/led_mqtt.sh"
LED_FILE="/sys/bus/i2c/devices/0-003f/frame"
LOG_FILE="/data/adb/led_mqtt.log"
STATE_FILE="/data/adb/led_state_json"
BB="/data/adb/magisk/busybox"
MOSQ_SUB="/data/adb/mosquitto_sub"
MOSQ_PUB="/data/adb/mosquitto_pub"

# MQTT Settings
MQTT_HOST="192.168.XX.XX"
MQTT_USER="YourUser"
MQTT_PASS="YourPassword"
TOPIC_SET="echodot/light/set"
TOPIC_STATE="echodot/light/state"

cd /data/adb

# --- Initialize Logging ---
if [ "$1" != "animation" ]; then
    > "$LOG_FILE"
    exec >> "$LOG_FILE" 2>&1
fi

# --- Helper: Kill Animation Process ---
stop_anim_proc() {
    if [ -f /data/adb/led_animation.pid ]; then
        PID=$(cat /data/adb/led_animation.pid)
        kill $PID 2>/dev/null
        rm -f /data/adb/led_animation.pid
    fi
}

# --- Helper: Generate Payload String (Run Once) ---
get_static_payload() {
    read STATE BRI R G B EFF < "$STATE_FILE"
    
    if [ "$STATE" = "OFF" ]; then
        # Return all black
        echo "000000000000000000000000000000000000000000000000000000000000000000000000"
        return
    fi

    R=${R:-255}; G=${G:-255}; B=${B:-255}; BRI=${BRI:-255}

    r_dim=$(( (R * BRI) / 255 ))
    g_dim=$(( (G * BRI) / 255 ))
    b_dim=$(( (B * BRI) / 255 ))

    hex_r=$($BB printf "%02x" $r_dim)
    hex_g=$($BB printf "%02x" $g_dim)
    hex_b=$($BB printf "%02x" $b_dim)
    hex_code="${hex_r}${hex_g}${hex_b}"

    # Construct Payload
    payload=""
    i=0; while [ $i -lt 12 ]; do payload="${payload}${hex_code}"; i=$((i + 1)); done
    echo "$payload"
}

# --- Animation/Keep-Alive Logic ---
run_animation() {
    TYPE="$1"
    PAYLOAD_CACHE="$2" # Only used for static

    # --- STATIC KEEP-ALIVE LOOP (OPTIMIZED) ---
    if [ "$TYPE" = "static" ]; then
        # This loop is now very lightweight. 
        # No math, no file reading, no printf. Just echo.
        while true; do
            echo "$PAYLOAD_CACHE" > "$LED_FILE"
            # 50ms sleep (20Hz) - Fast enough to stop flicker, low CPU use
            $BB usleep 50000
        done
    fi

    # --- DYNAMIC EFFECTS ---
    if [ "$TYPE" = "pulse_blue" ]; then
        while true; do
            val=0
            while [ $val -le 255 ]; do
                hex=$($BB printf "%02x" $val)
                seg="0000$hex"
                frame="$seg$seg$seg$seg$seg$seg$seg$seg$seg$seg$seg$seg"
                echo "$frame" > "$LED_FILE"
                val=$((val+10)); $BB usleep 20000
            done
            val=255
            while [ $val -ge 0 ]; do
                hex=$($BB printf "%02x" $val)
                seg="0000$hex"
                frame="$seg$seg$seg$seg$seg$seg$seg$seg$seg$seg$seg$seg"
                echo "$frame" > "$LED_FILE"
                val=$((val-10)); $BB usleep 20000
            done
        done
    elif [ "$TYPE" = "rainbow" ]; then
        colors="ff0000 ff7f00 ffff00 00ff00 00ffff 0000ff 4b0082 8b00ff ff0000 ff7f00 ffff00 00ff00"
        frame=""
        for color in $colors; do frame="${frame}${color}"; done
        while true; do
            echo "$frame" > "$LED_FILE"
            last_led=$($BB expr substr "$frame" 67 6)
            front_part=$($BB expr substr "$frame" 1 66)
            frame="${last_led}${front_part}"
            $BB usleep 150000
        done
    elif [ "$TYPE" = "notification" ]; then
        colors="00ffff 00ffff 00ffff 000000 000000 000000 000000 000000 000000 000000 000000 000000"
        frame=""
        for color in $colors; do frame="${frame}${color}"; done
        while true; do
            echo "$frame" > "$LED_FILE"
            last_led=$($BB expr substr "$frame" 67 6)
            front_part=$($BB expr substr "$frame" 1 66)
            frame="${last_led}${front_part}"
            $BB usleep 80000
        done
    fi
}

# --- State Reporting ---
publish_state() {
    read STATE BRI R G B EFF < "$STATE_FILE"
    R=${R:-0}; G=${G:-0}; B=${B:-0}; BRI=${BRI:-0}
    JSON="{\"state\":\"$STATE\",\"brightness\":$BRI,\"color_mode\":\"rgb\",\"color\":{\"r\":$R,\"g\":$G,\"b\":$B},\"effect\":\"$EFF\"}"
    $MOSQ_PUB -h "$MQTT_HOST" -u "$MQTT_USER" -P "$MQTT_PASS" -t "$TOPIC_STATE" -m "$JSON" -r
}

# --- Main Entry Point ---
if [ "$1" = "animation" ]; then
    run_animation "$2" "$3"
    exit 0
fi

echo "[MAIN] Starting MQTT LED Service (Optimized)..."
echo "[MAIN] Waiting for network..."
while ! $BB ping -c 1 "$MQTT_HOST" >/dev/null 2>&1; do sleep 5; done
echo "[MAIN] Network Up."

if [ ! -f "$STATE_FILE" ]; then
    echo "ON 255 255 255 255 none" > "$STATE_FILE"
fi

MY_PID=$$
for pid in $($BB ps | $BB grep "led_mqtt.sh" | $BB grep -v grep | $BB awk '{print $1}'); do
    if [ "$pid" != "$MY_PID" ]; then kill -9 $pid 2>/dev/null; fi
done

publish_state

# --- Main Listener Loop ---
while true; do
    $MOSQ_SUB -h "$MQTT_HOST" -u "$MQTT_USER" -P "$MQTT_PASS" -t "$TOPIC_SET" | while read -r PAYLOAD; do
        
        echo "[RECV] $PAYLOAD"
        read CUR_STATE CUR_BRI CUR_R CUR_G CUR_B CUR_EFF < "$STATE_FILE"

        NEW_STATE=$(echo "$PAYLOAD" | grep -o '"state": *"[^"]*"' | cut -d'"' -f4)
        [ -z "$NEW_STATE" ] && NEW_STATE="$CUR_STATE"

        NEW_BRI=$(echo "$PAYLOAD" | grep -o '"brightness": *[0-9]*' | cut -d: -f2 | tr -d ' ')
        [ -z "$NEW_BRI" ] && NEW_BRI="$CUR_BRI"

        NEW_R=$(echo "$PAYLOAD" | grep -o '"r": *[0-9]*' | cut -d: -f2 | tr -d ' ')
        NEW_G=$(echo "$PAYLOAD" | grep -o '"g": *[0-9]*' | cut -d: -f2 | tr -d ' ')
        NEW_B=$(echo "$PAYLOAD" | grep -o '"b": *[0-9]*' | cut -d: -f2 | tr -d ' ')
        if [ -n "$NEW_R" ]; then 
            CUR_R=$NEW_R; CUR_G=$NEW_G; CUR_B=$NEW_B
        fi

        NEW_EFF=$(echo "$PAYLOAD" | grep -o '"effect": *"[^"]*"' | cut -d'"' -f4)
        if [ -z "$NEW_EFF" ]; then NEW_EFF="$CUR_EFF"; fi
        if [ "$NEW_EFF" = "Stop Effect" ]; then NEW_EFF="none"; fi

        stop_anim_proc

        if [ "$NEW_STATE" = "OFF" ]; then
            echo "OFF $NEW_BRI $CUR_R $CUR_G $CUR_B none" > "$STATE_FILE"
            # Write OFF once, no background process needed
            OFF_STR=$(get_static_payload)
            echo "$OFF_STR" > "$LED_FILE"
        else
            echo "ON $NEW_BRI $CUR_R $CUR_G $CUR_B $NEW_EFF" > "$STATE_FILE"
            
            if [ "$NEW_EFF" != "none" ] && [ "$NEW_EFF" != "null" ]; then
                # Dynamic Effect
                $BB nohup "$SCRIPT_PATH" animation "$NEW_EFF" >> "$LOG_FILE" 2>&1 &
                echo $! > /data/adb/led_animation.pid
            else
                # Static Color - Pre-calculate string here
                STATIC_STR=$(get_static_payload)
                # Pass the string to the background process
                $BB nohup "$SCRIPT_PATH" animation "static" "$STATIC_STR" >> "$LOG_FILE" 2>&1 &
                echo $! > /data/adb/led_animation.pid
            fi
        fi
        publish_state
    done
    echo "[MAIN] MQTT Connection lost. Reconnecting in 5s..."
    sleep 5
done
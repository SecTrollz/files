#!/bin/bash

# Script: nonroot_app_forensics_hammer.sh
# Description: A NON-ROOT brutal forensic acquisition and monitoring tool. It goes H.A.M.
# Requires: ADB, no root needed.

# 1. DEFINE THE TARGETS (Edit this list!)
SUSPECT_PACKAGES=(
  "com.suspect.app1"
  "com.fishy.app2"
  "com.shady.app3"
)

# 2. SETUP THE EVIDENCE LOCKER
BACKUP_DIR="./App_Forensics_NonRoot_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
LOG_FILE="${BACKUP_DIR}/operation_log.txt"

# Function to log and print
log_message() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOG_FILE"
}

# Function to Call Mom via ntfy.sh
call_mom() {
    local message="$1"
    log_message "MOM NOTIFIED: $message"
    # UNCOMMENT AND SET YOUR TOPIC TO ENABLE
    # curl -H "Title: NON-ROOT HAMMER" -d "$message" "https://ntfy.sh/YOUR_SECRET_TOPIC" > /dev/null 2>&1 &
}

log_message "🔨 NON-ROOT HAMMER DROPPED. LET'S GO."

# 3. START GLOBAL SYSTEM INTERROGATION (The "Little Bitch" part)
log_message "📁 DUMPING GLOBAL SYSTEM STATE. THIS WILL BE MASSIVE."
# Get full device info
adb shell getprop > "${BACKUP_DIR}/device_properties.txt"
# List ALL packages
adb shell pm list packages -f > "${BACKUP_DIR}/all_packages_list.txt"
# List ALL running services
adb shell dumpsys activity services > "${BACKUP_DIR}/all_services_dump.txt"
# Grab network info
adb shell netstat -tunap > "${BACKUP_DIR}/network_connections.txt" 2>&1
adb shell ip addr show > "${BACKUP_DIR}/network_interfaces.txt"
# Start a background process to grab a HUGE logcat
adb logcat -d > "${BACKUP_DIR}/full_logcat_dump.log" 2>&1 &

call_mom "🚨 NON-ROOT operation started. Dumping system state for device $(adb shell getprop ro.product.model)."

# 4. THE MAIN ASSAULT - APP BY APP
for PACKAGE in "${SUSPECT_PACKAGES[@]}"; do

    log_message "🚓 TARGET ACQUIRED: $PACKAGE"
    PACKAGE_DIR="${BACKUP_DIR}/${PACKAGE}"
    mkdir -p "$PACKAGE_DIR"

    # 4A. ISOLATE THE TARGET (Make its life difficult)
    log_message "⛔ Force-stopping app: $PACKAGE"
    adb shell am force-stop "$PACKAGE"
    log_message "🧹 Clearing app cache: $PACKAGE"
    adb shell pm clear "$PACKAGE"

    # 4B. EXFILTRATE EVERYTHING WE CAN GET
    log_message "💾 ATTEMPTING BACKUP (This might fail without user permission)..."
    # This command will require you to tap 'Back up my data' on the phone screen!
    adb backup -f "${PACKAGE_DIR}/backup.ab" "$PACKAGE" >> "$LOG_FILE" 2>&1

    log_message "📊 DUMPING APP INFO AND STATS..."
    # Get app path and try to pull the APK
    APK_PATH=$(adb shell pm path "$PACKAGE" | sed 's/package://g')
    if [ ! -z "$APK_PATH" ]; then
        log_message "⬇️  Pulling APK from $APK_PATH"
        adb pull "$APK_PATH" "${PACKAGE_DIR}/" >> "$LOG_FILE" 2>&1
    fi

    # Dump package info (this works without root)
    adb shell dumpsys package "$PACKAGE" > "${PACKAGE_DIR}/package_info.dump"
    # Dump battery stats for the app
    adb shell dumpsys batterystats "$PACKAGE" > "${PACKAGE_DIR}/batterystats.dump"
    # Dump memory info (if available)
    adb shell dumpsys meminfo "$PACKAGE" > "${PACKAGE_DIR}/meminfo.dump" 2>&1

    # 4C. LOG THE HELL OUT OF IT (Start monitoring)
    log_message "🎙  Starting LIVE LOGCAT monitoring for $PACKAGE..."
    # This runs in the background, filtering logcat for the target package
    adb logcat --pid=$(adb shell pidof -s "$PACKAGE") > "${PACKAGE_DIR}/live_logcat.log" 2>&1 &
    # Save the background process ID to kill it later
    LOG_PID=$!
    echo $LOG_PID > "${PACKAGE_DIR}/logcat_pid.txt"

    log_message "✅ Finished initial processing for: $PACKAGE"

done

# 5. KEEP THE PRESSURE ON - MONITORING PHASE
log_message "🔍 Entering sustained monitoring phase for 30 seconds..."
call_mom "🔍 Now live-monitoring target apps for 30 seconds."

sleep 30 # Let the logcat monitors run for a bit

# 6. CLEANUP AND FINAL ASSAULT
log_message "🧹 Terminating background monitoring processes."
# Find and kill all our backgrounded logcat processes
for PACKAGE in "${SUSPECT_PACKAGES[@]}"; do
    PACKAGE_DIR="${BACKUP_DIR}/${PACKAGE}"
    if [ -f "${PACKAGE_DIR}/logcat_pid.txt" ]; then
        kill $(cat "${PACKAGE_DIR}/logcat_pid.txt") 2> /dev/null
    fi
done

# One final massive logcat grab for good measure
log_message "📁 GRABBING FINAL SYSTEM LOGCAT SNAPSHOT."
adb logcat -d > "${BACKUP_DIR}/final_logcat_snapshot.log" 2>&1

# 7. THE COUP DE GRÂCE - REVOKE PERMISSIONS
for PACKAGE in "${SUSPECT_PACKAGES[@]}"; do
    log_message "⚔️  NEUTRALIZING THREAT: Revoking ALL permissions for $PACKAGE"
    # Get list of permissions granted to the app
    PERMS=$(adb shell dumpsys package "$PACKAGE" | grep "granted=true" | sed -E 's/.*android.permission.//g' | cut -d\" -f1)
    for PERM in $PERMS; do
        adb shell pm revoke "$PACKAGE" "android.permission.$PERM" >> "$LOG_FILE" 2>&1
        log_message "   Revoked android.permission.$PERM"
    done
done

# 8. FINALIZE
log_message "🎉 NON-ROOT OPERATION COMPLETE. EVIDENCE LOCKER: $BACKUP_DIR"
call_mom "✅ NON-ROOT operation complete on $(adb shell getprop ro.product.model). Targets neutralized. Data acquired."

echo " "
echo "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM"
echo "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM"
echo "DDDDD    OOO   N   N  EEEEE !!! !!! !!!"
echo "D    D  O   O  NN  N  E     !!! !!! !!!"
echo "D     D O   O  N N N  EEE    !! !! !!"
echo "D    D  O   O  N  NN  E"
echo "DDDDD    OOO   N   N  EEEEE !!! !!! !!!"
echo "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM"
echo "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM"
echo " "
echo "Evidence pulled to: $BACKUP_DIR"
echo "Review the operation_log.txt for details."

#!/bin/bash
# shellcheck disable=SC2001,SC2004

###
#
#            Name:  install_or_defer.sh
#     Description:  This script, meant to be triggered periodically by a
#                   LaunchDaemon, will prompt users to install Apple software
#                   updates that the IT department has deemed "critical." Users
#                   will have the option to Restart Now or Defer. After a
#                   specified amount of time, the update will be forced.
#          Author:  Elliot Jordan <elliot@elliotjordan.com>
#         Created:  2017-03-09
#   Last Modified:  2018-10-04
#         Version:  1.1
#
###


########################## FILE PATHS AND IDENTIFIERS #########################

# Path to a plist file that is used to store settings locally. Omit ".plist"
# extension.
PLIST="/Library/Preferences/com.elliotjordan.install_or_defer"

# (Optional) Path to a logo that will be used in messaging. Recommend 512px,
# PNG format. If no logo is provided, the App Store icon will be used.
LOGO=""

# The identifier of the LaunchDaemon that is used to call this script, which
# should match the file in the payload/Library/LaunchDaemons folder. Omit
# ".plist" extension.
BUNDLE_ID="com.elliotjordan.install_or_defer"


################################## MESSAGING ##################################

# The message users will receive when updates are available, shown above the
# "Restart Now" and "Defer" buttons. This message uses the following dynamic
# substitutions:
#   - %DEFER_HOURS% will be automatically replaced by the number of hours
#     remaining in the deferral period.
#   - The section in the {{double curly braces}} will be removed when this
#     message is displayed for the final time before the deferral deadline.
MSG_ACT_OR_DEFER_HEADING="Critical updates are available"
MSG_ACT_OR_DEFER="Apple has released critical security updates, and the ExampleCorp IT department would like you to install them as soon as possible. Please save your work, then click Restart Now.

{{If now is not a good time, you may defer this message until later. }}%DEFER_HOURS% hours remain until your Mac restarts automatically to install these updates. This may result in losing unsaved work, so please don't wait until then.

If you have any questions, please call or email the ExampleCorp Help Desk."

# The message users will receive after the deferral deadline has been reached.
MSG_RESTART_HEADING="Please restart now"
MSG_RESTART="Please save your work immediately, then choose Restart from the Apple menu."


#################################### TIMING ###################################

# Number of seconds between the first script run and the updates being forced.
MAX_DEFERRAL_TIME=$(( 60 * 60 * 24 * 3 )) # (259200 = 3 days)

# When the user clicks "Defer" the next prompt is delayed by this much time.
EACH_DEFER=$(( 60 * 60 * 4 )) # (14400 = 4 hours)

# The number of seconds to wait between displaying the "please restart" message
# and attempting a soft restart.
SOFT_RESTART_DELAY=$(( 60 * 10 )) # (600 = 10 minutes)

# The number of seconds to wait between attempting a soft restart and forcing a
# restart.
HARD_RESTART_DELAY=$(( 60 * 5 )) # (300 = 5 minutes)


################################## FUNCTIONS ##################################

# This function takes a number of seconds as input and returns hh:mm:ss format.
# Source: http://stackoverflow.com/a/12199798
# License: CC BY-SA 3.0 (https://creativecommons.org/licenses/by-sa/3.0/)
# Created by: perreal (http://stackoverflow.com/users/390913/perreal)
convertsecs() {
    ((h=${1}/3600))
    ((m=(${1}%3600)/60))
    ((s=${1}%60))
    printf "%02dh:%02dm:%02ds\n" $h $m $s
}

# This function checks for all available software updates and triggers them to
# be installed at next restart.
trigger_updates_at_restart() {

    echo "Checking for pending recommended software updates..."
    updateCheck=$(softwareupdate --list)

    # If no updates need to be installed, bail out.
    if [[ "$updateCheck" == *"[recommended]"* ]]; then
        echo "Pre-downloading all recommended software updates..."
        softwareupdate --download --recommended
    else
        echo "No recommended updates available."
        clean_up

        echo "Running jamf recon..."
        $jamf recon

        echo "Unloading $BUNDLE_ID LaunchDaemon. Script will end here."
        launchctl unload -w "/private/tmp/$BUNDLE_ID.plist"
        exit 0
    fi

    echo "Configuring updates to be installed at restart..."
    # Code borrowed from: https://jamfnation.jamfsoftware.com/discussion.html?id=15390#responseChild94879

    $PListBuddy -c "Add :InstallAtLogout array" /Library/Updates/index.plist
    for update in $(defaults read /Library/Updates/index ProductPaths | grep -v "[{}]" | awk -F "=" '{print $1}' | grep -o "[^\" ]\+"); do
        $PListBuddy -c "Add :InstallAtLogout: string $update" /Library/Updates/index.plist
    done
    touch /var/db/.SoftwareUpdateAtLogout
    chmod og-r /var/db/.SoftwareUpdateAtLogout
    $PListBuddy -c "Add -RootInstallMode STRING YES" /var/db/.SoftwareUpdateOptions
    $PListBuddy -c "Add -SkipConfirm STRING YES" /var/db/.SoftwareUpdateOptions
    chmod og-r /var/db/.SoftwareUpdateOptions

    echo "Reloading com.apple.softwareupdated.plist..."
    launchctl unload /System/Library/LaunchDaemons/com.apple.softwareupdated.plist 2>/dev/null
    sleep 2
    launchctl load /System/Library/LaunchDaemons/com.apple.softwareupdated.plist

    echo "Reloading com.apple.suhelperd.plist..."
    launchctl unload /System/Library/LaunchDaemons/com.apple.suhelperd.plist 2>/dev/null
    sleep 2
    launchctl load /System/Library/LaunchDaemons/com.apple.suhelperd.plist

    echo "Updates configured to install at next restart."

}

# Invoked after the deferral deadline passes, this function displays an
# onscreen message instructing the user to restart.
display_please_restart_msg() {

    # Create a jamfHelper script that will be called by a LaunchDaemon.
    cat << EOF > "/private/tmp/$HELPER_SCRIPT"
#!/bin/bash
"$jamfHelper" -windowType "utility" -windowPosition "ur" -icon "$LOGO" -title "$MSG_RESTART_HEADING" -description "$MSG_RESTART"
EOF
    chmod +x "/private/tmp/$HELPER_SCRIPT"

    # Create the LaunchDaemon that we'll use to show the persistent jamfHelper
    # messages.
    cat << EOF > "/private/tmp/${BUNDLE_ID}_helper.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>KeepAlive</key>
	<true/>
	<key>Label</key>
	<string>${BUNDLE_ID}_helper</string>
	<key>Program</key>
	<string>/private/tmp/$HELPER_SCRIPT</string>
	<key>ThrottleInterval</key>
	<integer>10</integer>
</dict>
</plist>
EOF

    # Load the LaunchDaemon to show the jamfHelper message.
    echo "Displaying \"please restart\" message..."
    killall jamfHelper 2>/dev/null
    launchctl load -w "/private/tmp/${BUNDLE_ID}_helper.plist"

    # After specified delay, attempt a soft restart.
    echo "Waiting $(( SOFT_RESTART_DELAY / 60 )) minutes before attempting a \"soft restart\"..."
    sleep "$SOFT_RESTART_DELAY"
    echo "$(( SOFT_RESTART_DELAY / 60 )) minutes have elapsed since user was prompted to restart. Attempting \"soft\" restart..."

    trigger_restart

}

# This function immediately attempts a "soft" restart, waits a specified amount
# of time, and then forces a "hard" restart.
trigger_restart() {

    # Immediately attempt a "soft" restart.
    CURRENT_USER=$(/usr/bin/stat -f%Su /dev/console)
    USER_ID=$(id -u "$CURRENT_USER")
    if [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -le 9 ]]; then
        LOGINWINDOW_PID=$(pgrep -x -u "$USER_ID" loginwindow)
        launchctl bsexec "$LOGINWINDOW_PID" osascript -e 'tell application "System Events" to restart'
    elif [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -gt 9 ]]; then
        launchctl asuser "$USER_ID" osascript -e 'tell application "System Events" to restart'
    fi

    # After specified delay, kill all apps forcibly, which clears the way for
    # an unobstructed restart.
    echo "Waiting $(( HARD_RESTART_DELAY / 60 )) minutes before forcing a \"hard restart\"..."
    sleep "$HARD_RESTART_DELAY"
    echo "$(( HARD_RESTART_DELAY / 60 )) minutes have elapsed since user was prompted to restart. Forcing \"hard\" restart..."

    USER_PIDS=$(pgrep -u "$USER_ID")
    LOGINWINDOW_PID=$(pgrep -x -u "$USER_ID" loginwindow)
    for PID in $USER_PIDS; do
        # Kill all processes except the loginwindow process.
        if [[ "$PID" -ne "$LOGINWINDOW_PID" ]]; then
            kill -9 "$PID"
        fi
    done
    if [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -le 9 ]]; then
        launchctl bsexec "$LOGINWINDOW_PID" osascript -e 'tell application "System Events" to restart'
    elif [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -gt 9 ]]; then
        launchctl asuser "$USER_ID" osascript -e 'tell application "System Events" to restart'
    fi
    # Mac should restart now, ending this script and installing updates.

}

# Clean up plist values and self destruct LaunchDaemon and script.
clean_up() {

    echo "Cleaning up stored plist values..."
    defaults delete "$PLIST" AppleSoftwareUpdatesForcedAfter 2>/dev/null
    defaults delete "$PLIST" AppleSoftwareUpdatesDeferredUntil 2>/dev/null

    echo "Cleaning up main script and LaunchDaemon..."
    mv "/Library/LaunchDaemons/$BUNDLE_ID.plist" "/private/tmp/$BUNDLE_ID.plist"
    mv "$0" "/private/tmp/"

}


######################## VALIDATION AND ERROR CHECKING ########################

# Copy all output to the system log for diagnostic purposes.
exec 1> >(logger -s -t "$(basename "$0")") 2>&1
echo "Starting $(basename "$0") script. Performing validation and error checking..."

# Filename we will use for the auto-generated helper script.
HELPER_SCRIPT="$(basename "$0" | sed "s/.sh$//g")_helper.sh"

# Flag variable for catching show-stopping errors.
BAILOUT=false

# Bail out if the jamfHelper doesn't exist.
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
if [[ ! -x "$jamfHelper" ]]; then
    echo "[ERROR] The jamfHelper binary must be present in order to run this script."
    BAILOUT=true
fi

# Bail out if the jamf binary doesn't exist.
PATH="/usr/sbin:/usr/local/bin:$PATH"
jamf=$(which jamf)
if [[ -z $jamf ]]; then
    echo "[ERROR] The jamf binary could not be found."
    BAILOUT=true
fi

# Bail out if PListBuddy doesn't exist.
PListBuddy="/usr/libexec/PListBuddy"
if [[ ! -x $PListBuddy ]]; then
    echo "[ERROR] PListBuddy could not be found."
    BAILOUT=true
fi

# Determine OS X version.
OS_MAJOR=$(/usr/bin/sw_vers -productVersion | awk -F . '{print $1}')
OS_MINOR=$(/usr/bin/sw_vers -productVersion | awk -F . '{print $2}')

# If the OS is not 10.8 through 10.12, this script may not work. When new
# versions of macOS are released, this logic should be updated after the script
# has been tested successfully.
if [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -lt 8 ]] || [[ "$OS_MAJOR" -lt 10 ]]; then
    echo "[ERROR] This script requires at least OS X 10.8. This Mac has $OS_MAJOR.$OS_MINOR."
    BAILOUT=true
elif [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -gt 12 ]] || [[ "$OS_MAJOR" -gt 10 ]]; then
    echo "[ERROR] This script has been tested through 10.12 only. This Mac has $OS_MAJOR.$OS_MINOR."
    BAILOUT=true
fi

# We need to be connected to the internet in order to download updates.
ping -q -c 1 208.67.222.222 &>/dev/null
if [[ $? -ne 0 ]]; then
    echo "[ERROR] No connection to the Internet."
    BAILOUT=true
fi

# If FileVault encryption or decryption is in progress, installing updates that
# require a restart can cause problems.
if fdesetup status | grep -q "in progress"; then
    echo "[ERROR] FileVault encryption or decryption is in progress."
    BAILOUT=true
fi

# If any of the errors above are present, bail out of the script now.
if [[ "$BAILOUT" == "true" ]]; then
    START_INTERVAL=$(defaults read /Library/LaunchDaemons/$BUNDLE_ID.plist StartInterval 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo "Stopping due to errors, but will try again in $(convertsecs "$START_INTERVAL")."
    else
        echo "Stopping due to errors."
    fi
    exit 1
fi


################################ MAIN PROCESS #################################

echo "Validation and error checking passed. Starting main process..."

# Validate logo file, if a path is provided.
if [[ -z "$LOGO" ]]; then
    echo "No logo provided. Using App Store icon."
    LOGO="/Applications/App Store.app/Contents/Resources/AppStore.help/Contents/Resources/SharedGlobalArt/AppLanding_AppStore.png"
elif [[ ! -f "$LOGO" ]]; then
    echo "No logo exists at specified path ($LOGO). Using App Store icon."
    LOGO="/Applications/App Store.app/Contents/Resources/AppStore.help/Contents/Resources/SharedGlobalArt/AppLanding_AppStore.png"
fi

# Perform first run tasks, including calculating deadline and clearing cache.
FORCE_DATE=$(defaults read "$PLIST" AppleSoftwareUpdatesForcedAfter 2>/dev/null)
if [[ -z $FORCE_DATE || $FORCE_DATE -gt $(( $(date +%s) + MAX_DEFERRAL_TIME )) ]]; then
    FORCE_DATE=$(( $(date +%s) + MAX_DEFERRAL_TIME ))
    defaults write "$PLIST" AppleSoftwareUpdatesForcedAfter -int $FORCE_DATE

    echo "Clearing software update cache..."
    rm -rf /Library/Updates
fi

# Calculate how much time remains until deferral deadline.
DEFER_TIME_LEFT=$(( FORCE_DATE - $(date +%s) ))
echo "Deferral deadline: $(date -jf "%s" "+%Y-%m-%d %H:%M:%S" "$FORCE_DATE")"
echo "Time remaining: $(convertsecs $DEFER_TIME_LEFT)"

# Set updates to install at the next restart. (If this script has already run
# at least once, this will refresh the "InstallAtLogout" list of updates.)
trigger_updates_at_restart

# Get the "deferred until" timestamp, if one exists.
DEFERRED_UNTIL=$(defaults read "$PLIST" AppleSoftwareUpdatesDeferredUntil 2>/dev/null)
if [[ -n "$DEFERRED_UNTIL" ]] && (( DEFERRED_UNTIL > $(date +%s) && FORCE_DATE > DEFERRED_UNTIL )); then
    # If the policy ran recently and was deferred, we need to respect that
    # "defer until" timestamp, as long as it is earlier than the deferral
    # deadline.
    echo "The next prompt is deferred until after $(date -jf "%s" "+%Y-%m-%d %H:%M:%S" "$DEFERRED_UNTIL")."
    exit 0
fi

# Make a note of the time before displaying the prompt.
PROMPT_START=$(date +%s)

# If defer time remains, display the prompt. If not, install and restart.
if (( DEFER_TIME_LEFT > 0 )); then

    # Substitute the correct number of hours remaining.
    if (( DEFER_TIME_LEFT > 7200 )); then
        MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER//%DEFER_HOURS%/$(( DEFER_TIME_LEFT / 3600 ))}"
        MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER// 1 hours/ 1 hour}"
    elif (( DEFER_TIME_LEFT > 60 )); then
        MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER//%DEFER_HOURS% hours/$(( DEFER_TIME_LEFT / 60 )) minutes}"
        MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER// 1 minutes/ 1 minute}"
    else
        MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER//after %DEFER_HOURS% hours/very soon}"
    fi

    # Determine whether to include the "you may defer" wording.
    if (( EACH_DEFER > DEFER_TIME_LEFT )); then
        # Remove "{{" and "}}" including all the text between.
        MSG_ACT_OR_DEFER="$(echo "$MSG_ACT_OR_DEFER" | sed 's/{{.*}}//g')"
    else
        # Just remove "{{" and "}}" but leave the text between.
        MSG_ACT_OR_DEFER="$(echo "$MSG_ACT_OR_DEFER" | sed 's/[{{|}}]//g')"
    fi

    # Show the install/defer prompt.
    echo "Prompting to install updates now or defer..."
    PROMPT=$("$jamfHelper" -windowType "utility" -windowPosition "ur" -icon "$LOGO" -title "$MSG_ACT_OR_DEFER_HEADING" -description "$MSG_ACT_OR_DEFER" -button1 "Restart Now" -button2 "Defer" -defaultButton 2 -timeout 3600 -startlaunchd 2>/dev/null)
    JAMFHELPER_PID=$!

    # Make a note of the amount of time the prompt was shown onscreen.
    PROMPT_END=$(date +%s)
    PROMPT_ELAPSED_SEC=$(( PROMPT_END - PROMPT_START ))

    # Generate a duration string that will be used in log output.
    if [[ -n $PROMPT_ELAPSED_SEC && $PROMPT_ELAPSED_SEC -eq 0 ]]; then
        PROMPT_ELAPSED_STR="immediately"
    elif [[ -n $PROMPT_ELAPSED_SEC ]]; then
        PROMPT_ELAPSED_STR="after $(convertsecs "$PROMPT_ELAPSED_SEC")"
    elif [[ -z $PROMPT_ELAPSED_SEC ]]; then
        PROMPT_ELAPSED_STR="after an unknown amount of time"
        echo "[WARNING] Unable to determine elapsed time between prompt and action."
    fi

    # For reference, here is a list of the possible jamfHelper return codes:
    # https://gist.github.com/homebysix/18c1a07a284089e7f279#file-jamfhelper_help-txt-L72-L84

    # Take action based on the return code of the jamfHelper.
    if [[ -n $PROMPT && $PROMPT_ELAPSED_SEC -eq 0 ]]; then
        # Kill the jamfHelper prompt.
        kill -9 $JAMFHELPER_PID
        echo "[ERROR] jamfHelper returned code $PROMPT $PROMPT_ELAPSED_STR. It's unlikely that the user responded that quickly."
        exit 1
    elif [[ -n $PROMPT && $DEFER_TIME_LEFT -gt 0 && $PROMPT -eq 0 ]]; then
        echo "User clicked Restart Now $PROMPT_ELAPSED_STR."
        defaults delete "$PLIST" AppleSoftwareUpdatesDeferredUntil 2>/dev/null
        clean_up
        trigger_restart
    elif [[ -n $PROMPT && $DEFER_TIME_LEFT -gt 0 && $PROMPT -eq 1 ]]; then
        # Kill the jamfHelper prompt.
        kill -9 $JAMFHELPER_PID
        echo "[ERROR] jamfHelper was not able to launch $PROMPT_ELAPSED_STR."
        exit 1
    elif [[ -n $PROMPT && $DEFER_TIME_LEFT -gt 0 && $PROMPT -eq 2 ]]; then
        echo "User clicked Defer $PROMPT_ELAPSED_STR."
        NEXT_PROMPT=$(( $(date +%s) + EACH_DEFER ))
        defaults write "$PLIST" AppleSoftwareUpdatesDeferredUntil -int "$NEXT_PROMPT"
        echo "Next prompt will appear after $(date -jf "%s" "+%Y-%m-%d %H:%M:%S" "$NEXT_PROMPT")."
    elif [[ -n $PROMPT && $DEFER_TIME_LEFT -gt 0 && $PROMPT -eq 239 ]]; then
        echo "User deferred by exiting jamfHelper $PROMPT_ELAPSED_STR."
        NEXT_PROMPT=$(( $(date +%s) + EACH_DEFER ))
        defaults write "$PLIST" AppleSoftwareUpdatesDeferredUntil -int "$NEXT_PROMPT"
        echo "Next prompt will appear after $(date -jf "%s" "+%Y-%m-%d %H:%M:%S" "$NEXT_PROMPT")."
    elif [[ -n $PROMPT && $DEFER_TIME_LEFT -gt 0 && $PROMPT -gt 2 ]]; then
        # Kill the jamfHelper prompt.
        kill -9 $JAMFHELPER_PID
        echo "[ERROR] jamfHelper produced an unexpected value (code $PROMPT) $PROMPT_ELAPSED_STR."
        exit 1
    elif [[ -z $PROMPT ]]; then # $PROMPT is not defined
        # Kill the jamfHelper prompt.
        kill -9 $JAMFHELPER_PID
        echo "[ERROR] jamfHelper returned no value $PROMPT_ELAPSED_STR. Restart Now/Defer response was not captured. This may be because the user logged out without clicking Restart Now/Defer."
        exit 1
    else
        # Kill the jamfHelper prompt.
        kill -9 $JAMFHELPER_PID
        echo "[ERROR] Something went wrong. Check the jamfHelper return code ($PROMPT) and prompt elapsed seconds ($PROMPT_ELAPSED_SEC) for further information."
        exit 1
    fi

else
    # If no deferral time remains, force installation of updates now.
    echo "No deferral time remains."
    clean_up
    display_please_restart_msg
fi

exit 0

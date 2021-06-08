#!/bin/bash
# shellcheck disable=SC2001

###
#
#            Name:  Install or Defer.sh
#     Description:  This script, meant to be triggered periodically by a
#                   LaunchDaemon, will prompt users to install Apple system
#                   updates that the IT department has deemed "critical." Users
#                   will have the option to Run Updates or Defer. After a
#                   specified amount of time, the update will be forced on
#                   Intel Macs, and if updates requiring a restart were found
#                   in that update check, the system restarts automatically.
#         Authors:  Mario Panighetti and Elliot Jordan
#         Created:  2017-03-09
#   Last Modified:  2021-06-07
#         Version:  4.1.3
#
###


########################## FILE PATHS AND IDENTIFIERS #########################

# Path to a plist file that is used to store settings locally. Omit ".plist"
# extension.
PLIST="/Library/Preferences/com.github.mpanighetti.install-or-defer"

# (Optional) Path to a logo that will be used in messaging. Recommend 512px,
# PNG format. If no logo is provided, the Software Update icon will be used.
LOGO=""

# The identifier of the LaunchDaemon that is used to call this script, which
# should match the file in the payload/Library/LaunchDaemons folder. Omit
# ".plist" extension.
BUNDLE_ID="com.github.mpanighetti.install-or-defer"

# The file path of this script.
SCRIPT_PATH="/Library/Scripts/Install or Defer.sh"


################################## MESSAGING ##################################

# The label of the install button.
INSTALL_BUTTON="Update"

# The label of the defer button.
DEFER_BUTTON="Defer"

# The messages below use the following dynamic substitutions wherever found:
#   - %UPDATE_LIST% will be automatically replaced with a comma-separated list
#     of all recommended updates found in a Software Update check.
#   - %DEFER_HOURS% will be automatically replaced by the number of days, hours,
#     or minutes remaining in the deferral period.
#   - %DEADLINE_DATE% will be automatically replaced by the deadline date and
#     time before updates are enforced.
#   - The section in the {{double curly brackets}} will be removed when this
#     message is displayed for the final time before the deferral deadline.
#   - The sections in the <<double comparison operators>> will be removed if a
#     restart is not required for the pending updates.

# The message users will receive when updates are available, shown above the
# install and defer buttons.
MSG_ACT_OR_DEFER_HEADING="Updates are available"
MSG_ACT_OR_DEFER="Your Mac needs to run updates for %UPDATE_LIST% by %DEADLINE_DATE%.

Please save your work, quit any of the above applications, and click ${INSTALL_BUTTON}. {{If now is not a good time, you may defer this message until later. }}These updates will be required after %DEFER_HOURS%<<, forcing your Mac to restart after they run>>.

Please contact IT for any questions."

# The message users will receive after the deferral deadline has been reached.
MSG_ACT_HEADING="Please run updates now"
MSG_ACT="Your Mac is about to run updates for %UPDATE_LIST% << and restart>>.

Please save your work, quit any of the above applications, and click ${INSTALL_BUTTON} before the deadline.<< Your Mac will restart when all updates are finished running.>>

Please contact IT for any questions."

# The message users will receive when a manual update action is required.
MSG_ACT_NOW_HEADING="Updates are available"
MSG_ACT_NOW="Your Mac needs to run updates for %UPDATE_LIST% << which require a restart>>.

Please save your work, quit any of the above applications, then open System Preferences -> Software Update and run all available updates.<< Your Mac will restart when all updates are finished running.>>"

# The message users will receive while updates are running in the background.
MSG_UPDATING_HEADING="Running updates..."
MSG_UPDATING="Running updates for %UPDATE_LIST% in the background.<< Your Mac will restart automatically when this is finished.>>"


#################################### TIMING ###################################

# Number of seconds between the first script run and the updates being forced.
MAX_DEFERRAL_TIME=$(( 60 * 60 * 24 * 3 )) # (259200 = 3 days)

# When the user clicks "Defer" the next prompt is delayed by this much time.
EACH_DEFER=$(( 60 * 60 * 4 )) # (14400 = 4 hours)

# The number of seconds to wait between displaying the "run updates" message
# and applying updates, then attempting a soft restart.
UPDATE_DELAY=$(( 60 * 10 )) # (600 = 10 minutes)

# The number of seconds to wait between attempting a soft restart and forcing a
# restart.
HARD_RESTART_DELAY=$(( 60 * 5 )) # (300 = 5 minutes)


################################## FUNCTIONS ##################################

# Takes a number of seconds as input and returns hh:mm:ss format.
# Source: http://stackoverflow.com/a/12199798
# License: CC BY-SA 3.0 (https://creativecommons.org/licenses/by-sa/3.0/)
# Created by: perreal (http://stackoverflow.com/users/390913/perreal)
convert_seconds () {

    if [[ $1 -le 0 ]]; then
        DAYS=0
        HOURS=0
        MINUTES=0
        SECONDS=0
    else
        ((DAYS=${1}/86400))
        ((HOURS=${1}%86400/3600))
        ((MINUTES=(${1}%3600)/60))
        ((SECONDS=${1}%60))
    fi
    printf "%02dd:%02dh:%02dm:%02ds\n" "$DAYS" "$HOURS" "$MINUTES" "$SECONDS"

}

# Checks for recommended macOS updates, or exits if no such updates are
# available.
check_for_updates () {

    echo "Checking for pending system updates..."
    UPDATE_CHECK=$(/usr/sbin/softwareupdate --list 2>&1)

    # Determine whether any recommended macOS updates are available.
    # If a restart is required for any pending updates, then run all available
    # software updates.
    if [[ "$UPDATE_CHECK" =~ (Action: restart|\[restart\]) ]]; then
        INSTALL_WHICH="all"
        RESTART_FLAG="--restart"
        # Remove "<<" and ">>" but leave the text between
        # (retains restart warnings).
        MSG_ACT_OR_DEFER="$(echo "$MSG_ACT_OR_DEFER" | /usr/bin/sed 's/[\<\<|\>\>]//g')"
        MSG_ACT="$(echo "$MSG_ACT" | /usr/bin/sed 's/[\<\<|\>\>]//g')"
        MSG_ACT_NOW="$(echo "$MSG_ACT_NOW" | /usr/bin/sed 's/[\<\<|\>\>]//g')"
        MSG_UPDATING="$(echo "$MSG_UPDATING" | /usr/bin/sed 's/[\<\<|\>\>]//g')"
    # Otherwise, only target recommended updates.
    elif [[ "$UPDATE_CHECK" =~ (Recommended: YES|\[recommended\]) ]]; then
        INSTALL_WHICH="recommended"
        RESTART_FLAG=""
        # Remove "<<" and ">>" including all the text between
        # (removes restart warnings).
        MSG_ACT_OR_DEFER="$(echo "$MSG_ACT_OR_DEFER" | /usr/bin/sed 's/\<\<.*\>\>//g')"
        MSG_ACT="$(echo "$MSG_ACT" | /usr/bin/sed 's/\<\<.*\>\>//g')"
        MSG_ACT_NOW="$(echo "$MSG_ACT_NOW" | /usr/bin/sed 's/\<\<.*\>\>//g')"
        MSG_UPDATING="$(echo "$MSG_UPDATING" | /usr/bin/sed 's/\<\<.*\>\>//g')"
    # If no recommended updates need to be installed, bail out.
    else
        echo "No recommended updates available."
        exit_without_updating
    fi

    # Capture update names and versions.
    if [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -lt 15 ]]; then
      UPDATE_LIST="$(echo "$UPDATE_CHECK" | /usr/bin/awk -F'[\(\)]' '/recommended/ {print $1 $2}')"
    else
      UPDATE_LIST="$(echo "$UPDATE_CHECK" | /usr/bin/awk -F'[:,]' '/Title:/ {print $2 $4}')"
    fi
    # Convert update list from multiline to comma-separated list.
    UPDATE_LIST="$(echo "$UPDATE_LIST" | /usr/bin/tr '\n' ',' | /usr/bin/sed 's/^ *//; s/,/, /g; s/, $//')"
    # Reformat update list to replace last comma with ", and" or " and" as
    # needed for legibility. In this house, we use Oxford commas.
    COMMA_COUNT="$(echo "$UPDATE_LIST" | /usr/bin/tr -dc ',' | /usr/bin/wc -c | /usr/bin/bc)"
    if [ "$COMMA_COUNT" -gt 1 ]; then
        UPDATE_LIST="$(echo "$UPDATE_LIST" | sed 's/\(.*\),/\1, and/')"
    elif [ "$COMMA_COUNT" -eq 1 ]; then
        UPDATE_LIST="$(echo "$UPDATE_LIST" | sed 's/\(.*\),/\1 and/')"
    fi
    # Populate the list of pending updates in message text.
    MSG_ACT_OR_DEFER="$(echo "$MSG_ACT_OR_DEFER" | /usr/bin/sed "s/%UPDATE_LIST%/$UPDATE_LIST/")"
    MSG_ACT="$(echo "$MSG_ACT" | /usr/bin/sed "s/%UPDATE_LIST%/$UPDATE_LIST/")"
    MSG_ACT_NOW="$(echo "$MSG_ACT_NOW" | /usr/bin/sed "s/%UPDATE_LIST%/$UPDATE_LIST/")"
    MSG_UPDATING="$(echo "$MSG_UPDATING" | /usr/bin/sed "s/%UPDATE_LIST%/$UPDATE_LIST/")"

    # Download updates for Intel Macs (all updates if a restart is required for
    # any, otherwise just recommended updates).
    if [[ "$PLATFORM_ARCH" = "i386" ]]; then
        echo "Caching $INSTALL_WHICH system updates..."
        /usr/sbin/softwareupdate --download --$INSTALL_WHICH --no-scan
    fi

}

# Displays an onscreen message instructing the user to apply updates.
# This function is invoked after the deferral deadline passes.
display_act_msg () {

    # Display persistent HUD with update prompt message.
    echo "Killing any active jamfHelper notifications..."
    /usr/bin/killall jamfHelper 2>"/dev/null"
    echo "Displaying \"run updates\" message for $(( UPDATE_DELAY / 60 )) minutes before automatically applying updates..."
    "$JAMFHELPER" -windowType "utility" -windowPosition "ur" -title "$MSG_ACT_HEADING" -description "$MSG_ACT" -icon "$LOGO" -button1 "$INSTALL_BUTTON" -defaultButton 1 -alignCountdown "right" -timeout "$UPDATE_DELAY" -countdown >"/dev/null"

    # Run updates after either user confirmation or alert timeout.
    run_updates

}

# Displays HUD with updating message and runs all security updates (as defined
# by previous checks).
run_updates () {

    # On Apple Silicon Macs, running softwareupdate --install via script is
    # currently unsupported, so we'll just inform the user with a persistent
    # alert and open the Software Update window for manual update.
    if [[ "$PLATFORM_ARCH" = "arm64" ]]; then

        echo "This is an Apple Silicon Mac with pending updates. Displaying persistent alert until updates are applied..."

        # Loop this check until softwareupdate --list shows no more pending
        # recommended updates.
        while [[ $(/usr/sbin/softwareupdate --list) == *"Recommended: YES"* ]]; do

            # Display persistent HUD with update prompt message.
            echo "Prompting to install updates now and opening System Preferences -> Software Update..."
            "$JAMFHELPER" -windowType "hud" -windowPosition "ur" -icon "$LOGO" -title "$MSG_ACT_NOW_HEADING" -description "$MSG_ACT_NOW" -lockHUD &

            # Open System Preferences - Software Update in current user context.
            CURRENT_USER=$(/usr/bin/stat -f%Su "/dev/console")
            USER_ID=$(/usr/bin/id -u "$CURRENT_USER")
            /bin/launchctl asuser "$USER_ID" open "/System/Library/PreferencePanes/SoftwareUpdate.prefPane"

            # Leave the alert up for 60 seconds before looping.
            sleep 60

            # Clear out jamfHelper alert before looping to prevent pileups.
            echo "Killing any active jamfHelper notifications..."
            /usr/bin/killall jamfHelper 2>"/dev/null"

        done

    else

        # Display HUD with updating message.
        "$JAMFHELPER" -windowType "hud" -windowPosition "ur" -icon "$LOGO" -title "$MSG_UPDATING_HEADING" -description "$MSG_UPDATING" -lockHUD &

        # Run Apple system updates.
        echo "Running $INSTALL_WHICH Apple system updates..."
        # macOS Big Sur requires triggering the restart as part of the softwareupdate action, meaning the script will not be able to run its clean_up functions until the next time it is run.
        if [[ "$OS_MAJOR" -gt 10 ]] && [[ "$INSTALL_WHICH" = "all" ]]; then
          echo "System will restart as soon as the update is finished. Cleanup tasks will run on a subsequent update check."
        fi
        # shellcheck disable=SC2086
        UPDATE_OUTPUT_CAPTURE="$(/usr/sbin/softwareupdate --install --${INSTALL_WHICH} ${RESTART_FLAG} --no-scan 2>&1)"
        echo "Finished running Apple updates."

        # Trigger restart if script found an update which requires it.
        if [[ "$INSTALL_WHICH" = "all" ]]; then
            # Shut down the Mac if BridgeOS received an update requiring it.
            if [[ "$UPDATE_OUTPUT_CAPTURE" == *"select Shut Down from the Apple menu"* ]]; then
                trigger_restart "shut down"
            # Otherwise, restart the Mac.
            else
                trigger_restart "restart"
            fi
        fi

        clean_up

    fi

}

# Initializes plist values and moves all script and LaunchDaemon resources to
# /private/tmp for deletion on a subsequent restart.
clean_up () {

    echo "Killing any active jamfHelper notifications..."
    /usr/bin/killall jamfHelper 2>"/dev/null"

    echo "Cleaning up stored plist values..."
    /usr/bin/defaults delete "$PLIST" 2>"/dev/null"

    echo "Cleaning up script resources..."
    CLEANUP_FILES=(
        "/Library/LaunchDaemons/$BUNDLE_ID.plist"
        "$HELPER_LD"
        "$HELPER_SCRIPT"
        "$SCRIPT_PATH"
    )
    CLEANUP_DIR="/private/tmp/install-or-defer"
    /bin/mkdir "$CLEANUP_DIR"
    for TARGET_FILE in "${CLEANUP_FILES[@]}"; do
        if [[ -e "$TARGET_FILE" ]]; then
            /bin/mv -v "$TARGET_FILE" "$CLEANUP_DIR"
        fi
    done
    if [[ $(/bin/launchctl list) == *"${BUNDLE_ID}_helper"* ]]; then
        echo "Unloading ${BUNDLE_ID}_helper LaunchDaemon..."
        /bin/launchctl remove "${BUNDLE_ID}_helper"
    fi

}

# Restarts or shuts down the system depending on parameter input. Attempts a
# "soft" restart, waits a specified amount of time, and then forces a "hard"
# restart.
trigger_restart () {

    clean_up

    # Immediately attempt a "soft" restart.
    echo "Attempting a \"soft\" $1..."
    CURRENT_USER=$(/usr/bin/stat -f%Su "/dev/console")
    USER_ID=$(/usr/bin/id -u "$CURRENT_USER")
    /bin/launchctl asuser "$USER_ID" osascript -e "tell application \"System Events\" to $1"

    # After specified delay, kill all apps forcibly, which clears the way for
    # an unobstructed restart.
    echo "Waiting $(( HARD_RESTART_DELAY / 60 )) minutes before forcing a \"hard\" $1..."
    /bin/sleep "$HARD_RESTART_DELAY"
    echo "$(( HARD_RESTART_DELAY / 60 )) minutes have elapsed since \"soft\" $1 was attempted. Forcing \"hard\" $1..."

    USER_PIDS=$(pgrep -u "$USER_ID")
    LOGINWINDOW_PID=$(pgrep -x -u "$USER_ID" loginwindow)
    for PID in $USER_PIDS; do
        # Kill all processes except the loginwindow process.
        if [[ "$PID" -ne "$LOGINWINDOW_PID" ]]; then
            kill -9 "$PID"
        fi
    done
    /bin/launchctl asuser "$USER_ID" osascript -e "tell application \"System Events\" to $1"
    # Mac should restart now, ending this script and installing updates.

}

# Ends script without applying any security updates.
exit_without_updating () {

    echo "Updating Jamf Pro inventory..."
    "$JAMF_BINARY" recon

    clean_up

    # Unload main LaunchDaemon. This will likely kill the script.
    if [[ $(/bin/launchctl list) == *"$BUNDLE_ID"* ]]; then
        echo "Unloading $BUNDLE_ID LaunchDaemon..."
        /bin/launchctl remove "$BUNDLE_ID"
    fi
    echo "Script will end here."
    exit 0

}


######################## VALIDATION AND ERROR CHECKING ########################

# Copy all output to the system log for diagnostic purposes.
exec 1> >(/usr/bin/logger -s -t "$(/usr/bin/basename "$0")") 2>&1
echo "Starting $(/usr/bin/basename "$0"). Performing validation and error checking..."

# Define custom $PATH.
PATH="/usr/sbin:/usr/bin:/usr/local/bin:$PATH"

# Filename and path we will use for the auto-generated helper script and LaunchDaemon.
HELPER_SCRIPT="/Library/Scripts/$(/usr/bin/basename "$0" | /usr/bin/sed "s/.sh$//g")_helper.sh"
HELPER_LD="/Library/LaunchDaemons/${BUNDLE_ID}_helper.plist"

# Flag variable for catching show-stopping errors.
BAILOUT=false

# Bail out if the jamfHelper doesn't exist.
JAMFHELPER="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
if [[ ! -x "$JAMFHELPER" ]]; then
    echo "❌ ERROR: The jamfHelper binary must be present in order to run this script."
    BAILOUT=true
fi

# Bail out if the jamf binary doesn't exist.
JAMF_BINARY="/usr/local/bin/jamf"
if [[ ! -e "$JAMF_BINARY" ]]; then
    echo "❌ ERROR: The jamf binary could not be found."
    BAILOUT=true
fi

# Determine macOS version.
OS_MAJOR=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F . '{print $1}')
OS_MINOR=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F . '{print $2}')

# This script has currently been tested in macOS 10.13+ and macOS 11,
# and will exit with error for any other macOS versions.
# When new versions of macOS are released, this logic should be updated after
# the script has been tested successfully.
if [[ "$OS_MAJOR" -lt 10 ]] || [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -lt 13 ]] || [[ "$OS_MAJOR" -gt 11 ]]; then
    echo "❌ ERROR: This script supports macOS 10.13+ and macOS 11, but this Mac is running macOS ${OS_MAJOR}.${OS_MINOR}, unable to proceed."
    BAILOUT=true
fi

# Determine platform architecture.
PLATFORM_ARCH=$(/usr/bin/arch)

# We need to be connected to the internet in order to download updates.
if nc -zw1 swscan.apple.com 443; then
    # Check if a custom CatalogURL is set and if it is available
    # (deprecated in macOS 11+).
    if [[ "$OS_MAJOR" -lt 11 ]]; then
        SU_CATALOG=$(/usr/bin/defaults read "/Library/Managed Preferences/com.apple.SoftwareUpdate" CatalogURL 2>"/dev/null")
        if [[ "$SU_CATALOG" != "None" ]]; then
            if /usr/bin/curl --user-agent "Darwin/$(/usr/bin/uname -r)" -s --head "$SU_CATALOG" | /usr/bin/grep "200 OK" >"/dev/null"; then
                echo "❌ ERROR: Software update catalog can not be reached."
                BAILOUT=true
            fi
        fi
    fi
else
    echo "❌ ERROR: No connection to the Internet."
    BAILOUT=true
fi

# If FileVault encryption or decryption is in progress, installing updates that
# require a restart can cause problems.
if /usr/bin/fdesetup status | /usr/bin/grep -q "in progress"; then
    echo "❌ ERROR: FileVault encryption or decryption is in progress."
    BAILOUT=true
fi

# If any of the errors above are present, bail out of the script now.
if [[ "$BAILOUT" = "true" ]]; then
    # Checks for StartInterval definition in LaunchDaemon.
    START_INTERVAL=$(/usr/bin/defaults read "/Library/LaunchDaemons/$BUNDLE_ID.plist" StartInterval 2>"/dev/null")
    if [[ -n "$START_INTERVAL" ]]; then
        echo "Stopping due to errors, but will try again in $(convert_seconds "$START_INTERVAL")."
    else
        echo "Stopping due to errors."
    fi
    exit 1
else
    echo "Validation and error checking passed. Starting main process..."
fi


################################ MAIN PROCESS #################################

# Validate logo file. If no logo is provided or if the file cannot be found at
# specified path, default to the Software Update preference pane icon.
if [[ -z "$LOGO" ]] || [[ ! -f "$LOGO" ]]; then
    echo "No logo provided, or no image file exists at specified path. Using Software Update icon."
    # macOS High Sierra is the only supported macOS that does not have a
    # Software Update prefPane, so we'll use the Software Update.app icon
    # instead.
    if [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -eq 13 ]]; then
        LOGO="/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns"
    else
        LOGO="/System/Library/PreferencePanes/SoftwareUpdate.prefPane/Contents/Resources/SoftwareUpdate.icns"
    fi
fi

# Validate max deferral time and whether to skip deferral. To customize these
# values, make a configuration profile enforcing the MaxDeferralTime (in
# seconds) and SkipDeferral (boolean) attributes in $BUNDLE_ID to settings of
# your choice.
SKIP_DEFERRAL=$(/usr/bin/defaults read "/Library/Managed Preferences/$BUNDLE_ID" SkipDeferral 2>"/dev/null")
if [[ "$SKIP_DEFERRAL" = "True" ]]; then
    MAX_DEFERRAL_TIME=0
else
    MAX_DEFERRAL_TIME_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/$BUNDLE_ID" MaxDeferralTime 2>"/dev/null")
    if (( MAX_DEFERRAL_TIME_CUSTOM > 0 )); then
        MAX_DEFERRAL_TIME="$MAX_DEFERRAL_TIME_CUSTOM"
    else
        echo "Max deferral time undefined, or not set to a positive integer. Using default value."
    fi
fi
echo "Maximum deferral time: $(convert_seconds "$MAX_DEFERRAL_TIME")"

# Check for updates, exit if none found, otherwise cache locally and continue.
check_for_updates

# Perform first run tasks, including calculating deadline.
FORCE_DATE=$(/usr/bin/defaults read "$PLIST" UpdatesForcedAfter 2>"/dev/null")
if [[ -z $FORCE_DATE || $FORCE_DATE -gt $(( $(/bin/date +%s) + MAX_DEFERRAL_TIME )) ]]; then
    FORCE_DATE=$(( $(/bin/date +%s) + MAX_DEFERRAL_TIME ))
    /usr/bin/defaults write "$PLIST" UpdatesForcedAfter -int $FORCE_DATE
fi

# Calculate how much time remains until deferral deadline.
DEFER_TIME_LEFT=$(( FORCE_DATE - $(/bin/date +%s) ))
echo "Deferral deadline: $(/bin/date -jf "%s" "+%Y-%m-%d %H:%M:%S" "$FORCE_DATE")"
echo "Time remaining: $(convert_seconds $DEFER_TIME_LEFT)"

# Get the "deferred until" timestamp, if one exists.
DEFERRED_UNTIL=$(/usr/bin/defaults read "$PLIST" UpdatesDeferredUntil 2>"/dev/null")
if [[ -n "$DEFERRED_UNTIL" ]] && (( DEFERRED_UNTIL > $(/bin/date +%s) && FORCE_DATE > DEFERRED_UNTIL )); then
    # If the policy ran recently and was deferred, we need to respect that
    # "defer until" timestamp, as long as it is earlier than the deferral
    # deadline.
    echo "The next prompt is deferred until after $(/bin/date -jf "%s" "+%Y-%m-%d %H:%M:%S" "$DEFERRED_UNTIL")."
    exit 0
fi

# Make a note of the time before displaying the prompt.
PROMPT_START=$(/bin/date +%s)

# If defer time remains, display the prompt. If not, install and restart.
if (( DEFER_TIME_LEFT > 0 )); then

    # Substitute the correct number of hours remaining.
    # If time left is more than 2 days, use days
    if (( DEFER_TIME_LEFT > 172800 )); then
        MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER//%DEFER_HOURS%/$(( DEFER_TIME_LEFT / 86400 )) days}"
        MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER// 1 days/ 1 day}"
    # If time left is more than 2 hours, use hours
    elif (( DEFER_TIME_LEFT > 7200 )); then
        MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER//%DEFER_HOURS%/$(( DEFER_TIME_LEFT / 3600 )) hours}"
        MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER// 1 hours/ 1 hour}"
    # If time left is more than 1 minute, use minutes
    elif (( DEFER_TIME_LEFT > 60 )); then
        MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER//%DEFER_HOURS% hours/$(( DEFER_TIME_LEFT / 60 )) minutes}"
        MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER// 1 minutes/ 1 minute}"
    else
        MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER//after %DEFER_HOURS% hours/very soon}"
    fi

    # Substitute the deadline date.
    MSG_ACT_OR_DEFER="${MSG_ACT_OR_DEFER//%DEADLINE_DATE%/$(/bin/date -jf "%s" "+%b %d, %Y at %I:%M%p" "$FORCE_DATE")}"
    MSG_ACT_OR_DEFER_HEADING="${MSG_ACT_OR_DEFER_HEADING//%DEADLINE_DATE%/$(/bin/date -jf "%s" "+%b %d, %Y" "$FORCE_DATE")}"

    # Determine whether to include the "you may defer" wording.
    if (( EACH_DEFER > DEFER_TIME_LEFT )); then
        # Remove "{{" and "}}" including all the text between.
        MSG_ACT_OR_DEFER="$(echo "$MSG_ACT_OR_DEFER" | /usr/bin/sed 's/{{.*}}//g')"
    else
        # Just remove "{{" and "}}" but leave the text between.
        MSG_ACT_OR_DEFER="$(echo "$MSG_ACT_OR_DEFER" | /usr/bin/sed 's/[{{|}}]//g')"
    fi

    # Show the install/defer prompt.
    echo "Prompting to install updates now or defer..."
    PROMPT=$("$JAMFHELPER" -windowType "utility" -windowPosition "ur" -icon "$LOGO" -title "$MSG_ACT_OR_DEFER_HEADING" -description "$MSG_ACT_OR_DEFER" -button1 "$INSTALL_BUTTON" -button2 "$DEFER_BUTTON" -defaultButton 2 -timeout 3600 -startlaunchd 2>"/dev/null")
    JAMFHELPER_PID=$!

    # Make a note of the amount of time the prompt was shown onscreen.
    PROMPT_END=$(/bin/date +%s)
    PROMPT_ELAPSED_SEC=$(( PROMPT_END - PROMPT_START ))

    # Generate a duration string that will be used in log output.
    if [[ -n $PROMPT_ELAPSED_SEC && $PROMPT_ELAPSED_SEC -eq 0 ]]; then
        PROMPT_ELAPSED_STR="immediately"
    elif [[ -n $PROMPT_ELAPSED_SEC ]]; then
        PROMPT_ELAPSED_STR="after $(convert_seconds "$PROMPT_ELAPSED_SEC")"
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
        echo "❌ ERROR: jamfHelper returned code $PROMPT $PROMPT_ELAPSED_STR. It's unlikely that the user responded that quickly."
        exit 1
    elif [[ -n $PROMPT && $DEFER_TIME_LEFT -gt 0 && $PROMPT -eq 0 ]]; then
        echo "User clicked Run Updates $PROMPT_ELAPSED_STR."
        /usr/bin/defaults delete "$PLIST" UpdatesDeferredUntil 2>"/dev/null"
        run_updates
    elif [[ -n $PROMPT && $DEFER_TIME_LEFT -gt 0 && $PROMPT -eq 1 ]]; then
        # Kill the jamfHelper prompt.
        kill -9 $JAMFHELPER_PID
        echo "❌ ERROR: jamfHelper was not able to launch $PROMPT_ELAPSED_STR."
        exit 1
    elif [[ -n $PROMPT && $DEFER_TIME_LEFT -gt 0 && $PROMPT -eq 2 ]]; then
        echo "User clicked Defer $PROMPT_ELAPSED_STR."
        NEXT_PROMPT=$(( $(/bin/date +%s) + EACH_DEFER ))
        if (( FORCE_DATE < NEXT_PROMPT )); then
            NEXT_PROMPT="$FORCE_DATE"
        fi
        /usr/bin/defaults write "$PLIST" UpdatesDeferredUntil -int "$NEXT_PROMPT"
        echo "Next prompt will appear after $(/bin/date -jf "%s" "+%Y-%m-%d %H:%M:%S" "$NEXT_PROMPT")."
    elif [[ -n $PROMPT && $DEFER_TIME_LEFT -gt 0 && $PROMPT -eq 239 ]]; then
        echo "User deferred by exiting jamfHelper $PROMPT_ELAPSED_STR."
        NEXT_PROMPT=$(( $(/bin/date +%s) + EACH_DEFER ))
        if (( FORCE_DATE < NEXT_PROMPT )); then
            NEXT_PROMPT="$FORCE_DATE"
        fi
        /usr/bin/defaults write "$PLIST" UpdatesDeferredUntil -int "$NEXT_PROMPT"
        echo "Next prompt will appear after $(/bin/date -jf "%s" "+%Y-%m-%d %H:%M:%S" "$NEXT_PROMPT")."
    elif [[ -n $PROMPT && $DEFER_TIME_LEFT -gt 0 && $PROMPT -gt 2 ]]; then
        # Kill the jamfHelper prompt.
        kill -9 $JAMFHELPER_PID
        echo "❌ ERROR: jamfHelper produced an unexpected value (code $PROMPT) $PROMPT_ELAPSED_STR."
        exit 1
    elif [[ -z $PROMPT ]]; then # $PROMPT is not defined
        # Kill the jamfHelper prompt.
        kill -9 $JAMFHELPER_PID
        echo "❌ ERROR: jamfHelper returned no value $PROMPT_ELAPSED_STR. Run Updates/Defer response was not captured. This may be because the user logged out without clicking Run Updates/Defer."
        exit 1
    else
        # Kill the jamfHelper prompt.
        kill -9 $JAMFHELPER_PID
        echo "❌ ERROR: Something went wrong. Check the jamfHelper return code ($PROMPT) and prompt elapsed seconds ($PROMPT_ELAPSED_SEC) for further information."
        exit 1
    fi

else
    # If no deferral time remains, force installation of updates now.
    echo "No deferral time remains."
    display_act_msg
fi

exit 0

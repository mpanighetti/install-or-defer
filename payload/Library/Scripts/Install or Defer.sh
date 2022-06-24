#!/bin/bash
# shellcheck disable=SC2001

###
#
#            Name:  Install or Defer.sh
#     Description:  This script prompts users to install Apple system updates
#                   that the IT department has deemed "critical." Users will
#                   have the option to install the listed updates or defer for
#                   the established time period, with a LaunchDaemon
#                   periodically triggering the script to rerun. After a
#                   specified amount of time, alerts will be displayed until all
#                   required updates have been run, and if updates requiring a
#                   restart were run, the system restarts automatically.
#                   https://github.com/mpanighetti/install-or-defer
#         Authors:  Mario Panighetti and Elliot Jordan
#         Created:  2017-03-09
#   Last Modified:  2022-06-21
#         Version:  5.0.6
#
###


########################## FILE PATHS AND IDENTIFIERS #########################

# Path to a plist file that is used to store settings locally. Omit ".plist"
# extension.
PLIST="/Library/Preferences/com.github.mpanighetti.install-or-defer"

# The identifier of the LaunchDaemon that is used to call this script, which
# should match the file name in the payload/Library/LaunchDaemons folder. Omit
# ".plist" extension.
BUNDLE_ID="com.github.mpanighetti.install-or-defer"

# The file path of this script. Used to assist with resource file clean-up.
SCRIPT_PATH="/Library/Scripts/Install or Defer.sh"


################################## MESSAGING ##################################

# The messages below use the following dynamic substitutions wherever found:
#   - %DEADLINE_DATE% will be automatically replaced with the deadline date and
#     time before updates are enforced.
#   - %DEFER_HOURS% will be automatically replaced by the number of days, hours,
#     or minutes remaining in the deferral period.
#   - %SUPPORT_CONTACT% will be automatically replaced with "IT" or a custom
#     value set via configuration profile key.
#   - %UPDATE_LIST% will be automatically replaced with a comma-separated list
#     of all recommended updates found in a Software Update check.
#   - The section in the {{double curly brackets}} will be removed when this
#     message is displayed for the final time before the deferral deadline.
#   - The sections in the <<double comparison operators>> will be removed if a
#     restart is not required for the pending updates.

# The message users will receive when updates are available, shown above the
# install and defer buttons.
MSG_INSTALL_OR_DEFER_HEADING="Updates are available"
MSG_INSTALL_OR_DEFER="Your Mac needs to install updates for %UPDATE_LIST% by %DEADLINE_DATE%.

Please save your work and install all available updates. {{If now is not a good time, you may defer to delay this message until later. }}These updates will be required after %DEFER_HOURS%<<, forcing your Mac to restart after they are installed>>.

Please contact %SUPPORT_CONTACT% for any questions."

# The message users will receive after the deferral deadline has been reached.
MSG_INSTALL_HEADING="Please install updates now"
MSG_INSTALL="Your Mac is about to install updates for %UPDATE_LIST%<< and restart>>.

Please save your work and install all available updates before the deadline.<< Your Mac will restart when all updates are finished installing.>>

Please contact %SUPPORT_CONTACT% for any questions."

# The message users will receive when a manual update install action is required.
MSG_INSTALL_NOW_HEADING="Updates are available"
MSG_INSTALL_NOW="Your Mac needs to install updates for %UPDATE_LIST%<< which require a restart>>.

Please save your work, open System Preferences -> Software Update, and install all available updates.<< Your Mac will restart when all updates are finished installing.>>

Please contact %SUPPORT_CONTACT% for any questions."

# The message users will receive while updates are installing in the background.
MSG_UPDATING_HEADING="Installing updates..."
MSG_UPDATING="Installing updates for %UPDATE_LIST% in the background.<< Your Mac will restart automatically when this is finished.>> Please contact %SUPPORT_CONTACT% for any questions."


######################### CURRENT USER CONTEXT ################################

# Identify current user and UID. Used for any functions that need to run in the
# context of the logged-in user account.
CURRENT_USER=$(/usr/bin/stat -f%Su "/dev/console")
USER_ID=$(/usr/bin/id -u "$CURRENT_USER")


######################## CONFIGURATION PROFILE SETTINGS #######################

# Checks for whether any custom settings have been applied via a configuration
# profile, in order to override script defaults with these custom values. To
# customize these values, make a configuration profile for $BUNDLE_ID and make
# new selections for each specified key.

### ALERTING ###
# - InstallButtonLabel (String). The label of the install button. Defaults to
# "Install".
INSTALL_BUTTON_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" InstallButtonLabel 2>"/dev/null")
# - DeferButtonLabel (String). The label of the defer button. Defaults to
# "Defer".
DEFER_BUTTON_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" DeferButtonLabel 2>"/dev/null")
# - DisablePostInstallAlert (Boolean). Whether to suppress the persistent alert
# to run updates. Defaults to False. If set to True, clicking the install button
# will only launch the Software Update pane without displaying a persistent
# alert to upgrade, until the deadline date is reached.
DISABLE_POST_INSTALL_ALERT_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" DisablePostInstallAlert 2>"/dev/null")
# - MessagingLogo (String). File path to a logo that will be used in messaging.
# Recommend 512px, PNG format. Defaults to the Software Update icon.
MESSAGING_LOGO_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" MessagingLogo 2>"/dev/null")
# - SupportContact (String). Contact information for technical support included
# in messaging alerts. Recommend using a team name (e.g. "Technical Support"),
# email address (e.g. "support@contoso.com"), or chat channel (e.g.
# "#technical-support"). Defaults to "IT".
SUPPORT_CONTACT_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" SupportContact 2>"/dev/null")

### TIMING ###
# - DeferralPeriod (Integer). Number of seconds between when the user clicks
# "Defer" and the next prompt appears. Defaults to 14400 = 4 hours.
DEFERRAL_PERIOD_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" DeferralPeriod 2>"/dev/null")
# - HardRestartDelay (Integer). Number of seconds to wait between attempting a
# soft restart and forcing a restart. This value must be less than the
# MaxDeferralTime value. Defaults to 300 (5 minutes).
HARD_RESTART_DELAY_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" HardRestartDelay 2>"/dev/null")
# - MaxDeferralTime (Integer). Number of seconds between the first script run
# and the updates being enforced. Defaults to 259200 (3 days).
MAX_DEFERRAL_TIME_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" MaxDeferralTime 2>"/dev/null")
# - PromptTimeout (Integer). Number of seconds to wait before timing out the
# Install or Defer prompt. This value must be less than the DeferralPeriod
# value. Defaults to 3600 (1 hour).
PROMPT_TIMEOUT_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" PromptTimeout 2>"/dev/null")
# - SkipDeferral (Boolean). Whether to bypass deferral time entirely and skip
# straight to update enforcement (useful for script testing purposes). Defaults
# to False. If set to True, this setting supersedes any values set for
# MaxDeferralTime.
SKIP_DEFERRAL_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" SkipDeferral 2>"/dev/null")
# - UpdateDelay (Integer). Number of seconds to wait between displaying the
# "install updates" message and applying updates, then attempting a soft
# restart. Defaults to 600 (10 minutes).
UPDATE_DELAY_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" UpdateDelay 2>"/dev/null")
# - WorkdayStartHour (Integer). The hour that a workday starts in your
# organization. This value must be an integer between 0 and 22, and the end hour
# must be later than the start hour. If the update deadline falls within this
# window of time, it will be moved forward to occur at the end of the workday.
# If WorkdayStartHour or WorkdayEndHour are undefined, deadlines will be
# scheduled based on maximum deferral time and not account for the time of day
# that the deadline lands.
WORKDAY_START_HR_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" WorkdayStartHour 2>"/dev/null")
# - WorkdayEndHour (Integer). The hour that a workday ends in your organization.
# This value must be an integer between 1 and 23, and the end hour must be later
# than the start hour. If the update deadline falls within this window of time,
# it will be moved forward to occur at the end of the workday. If
# WorkdayStartHour or WorkdayEndHour are undefined, deadlines will be scheduled
# based on maximum deferral time and not account for the time of day that the
# deadline lands.
WORKDAY_END_HR_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" WorkdayEndHour 2>"/dev/null")

### BACKEND ###
# - DiagnosticLog (Boolean). Whether to write to a persistent log file at
# /var/log/install-or-defer.log. If undefined or set to false, the script writes
# all output to the system log for live diagnostics.
DIAGNOSTIC_LOG_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" DiagnosticLog 2>"/dev/null")
# - ManualUpdates (Boolean). Whether to prompt users to run updates manually via
# System Preferences. This is always the behavior on Apple Silicon Macs and
# cannot be overridden. If undefined or set to false on Intel Macs, the script
# triggers updates via scripted softwareupdate commands.
MANUAL_UPDATES_CUSTOM=$(/usr/bin/defaults read "/Library/Managed Preferences/${BUNDLE_ID}" ManualUpdates 2>"/dev/null")


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

# Deletes cached results of previous software update checks, force-restarts the
# com.apple.softwareupdated system service, and sleeps for a period specified by
# the function run command. Necessary to make repeated update checks more
# reliable in macOS Big Sur and later.
restart_softwareupdate_daemon () {

    if [[ "$OS_MAJOR" -ge 11 ]]; then
        echo "Deleting cached update check data..."
        /usr/bin/defaults delete "/Library/Preferences/com.apple.SoftwareUpdate.plist"
        /bin/rm -f "/Library/Preferences/com.apple.SoftwareUpdate.plist"
        # Write macOS beta channel catalog URL back to the plist if previously defined.
        if [[ -n "$SOFTWAREUPDATE_CATALOG_URL" ]]; then
            /usr/bin/defaults write "/Library/Preferences/com.apple.SoftwareUpdate" CatalogURL -string "$SOFTWAREUPDATE_CATALOG_URL"
            echo "Restored macOS beta channel catalog URL."
        fi
        echo "Restarting com.apple.softwareupdated system service..."
        /bin/launchctl kickstart -k "system/com.apple.softwareupdated"
        sleep "${1}"
    fi

}

# Checks for recommended macOS updates, or exits if no such updates are
# available.
check_for_updates () {

    restart_softwareupdate_daemon "30"
    echo "Checking for pending system updates..."
    UPDATE_CHECK="$(/usr/sbin/softwareupdate --list 2>&1)"

    # Determine whether any recommended macOS updates are available.
    # If a restart is required for any pending updates, then install all
    # available software updates.
    if [[ "$UPDATE_CHECK" =~ (Action: restart|\[restart\]) ]]; then
        INSTALL_WHICH="all"
        RESTART_FLAG="--restart"
        # Remove "<<" and ">>" but leave the text between
        # (retains restart warnings).
        MSG_INSTALL_OR_DEFER="$(echo "$MSG_INSTALL_OR_DEFER" | /usr/bin/sed 's/[\<\<|\>\>]//g')"
        MSG_INSTALL="$(echo "$MSG_INSTALL" | /usr/bin/sed 's/[\<\<|\>\>]//g')"
        MSG_INSTALL_NOW="$(echo "$MSG_INSTALL_NOW" | /usr/bin/sed 's/[\<\<|\>\>]//g')"
        MSG_UPDATING="$(echo "$MSG_UPDATING" | /usr/bin/sed 's/[\<\<|\>\>]//g')"
    # Otherwise, only target recommended updates.
    elif [[ "$UPDATE_CHECK" =~ (Recommended: YES|\[recommended\]) ]]; then
        INSTALL_WHICH="recommended"
        RESTART_FLAG=""
        # Remove "<<" and ">>" including all the text between
        # (removes restart warnings).
        MSG_INSTALL_OR_DEFER="$(echo "$MSG_INSTALL_OR_DEFER" | /usr/bin/sed 's/\<\<.*\>\>//g')"
        MSG_INSTALL="$(echo "$MSG_INSTALL" | /usr/bin/sed 's/\<\<.*\>\>//g')"
        MSG_INSTALL_NOW="$(echo "$MSG_INSTALL_NOW" | /usr/bin/sed 's/\<\<.*\>\>//g')"
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
        # Omit the Version column if the update list includes a "macOS" update,
        # as those updates tend to already include version information in the
        # Title column.
        # Note that this will omit version strings from any other pending
        # updates, e.g. Safari.
        if echo "$UPDATE_CHECK" | /usr/bin/grep -q "macOS"; then
            UPDATE_LIST="$(echo "$UPDATE_CHECK" | /usr/bin/awk -F'[:,]' '/Title:/ {print $2}')"
        else
            UPDATE_LIST="$(echo "$UPDATE_CHECK" | /usr/bin/awk -F'[:,]' '/Title:/ {print $2 $4}')"
        fi
    fi
    # Convert update list from multiline to comma-separated list.
    UPDATE_LIST="$(echo "$UPDATE_LIST" | /usr/bin/tr '\n' ',' | /usr/bin/sed 's/^ *//; s/,/, /g; s/, $//')"
    # Reformat update list to replace last comma with ", and" or " and" as
    # needed for legibility. In this house, we use Oxford commas.
    COMMA_COUNT="$(echo "$UPDATE_LIST" | /usr/bin/tr -dc ',' | /usr/bin/wc -c | /usr/bin/bc)"
    if [[ "$COMMA_COUNT" -gt 1 ]]; then
        UPDATE_LIST="$(echo "$UPDATE_LIST" | sed 's/\(.*\),/\1, and/')"
    elif [[ "$COMMA_COUNT" -eq 1 ]]; then
        UPDATE_LIST="$(echo "$UPDATE_LIST" | sed 's/\(.*\),/\1 and/')"
    fi
    # Populate the list of pending updates in message text.
    MSG_INSTALL_OR_DEFER="$(echo "$MSG_INSTALL_OR_DEFER" | /usr/bin/sed "s/%UPDATE_LIST%/${UPDATE_LIST}/")"
    MSG_INSTALL="$(echo "$MSG_INSTALL" | /usr/bin/sed "s/%UPDATE_LIST%/${UPDATE_LIST}/")"
    MSG_INSTALL_NOW="$(echo "$MSG_INSTALL_NOW" | /usr/bin/sed "s/%UPDATE_LIST%/${UPDATE_LIST}/")"
    MSG_UPDATING="$(echo "$MSG_UPDATING" | /usr/bin/sed "s/%UPDATE_LIST%/${UPDATE_LIST}/")"

}

# Displays an onscreen message instructing the user to apply updates.
# This function is invoked after the deferral deadline passes.
display_act_msg () {

    # Display persistent HUD with update prompt message.
    echo "Killing any active jamfHelper notifications..."
    /usr/bin/killall jamfHelper 2>"/dev/null"
    echo "Displaying \"install updates\" message for $(( UPDATE_DELAY / 60 )) minutes before automatically applying updates..."
    "$JAMFHELPER" -windowType "utility" -windowPosition "ur" -title "$MSG_INSTALL_HEADING" -description "$MSG_INSTALL" -icon "$MESSAGING_LOGO" -button1 "$INSTALL_BUTTON" -defaultButton 1 -alignCountdown "right" -timeout "$UPDATE_DELAY" -countdown >"/dev/null"

    # Install updates after either user confirmation or alert timeout.
    install_updates

}

# Opens System Preferences -> Software Update, optionally prompting user to
# install updates via HUD message and automatically applying the update when
# able.
install_updates () {

    # If manual updates are enabled, inform the user of required updates and
    # open the Software Update window.
    if [[ "$MANUAL_UPDATES" = "True" ]]; then

        echo "Script has been configured to have user run updates manually."
        # If persistent notification is disabled and there is still deferral
        # time left, just open Software Update once.
        if [[ "$DISABLE_POST_INSTALL_ALERT_CUSTOM" -eq 1 ]] && (( DEFER_TIME_LEFT > 0 )) ; then
        echo "Persistent alerting is disabled with deferral time remaining. Opening Software Update a single time..."

        # Open System Preferences -> Software Update in current user context.
        /bin/launchctl asuser "$USER_ID" open "/System/Library/PreferencePanes/SoftwareUpdate.prefPane"

        # Display a persistent alert while opening Software Update and repeat
        # until the user manually runs updates.
        else
            echo "Displaying persistent alert until updates are applied..."

            # Loop this check until softwareupdate --list shows no more pending
            # recommended updates.
            while [[ $(/usr/sbin/softwareupdate --list) == *"Recommended: YES"* ]]; do

                # Clear out jamfHelper alert to prevent pileups.
                echo "Killing any active jamfHelper notifications..."
                /usr/bin/killall jamfHelper 2>"/dev/null"

                # Display persistent HUD with update prompt message.
                echo "Prompting to install updates now and opening System Preferences -> Software Update..."
                "$JAMFHELPER" -windowType "hud" -windowPosition "ur" -icon "$MESSAGING_LOGO" -title "$MSG_INSTALL_NOW_HEADING" -description "$MSG_INSTALL_NOW" -lockHUD &

                # Open System Preferences -> Software Update in current user context.
                /bin/launchctl asuser "$USER_ID" open "/System/Library/PreferencePanes/SoftwareUpdate.prefPane"

                # Leave the alert up for 60 seconds before looping.
                sleep 60

            done

        fi

    else
        # Display HUD with updating message.
        "$JAMFHELPER" -windowType "hud" -windowPosition "ur" -icon "$MESSAGING_LOGO" -title "$MSG_UPDATING_HEADING" -description "$MSG_UPDATING" -lockHUD &

        # Install Apple system updates.
        restart_softwareupdate_daemon "30"
        echo "Installing ${INSTALL_WHICH} Apple system updates..."
        # macOS Big Sur requires triggering the restart as part of the
        # softwareupdate action, meaning the script will not be able to run its
        # clean_up functions until the next time it is run.
        if [[ "$OS_MAJOR" -gt 10 ]] && [[ "$INSTALL_WHICH" = "all" ]]; then
            echo "System will restart as soon as the update is finished. Cleanup tasks will run on a subsequent update check."
        fi
        # shellcheck disable=SC2086
        UPDATE_OUTPUT_CAPTURE="$(/usr/sbin/softwareupdate --install --"${INSTALL_WHICH}" ${RESTART_FLAG} --no-scan 2>&1)"
        echo "Finished installing Apple updates."

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
        "/Library/LaunchDaemons/${BUNDLE_ID}.plist"
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
    echo "Attempting a \"soft\" ${1}..."
    /bin/launchctl asuser "$USER_ID" osascript -e "tell application \"System Events\" to ${1}"

    # After specified delay, kill all apps forcibly, which clears the way for
    # an unobstructed restart.
    echo "Waiting $(( HARD_RESTART_DELAY / 60 )) minutes before forcing a \"hard\" ${1}..."
    /bin/sleep "$HARD_RESTART_DELAY"
    echo "$(( HARD_RESTART_DELAY / 60 )) minutes have elapsed since \"soft\" ${1} was attempted. Forcing \"hard\" ${1}..."

    USER_PIDS=$(pgrep -u "$USER_ID")
    LOGINWINDOW_PID=$(pgrep -x -u "$USER_ID" loginwindow)
    for PID in $USER_PIDS; do
        # Kill all processes except the loginwindow process.
        if [[ "$PID" -ne "$LOGINWINDOW_PID" ]]; then
            kill -9 "$PID"
        fi
    done
    /bin/launchctl asuser "$USER_ID" osascript -e "tell application \"System Events\" to ${1}"
    # Mac should restart now, ending this script and installing updates.

}

# Ends script without applying any security updates.
exit_without_updating () {

    echo "Updating Jamf Pro inventory..."
    "$JAMF_BINARY" recon

    clean_up

    # Unload main LaunchDaemon. This will likely kill the script.
    if [[ $(/bin/launchctl list) == *"${BUNDLE_ID}"* ]]; then
        echo "Unloading ${BUNDLE_ID} LaunchDaemon..."
        /bin/launchctl remove "$BUNDLE_ID"
    fi
    echo "Script will end here."
    exit 0

}


#################################### TIMING ###################################

echo "Calculating script timing..."

# Set maximum deferral to 0 if deferral skip is enabled.
if [[ "$SKIP_DEFERRAL_CUSTOM" -eq 1 ]]; then
    MAX_DEFERRAL_TIME=0
else
    # Check for a custom maximum deferral time, otherwise default to 3 days.
    if (( MAX_DEFERRAL_TIME_CUSTOM > 0 )); then
        MAX_DEFERRAL_TIME="$MAX_DEFERRAL_TIME_CUSTOM"
    else
        MAX_DEFERRAL_TIME=$(( 60 * 60 * 24 * 3 )) # (259200 seconds = 3 days)
    fi
fi
echo "Maximum deferral time: $(convert_seconds "$MAX_DEFERRAL_TIME")"

if (( DEFERRAL_PERIOD_CUSTOM > 0 && DEFERRAL_PERIOD_CUSTOM < MAX_DEFERRAL_TIME )); then
    EACH_DEFER="$DEFERRAL_PERIOD_CUSTOM"
else
    EACH_DEFER=$(( 60 * 60 * 4 )) # (14400 = 4 hours)
fi
echo "Deferral period: $(convert_seconds "$EACH_DEFER")"

if (( PROMPT_TIMEOUT_CUSTOM > 0 && PROMPT_TIMEOUT_CUSTOM < EACH_DEFER )); then
    PROMPT_TIMEOUT="$PROMPT_TIMEOUT_CUSTOM"
else
    PROMPT_TIMEOUT=$(( 60 * 60 )) # (3600 = 1 hour)
fi
echo "Prompt timeout: $(convert_seconds "$PROMPT_TIMEOUT")"

if (( UPDATE_DELAY_CUSTOM > 0 )); then
    UPDATE_DELAY="$UPDATE_DELAY_CUSTOM"
else
    UPDATE_DELAY=$(( 60 * 10 )) # (600 = 10 minutes)
fi
echo "Update delay: $(convert_seconds "$UPDATE_DELAY")"

if (( HARD_RESTART_DELAY_CUSTOM > 0 )); then
    HARD_RESTART_DELAY="$HARD_RESTART_DELAY_CUSTOM"
else
    HARD_RESTART_DELAY=$(( 60 * 5 )) # (300 = 5 minutes)
fi
echo "Hard restart delay: $(convert_seconds "$HARD_RESTART_DELAY")"


######################## VALIDATION AND ERROR CHECKING ########################

# Checks for a custom diagnostic log preference,
# otherwise defaults to copying all output to the system log.
if [[ "$DIAGNOSTIC_LOG_CUSTOM" -eq 1 ]]; then
    exec 1>>"/var/log/install-or-defer.log" 2>&1
else
    exec 1> >(/usr/bin/logger -s -t "$(/usr/bin/basename "$0")") 2>&1
fi
echo "Starting $(/usr/bin/basename "$0"). Performing validation and error checking..."

# Define custom $PATH.
PATH="/usr/sbin:/usr/bin:/usr/local/bin:${PATH}"

# Filename and path we will use for the auto-generated helper script and
# LaunchDaemon.
HELPER_SCRIPT="/Library/Scripts/$(/usr/bin/basename "$0" | /usr/bin/sed "s/.sh$//g")_helper.sh"
HELPER_LD="/Library/LaunchDaemons/${BUNDLE_ID}_helper.plist"

# Flag variable for catching show-stopping errors.
BAILOUT="false"

# Bail out if the jamfHelper doesn't exist.
JAMFHELPER="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
if [[ ! -x "$JAMFHELPER" ]]; then
    echo "❌ ERROR: The jamfHelper binary must be present in order to run this script."
    BAILOUT="true"
fi

# Bail out if the jamf binary doesn't exist.
JAMF_BINARY="/usr/local/bin/jamf"
if [[ ! -e "$JAMF_BINARY" ]]; then
    echo "❌ ERROR: The jamf binary could not be found."
    BAILOUT="true"
fi

# Determine macOS version.
OS_MAJOR=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F . '{print $1}')
OS_MINOR=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F . '{print $2}')

# This script has currently been tested in macOS 10.14+, macOS 11, and macOS 12.
# It will exit with error for any other macOS versions.
# When new versions of macOS are released, this logic should be updated after
# the script has been tested successfully.
if [[ "$OS_MAJOR" -lt 10 ]] || [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -lt 14 ]] || [[ "$OS_MAJOR" -gt 12 ]]; then
    echo "❌ ERROR: This script supports macOS 10.14+, macOS 11, and macOS 12, but this Mac is running macOS ${OS_MAJOR}.${OS_MINOR}, unable to proceed."
    BAILOUT="true"
fi

# Determine platform architecture.
PLATFORM_ARCH="$(/usr/bin/arch)"

# Determine software update custom catalog URL if defined. Used for running beta
# macOS releases. This URL needs to be retained in
# /Library/Preferences/com.apple.SoftwareUpdate.plist if that file is reset in
# the restart_softwareupdate_daemon function.
SOFTWAREUPDATE_CATALOG_URL=$(/usr/bin/defaults read "/Library/Preferences/com.apple.SoftwareUpdate" CatalogURL 2>"/dev/null")
if [[ -n "$SOFTWAREUPDATE_CATALOG_URL" ]]; then
    echo "Found macOS beta channel catalog URL, will retain this setting whenever com.apple.SoftwareUpdate is reset: ${SOFTWAREUPDATE_CATALOG_URL}"
fi

# We need to be connected to the internet in order to download updates.
if nc -zw1 "swscan.apple.com" 443; then
    # Check if a software update custom catalog URL is set as a managed
    # preference and if it is available (deprecated in macOS Big Sur and later).
    if [[ "$OS_MAJOR" -lt 11 ]]; then
        SOFTWAREUPDATE_CATALOG_URL_MANAGED=$(/usr/bin/defaults read "/Library/Managed Preferences/com.apple.SoftwareUpdate" CatalogURL 2>"/dev/null")
        if [[ "$SOFTWAREUPDATE_CATALOG_URL_MANAGED" != "None" ]]; then
            if /usr/bin/curl --user-agent "Darwin/$(/usr/bin/uname -r)" -s --head "$SOFTWAREUPDATE_CATALOG_URL_MANAGED" | /usr/bin/grep "200 OK" >"/dev/null"; then
                echo "❌ ERROR: Software update catalog can not be reached."
                BAILOUT="true"
            fi
        fi
    fi
else
    echo "❌ ERROR: No connection to the Internet."
    BAILOUT="true"
fi

# If FileVault encryption or decryption is in progress, installing updates that
# require a restart can cause problems.
if /usr/bin/fdesetup status | /usr/bin/grep -q "in progress"; then
    echo "❌ ERROR: FileVault encryption or decryption is in progress."
    BAILOUT="true"
fi

# Validate workday start and end hours (if defined).
if [[ -n "$WORKDAY_START_HR_CUSTOM" ]] && [[ -n "$WORKDAY_END_HR_CUSTOM" ]]; then
    if (( 0 <= WORKDAY_START_HR_CUSTOM && WORKDAY_START_HR_CUSTOM < WORKDAY_END_HR_CUSTOM && WORKDAY_END_HR_CUSTOM < 24 )); then
        echo "Workday: ${WORKDAY_START_HR_CUSTOM}:00-${WORKDAY_END_HR_CUSTOM}:00"
    else
        echo "❌ ERROR: There is a logical disconnect between the workday start hour (${WORKDAY_START_HR_CUSTOM}) and end hour (${WORKDAY_END_HR_CUSTOM}). Please update these values to meet script requirements (start hour ≥ 0, start hour < end hour, end hour < 24)."
        BAILOUT="true"
    fi
fi

# If any of the errors above are present, bail out of the script now.
if [[ "$BAILOUT" = "true" ]]; then
    # Checks for StartInterval definition in LaunchDaemon.
    START_INTERVAL=$(/usr/bin/defaults read "/Library/LaunchDaemons/${BUNDLE_ID}.plist" StartInterval 2>"/dev/null")
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

# Validate configuration profile-enforced settings or use script defaults accordingly.
# Whether to use custom labels for the install/defer buttons (default to "Install" and "Defer").
if [[ -n "$INSTALL_BUTTON_CUSTOM" ]]; then
    INSTALL_BUTTON="$INSTALL_BUTTON_CUSTOM"
else
    echo "Install button label undefined by administrator. Using default value."
    INSTALL_BUTTON="Install"
fi
echo "Install button label: ${INSTALL_BUTTON}"
if [[ -n "$DEFER_BUTTON_CUSTOM" ]]; then
    DEFER_BUTTON="$DEFER_BUTTON_CUSTOM"
else
    echo "Defer button label undefined by administrator. Using default value."
    DEFER_BUTTON="Defer"
fi
echo "Defer button label: ${DEFER_BUTTON}"

# Whether to have the user run updates manually (default to false on Intel Macs,
# always true on Apple Silicon Macs.)
if [[ "$PLATFORM_ARCH" = "arm64" ]]; then
    MANUAL_UPDATES="True"
elif [[ -n "$MANUAL_UPDATES_CUSTOM" ]]; then
    if [[ "$MANUAL_UPDATES_CUSTOM" -eq 1 ]]; then
        MANUAL_UPDATES="True"
    elif [[ "$MANUAL_UPDATES_CUSTOM" -eq 0 ]]; then
        MANUAL_UPDATES="False"
    else
        echo "Manual update preference not set to a valid boolean. Using default value."
        MANUAL_UPDATES="False"
    fi
else
    echo "Manual update preference undefined by administrator. Using default value."
    MANUAL_UPDATES="False"
fi
echo "Manual updates: ${MANUAL_UPDATES}"

# Check for a custom messaging logo image, otherwise default to the Software
# Update preference pane icon.
if [[ -n "$MESSAGING_LOGO_CUSTOM" ]] && [[ -f "$MESSAGING_LOGO_CUSTOM" ]]; then
    MESSAGING_LOGO="$MESSAGING_LOGO_CUSTOM"
else
    echo "Messaging logo undefined by admininstrator, or not found at specified path. Using default value."
    MESSAGING_LOGO="/System/Library/PreferencePanes/SoftwareUpdate.prefPane/Contents/Resources/SoftwareUpdate.icns"
fi
echo "Messaging logo: ${MESSAGING_LOGO}"

# Populate support contact information (default to "IT").
if [[ -n "$SUPPORT_CONTACT_CUSTOM" ]]; then
    SUPPORT_CONTACT="$SUPPORT_CONTACT_CUSTOM"
else
    SUPPORT_CONTACT="IT"
fi
echo "Support contact: ${SUPPORT_CONTACT}"
MSG_INSTALL_OR_DEFER="$(echo "$MSG_INSTALL_OR_DEFER" | /usr/bin/sed "s/%SUPPORT_CONTACT%/${SUPPORT_CONTACT}/")"
MSG_INSTALL="$(echo "$MSG_INSTALL" | /usr/bin/sed "s/%SUPPORT_CONTACT%/${SUPPORT_CONTACT}/")"
MSG_INSTALL_NOW="$(echo "$MSG_INSTALL_NOW" | /usr/bin/sed "s/%SUPPORT_CONTACT%/${SUPPORT_CONTACT}/")"
MSG_UPDATING="$(echo "$MSG_UPDATING" | /usr/bin/sed "s/%SUPPORT_CONTACT%/${SUPPORT_CONTACT}/")"

# Check for updates, exit if none found, otherwise continue.
check_for_updates

# Perform first-run tasks, including calculating deadline.
FORCE_DATE=$(/usr/bin/defaults read "$PLIST" UpdatesForcedAfter 2>"/dev/null")
if [[ -z "$FORCE_DATE" || "$FORCE_DATE" -gt $(( $(/bin/date +%s) + MAX_DEFERRAL_TIME )) ]]; then
    FORCE_DATE=$(( $(/bin/date +%s) + MAX_DEFERRAL_TIME ))
    /usr/bin/defaults write "$PLIST" UpdatesForcedAfter -int "$FORCE_DATE"
fi

# If a workday start and end hour have been defined and the deadline currently
# occurs during the workday, shift it forward to the end of the workday.
if [[ -n "$WORKDAY_START_HR_CUSTOM" ]] && [[ -n "$WORKDAY_END_HR_CUSTOM" ]]; then
    FORCE_DATE_HR=$(/bin/date -jf "%s" "+%H" "$FORCE_DATE")
    if [[ "$FORCE_DATE_HR" -ge "$WORKDAY_START_HR_CUSTOM" ]] && [[ "$FORCE_DATE_HR" -lt "$WORKDAY_END_HR_CUSTOM" ]]; then
        FORCE_DATE_YMD=$(/bin/date -jf "%s" "+%Y-%m-%d" "$FORCE_DATE")
        FORCE_DATE=$(/bin/date -jf "%Y-%m-%d %H:%M:%S" "+%s" "${FORCE_DATE_YMD} ${WORKDAY_END_HR_CUSTOM}:00:00")
        /usr/bin/defaults write "$PLIST" UpdatesForcedAfter -int "$FORCE_DATE"
        echo "Shifted deferral deadline forward to occur outside of workday."
    fi
fi

# Calculate how much time remains until deferral deadline.
DEFER_TIME_LEFT=$(( FORCE_DATE - $(/bin/date +%s) ))
echo "Deferral deadline: $(/bin/date -jf "%s" "+%Y-%m-%d %H:%M:%S" "$FORCE_DATE")"
echo "Time remaining: $(convert_seconds "$DEFER_TIME_LEFT")"

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
PROMPT_START="$(/bin/date +%s)"

# If defer time remains, display the prompt. If not, install and restart.
if (( DEFER_TIME_LEFT > 0 )); then

    # Substitute the correct number of hours remaining.
    # If time left is more than 2 days, use days.
    if (( DEFER_TIME_LEFT > 172800 )); then
        MSG_INSTALL_OR_DEFER="${MSG_INSTALL_OR_DEFER//%DEFER_HOURS%/$(( DEFER_TIME_LEFT / 86400 )) days}"
        MSG_INSTALL_OR_DEFER="${MSG_INSTALL_OR_DEFER// 1 days/ 1 day}"
    # If time left is more than 2 hours, use hours.
    elif (( DEFER_TIME_LEFT > 7200 )); then
        MSG_INSTALL_OR_DEFER="${MSG_INSTALL_OR_DEFER//%DEFER_HOURS%/$(( DEFER_TIME_LEFT / 3600 )) hours}"
        MSG_INSTALL_OR_DEFER="${MSG_INSTALL_OR_DEFER// 1 hours/ 1 hour}"
    # If time left is more than 1 minute, use minutes.
    elif (( DEFER_TIME_LEFT > 60 )); then
        MSG_INSTALL_OR_DEFER="${MSG_INSTALL_OR_DEFER//%DEFER_HOURS%/$(( DEFER_TIME_LEFT / 60 )) minutes}"
        MSG_INSTALL_OR_DEFER="${MSG_INSTALL_OR_DEFER// 1 minutes/ 1 minute}"
    else
        MSG_INSTALL_OR_DEFER="${MSG_INSTALL_OR_DEFER//after %DEFER_HOURS%/very soon}"
    fi

    # Substitute the deadline date.
    MSG_INSTALL_OR_DEFER="${MSG_INSTALL_OR_DEFER//%DEADLINE_DATE%/$(/bin/date -jf "%s" "+%b %d, %Y at %I:%M%p" "$FORCE_DATE")}"
    MSG_INSTALL_OR_DEFER_HEADING="${MSG_INSTALL_OR_DEFER_HEADING//%DEADLINE_DATE%/$(/bin/date -jf "%s" "+%b %d, %Y" "$FORCE_DATE")}"

    # Determine whether to include the "you may defer" wording.
    if (( EACH_DEFER > DEFER_TIME_LEFT )); then
        # Remove "{{" and "}}" including all the text between.
        MSG_INSTALL_OR_DEFER="$(echo "$MSG_INSTALL_OR_DEFER" | /usr/bin/sed 's/{{.*}}//g')"
    else
        # Just remove "{{" and "}}" but leave the text between.
        MSG_INSTALL_OR_DEFER="$(echo "$MSG_INSTALL_OR_DEFER" | /usr/bin/sed 's/[{{|}}]//g')"
    fi

    # Show the install/defer prompt.
    echo "Prompting to install updates now or defer..."
    PROMPT=$("$JAMFHELPER" -windowType "utility" -windowPosition "ur" -icon "$MESSAGING_LOGO" -title "$MSG_INSTALL_OR_DEFER_HEADING" -description "$MSG_INSTALL_OR_DEFER" -button1 "$INSTALL_BUTTON" -button2 "$DEFER_BUTTON" -defaultButton 2 -timeout "$PROMPT_TIMEOUT" -startlaunchd 2>"/dev/null")
    JAMFHELPER_PID="$!"

    # Make a note of the amount of time the prompt was shown onscreen.
    PROMPT_END="$(/bin/date +%s)"
    PROMPT_ELAPSED_SEC=$(( PROMPT_END - PROMPT_START ))

    # Generate a duration string that will be used in log output.
    if [[ -n "$PROMPT_ELAPSED_SEC" && "$PROMPT_ELAPSED_SEC" -eq 0 ]]; then
        PROMPT_ELAPSED_STR="immediately"
    elif [[ -n "$PROMPT_ELAPSED_SEC" ]]; then
        PROMPT_ELAPSED_STR="after $(convert_seconds "$PROMPT_ELAPSED_SEC")"
    else
        PROMPT_ELAPSED_STR="after an unknown amount of time"
        echo "[WARNING] Unable to determine elapsed time between prompt and action."
    fi

    # For reference, here is a list of the possible jamfHelper return codes:
    # https://gist.github.com/homebysix/18c1a07a284089e7f279#file-jamfhelper_help-txt-L72-L84

    # Take action based on the return code of the jamfHelper.
    if [[ -n "$PROMPT" ]]; then

        # Zero response time is erroneous, so we'll bail out.
        if [[ "$PROMPT_ELAPSED_SEC" -eq 0 ]]; then

            kill -9 "$JAMFHELPER_PID"
            echo "❌ ERROR: jamfHelper returned code ${PROMPT} ${PROMPT_ELAPSED_STR}. It's unlikely that the user responded that quickly."
            exit 1

        # User clicked the install button.
        elif [[ "$PROMPT" -eq 0 ]]; then

            echo "User clicked ${INSTALL_BUTTON} ${PROMPT_ELAPSED_STR}."

            # If manual updates are enabled,
            # track the next deferral before proceeding.
            if [[ "$MANUAL_UPDATES_CUSTOM" -eq 1 ]]; then
                echo "Manual updates are enabled, so we'll continue to track the next deferral date in case the update isn't run in a timely manner."
                NEXT_PROMPT=$(( $(/bin/date +%s) + EACH_DEFER ))
                if (( FORCE_DATE < NEXT_PROMPT )); then
                    NEXT_PROMPT="$FORCE_DATE"
                fi
                /usr/bin/defaults write "$PLIST" UpdatesDeferredUntil -int "$NEXT_PROMPT"
                echo "Next prompt will appear after $(/bin/date -jf "%s" "+%Y-%m-%d %H:%M:%S" "$NEXT_PROMPT")."
            fi
            install_updates

        # jamfHelper failed to launch.
        elif [[ "$PROMPT" -eq 1 ]]; then

            kill -9 "$JAMFHELPER_PID"
            echo "❌ ERROR: jamfHelper was not able to launch ${PROMPT_ELAPSED_STR}."
            exit 1

        # User clicked the defer button.
        elif [[ "$PROMPT" -eq 2 ]]; then

            echo "User clicked ${DEFER_BUTTON} ${PROMPT_ELAPSED_STR}."
            NEXT_PROMPT=$(( $(/bin/date +%s) + EACH_DEFER ))
            if (( FORCE_DATE < NEXT_PROMPT )); then
                NEXT_PROMPT="$FORCE_DATE"
            fi
            /usr/bin/defaults write "$PLIST" UpdatesDeferredUntil -int "$NEXT_PROMPT"
            echo "Next prompt will appear after $(/bin/date -jf "%s" "+%Y-%m-%d %H:%M:%S" "$NEXT_PROMPT")."

        # User clicked the jamfHelper exit button.
        elif [[ "$PROMPT" -eq 239 ]]; then

            echo "User deferred by exiting jamfHelper ${PROMPT_ELAPSED_STR}."
            NEXT_PROMPT=$(( $(/bin/date +%s) + EACH_DEFER ))
            if (( FORCE_DATE < NEXT_PROMPT )); then
                NEXT_PROMPT="$FORCE_DATE"
            fi
            /usr/bin/defaults write "$PLIST" UpdatesDeferredUntil -int "$NEXT_PROMPT"
            echo "Next prompt will appear after $(/bin/date -jf "%s" "+%Y-%m-%d %H:%M:%S" "$NEXT_PROMPT")."

        # Unexpected return code from jamfHelper.
        elif [[ "$PROMPT" -gt 2 ]]; then

            # Kill the jamfHelper prompt.
            kill -9 "$JAMFHELPER_PID"
            echo "❌ ERROR: jamfHelper produced an unexpected value (code ${PROMPT}) ${PROMPT_ELAPSED_STR}."
            exit 1

        fi

    # $PROMPT is not defined.
    elif [[ -z "$PROMPT" ]]; then

        # Kill the jamfHelper prompt.
        kill -9 "$JAMFHELPER_PID"
        echo "❌ ERROR: jamfHelper returned no value ${PROMPT_ELAPSED_STR}. ${INSTALL_BUTTON}/${DEFER_BUTTON} response was not captured. This may be because the user logged out without clicking ${INSTALL_BUTTON} or ${DEFER_BUTTON}."
        exit 1

    # Unexpected response.
    else

        # Kill the jamfHelper prompt.
        kill -9 "$JAMFHELPER_PID"
        echo "❌ ERROR: Something went wrong. Check the jamfHelper return code (${PROMPT}) and prompt elapsed seconds (${PROMPT_ELAPSED_SEC}) for further information."
        exit 1

    fi

else
    # If no deferral time remains, force installation of updates now.
    echo "No deferral time remains."
    display_act_msg
fi

exit 0

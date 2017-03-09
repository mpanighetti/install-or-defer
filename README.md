# Install or Defer Critical Apple Updates

This framework will prompt users of Jamf-managed Macs to install Apple software updates when specific updates that the IT department has deemed "critical" are available. Users will have the option to __Restart Now__ or __Defer__. After a specified amount of time, the Mac will be forced to restart and install the updates.

![Install or defer prompt](img/install-or-defer-fullscreen.png)

This workflow is most useful for updates that require a restart and include important security-related patches (e.g. Security Update 2017-003 or macOS 10.12.3).

This framework is distributed in the form of a [munkipkg](https://github.com/munki/munki-pkg) project, which allows easy creation of a new pkg when changes are made to the script or to the LaunchDaemon that runs it. (Despite the name, packages generated with munkipkg don't require Munki. They work great with Casper/Jamf Pro.) See the [Installer Creation](#installer-creation) section below for specific steps on creating the installer for this framework.


## Requirements and assumptions

Here's what needs to be in place in order to use this framework:

- This framework has been tested only on __OS X 10.8 through 10.12__, but will most likely work on 10.7+.
- Target Macs must be __enrolled in the JSS__ and have the `jamfHelper` binary installed.
- A __company logo__ graphic file must already exist in a "stash" on each Mac.
- We're assuming all the desired updates will __require a restart__. (If updates don't require a restart, they can be installed without user interaction, making this workflow unnecessary.)
- Optional but recommended: An __OS X Server with Caching service active__ at all major office locations. This will conserve network bandwidth and improve the download speed of updates.


## Workflow detail

Here's how everything works, once it's configured:

1. When a new critical Apple security update is released, the Jamf administrator creates a smart group for this update and adds it to the existing policy.
2. People who fall into the smart group start running the policy at next check-in.
3. The policy installs a package that places a LaunchDaemon and a script.
4. The LaunchDaemon executes the script, which performs the following actions:
    1. The script uses `softwareupdate --download --all` to download all available Apple updates in the background.
    2. The script sets all available updates to be installed when the next restart occurs.
    3. A company-branded onscreen message appears, indicating the new updates are required to be installed. Two options are given: __Restart Now__ or __Defer__.

    (Note: Your company logo will appear in place of the App Store icon, if you specify the `LOGO` path.)
    ![Install or Defer](img/install-or-defer.png)
    4. If the user clicks __Defer__, the prompt will be dismissed. The next prompt will reappear after 4 hours (customizable). Users can defer for up to 72 hours (also customizable). After 72 hours, the Mac automatically restarts and the updates install.
    5. When the user clicks __Restart Now__, the script attempts a "soft" restart.
5. If the deferral deadline passes, the script behaves differently:
    1. The user sees a non-dismissable prompt asking them to restart immediately.
        ![Restart Now](img/restart-now.png)
    2. If the user ignores the restart prompt for 10 minutes, the script attempts a "soft" restart.
    3. 5 minutes after the "soft" restart, if the user still has not restarted (or if unsaved work prevents the "soft" restart from occurring), the script forces a restart to occur.
    4. When the restart occurs, Apple's native software update mechanism kicks in and installs all available software updates.
6. When finished, the script and LaunchDaemon self-destruct in order to prevent the prompt from incorrectly appearing again after the updates have been installed.


## Limitations

The framework has two major limitations:

- Sequential updates cannot be installed as a group. If multiple sequential critical updates are available, they are treated as two separate rounds of prompting/deferring. Macs requiring sequential updates may take up to 6 days (2x defer deadline) to be fully patched.
    - Possible solution: Install a LaunchDaemon that installs any remaining updates upon the next restart, enabling all updates to be installed in a single session. We did not take this approach due to the risk of false-positives causing update loops to occur.
- All available Apple updates are installed (even the ones that aren't deemed critical).
    - Possible solution: The framework could be reworked to target a specific update, but we've found there's very little downside to installing all available updates.
- Reasonable attempts have been made to make this workflow enforceable, but there's nothing stopping an administrator of a Mac from unloading the LaunchDaemon or resetting the preference file.


## Script configuration

Open the script file with a text editor (e.g. TextWrangler or Atom): __payload/Library/Scripts/install_or_defer.sh__

There are several variables in the script that should be customized to your organization's needs:

### File paths and identifiers

- `PLIST`
    Path to a plist file that is used to store settings locally. Omit ".plist" extension.

- `LOGO`
    (Optional) Path to a logo that will be used in messaging. Recommend 512px, PNG format. If no logo is provided, the App Store icon will be used (as shown in the screenshots above).

- `BUNDLE_ID`
    The identifier of the LaunchDaemon that is used to call this script, which should match the file in the __payload/Library/LaunchDaemons__ folder. Omit ".plist" extension.

### Messaging

- `MSG_ACT_OR_DEFER_HEADING`
    The heading/title of the message users will receive when updates are available.

- `MSG_ACT_OR_DEFER`
    The body of the message users will receive when updates are available.

    - This message uses the following dynamic substitutions:
        - `%DEFER_HOURS%` will be automatically replaced by the number of hours remaining in the deferral period.
        - The section in the {{double curly braces}} will be removed when this message is displayed for the final time before the deferral deadline.

- `MSG_RESTART_HEADING`
    The heading/title of the message users will receive when they must restart immediately.

- `MSG_RESTART`
    The body of the message users will receive when they must restart immediately.

### Timing

- `MAX_DEFERRAL_TIME`
    Number of seconds between the first script run and the updates being forced.

- `EACH_DEFER`
    When the user clicks "Defer" the next prompt is delayed by this much time.

- `SOFT_RESTART_DELAY`
    The number of seconds to wait between displaying the "please restart" message and attempting a soft restart.

- `HARD_RESTART_DELAY`
    The number of seconds to wait between attempting a soft restart and forcing a restart.


## Installer creation

Download and install [munkipkg](https://github.com/munki/munki-pkg), if you haven't already. Add the `munkipkg` binary location to your `PATH` or create an alias in your bash profile so that you can reference the command directly.

Each time you make changes to the script, we recommend changing the following three things:

- The Last Modified metadata in the script.
- The Version metadata in the script.
- The `version` key in the build-info.plist file. (Recommend matching the script version.)

With munkipkg installed, his command will generate a new pkg installer in the build folder:

    munkipkg /path/to/install_or_defer

The subsequent pkg can be uploaded to Jamf and scoped as specified below in the JSS setup section.


## JSS setup

The following objects should be created on the JSS in order to implement this framework:

### Packages

Upload this package (created with munkipkg above) to the JSS via Casper Admin or via the JSS web app:

- __install_or_defer-x.x.x.pkg__

### Smart Groups

Create a smart group for each software update or OS patch you wish to enforce. Here are four examples to serve as guides.

- __Critical update needed: 10.10.5__
    - `Last check-in` `less than x days ago` `7`
    - `and` `(` `Operating system` `is` `10.10`
    - `or` `Operating system` `is` `10.10.1`
    - `or` `Operating system` `is` `10.10.2`
    - `or` `Operating system` `is` `10.10.3`
    - `or` `Operating system` `is` `10.10.4` `)`

- __Critical update needed: 10.11.6__
    - `Last check-in` `less than x days ago` `7`
    - `and` `(` `Operating system` `is` `10.11`
    - `or` `Operating system` `is` `10.11.1`
    - `or` `Operating system` `is` `10.11.2`
    - `or` `Operating system` `is` `10.11.3`
    - `or` `Operating system` `is` `10.11.4`
    - `or` `Operating system` `is` `10.11.5` `)`

- __Critical update needed: 2016-005 for 10.10__
    - `Last check-in` `less than x days ago` `7`
    - `and` `Operating system` `is` `14F1909`

- __Critical update needed: 2016-003 for 10.11__
    - `Last check-in` `less than x days ago` `7`
    - `and` `Operating system` `is` `15G31`

Note: The "Last check-in" criteria has been added in the examples above in order to make the smart group membership count more accurately reflect the number of _active_ computers that need patching, rather than including computers that have been lost, decommissioned, or shelved. The presence or absence of the "Last check-in" criteria does not have a significant effect on behavior or scope of this framework.

### Policies

Create the following two policies:

- __Update inventory at startup__
    - Triggers:
        - __Startup__
    - Execution Frequency: __Ongoing__
    - Maintenance:
        - __Update inventory__
    - Scope: __All computers__

- __Prompt to install or defer critical Apple updates__
    - Triggers:
        - __Recurring check-in__
        - Custom: __critical-updates__
    - Execution Frequency: __Once every day__
    - Packages:
        - __install_or_defer-x.x.x.pkg__
    - Scope:
        - For now, just a handful of Macs you can test on.


## Testing

1. Add your test Mac to the scope of the __Prompt to install or defer critical Apple updates__ policy.

2. On the test Mac, open Console.app. To display activity in OS X 10.11 and lower, filter for `install_or_defer`.

    Or run this Terminal command:

        tail -f /var/log/system.log | grep "install_or_defer"

    To display activity in macOS 10.12 and higher, filter for the Process `logger`.

    Or run this Terminal command:

        log stream --style syslog --predicate 'senderImagePath ENDSWITH "logger"'

3. Open Terminal and trigger the "stash" policy that deploys the logo graphics, if not already installed:
    ```
    sudo jamf policy -event stash
    ```

4. Then trigger the __Prompt to install or defer critical Apple updates__ policy:
    ```
    sudo jamf policy -event critical-updates
    ```

5. Enter your administrative password when prompted.

6. The policy should run and install the script/LaunchDaemon. Switch back to Console to view the output. You should see something like the following:
    ```
    Starting install_or_defer.sh script. Performing validation and error checking...
    Validation and error checking passed. Starting main process...
    Setting deferral deadline: 2016-09-11 16:30:53
    Time remaining until deferral deadline: 72h:00m:00s
    Pre-downloading all available software updates...
    Software Update Tool
    Copyright 2002-2015 Apple Inc.
    Finding available software
    Downloaded Security Update 2016-001
    Done.
    Configuring updates to be installed at restart...
    File Doesn't Exist, Will Create: /var/db/.SoftwareUpdateOptions
    Reloading com.apple.softwareupdated.plist...
    Reloading com.apple.suhelperd.plist...
    Updates configured to install at next restart.
    Prompting to install updates now or defer...
    ```

7. After the updates are downloaded, you should see the following prompt appear onscreen:
    ![Install or Defer](img/install-or-defer.png)

8. Click __Defer__. You should see the following output appear in Console:
    ```
    User clicked Defer after 00h:00m:20s.
    Next prompt will appear after 2016-09-08 20:31:45.
    ```

9. Run the following command in Terminal:
    ```
    sudo defaults read /Library/Preferences/com.elliotjordan.install_or_defer | grep AppleSoftwareUpdates
    ```

10. You should see something similar to the following output (the numbers, which represent dates, will vary):
    ```
        AppleSoftwareUpdatesDeferredUntil = 1473391905;
        AppleSoftwareUpdatesForcedAfter = 1473636653;
    ```

11. Enter the following commands to "skip ahead" to the next deferral and re-trigger the prompt:
    ```
    sudo defaults write /Library/Preferences/com.elliotjordan.install_or_defer AppleSoftwareUpdatesDeferredUntil -int $(date +%s)
    sudo launchctl unload /Library/LaunchDaemons/com.elliotjordan.install_or_defer.plist
    sudo launchctl load /Library/LaunchDaemons/com.elliotjordan.install_or_defer.plist
    ```

12. You should see the install/defer prompt appear again.

13. Click __Restart Now__. As long as there are no apps with unsaved changes, the Mac should restart immediately and updates should be installed.
    - If you want to test the "hard restart" feature of this framework, open Terminal and type `top` before clicking the __Restart Now__ button. Then wait 5 minutes and confirm that the Mac restarts successfully.

14. After updates are installed and the Mac is successfully restarted, you should not see any more onscreen messages.

15. (OPTIONAL) If an additional round of updates is needed (e.g. Security Update 2016-001), run `sudo jamf policy -event critical-updates` again to start the process over. Sequential updates cannot be installed as a group (see __Limitations__ section above).


## Deployment

Once the Testing steps above have been followed, there are only a few steps remaining to deploy the framework:

1. On the JSS web app, edit the __Prompt to install or defer critical Apple updates policy__ and click on the __Scope__ tab.
2. Remove the test Macs from the scope.
3. Add all the __Critical updates available__ smart groups into the scope.
4. Click __Save__.
5. Monitor the policy logs to ensure the script is working as expected.


## Rollback

If major problems are detected with the critical update prompt or installation workflow, disable the __Prompt to install or defer critical Apple updates policy__. This will prevent computers from being newly prompted for installation of updates.

Once the script is debugged and updated, you can generate a new installer, upload the installer to the JSS and link it to the policy, and re-enable the policy.


## Miscellaneous Notes

- Feel free to change the com.elliotjordan style identifier to match your company instead. If you do this, make sure to update the filenames of the LaunchDaemons, the preinstall script, and the postinstall script.
- You can also specify a different default logo, if you'd rather not use the App Store icon. The `sips` command can be used to convert .icns files into .png files on the fly, if needed.
- If you encounter any issues or have questions, please open an issue on this GitHub repo.

Enjoy!

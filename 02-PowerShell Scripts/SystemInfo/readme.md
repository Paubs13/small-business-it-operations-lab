*Purpose*: \
Collects a basic hardware and OS inventory from one or more Windows computers and returns it as structured PowerShell objects. By default it also writes a CSV report.

*Process*: \
I made a draft of the Script using Claude, since i'm not very familiar with the cmdlets, but i'm familiar with programming.

After i got the draft, i deleted the feature to export it as an HTML and keep the CSV export, because it's more useful for
productive environments. I ran it a couple of times to test it and detect errors. Since it's a simple script, it didn't have
any errors and it worked like a charm.

I've decided to use AI, because in productive environments it's the norm. I understand the logic of the script, and i believe
that's what matters most. The only thing that this scripts does is read values, record them in a variable and then output it
in a readable way. Simple.

After doing the first one, i've decided to add the features to run it on multiple machines remotely, like an IT admin would.
I don't have a Windows VM machine to test if it works, locally it does. I'll come back to it when i do other troubleshooting
jobs later down the project.

*Limitations*:
- Windows only.
- Fixed disks only (DriveType=3). Removable, optical and network drives are not listed.
- CPU model is taken from the first processor; core and logical counts are summed across sockets.
- LoggedInUser is the console session user only (RDP sessions are not included). For local accounts the MACHINENAME\ prefix is removed; domain accounts keep DOMAIN\user. No interactive user means nobody is signed in at the console.
- LastBoot is shown in the time zone of the computer running the script. Uptime itself is calculated on the target's own clock, so it is not affected.
- Connections are opened one after another; only the queries run concurrently. Many unreachable hosts can add up to -TimeoutSec each before querying starts.
- Error text depends on what Windows returns. For a multi-host run, a query error that does not mention the host name is reported as the generic "No data returned (host unreachable or access denied)".
- Local aliases: ., localhost, 127.0.0.1, ::1 and the computer's own short name are treated as local. The computer's own FQDN or LAN IP is not, and goes through the remote path (so it needs WinRM and administrator rights).
- -Credential is ignored for the local computer.

*Parameters*: \
-ComputerName	\
One or more names, FQDNs or IP addresses. Defaults to the local computer (unless only -ComputerListPath is given).

-ComputerListPath	\
Text file with one name per line. Blank lines and lines starting with # are ignored.

-Credential	\
Credential for remote targets. Ignored for the local computer.

-OutputPath	\
Folder for the CSV report. Created if missing. Defaults to the current folder.

-NoCsv	\
Return objects only; do not write a CSV.

-FallbackToDcom	\
Retry over DCOM when WinRM is unavailable on a target.

-TimeoutSec	\
Per-operation timeout, 5-600 seconds. Default 30.

-WhatIf / -Confirm	\
Apply to the folder and file the script creates. Nothin

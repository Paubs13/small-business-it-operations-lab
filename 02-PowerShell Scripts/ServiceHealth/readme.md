I used the same process as SystemInfo, so i just reviewed and tested the AI-generated code. I added a few of try-catchs to make it more consistent on edge cases, as well as adding a function that checks that it's running on Windows. It's basically the same logic as SystemInfo too. Gets the services and their state, and based on which functions have been executed it displays them and stores them in a CSV.

Also this code has a couple of flags that can be used when executed on the Shell.

*Limitations:*
- Windows only.
- AutoButStopped is not always a fault. Some Automatic services run a task and exit, or are trigger-start services that Windows starts on demand. The Note column flags these where it can, but check.
- Trigger-start detection is local only (it reads the local registry). For remote computers IsTriggerStart is empty.
- -StartStoppedAutoServices works on the local computer only, and skips trigger-start services.
- Remote queries use CIM over WinRM and depend on firewall and permission setup.
- Kernel and file-system drivers are not included, only Win32 services.
- The summary uses Write-Host, so it appears on the console only and is printed before the table.
- The CSV export contains the objects returned by the script, after -ProblemsOnly is applied.

*Parameters:*

-ExportCSVPath C:\desiredpath\filename.csv \
The output will always be only on the shell if you don't use this flag.

-ComputerName ComputerNameHere \
To run on a remote computer. If not used, it will automatically be done locally.

-ServiceName ServiceNameHere \
To search for a specific service. It automatically will list all if not used.

-ProblemsOnly \
Will return only the services on state "AutoButStopped".

-StartStoppedAutoServices \
Tries to start AutoButStopped services. If not executed with elevated permissions, it won't be performed.

-ShowSummary \
Shows a colored summary on the console, additionally of the objects.

-Verbose \
Shows what the script is doing.

-WhatIf / -Confirm \
Safety switches for the start of the operation.

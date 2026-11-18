*Purpose*:
Collects hardware, serial number, OS, disk and installed-software inventory from the local computer (or remote Windows computers) and exports it to CSV. Every collector returns structured PowerShell objects; the CSV files are just one rendering of those objects.

*Process*:
Same process as the other ones. It had an error on the output at first. The $Notes list started empty, and PowerShell refuses to bind an empty collection to a Mandatory parameter unless it’s marked AllowEmptyCollection. Because that error was caught by the outer try/catch, every collector failed before it ran. To solve it i added that attribute to all five functions that take $Notes.

*Limitations:*
- Windows only.
- Serial numbers depend on firmware. Virtual machines, white-box PCs and some OEM boards report blank or placeholder values; these appear as Unavailable / Unavailable (placeholder). Physical disk serials may be empty for NVMe/RAID/virtual disks or without admin rights.
- Installed software comes from the machine-wide Uninstall registry keys. It excludes per-user installs (HKCU), Microsoft Store/MSIX apps, and portable apps. Remote collection needs WinRM; if that is unavailable, the software file is empty and a note is recorded.
- Disk scope: only fixed local volumes (DriveType 3); removable, network and CD drives are skipped.
- Remote access uses WinRM. Firewalls, workgroup trust settings (TrustedHosts) and UAC remote restrictions can block it; the script reports the error rather than changing any configuration.
- Sequential: computers are processed one at a time, so large fleets will be slow.
- CSV values such as PercentFree use . as the decimal separator regardless of locale in the objects, but Excel in some locales may interpret them differently when opening the file.

*Parameters:*
-ComputerName	\
One or more hostnames / IPv4 addresses (validated). Default is local computer. 

-Credential	\
Credential for remote computers (ignored locally). Default is	current user 

-OutputDirectory \
Folder for CSVs; created if missing. Default is	.\InventoryOutput.

-SkipSoftware	\
Don't collect installed software. It's off by default.

-TimeoutSeconds \	
Remote CIM operation timeout, 1-300. Default is	30.

-Force	\
Overwrite existing output files without prompting. It's	off by default.

-PassThru	
Emit full result objects instead of only summaries. It's	off by default.

-WhatIf / -Confirm \
Standard PowerShell safety switches.

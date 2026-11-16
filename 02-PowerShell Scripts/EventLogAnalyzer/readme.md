I did the same process than with ServiceHealth. I used it as a model and the AI automatically added the functions i had to manually add last time, so now i just had to review it and test it.

*Limitations:*
- Windows only.
- Messages come from the source's registered message DLLs. If they are missing, the message shows a placeholder.
- -MaxEvents applies per log during the query and again to the combined, sorted result.
- Very large ranges on busy logs can be slow; narrow the range or add -EventId / -ProviderName.
- Timestamps are in the time zone of the machine running the script (for remote queries, converted by PowerShell on your machine).
- Remote queries depend on network, firewall and DCOM/RPC configuration that this script cannot change.

*Parameters:*

-LogName \
Log names (wildcards allowed)

-HoursBack \
Look back N hours (1-8760)

-StartTime / -EndTime \
Absolute range (alternative to -HoursBack)

-Level \
Critical, Error, or both

-EventId \
Only these event IDs

-ProviderName \
Only these sources
  
-MaxEvents \
Maximum events returned (newest first)

-ComputerName, -Credential \
Query a remote machine

-MessageMaxLength \
Truncate messages (0 = no truncation)
  
-ExportPath \
Write results to .csv or .json
  
-Force \
Overwrite the export file without asking

-WhatIf / -Confirm \
Preview or confirm the export write

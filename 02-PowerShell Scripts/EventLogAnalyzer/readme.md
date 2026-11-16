I did the same process than with ServiceHealth. I used it as a model and the AI automatically added the functions i had to manually add last time, so now i just had to review it and test it.


Parameters: \
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

Same process of the other two. I tested everything except remote execution (yet, i plan to do this later) and it works. Using the code previously done as a framework for the AI to follow seems to do the trick.

*Limitations:*
- Windows only; not tested on non-Windows PowerShell.
- A failed ping does not mean a host is down: ICMP is often blocked. Use the TCP results to confirm.
- A TimedOut TCP result cannot distinguish a firewall drop from an offline host.
- DNS lookups use the system's configured resolvers.
- IPv6 link-local gateways may fail the ping test because the zone/interface is not included in the gateway address.
- Tests run sequentially, so many targets x ports x a long timeout can be slow.
- It tests connectivity only; it does not scan ports, change adapter settings or repair anything.
- Text mode shows IPv4 addresses only; IPv6 addresses and the prefix length are in the object / JSON output.

*Parameters:*
-Target	\
Hosts / IPs to resolve, ping and test. Default is www.microsoft.com, one.one.one.one \

-Port \	
TCP ports (1-65535) tested on every target. Default is 80 and 443. \

-TimeoutMs \
Timeout per ping / TCP attempt (100-60000). Default is 2000ms. \

-PingCount	\
Echo requests per host (1-10). Default is 2. \

-IncludeDisconnected	\
Also list adapters that are not Up. It's off by default. \

-TestDnsServerPort	\
Also test TCP/53 on each configured DNS server. It's off by default. \

-FlushDnsCache	\
Clear DNS client cache first. It's off by default and requires elevated permissions. \

-OutputFormat	\
Object, Json or Text. Default is object. \

-Path \
 Save the report to a file. By default it does not. \

-WhatIf / -Confirm		\
Standard safety switches for the flush. \

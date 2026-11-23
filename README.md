# Small Business IT Operations Lab

A hands-on IT operations project simulating the infrastructure, administration, and technical support environment of a small business.

## Overview

This project aims to build and manage a simulated small-business IT environment using Windows 11 and Ubuntu Server, with a focus on practical IT support, system administration, automation, network troubleshooting, and incident management.

The lab provides me an opportunity to apply technical knowledge in realistic scenarios, develop troubleshooting methodologies, and document IT operations following professional practices.

## Objectives

- Build and configure a small-business IT infrastructure.
- Develop PowerShell scripts to automate routine IT administration and diagnostic tasks.
- Administer and secure a Linux server.
- Implement basic network services and troubleshoot connectivity issues.
- Simulate IT service desk operations, including incident prioritization, documentation, and resolution.
- Practice cross-platform troubleshooting involving Windows and Linux environments.
- Maintain technical documentation and evidence of testing and configuration.

## Infrastructure

The project uses a Windows 11 physical PC as the administrative workstation and VirtualBox to host the Ubuntu Server virtual machine.

### Environment

| Component | Configuration |
|---|---|
| Host OS | Windows 11 |
| Virtualization | Oracle VirtualBox |
| Server OS | Ubuntu Server 24.04 LTS |
| Server hostname | NS-SRV01 |
| Administration | PowerShell, SSH, Linux CLI |

## Project Components

### 1. Infrastructure Setup --COMPLETED-- 

- Virtual machine creation and configuration.
- Operating system installation and initial setup.
- Hostname and network configuration.
- User and permission management.
- Connectivity testing between Windows and Ubuntu.

### 2. PowerShell Automation Toolkit --COMPLETED*--

A collection of scripts designed to automate common IT support and system administration tasks.

Planned utilities include:

- **System Information Collector:** Retrieves operating system, hardware, memory, storage, and system information.
- **Service Health Checker:** Inspects Windows services and identifies unexpected service states.
- **Event Log Analyzer:** Retrieves and analyzes relevant Windows event logs.
- **Network Diagnostics:** Checks network configuration, connectivity, DNS resolution, and TCP ports.
- **Asset Inventory Collector:** Collects hardware and software inventory information.

An additional objective is to implement remote execution across multiple Windows endpoints and consolidate collected information into centralized CSV reports. * Further testing of this feature will be performed at the end of the project. Locally, all scripts are currently functional.

### 3. Linux Administration and Security --COMPLETED*--

Configuration and administration of the Ubuntu Server environment, including:

- User and group management.
- Administrative privileges and least-privilege practices.
- SSH configuration and key-based authentication.
- Firewall configuration using UFW.
- System updates and service management.
- Nginx installation and configuration.
- Log inspection and basic security monitoring.
- Linux service and connectivity troubleshooting.

*Further modifications of the NGINX page will be performed at a later stage. Now it's completely functional, but not quite there to my taste.

### 4. IT Service Desk Simulation --WIP--

A simulated IT support environment representing a small business with multiple departments and employees.

Planned activities include:

- Incident creation and documentation.
- Ticket categorization and prioritization.
- Incident assignment and escalation.
- Troubleshooting and resolution tracking.
- User-facing explanations and internal technical notes.
- Basic service desk procedures and documentation.

### 5. Integrated Troubleshooting Scenarios --WIP--

Practical scenarios combining multiple areas of IT operations.

Examples include:

- Internal website connectivity failures.
- Windows workstation performance issues.
- Linux service failures.
- Authentication and access problems.
- Suspicious authentication activity.
- New employee onboarding and equipment assignment.

Each scenario will document the initial problem, investigation, diagnosis, resolution, and verification.

## Technologies and Tools

- Windows 11
- Ubuntu Server 24.04 LTS
- Oracle VirtualBox
- PowerShell
- Bash
- SSH
- Nginx
- UFW
- Git and GitHub
- CSV and Markdown documentation

## Testing and Documentation

The project emphasizes practical testing and documentation rather than configuration alone.

Each major component will include relevant configuration details, testing procedures, expected results, and troubleshooting notes.

Screenshots and sample outputs will be included where they provide meaningful evidence of functionality.

## Development Approach

This is an ongoing personal learning project. Features are implemented incrementally, tested in a virtualized environment, and documented as they are completed.

AI tools may be used to assist with code generation, research, debugging, and documentation. Technical decisions, code review, testing, and validation remain part of the development process.

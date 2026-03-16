# Unified Package Caching System

An open-source repository for deploying a local package caching server for **APT**, **npm**, and **pip** using script-based automation and Dockerized services.

> Current implementation focus: the **server runs through the main shell script**, **automatic configuration is implemented**, and the **GUI installer remains an initial prototype**.

## Project Title

**Unified Package Caching System for Bandwidth Optimization Through Data Caching**

## Project Description

### Problem Statement

In shared labs, development teams, and educational networks, the same packages are downloaded repeatedly by multiple users. This wastes bandwidth, slows down software installation, and increases dependency setup time.

### Objectives

- Reduce repeated internet downloads by serving packages from a local cache.
- Speed up package installation for Debian/Ubuntu, Node.js, and Python environments.
- Provide an automated server setup process.
- Provide client-side auto-configuration for Linux and Windows environments.
- Keep the system simple enough for classroom, lab, and small-team deployment.

### Target Users

- University and school computer labs
- Development teams on shared local networks
- Training centers and classrooms
- Small organizations with limited internet bandwidth
- Homelab users who want faster repeated package installation

### Overview

This project sets up a central package cache server that proxies package requests through three services:

- **apt-cacher-ng** for Debian/Ubuntu packages
- **Verdaccio** for npm packages
- **devpi** for Python packages

The main server workflow is handled by `pkg-cache.sh`. During setup, the script automatically prepares Docker, generates the required runtime configuration, and starts the three caching services. Linux clients can also be configured by the same script. Windows clients are configured through `pkg-cache-client.ps1`. A Tkinter-based GUI installer is included as an early-stage prototype for easier client setup.

## System Architecture / Design

### Workflow Summary

1. The administrator runs `./pkg-cache.sh server install` on the cache server.
2. The script checks Docker and Docker Compose availability.
3. Runtime files are generated for the Dockerized cache services.
4. Three services start: APT cache, npm cache, and pip cache.
5. Clients are pointed to the local cache server instead of downloading everything directly from the internet.

### High-Level Architecture Diagram

![Architecture overview](docs/diagrams/architecture-overview.svg)

### Deployment Workflow Diagram

![Deployment workflow](docs/diagrams/deployment-workflow.svg)

### Main Components

| Component              | Purpose                                                                     |
| ---------------------- | --------------------------------------------------------------------------- |
| `pkg-cache.sh`         | Main automation entry point for server setup and Linux client configuration |
| `pkg-cache-client.ps1` | Windows client configuration script                                         |
| `apt-cacher-ng`        | Caches Debian/Ubuntu packages                                               |
| `Verdaccio`            | Caches npm packages                                                         |
| `devpi`                | Caches Python packages                                                      |
| `installers/`          | Initial GUI installer prototype source                                      |

### Runtime-Generated Server Layout

The server creates its working files during installation:

```text
pkg-cache/
├── docker-compose.yml
├── .env
├── verdaccio/
│   └── conf/
│       └── config.yaml
└── data/
    ├── apt-cacher-ng/
    ├── verdaccio/
    └── devpi/
```

## Technologies Used

| Category               | Technology                                        |
| ---------------------- | ------------------------------------------------- |
| Programming languages  | Bash, PowerShell, Python                          |
| GUI                    | Tkinter                                           |
| Containerization       | Docker, Docker Compose                            |
| Package cache services | apt-cacher-ng, Verdaccio, devpi                   |
| Build tooling          | PyInstaller (for installer packaging experiments) |
| Version control        | Git / GitHub                                      |
| Operating systems      | Linux server, Linux clients, Windows clients      |

## Installation Instructions

### Requirements

**Server**

- Linux machine (Debian/Ubuntu preferred)
- Network access for Docker image pulls
- Open ports `3142`, `4873`, and `3141`

**Linux client**

- Debian/Ubuntu for APT caching support
- `curl` recommended for reachability checks
- `npm` and `python3`/`pip` installed if those ecosystems are required

**Windows client**

- PowerShell
- `npm` installed for Node.js caching
- Python with `pip` installed for Python package caching

### Clone or Download

```bash
git clone https://github.com/Mr-AbdullahFahim/Caching-System.git
cd Caching-System
```

Or download the source code as a ZIP and extract it.

### Run the Server

```bash
chmod +x pkg-cache.sh
./pkg-cache.sh server install
```

### Configure a Linux Client

```bash
./pkg-cache.sh client install <SERVER_IP_OR_HOST>
```

Example:

```bash
./pkg-cache.sh client install 192.168.1.50
```

### Configure a Windows Client

```powershell
powershell -ExecutionPolicy Bypass -File .\pkg-cache-client.ps1 -Action install -ServerHost <SERVER_IP_OR_HOST>
```

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\pkg-cache-client.ps1 -Action install -ServerHost 192.168.1.50
```

### Run the GUI Installer Prototype

```bash
cd installers/linux
python installer.py
```

or

```powershell
cd installers\windows
python installer.py
```

## Usage Instructions

### Common Commands

```bash
./pkg-cache.sh server install
./pkg-cache.sh server reset
./pkg-cache.sh client install 192.168.1.50
./pkg-cache.sh client reset
```

```powershell
powershell -ExecutionPolicy Bypass -File .\pkg-cache-client.ps1 -Action install -ServerHost 192.168.1.50
powershell -ExecutionPolicy Bypass -File .\pkg-cache-client.ps1 -Action status -ServerHost 192.168.1.50
powershell -ExecutionPolicy Bypass -File .\pkg-cache-client.ps1 -Action reset
```

### Example Inputs and Outputs

# Usage Examples

## 1. Start the Cache Server

```bash
chmod +x pkg-cache.sh
./pkg-cache.sh server install
```

Expected result:

- Docker and Docker Compose are checked or installed.
- The three cache services are started.
- The server prints the local URLs for APT, npm, and pip clients.

## 2. Configure a Linux Client

```bash
./pkg-cache.sh client install 192.168.1.50
```

Expected result:

- APT proxy settings are written for Debian/Ubuntu systems.
- npm registry is redirected to the local Verdaccio service.
- pip index-url is redirected to the local devpi service.

## 3. Configure a Windows Client

```powershell
powershell -ExecutionPolicy Bypass -File .\pkg-cache-client.ps1 -Action install -ServerHost 192.168.1.50
```

Expected result:

- npm registry is redirected to the local Verdaccio service.
- pip configuration is redirected to the local devpi service.

## 4. Reset Client Settings

```bash
./pkg-cache.sh client reset
```

```powershell
powershell -ExecutionPolicy Bypass -File .\pkg-cache-client.ps1 -Action reset
```

## Dataset

This project does **not** include a static dataset.

Instead, it works with live package requests from upstream software repositories during runtime:

- Debian/Ubuntu package mirrors for APT
- The npm registry for Node.js packages
- PyPI for Python packages

The package metadata and artifacts remain subject to the licensing and terms of their original upstream ecosystems.

## Project Structure

```text
unified-package-caching-system/
├── README.md
├── LICENSE
├── .gitignore
├── pkg-cache.sh
├── pkg-cache-client.ps1
├── installers/
│   ├── README.md
│   ├── linux/
│   │   ├── installer.py
│   │   └── installer.spec
│   └── windows/
│       ├── installer.py
│       └── installer.spec
├── docs/
│   ├── architecture.md
│   ├── project-information.md
│   ├── project-status.md
│   └── diagrams/
│       ├── architecture-overview.svg
│       └── deployment-workflow.svg
└── examples/
    ├── generated-server-layout.txt
    └── usage-examples.md
```

## Screenshots / Demo

### Architecture Snapshot

![Architecture snapshot](docs/diagrams/architecture-overview.svg)

### Demo Notes

### Sample Demo Flow

1. Start the cache server with `./pkg-cache.sh server install`.
2. Configure a Linux or Windows client.
3. Install packages from the client machine.
4. Repeat the same install to demonstrate that packages are served from the local cache path.

## Contributors

| Team member                 | Role                                                               |
| --------------------------- | ------------------------------------------------------------------ |
| Abdullah Fahim              | Core server automation, Linux client setup, repository integration |
| Amjad Hussain               | Windows client support and configuration                           |
| Mohomad Fazil (Fazilfareed) | GUI installer prototype and UI improvements                        |

## Contact Information

| Item        | Details                                           |
| ----------- | ------------------------------------------------- |
| Name        | Project Team / Repository Maintainer              |
| Email       | fahimabdullah528@gmail.com                        |
| Institution | University of Jaffna                              |

## Licence

This project is released as **open source** under the **MIT License**. See the [`LICENSE`](LICENSE) file for details.

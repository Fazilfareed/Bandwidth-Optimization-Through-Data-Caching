# 📦 Unified Package Caching System (pkg-cache)

A production-ready, automated Bash script to set up a centralized caching server for **APT** (Debian/Ubuntu), **NPM** (Node.js), and **PyPI** (Python).

This project simplifies network infrastructure for development teams, labs, or offline-constrained environments. It drastically reduces bandwidth usage and speeds up `apt update`, `npm install`, and `pip install` commands by caching packages locally.

## 🚀 Features

* **Multi-Protocol Caching:**
  * **APT:** Uses `apt-cacher-ng` (Port `3142`) for Debian/Ubuntu packages.
  * **NPM:** Uses `verdaccio` (Port `4873`) for Node.js packages.
  * **PyPI:** Uses `devpi` (Port `3141`) for Python packages.
* **One-Script Setup:** Handles everything from installing Docker to configuring client machines.
* **Smart Maintenance (GC):** Built-in "Garbage Collector" policy that runs automatically to:
  * Cap cache size per service (Default: **3GB**).
  * Remove old files (Default: **1 day** TTL).
* **Robust Client Config:** Automatically backs up previous client configurations before applying changes and supports full rollback/reset.
* **Permission Handling:** Automatically manages Docker group permissions (`sudo`, `sg`, or direct) without requiring a user logout.
* **Security Fixes:** Includes specific workarounds for `security.ubuntu.com` to prevent 404 errors through the proxy.

## 📋 Prerequisites

### Server Side
* **OS:** Linux (Debian/Ubuntu preferred for auto-install features).
* **Dependencies:** The script will automatically attempt to install `docker` and `docker compose` if they are missing.
* **Ports:** Ensure ports `3142`, `4873`, and `3141` are open on your firewall.

### Client Side
* **OS:** Any Linux distribution (Debian/Ubuntu required for APT caching features).
* **Dependencies:** `curl` (used for connectivity checks).
* **Access:** Must be on the same network as the server.

---

## 🛠️ Installation & Usage

Download the `pkg-cache.sh` script to your machine and make it executable:

```bash
chmod +x pkg-cache.sh

```

### 1. Setting up the Server

Run this command on the machine that will act as the cache server.

```bash
./pkg-cache.sh server install

```

This will:

1. Install Docker and Docker Compose (if missing).
2. Start the caching services.
3. Install a systemd timer to run the cleanup policy every hour.
4. Output the status and available URLs.

**Customizing Cache Limits:**
You can override the default cache size (3GB) and retention period (1 day) using environment variables before running the install command:

```bash
# Example: 10GB limit per service, keep files for 7 days
PKGCACHE_MAX_GB=10 PKGCACHE_TTL_DAYS=7 ./pkg-cache.sh server install

```

### 2. Setting up a Client

Run this command on any machine that needs to use the cache. Replace `192.168.X.X` with your server's IP address.

```bash
./pkg-cache.sh client install 192.168.X.X

```

This will:

1. **APT:** Configure `/etc/apt/apt.conf.d/01-pkg-cache-proxy` and handle security repo exceptions.
2. **NPM:** Set the registry to the Verdaccio instance.
3. **Pip:** Configure `global.index-url` and `trusted-host`.
4. **Verify:** Run connectivity checks to ensure the server is reachable.

> **Tip:** To verify caching is working, run `npm install lodash` or `apt update` on the client and check the server logs.

---

## 🧹 Maintenance & Policies

The server setup installs a background job (systemd timer) that automatically cleans the cache directories to prevent disk overflow.

### Manual Cleanup

You can force a cleanup immediately (prune files older than TTL or exceeding MAX_GB):

```bash
./pkg-cache.sh server policy-run

```

### Uninstall Policy

To stop the automatic background cleanup:

```bash
./pkg-cache.sh server policy-uninstall

```

---

## 🔄 Reset & Uninstall

### Reset Server

Stops all containers, removes the data volumes, and deletes the server directory.

```bash
./pkg-cache.sh server reset

```

### Reset Client

Reverts all client-side configurations (APT proxy, NPM registry, Pip index) to their previous states.

```bash
./pkg-cache.sh client reset

```

---

## 📂 Architecture

The script creates the following directory structure on the server (default: `./pkg-cache` relative to the script location):

```text
pkg-cache/
├── docker-compose.yml       # Service definitions
├── .env                     # Contains generated passwords (e.g., DEVPI_ROOT_PASS)
├── pkg-cache-policy.sh      # The generated maintenance script
├── verdaccio/
│   └── conf/config.yaml     # NPM proxy configuration
└── data/                    # Persistent storage volumes
    ├── apt-cacher-ng/       # .deb files
    ├── verdaccio/           # npm tarballs
    └── devpi/               # python packages

```

---

## ❗ Troubleshooting

| Issue | Solution |
| --- | --- |
| **APT 404 Errors** | The script forces `security.ubuntu.com` to go DIRECT. If you see other 404s, ensure your client `sources.list` uses `http://` instead of `https://` where possible. |
| **Docker Permission Denied** | The script tries to fix this automatically. If it fails, add your user to the docker group: `sudo usermod -aG docker $USER`, then log out and back in. |
| **NPM EACCES / 500** | This is usually a volume permission error. Run `./pkg-cache.sh server install` again; it includes a fix to `chown` the data directory correctly. |
| **Client Connection Refused** | Check if the server's firewall allows traffic on ports `3142`, `4873`, and `3141`. |

---

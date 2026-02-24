# Frappe Docker Setup (v16)

This repository contains `setup_v16.sh`, a one-command bootstrap script for a local **Frappe/ERPNext v16** development environment.

It helps with common setup pain points by:
- Installing and configuring Python via `pyenv`
- Installing and configuring Node.js via `nvm`
- Installing `frappe-bench`
- Initializing a bench and site
- Installing ERPNext (and optional apps)
- Auto-starting MariaDB/Redis services from Docker Compose when needed

## What This Script Supports

- DevContainer-based setup (recommended)
- Automatic `frappe_docker` cloning when no compose file is found
- VS Code Dev Container bootstrap (`--init-vscode`)
- Bare-metal mode (`--bare-metal`) for local MariaDB/Redis
- Optional app installation:
  - `webshop`
  - `hrms`
  - `crm`

## Prerequisites

- macOS or Linux shell environment
- Docker running (unless using `--bare-metal`)
- At least 8 GB RAM
- `pyenv` and `nvm` available (or use `--install-deps`)

## Quick Start

```bash
chmod +x setup_v16.sh
./setup_v16.sh
```

Default values:
- Bench: `frappe-bench`
- Site: `development16.localhost`
- Admin password: `admin`
- DB root password: `123` (or `$DB_ROOT_PASSWORD`)
- Python: `3.14` (auto-fallback to latest available patch version if needed)
- Node: `24`

## Common Usage Examples

### 1) Initialize VS Code DevContainer workspace

```bash
./setup_v16.sh --init-vscode
```

Then open the cloned `frappe_docker` directory in VS Code and run:

```bash
./setup_v16.sh
```

inside the container.

### 2) Full setup with dependency installation

```bash
./setup_v16.sh --install-deps --install-webshop --install-hrms
```

### 3) Use a custom compose file

```bash
./setup_v16.sh --docker-compose-file ../pwd.yml --docker-project-dir ..
```

### 4) Bare-metal setup (no Docker-managed DB/Redis)

```bash
./setup_v16.sh --bare-metal
```

## Key Options

- `-b, --bench-name <name>`: Bench directory name
- `-s, --site-name <name>`: Site name
- `-a, --admin-password <password>`: Admin password
- `-r, --db-root-password <password>`: MariaDB root password
- `-p, --python-version <version>`: Python version for pyenv
- `-n, --node-version <version>`: Node version for nvm
- `--install-deps`: Install `pyenv` and `nvm` if missing
- `--install-webshop`: Install webshop app
- `--install-hrms`: Install HRMS app
- `--install-crm`: Install CRM app
- `--skip-bench-init`: Skip `bench init` if bench already exists
- `--skip-docker-up`: Skip starting Docker services
- `--docker-compose-file <path>`: Compose file path
- `--docker-project-dir <path>`: Compose project root
- `--clone-dir <path>`: Clone target for `frappe_docker`
- `--skip-clone`: Reuse existing clone
- `--init-vscode`: Prepare VS Code devcontainer setup
- `--bare-metal`: Use localhost DB/Redis instead of Docker service names

For full option help:

```bash
./setup_v16.sh --help
```

## After Setup

Start development server:

```bash
cd frappe-bench
bench start
```

Open site:

- `http://development16.localhost:8000`

## Notes

- The script is designed around the Frappe Docker/devcontainer flow.
- If running outside a devcontainer in Docker mode, internal compose service hostnames may not be reachable from your host shell.
- Use `--bare-metal` if you want to connect to locally running MariaDB/Redis (`localhost`).
- Thanks to Antony for the original outline in the Frappe Forum https://discuss.frappe.io/t/tutorial-erpnext-v16-local-docker-setup-for-development/159165/14

# CodeIsland Distribution Node & CI/CD Deployment

This guide documents the architecture, automated deployment pipelines, and node setup required to distribute CodeIsland updates via self-hosted Debian infrastructure and Sparkle auto-updates.

---

## 1. Architecture Overview

CodeIsland operates a zero-cost, self-hosted build and distribution pipeline:
- **Build Runner:** Local KVM-accelerated macOS Sonoma VM (`macos-kvm-builder`) on AMD Ryzen hardware, eliminating cloud macOS runner costs.
- **Orchestration:** Self-hosted Woodpecker CI Server (`ci-codeisland.azhr.cloud`) connected to the local runner over a persistent reverse SSH tunnel.
- **Distribution Node:** Debian server (`codeisland.azhr.cloud`) fronted by Cloudflare Tunnel and Nginx, serving signed DMGs and Sparkle XML feeds.

```mermaid
flowchart TD
    subgraph GitHub["GitHub Remote: fzrsahi/CodeIsland"]
        E_PR["Event: pull_request"]
        E_DEV["Event: push to dev"]
        E_MAIN["Event: push to main"]
        E_TAG["Event: tag v*"]
    end

    subgraph Orchestration["AWS CI Server: ci-codeisland.azhr.cloud"]
        WP["Woodpecker Server Engine"]
        TUNNEL["Reverse SSH Tunnel (:9090)"]
        WP <--> TUNNEL
    end

    subgraph Runner["Local Runner: macos-kvm-builder"]
        AGENT["Woodpecker Agent (darwin/amd64)"]
        TUNNEL <--> AGENT
        
        STEP_TEST["Step: test\nswift test (531 targets)"]
        STEP_DEV["Step: build-dev-dmg\nBuild Beta DMG + Sign"]
        STEP_PROD["Step: build-release-dmg\nBuild Prod DMG + Sign"]
    end

    subgraph Distribution["AWS Debian Server: codeisland.azhr.cloud"]
        WEB["Nginx Web Root (/var/www/codeisland-updates)"]
        FEED_DEV["appcast-dev.xml\n(Beta Channel)"]
        FEED_PROD["appcast.xml\n(Stable Channel)"]
        WEB --> FEED_DEV
        WEB --> FEED_PROD
    end

    E_PR --> WP
    E_DEV --> WP
    E_MAIN --> WP
    E_TAG --> WP

    WP -->|Trigger| STEP_TEST
    WP -->|Trigger| STEP_DEV
    WP -->|Trigger| STEP_PROD

    STEP_DEV -->|Webhook POST /api/deploy-webhook| FEED_DEV
    STEP_PROD -->|Webhook POST /api/deploy-webhook| FEED_PROD
```

---

## 2. End-to-End Release Sequence

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Developer
    participant Git as GitHub (fzrsahi/CodeIsland)
    participant WP as AWS Woodpecker Server
    participant Run as Local macOS Runner
    participant Web as AWS Debian Node
    actor User as End User (App)

    rect rgb(245, 247, 250)
        Note over Dev,Run: Phase 1: Pull Request & Test Validation
        Dev->>Git: Push feature branch & open PR to dev/main
        Git->>WP: Webhook: pull_request
        WP->>Run: Dispatch step: test
        Run->>Run: swift test (531 targets, native XCTest)
        Run-->>WP: Status: exit code 0 (Success)
        WP->>Git: Commit Status: Green Checkmark
    end

    rect rgb(240, 245, 255)
        Note over Dev,Web: Phase 2: Dual-Track Build & Deployment
        alt Dev Merge (Beta Channel)
            Git->>WP: Webhook: push to dev
            WP->>Run: Dispatch step: build-dev-dmg
            Run->>Run: Package CodeIsland-dev.dmg & sign with Ed25519
            Run->>Web: Webhook POST /api/deploy-webhook (channel: dev)
            Web->>Web: Atomically update appcast-dev.xml
        else Release Tag (Stable Channel)
            Dev->>Git: Push tag v1.0.X to main
            Git->>WP: Webhook: tag v1.0.X
            WP->>Run: Dispatch step: build-release-dmg
            Run->>Run: Package CodeIsland.dmg & sign with Ed25519
            Run->>Web: Webhook POST /api/deploy-webhook (channel: stable)
            Web->>Web: Atomically update appcast.xml & latest.dmg
        end
    end

    rect rgb(250, 250, 250)
        Note over Web,User: Phase 3: Client Update Verification
        User->>Web: GET /appcast.xml (or appcast-dev.xml)
        Web-->>User: Enclosure with Ed25519 signature
        User->>User: Verify signature against Info.plist SUPublicEDKey
        User->>Web: Download verified DMG and install
    end
```

---

## 3. Debian Server Setup

### 1. Run Node Setup Script
Copy the `deploy/debian/` directory to the Debian server and execute:

```bash
sudo ./deploy/debian/setup-debian-node.sh
```

The script performs the following tasks:
- Installs `webhook`, `curl`, and `jq`.
- Creates `/var/www/codeisland-updates/releases/` with `www-data` ownership.
- Generates a cryptographically random 32-character `WEBHOOK_SECRET`.
- Configures and starts the systemd service `codeisland-webhook.service` on `127.0.0.1:9000`.

> [!IMPORTANT]
> Record the `WEBHOOK_SECRET` printed at the end of the script output. It is stored in Woodpecker CI Server secrets as `codeisland_webhook_secret`.

---

### 2. Configure Nginx
Copy the Nginx configuration template to `sites-available`:

```bash
sudo cp deploy/debian/nginx-updates.conf /etc/nginx/sites-available/codeisland-updates.conf
```

Edit the file to set the `server_name` to match your designated Cloudflare Tunnel domain:

```bash
sudo nano /etc/nginx/sites-available/codeisland-updates.conf
# Set: server_name codeisland.azhr.cloud;
```

Enable the configuration and reload Nginx:

```bash
sudo ln -s /etc/nginx/sites-available/codeisland-updates.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

### 3. Cloudflare Tunnel Routing
Ensure your Cloudflare Zero Trust tunnel configuration routes the designated hostname to the local Nginx instance on port 80:

```yaml
ingress:
  - hostname: codeisland.azhr.cloud
    service: http://localhost:80
  - service: http_status:404
```

---

## 4. Secret Configuration (Woodpecker CI)

Secrets are securely maintained in Woodpecker Server (`https://ci-codeisland.azhr.cloud/fzrsahi/CodeIsland/settings/secrets`):

| Secret Name | Description | Scope |
|---|---|---|
| `codeisland_webhook_secret` | Shared secret token for `/api/deploy-webhook` | Injected into `build-dev-dmg` & `build-release-dmg` |
| `sparkle_private_key` | Ed25519 private key used to sign DMG releases | Injected in-memory to `sign_update` |

---

## 5. Release Execution & Verification

### Production Release (Stable)
Push a semantic version tag to `main`:
```bash
git tag v1.0.41
git push origin v1.0.41
```
The CI runner will compile universal arm64/x86_64 binaries, assemble `CodeIsland.dmg`, sign with the Ed25519 key, and update `https://codeisland.azhr.cloud/appcast.xml`.

### Development Release (Beta)
Merge any pull request into the `dev` branch. The runner automatically packages `CodeIsland-dev.dmg` and publishes the pre-release item to `https://codeisland.azhr.cloud/appcast-dev.xml`.

---

## 6. Monitoring and Logs on Debian

### Standalone Daemon (Systemd)
```bash
journalctl -u codeisland-webhook.service -f
```

### Docker Containerized Node (`codeisland-node`)
```bash
# View real-time webhook & ingress logs
docker logs -f codeisland-node

# Inspect resource utilization (RAM capped at 64MB)
docker stats --no-stream codeisland-node

# Inspect releases directory
docker exec codeisland-node ls -la /data/releases/
```

Verify the Sparkle update feed endpoint:
```bash
curl -I https://codeisland.azhr.cloud/appcast.xml
curl -I https://codeisland.azhr.cloud/appcast-dev.xml
```

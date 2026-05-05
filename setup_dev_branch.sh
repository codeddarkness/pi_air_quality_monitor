#!/usr/bin/env bash
# =============================================================================
# setup_dev_branch.sh v0.1.0
# Sets up custom_dev branch, organizes custom/ and diagnostic files,
# seeds semantic versioning, and prepares development structure.
# Usage: bash setup_dev_branch.sh
# =============================================================================

set -euo pipefail

SCRIPT_VERSION="0.1.0"
REPO_DIR="${HOME}/pi_air_quality_monitor"
BRANCH="custom_dev"

log() { echo -e "[\033[0;36m$(date +%H:%M:%S)\033[0m] $*"; }
ok()  { echo -e "[\033[0;32mOK\033[0m] $*"; }
err() { echo -e "[\033[0;31mERR\033[0m] $*" >&2; exit 1; }

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ -d "${REPO_DIR}/.git" ]] || err "Not a git repo: ${REPO_DIR}"
cd "${REPO_DIR}"

CURRENT=$(git branch --show-current)
[[ "${CURRENT}" == "main" ]] || { log "Not on main (on ${CURRENT}). Switching..."; git checkout main; }

git pull --ff-only origin main 2>/dev/null || log "Could not pull — continuing offline."

# ── Create branch ─────────────────────────────────────────────────────────────
if git show-ref --quiet "refs/heads/${BRANCH}"; then
    log "Branch '${BRANCH}' exists — checking out."
    git checkout "${BRANCH}"
else
    log "Creating branch '${BRANCH}'..."
    git checkout -b "${BRANCH}"
fi

# ── Directory structure ────────────────────────────────────────────────────────
log "Setting up dev directory layout..."

mkdir -p docs/diagnostics
mkdir -p scripts/kiosk
mkdir -p scripts/data
mkdir -p scripts/service
mkdir -p systemd
mkdir -p logs

# ── Move diagnostic/install logs out of root → docs/diagnostics ───────────────
for f in make_install.log make_run.log docker_ps.txt; do
    if [[ -f "${f}" ]]; then
        git mv "${f}" "docs/diagnostics/${f}" 2>/dev/null || mv "${f}" "docs/diagnostics/${f}"
        ok "Moved ${f} → docs/diagnostics/"
    fi
done

# ── Migrate custom/ scripts into organised subdirectories ─────────────────────
log "Migrating custom/ scripts..."

# Kiosk scripts
for f in start_firefox_kiosk.sh fix_perms.sh run_diagnostic.sh update-kiosk-service.sh; do
    [[ -f "custom/${f}" ]] && { git mv "custom/${f}" "scripts/kiosk/${f}" 2>/dev/null || mv "custom/${f}" "scripts/kiosk/${f}"; ok "Moved ${f} → scripts/kiosk/"; }
done

# Data / reformatter scripts
for f in reformat_aqi_data.sh run_reformatter.sh pull_aqi_api_data.sh follow_api_curl_dump.sh check_ranges.func gen_debug.sh debug.func; do
    [[ -f "custom/${f}" ]] && { git mv "custom/${f}" "scripts/data/${f}" 2>/dev/null || mv "custom/${f}" "scripts/data/${f}"; ok "Moved ${f} → scripts/data/"; }
done

# Service / install scripts
for f in install.sh aqi_monitor.func paqm.service pi-crontab set_tty_aqi.sh; do
    [[ -f "custom/${f}" ]] && { git mv "custom/${f}" "scripts/service/${f}" 2>/dev/null || mv "custom/${f}" "scripts/service/${f}"; ok "Moved ${f} → scripts/service/"; }
done

# Systemd unit files
for f in paqm.service; do
    [[ -f "scripts/service/${f}" ]] && { cp "scripts/service/${f}" "systemd/${f}"; ok "Copied ${f} → systemd/"; }
done

# docker-compose override for custom timezone mounts
[[ -f "custom/docker-compose.yaml" ]] && { git mv "custom/docker-compose.yaml" "docker-compose.custom.yaml" 2>/dev/null || mv "custom/docker-compose.yaml" "docker-compose.custom.yaml"; ok "Moved custom docker-compose.yaml → docker-compose.custom.yaml"; }

# Python util
[[ -f "custom/show_current_time.py" ]] && { git mv "custom/show_current_time.py" "scripts/data/show_current_time.py" 2>/dev/null || mv "custom/show_current_time.py" "scripts/data/show_current_time.py"; ok "Moved show_current_time.py → scripts/data/"; }

# bashrc snippet
[[ -f "custom/add_to_bashrc.txt" ]] && { git mv "custom/add_to_bashrc.txt" "docs/add_to_bashrc.txt" 2>/dev/null || mv "custom/add_to_bashrc.txt" "docs/add_to_bashrc.txt"; ok "Moved add_to_bashrc.txt → docs/"; }

# Remove empty custom/ dir if empty
[[ -d "custom" ]] && rmdir --ignore-fail-on-non-empty "custom" && ok "Removed empty custom/ directory"

# ── VERSION file (semantic versioning) ────────────────────────────────────────
log "Writing VERSION..."
cat > VERSION << 'EOF'
# pi_air_quality_monitor version
# Format: MAJOR.MINOR.PATCH[-prerelease]
# MAJOR - breaking API or deployment change
# MINOR - new feature (kiosk, grafana endpoint, etc.)
# PATCH - bug fix / config adjustment
0.2.0-dev
EOF
ok "VERSION → 0.2.0-dev"

# ── CHANGELOG stub ────────────────────────────────────────────────────────────
[[ -f CHANGELOG.md ]] || cat > CHANGELOG.md << 'EOF'
# Changelog

## [Unreleased] - 0.2.0-dev
### Added
- `custom_dev` branch for structured re-implementation
- `scripts/kiosk/` — Firefox ESR kiosk scripts (migrated from custom/)
- `scripts/data/` — data collection, reformat, and API scripts
- `scripts/service/` — install, aqi_monitor.func, crontab
- `systemd/` — unit files for review and deployment
- `docs/diagnostics/` — make_install.log, make_run.log, docker_ps.txt

### Known Issues (to fix)
- docker-compose v1.29.2 ContainerConfig KeyError → migrate to `docker compose` (V2 plugin)
- Data refresh stale in browser → reformat_aqi_data.sh cron reliability
- Kiosk start order race (Firefox before docker stack is ready)
- Redis data not persisted across restarts on clean run

## [0.1.0] - initial mirror
### Added
- Mirror of rydercalmdown/pi_air_quality_monitor
- custom/ directory with previous deployment scripts
EOF
ok "CHANGELOG.md created"

# ── .gitignore additions ───────────────────────────────────────────────────────
grep -q 'logs/' .gitignore 2>/dev/null || cat >> .gitignore << 'EOF'

# Dev additions
logs/
*.log
_local_data/
json_data/
data/redis/
.env
EOF
ok ".gitignore updated"

# ── Commit everything ──────────────────────────────────────────────────────────
log "Staging and committing..."
git add -A
git commit -m "chore(v0.2.0-dev): init custom_dev branch

- Migrate custom/ scripts → scripts/{kiosk,data,service}/
- Move diagnostic logs → docs/diagnostics/
- Add VERSION (0.2.0-dev), CHANGELOG.md
- Update .gitignore
- Preserve custom docker-compose as docker-compose.custom.yaml

Known issues documented in CHANGELOG.md"

ok "Branch '${BRANCH}' committed."

# ── Push branch ───────────────────────────────────────────────────────────────
log "Pushing ${BRANCH} to origin..."
git push -u origin "${BRANCH}"
ok "Pushed → git@github.com:codeddarkness/pi_air_quality_monitor.git (${BRANCH})"

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo "======================================================================"
echo "  Branch ready: ${BRANCH}  (v0.2.0-dev)"
echo "======================================================================"
echo "  Layout:"
echo "    scripts/kiosk/    — Firefox ESR kiosk scripts"
echo "    scripts/data/     — reformat, API, collection scripts"
echo "    scripts/service/  — aqi_monitor.func, install, crontab"
echo "    systemd/          — unit files for kiosk + paqm services"
echo "    docs/diagnostics/ — make_run.log, make_install.log, docker_ps.txt"
echo
echo "  Priority fixes to tackle next:"
echo "    1. Replace 'docker-compose' (v1) → 'docker compose' (V2 plugin)"
echo "    2. Fix Makefile targets to use docker compose V2"
echo "    3. Stabilise reformat_aqi_data.sh + cron scheduling"
echo "    4. Wire systemd units: paqm.service → firefox-kiosk.service"
echo "    5. Add /api/v1/metrics endpoint for Grafana HTTP data source"
echo "======================================================================"
echo
echo "  Network endpoints (when running):"
echo "    Local kiosk  : http://localhost:8000"
echo "    Network      : http://$(hostname -I | awk '{print $1}'):8000"
echo "    Grafana      : http://10.0.0.194:3000"
echo "======================================================================"

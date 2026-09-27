#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
set -euo pipefail

# Options are read straight from /data/options.json (written by the Supervisor) so startup
# does not depend on the Supervisor API being reachable.
OPTIONS=/data/options.json
option() {
    jq -r --arg key "$1" --arg default "${2:-}" \
        'if has($key) and .[$key] != null then (.[$key] | tostring) else $default end' "${OPTIONS}"
}
option_true() {
    [[ "$(option "$1" false)" == "true" ]]
}

bashio::log.level "$(option log_level info)"

AMP_API_KEY="$(option amp_api_key)"
if [[ -z "${AMP_API_KEY}" ]]; then
    bashio::log.fatal
    bashio::log.fatal "The 'amp_api_key' option is empty."
    bashio::log.fatal "Create an access token at https://ampcode.com/settings/security (it starts"
    bashio::log.fatal "with sgamp_), paste it into the add-on configuration and start again."
    bashio::log.fatal
    bashio::exit.nok
fi
if [[ "${AMP_API_KEY}" != sgamp_* ]]; then
    bashio::log.warning "amp_api_key does not start with 'sgamp_'; Amp rejects session tokens from 'amp login'. Use an access token from ampcode.com/settings/security."
fi

# Everything Amp writes (settings, account, logs, self-updated binary) lives under /data so it
# survives add-on restarts and updates.
export HOME=/data/home
export AMP_API_KEY

RUNNER_ID="$(option runner_id home-assistant)"
WORKSPACE=/data/workspace
TEMPLATE=/opt/workspace
AMP_BIN="${HOME}/.amp/bin/amp"

mkdir -p "${HOME}/.amp/bin" "${HOME}/.config/amp" "${WORKSPACE}"

# ---------------------------------------------------------------------------
# Amp CLI binary: copy the image's build into /data on first start or when the image
# carries a newer release than the persisted (self-updated) copy.
# ---------------------------------------------------------------------------
image_version="$(cat /opt/amp/version)"
installed_version=""
if [[ -x "${AMP_BIN}" ]]; then
    installed_version="$("${AMP_BIN}" --version 2>/dev/null | awk 'NR==1 {print $1}')" || installed_version=""
fi
if [[ -z "${installed_version}" ]] \
    || [[ "$(printf '%s\n%s\n' "${installed_version}" "${image_version}" | sort -V | tail -n1)" != "${installed_version}" ]]; then
    bashio::log.info "Installing Amp CLI ${image_version} into ${AMP_BIN}"
    install -m 0755 /opt/amp/bin/amp "${AMP_BIN}"
fi
export PATH="${HOME}/.amp/bin:${WORKSPACE}/bin:${PATH}"

# ---------------------------------------------------------------------------
# Workspace: the directory the runner serves. bin/ is always restored from the add-on;
# AGENTS.md is refreshed unless you edited it; anything else you add is kept.
# ---------------------------------------------------------------------------
sync_template_file() {
    local rel="$1"
    local src="${TEMPLATE}/${rel}"
    local dst="${WORKSPACE}/${rel}"
    local stamp="${WORKSPACE}/.template-sha/${rel}.sha256"
    local new_sum
    new_sum="$(sha256sum "${src}" | cut -d' ' -f1)"

    if [[ "${rel}" != bin/* && -f "${dst}" && -f "${stamp}" ]]; then
        local old_sum current_sum
        old_sum="$(cat "${stamp}")"
        current_sum="$(sha256sum "${dst}" | cut -d' ' -f1)"
        if [[ "${current_sum}" != "${old_sum}" ]]; then
            bashio::log.notice "Keeping your edited ${rel} (add-on ships a newer version at ${TEMPLATE}/${rel})"
            return
        fi
    fi
    mkdir -p "$(dirname "${dst}")" "$(dirname "${stamp}")"
    cp "${src}" "${dst}"
    echo "${new_sum}" > "${stamp}"
}

while IFS= read -r -d '' file; do
    sync_template_file "${file#"${TEMPLATE}"/}"
done < <(find "${TEMPLATE}" -type f -print0)
chmod a+x "${WORKSPACE}"/bin/* 2>/dev/null || true

# A Git checkout makes the Changes pane work on ampcode.com and gives you history of what
# the agent wrote into the workspace.
if [[ ! -d "${WORKSPACE}/.git" ]]; then
    git -C "${WORKSPACE}" init -q -b main
    git -C "${WORKSPACE}" add -A
    git -C "${WORKSPACE}" -c user.name='Amp Runner' -c user.email='amp-runner@localhost' \
        commit -q -m 'Initial workspace' || true
fi
if [[ -z "$(git config --global --get user.name || true)" ]]; then
    git config --global user.name 'Amp Runner'
    git config --global user.email 'amp-runner@localhost'
fi
git config --global --add safe.directory '*'

# ---------------------------------------------------------------------------
# Runner flags
# ---------------------------------------------------------------------------
args=(--no-tui --runner-id "${RUNNER_ID}")
if [[ -d /homeassistant ]]; then
    args+=(--dir /homeassistant)
fi
if option_true remote_terminal; then
    args+=(--remote-control-terminal)
fi
if option_true amp_env; then
    args+=(--amp-env)
fi
if option_true share_runner; then
    bashio::log.warning "share_runner is on: every member of your Amp workspace can run threads on this machine."
    args+=(--share)
fi

cd "${WORKSPACE}"
bashio::log.info "Amp CLI $(amp --version 2>/dev/null | awk 'NR==1 {print $1}')"
bashio::log.info "Workspace: ${WORKSPACE}; flags: ${args[*]}"

# Keep the runner alive for as long as the add-on runs. Amp's own self-update restarts the
# process; a crash or a network outage at boot just gets retried.
delay=5
while true; do
    bashio::log.info "Starting Amp runner '${RUNNER_ID}'"
    started=${SECONDS}
    if amp "${args[@]}"; then
        bashio::log.info "Amp runner exited; restarting in ${delay}s"
    else
        bashio::log.warning "Amp runner exited with status $?; restarting in ${delay}s"
    fi
    sleep "${delay}"
    # Back off on quick failures (bad token, no network yet); reset after a healthy run.
    if (( SECONDS - started > 120 )); then
        delay=5
    elif (( delay < 120 )); then
        delay=$(( delay * 2 ))
    fi
done

#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Inputs (GitHub Action -> $INPUT_*)
# ==============================
# Port / repo management (kept from previous script)
port_client_id="${INPUT_PORTCLIENTID:-}"
port_client_secret="${INPUT_PORTCLIENTSECRET:-}"
port_run_id="${INPUT_PORTRUNID:-}"
github_token="${INPUT_TOKEN:-}"
blueprint_identifier="${INPUT_BLUEPRINTIDENTIFIER:-}"
repository_name="${INPUT_REPOSITORYNAME:-}"
org_name="${INPUT_ORGANIZATIONNAME:-}"
create_port_entity="${INPUT_CREATEPORTENTITY:-true}"
monorepo_url="${INPUT_MONOREPOURL:-}"
scaffold_directory="${INPUT_SCAFFOLDDIRECTORY:-}"
port_user_inputs="${INPUT_PORTUSERINPUTS:-}"   # may be used as a fallback for Maven options
branch_name="port_${INPUT_PORTRUNID:-$(date +%s)}"
git_url="${INPUT_GITHUBURL:-https://api.github.com}"

# Artifactory + Maven
artifactory_username="${INPUT_ARTIFACTORYUSERNAME:-}"
artifactory_password="${INPUT_ARTIFACTORYPASSWORD:-}"
artifactory_host="${INPUT_ARTIFACTORYHOST:-}"
settings_template_path="${INPUT_SETTINGSTEMPLATEPATH:-/github/workspace/.github/config-files/settings.xml.tpl}"

archetype_group_id="${INPUT_ARCHETYPEGROUPID:-}"
archetype_artifact_id="${INPUT_ARCHETYPEARTIFACTID:-}"
archetype_version="${INPUT_ARCHETYPEVERSION:-}"
# JSON object with arbitrary -Dkey=value pairs for different archetypes
# Example: '{"groupId":"pe.interbank","artifactId":"mdp-pagopush-customer","version":"1.0.0"}'
maven_options_json="${INPUT_MAVENOPTIONSJSON:-}"
# Extra CLI flags if needed (e.g., "-DarchetypeCatalog=internal")
maven_extra_args="${INPUT_MAVENEXTRAARGS:-}"

# ==============================
# Helpers
# ==============================
get_access_token() {
  if [[ -z "${port_client_id}" || -z "${port_client_secret}" ]]; then
    echo "Skipping Port token fetch (client id/secret not provided)."
    return 0
  fi
  curl -sS --location --request POST "https://api.getport.io/v1/auth/access_token" \
    --header 'Content-Type: application/json' \
    --data-raw "{\n      \"clientId\": \"${port_client_id}\",\n      \"clientSecret\": \"${port_client_secret}\"\n    }" | jq -r '.accessToken'
}

send_log() {
  local message="${1:-}"
  if [[ -n "${port_run_id}" && -n "${access_token:-}" ]]; then
  curl -sS --location "https://api.getport.io/v1/actions/runs/${port_run_id}/logs" \
  --header "Authorization: Bearer ${access_token}" \
  --header "Content-Type: application/json" \
  --data "$(jq -n --arg m "$message" '{message:$m}')" >/dev/null || true
  fi
  echo "$message"
}

add_link() {
  local url="$1"
  if [[ -n "${port_run_id}" && -n "${access_token:-}" ]]; then
    curl -sS --request PATCH --location "https://api.getport.io/v1/actions/runs/${port_run_id}" \
      --header "Authorization: Bearer ${access_token}" \
      --header "Content-Type: application/json" \
      --data "{\n        \"link\": \"${url}\"\n      }" >/dev/null || true
  fi
}

create_repository() {
  local who_resp userType http out
  who_resp=$(curl -fsS -H "Authorization: token ${github_token}" \
    -H "Accept: application/json" "${git_url}/users/${org_name}")
  userType=$(jq -r '.type' <<<"${who_resp}")

  if [[ "${userType}" == "User" ]]; then
    out=$(mktemp)
    http=$(curl -sS -o "${out}" -w "%{http_code}" -X POST \
      -H "Authorization: token ${github_token}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Accept: application/json" \
      -d "{\"name\":\"${repository_name}\",\"private\":true}" \
      "${git_url}/user/repos")
  elif [[ "${userType}" == "Organization" ]]; then
    out=$(mktemp)
    http=$(curl -sS -o "${out}" -w "%{http_code}" -X POST \
      -H "Authorization: token ${github_token}" \
      -H "Accept: application/json" \
      -d "{\"name\":\"${repository_name}\",\"private\":true}" \
      "${git_url}/orgs/${org_name}/repos")
  else
    echo "Invalid user/org: ${org_name}" >&2; exit 1
  fi

  if [[ "${http}" != "201" ]]; then
    echo "Failed to create repo ${org_name}/${repository_name} (HTTP ${http}). Response:" >&2
    cat "${out}" >&2
    exit 1
  fi
}

clone_monorepo() {
  git clone "${monorepo_url}" monorepo
  cd monorepo
  git checkout -b "${branch_name}"
}

cd_to_scaffold_directory() {
  if [[ -n "${monorepo_url}" && -n "${scaffold_directory}" ]]; then
    cd "${scaffold_directory}"
  fi
}

mask_secrets() {
  # Ensure secrets don't show up in logs
  [[ -n "${artifactory_password}" ]] && echo "::add-mask::${artifactory_password}"
  [[ -n "${artifactory_username}" ]] && echo "::add-mask::${artifactory_username}"
}

render_maven_settings() {
  if [[ ! -f "${settings_template_path}" ]]; then
    echo "settings.xml.tpl not found at ${settings_template_path}" >&2
    exit 1
  fi
  mkdir -p "${HOME}/.m2"
  SETTINGS_TPL_PATH="${settings_template_path}" \
  ARTIFACTORY_USERNAME="${artifactory_username}" \
  ARTIFACTORY_PASSWORD="${artifactory_password}" \
  ARTIFACTORY_HOST="${artifactory_host}" \
  python3 - <<'PY'
import os, sys
src = os.environ['SETTINGS_TPL_PATH']
dst = os.path.expanduser('~/.m2/settings.xml')
with open(src, 'r', encoding='utf-8') as f:
    s = f.read()
s = s.replace('{ARTIFACTORY_USERNAME}', os.environ.get('ARTIFACTORY_USERNAME', ''))
s = s.replace('{ARTIFACTORY_PASSWORD}', os.environ.get('ARTIFACTORY_PASSWORD', ''))
s = s.replace('{ARTIFACTORY_HOST}', os.environ.get('ARTIFACTORY_HOST', ''))
os.makedirs(os.path.dirname(dst), exist_ok=True)
with open(dst, 'w', encoding='utf-8') as f:
    f.write(s)
print(dst)
PY
}

prepare_maven_options_json() {
  # If the user supplied MAVENOPTIONSJSON, use it. Otherwise, derive from Port user inputs
  if [[ -n "${maven_options_json}" && "${maven_options_json}" != "null" ]]; then
    echo "${maven_options_json}"
  else
    # Derive from keys that start with maven_ (e.g., maven_groupId, maven_artifactId)
    if [[ -n "${port_user_inputs}" ]]; then
      echo "${port_user_inputs}" | jq -r 'with_entries(select(.key | startswith("maven_")) | .key |= sub("^maven_"; ""))'
    else
      echo '{}'
    fi
  fi
}

apply_maven_archetype() {
  # Render ~/.m2/settings.xml with Artifactory creds
  send_log "Preparing Maven settings.xml for Artifactory auth 🔐"
  render_maven_settings

  # Build -D options from JSON
  local opts_json
  opts_json=$(prepare_maven_options_json)

  # Convert JSON into -Dkey=value args
  local dyn_args=()
  if [[ -n "${opts_json}" && "${opts_json}" != "null" ]]; then
    while IFS= read -r key; do
      local val
      val=$(jq -r --arg k "$key" '.[$k]' <<<"${opts_json}")
      dyn_args+=("-D${key}=${val}")
    done < <(jq -r 'keys[]' <<<"${opts_json}")
  fi

  # Validate required archetype coordinates
  if [[ -z "${archetype_group_id}" || -z "${archetype_artifact_id}" || -z "${archetype_version}" ]]; then
    echo "archetype coordinates are required: ARCHETYPEGROUPID, ARCHETYPEARTIFACTID, ARCHETYPEVERSION" >&2
    exit 1
  fi

  # Do not echo secrets or full command — show a sanitized preview
  send_log "Running Maven archetype generate ☕ (groupId=${archetype_group_id}, artifactId=${archetype_artifact_id}, version=${archetype_version})"

  mvn -s "${HOME}/.m2/settings.xml" archetype:generate --batch-mode \
    -DarchetypeGroupId="${archetype_group_id}" \
    -DarchetypeArtifactId="${archetype_artifact_id}" \
    -DarchetypeVersion="${archetype_version}" \
    -DinteractiveMode=false \
    ${maven_extra_args} \
    "${dyn_args[@]}"
}

push_to_repository() {
  if [[ -n "${monorepo_url}" && -n "${scaffold_directory}" ]]; then
    git config user.name "GitHub Actions Bot"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add .
    git commit -m "Scaffolded project in ${scaffold_directory} via Maven archetype"
    git push -u origin "${branch_name}"

    send_log "Creating pull request to merge ${branch_name} into main 🚢"

    local remote_url owner repo
    remote_url=$(git config --get remote.origin.url)
    owner=$(printf "%s" "$remote_url" | sed -E 's#(git@|https?://)github.com[:/]|\.git$##; s#^[^/]+/##; s#/.*$##')
    repo=$(printf "%s" "$remote_url" | sed -E 's#(git@|https?://)github.com[:/]|\.git$##; s#^[^/]+/##; s#^.*/##')

    local PR_PAYLOAD
    PR_PAYLOAD=$(jq -n --arg title "Scaffolded project in ${repo}" --arg head "${branch_name}" --arg base "main" '{title:$title, head:$head, base:$base}')

    pr_url=$(curl -sS -X POST \
      -H "Authorization: token ${github_token}" \
      -H "Content-Type: application/json" \
      -d "${PR_PAYLOAD}" \
      "${git_url}/repos/${owner}/${repo}/pulls")

    [[ -n "${pr_url}" && "${pr_url}" != "null" ]] && send_log "Opened a new PR: ${pr_url} 🚀" && add_link "${pr_url}"
  else
    # Move into the newly generated project directory (most recent folder)
    local gen_dir
    gen_dir=$(ls -td -- */ 2>/dev/null | head -n 1 | sed 's#/##')
    if [[ -z "${gen_dir}" ]]; then
      echo "Could not locate generated project directory" >&2
      exit 1
    fi
    cd "${gen_dir}"

    git init
    git config user.name "GitHub Actions Bot"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add .
    git commit -m "Initial commit after Maven archetype scaffolding"
    git branch -M main
    git remote add origin "https://oauth2:${github_token}@github.com/${org_name}/${repository_name}.git"
    git push -u origin main
  fi
}

report_to_port() {
  if [[ -z "${blueprint_identifier}" || -z "${port_run_id}" || -z "${access_token:-}" ]]; then
    return 0
  fi
  curl -sS --location "https://api.getport.io/v1/blueprints/${blueprint_identifier}/entities?run_id=${port_run_id}" \
    --header "Authorization: Bearer ${access_token}" \
    --header "Content-Type: application/json" \
    --data "{\n      \"identifier\": \"${repository_name}\",\n      \"title\": \"${repository_name}\",\n      \"properties\": {}\n    }" >/dev/null || true
}

main() {
  mask_secrets
  access_token=$(get_access_token || true)

  if [[ -z "${monorepo_url}" || -z "${scaffold_directory}" ]]; then
    send_log "Creating a new repository: ${repository_name} 🏃"
    create_repository
    send_log "Created a new repository at https://github.com/${org_name}/${repository_name} 🚀"
  else
    send_log "Using monorepo scaffolding 🏃"
    clone_monorepo
    cd_to_scaffold_directory
    send_log "Cloned monorepo and created branch ${branch_name} 🚀"
  fi

  send_log "Starting scaffolding with Maven archetype ☕"
  apply_maven_archetype

  send_log "Pushing the scaffolded code to the repository ⬆️"
  push_to_repository

  if [[ "${create_port_entity}" == "true" ]]; then
    send_log "Reporting the new entity to Port 🚢"
    report_to_port
  else
    send_log "Skipping Port entity creation 🚢"
  fi

  if [[ -n "${monorepo_url}" && -n "${scaffold_directory}" ]]; then
    send_log "Finished! 🏁✅"
  else
    send_log "Finished! Visit https://github.com/${org_name}/${repository_name} 🏁✅"
  fi
}

main

#!/usr/bin/env bash

# Exit on any error, undefined variable, or pipe failure 
set -eo pipefail

log() {
  local prefix_spacer="-----"
  local component="Deploy"
  local prefix="${prefix_spacer} [${component}]"
  if [ "${1}" = 'debug' ]; then
    if [ "$debug" = 1 ]; then
      echo "$prefix DEBUG: ${2}"
    fi
  elif [ "${1}" = 'info' ]; then
    echo "$prefix INFO: ${2}"
  elif [ "${1}" = 'warn' ]; then
    echo "$prefix WARN: ${2}" >&2
  elif [ "${1}" = 'error' ]; then
    echo "$prefix ERROR: ${2}" >&2
  else
    echo "$prefix INTERNAL ERROR: invalid option \"${1}\" for log() with message \"${2}\"" >&2 "" >&2
  fi
}

verify_var_set() {
  if [ -z "${!1}" ]; then
    if [ -z "${2}" ]; then
      log 'error' "\"${1}\" is blank or unset!"
    else
      log 'error' "${2}"
    fi
    exit 1
  fi
}

check_exists_file() {
  if [ ! -f "$1" ]; then
    if [ -e "$1" ]; then
      log 'error' "Item at path \"$1\" exists, but it is not a file!"
    else
      log 'error' "File \"$1\" does not exist!"
    fi
    exit 1
  else
    log 'debug' "File \"$1\" exists!"
  fi
}

# Translate input environment variables
deploy_server="${INPUT_DEPLOY_SERVER}"
deploy_username="${INPUT_DEPLOY_USERNAME}"
deploy_root_dir="${INPUT_DEPLOY_ROOT_DIR}"
encrypted_deploy_key_encryption_key="${INPUT_ENCRYPTED_DEPLOY_KEY_ENCRYPTION_KEY}"
app_path="${INPUT_PATH}"
stable_branch="${INPUT_STABLE_BRANCH}"
beta_branch="${INPUT_BETA_BRANCH}"
debug="${INPUT_DEBUG}"

repository="${GITHUB_REPOSITORY}"
ref="${GITHUB_REF}"

verify_var_set 'ref' 'GITHUB_REF is blank or unset!'
verify_var_set 'repository' 'GITHUB_REPOSITORY is blank or unset!'

verify_var_set 'stable_branch'
verify_var_set 'beta_branch'

if echo "$ref" | grep -qE '^refs\/(tags|remote)\/'; then
  ref_type='tag/remote'
elif echo "$ref" | grep -qE '^refs\/heads\/'; then
  ref_type='branch'
fi

verify_var_set 'ref_type' "Could not detect valid ref type from ref \"${ref}\""

ref_name=$(echo "${ref}" | sed -E 's/refs\/(heads|tags|remote)\///')

verify_var_set 'ref_name' 'Could not extract a proper supported Git ref name!'

log 'debug' "Ref type detected \"${ref_type}\" with name \"${ref_name}\""

if [ "$ref_type" = 'tag/remote' ]; then
  log 'error' "Unsupported ref \"${ref}\" with detected ref type \"${ref_type}\""
  exit 1
elif [ "$ref_type" = 'branch' ]; then
  if [ "$ref_name" = "$stable_branch" ]; then
    channel='stable'
  elif [ "$ref_name" = "$beta_branch" ]; then 
    channel='beta'
  fi
fi

verify_var_set 'channel' "Could not detect release channel from ref type \"${ref_type}\" and ref name \"${ref_name}\""

log 'debug' "Detected release channel \"${channel}\""

repository_path='/github/workspace'

verify_var_set 'deploy_server'
verify_var_set 'deploy_username'
verify_var_set 'deploy_root_dir'
verify_var_set 'encrypted_deploy_key_encryption_key'
verify_var_set 'app_path' 'path is blank or unset!'
verify_var_set 'debug'
verify_var_set 'repository_path'

local_image_id="$(docker images -q "${GITHUB_REPOSITORY}" 2> /dev/null)"

verify_var_set 'local_image_id' "No local Docker image detected for this repository! Please build a local image first before deploying, and ensure it is tagged with the name of this repository \"$repository\"."

log 'debug' "Local Docker image ID(s) detected: \"${local_image_id}\""

if [ "$(echo "${local_image_id}" | grep -c '$')" -gt 1 ]; then
  log 'error' $"Detected multiple Docker image IDs for this repository! Make sure there is only one Docker image tagged with the name of this repository \"${repository}\"."
  exit 1
fi

local_image="$(docker inspect --format='{{ (index .RepoTags 0) }}' "${local_image_id}" 2> /dev/null)"

verify_var_set 'local_image' 'Could not find the local Docker image name and tag!'

log 'debug' "Local Docker image name and tag: ${local_image}"

encrypted_deploy_key_path="${repository_path}/${app_path}/deploy_key.enc"
verify_var_set 'encrypted_deploy_key_path'
check_exists_file "${encrypted_deploy_key_path}"

openssl enc -aes-256-cbc -d -in "${encrypted_deploy_key_path}" -out deploy_key -k "${encrypted_deploy_key_encryption_key}"

chmod 600 'deploy_key'

eval "$(ssh-agent -s)"

ssh-add 'deploy_key'

ssh_path="${HOME}/.ssh"
verify_var_set 'ssh_path'
mkdir -p "${ssh_path}"

log 'debug' "Scanning for keys..."

{ ssh-keyscan -H "${deploy_server}" >> "${ssh_path}/known_hosts"; } 2>&1
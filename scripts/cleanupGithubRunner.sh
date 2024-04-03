#!/usr/bin/env bash

set -eo pipefail

RUNNER_NAME="${{ github.run_id }}-${{ matrix.index }}"

GITHUB_RUNNER_ID=$(curl -s \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${{ inputs.pat_token }}" \
  https://api.github.com/repos/${{ github.repository }}/actions/runners \
  | jq '.runners | map(select(.name == "'${RUNNER_NAME}'")) | .[].id' -r)

ECS_TASK_ID=""

if [[ -n "${ECS_TASK_ID_ENV}" ]]; then
  ECS_TASK_ID=${ECS_TASK_ID_ENV}
  echo "[INFO] Use ECS Task id from artifact ${ECS_TASK_ID_ENV}"
else
  ECS_TASK_ID=$(curl -s \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${{ inputs.pat_token }}" \
    https://api.github.com/repos/${{ github.repository }}/actions/runners/${GITHUB_RUNNER_ID} \
    | jq -r '.labels[] | select(.name | startswith("task_id:")) | .name' \
    | cut -d: -f2)
fi

aws ecs stop-task \
  --cluster ${{ inputs.ecs_cluster_name }} \
  --task ${ECS_TASK_ID} > /dev/null

echo "[INFO] ECS task ${ECS_TASK_ID} stopped"

curl -s \
  -X DELETE \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${{ inputs.pat_token }}" \
  https://api.github.com/repos/${{ github.repository }}/actions/runners/${GITHUB_RUNNER_ID}

START_TIME=$(date +%s)
while [ $(( $(date +%s) - 120 )) -lt $START_TIME ]; do

  echo "[INFO] Waiting for runner ${{ inputs.runner_name }} to be deleted from Github"

  GITHUB_RUNNER_ID=$(curl -s \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${{ inputs.pat_token }}" \
    https://api.github.com/repos/${{ github.repository }}/actions/runners \
    | jq '.runners | map(select(.name == "'${RUNNER_NAME}'")) | .[].id' -r)

  if [ -z "$GITHUB_RUNNER_ID" ]; then
    echo "[INFO] Runner ${RUNNER_NAME} has been deleted"
    break
  fi

  sleep 10

done

if [ -n "$GITHUB_RUNNER_ID" ]; then
  echo "[ERROR] Runner ${RUNNER_NAME} was not deleted from Github" >&2
  exit 1
fi

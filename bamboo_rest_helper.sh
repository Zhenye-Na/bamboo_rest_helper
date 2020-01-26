#!/usr/bin/bash

# Handy helper functions for using Bamboo REST API Service
# @author: Zhenye Na
# @date: Jan 17, 2019

BAMBOO_REST_API_URL="localhost:8085/rest/api/latest"
USER_AUTH="Authorization: Bearer <your_rest_api_token>"


function getProjectKeyByName() {
  local project_name=${1}
  local project_key=$( curl -s "${BAMBOO_REST_API_URL}/deploy/project/all.json?max_result=100000" -H "${USER_AUTH}" | jq --raw-output --arg project_name "${project_name}" '.[] | select(.name==${project_name}) | .planKey.key' )
  echo "${project_key}"
}


function getProjectIdByName() {
  local project_name=${1}
  local project_id=$( curl -s "${BAMBOO_REST_API_URL}/deploy/project/all.json?max_result=100000" -H "${USER_AUTH}" | jq --arg project_name "${project_name}" '.[] | select(.name==${project_name}) | .id' )
  echo "${proejct_id}"
}


function getEnvIdByName() {
  local env_name=${1}
  local project_id=${2}
  local env_id=$( curl -s "${BAMBOO_REST_API_URL}/deploy/project/${project_id}.json" -H "${USER_AUTH}" | jq --arg env_name "${env_name}" '.environments[] | select(.name==${env_name}) | .id' )
  echo "${env_id}"
}


function getDeploymentReleaseList() {
  local branch_pattern=${1}
  local label_pattern=${2}
  local project_key=${3}
  local deployment_release_list=
  deployment_release_list=$( curl -s "${BAMBOO_REST_API_URL}/plan/${project_key}/branch.json?enabledOnly&expand=branches.branch.latestResult.labels&max_result=100000" -H "${USER_AUTH}" | jq --raw-output --arg branch_pattern "${branch_pattern}" --arg label_pattern "${label_pattern}" '.branches.branch[] | select(.shortName|test($branch_pattern)) | select(.latestResult.state=="Successful") | select(.latestResult.labels.label[].name|test($label_pattern)) | .key,.shortName,.latestResult.buildNumber,.latestResult.state' | paste -d " " - - - - | awk '!a[$0]++' | awk '{"date -d \""$4"\" +\"%s\"" | getline $4; print $0}' | sort -V -r -k 4 | awk '{print $1" "$2" "$3" "$4}' )
  echo "${deployment_release_list}"
}


function getDeploymentVersionId() {
  local project_id=${1}
  local plan_branch_key=${2}
  local latest_build_number=${3}
  local deployment_release_version_id=
  deployment_release_version_id=$( curl -s "${BAMBOO_REST_API_URL}/deploy/project/${project_id}/versions.json?branchKey=${plan_branch_key}" -H "${USER_AUTH}" | jq --arg planResultKey "${plan_branch_key}-${latest_build_number}" '.versions[] | select(.items[].planResultKey.key==${planResultKey}) | .id' )
  echo "${deployment_release_version_id}"
}


function getBuildLabels() {
  local projectKey_buildKey_buildNumber=${1}
  local label_pattern=${2}
  local label_value=$( curl -s "${BAMBOO_REST_API_URL}/result/${projectKey_buildKey_buildNumber}/label.json" -H "${USER_AUTH}" | jq --raw--output --arg label_pattern "${label_pattern}" '.labels.label[] | select(.name|test(${label_pattern})) | .name' )
  echo "${label_value}"
}


function createNewReleaseVersion() {
  local deployment_project_id=${1}
  local plan_branch_key=${2}
  local latest_build_number=${3}
  local branch_name=${4}
  local deployment_release_version_id=
  deployment_release_version_id=$( curl -sX POST "${BAMBOO_REST_API_URL}/deploy/project/${deployment_project_id}/version.json" -H "${USER_AUTH}" -H "Content-Type: application/json" -d '{"planResultKey" : "'${plan_branch_key}'-'${latest_build_number}'", "name" : "'${branch_name}'-'${latest_build_number}'"}' | jq '.id' )
  echo "${deployment_release_version_id}"
}


function triggerDeploy() {
  local release_deploy_list=$( getDeploymentReleaseList "${branch_pattern}" "${label_pattern}" "${project_key}" )
  local environment_id=${1}
  # other variables append here if needed

  release_deploy_version_id=
  while read -r plan_branch_key branch_name latest_build_number build_status; do
    echo "${plan_branch_key} ${branch_name} ${latest_build_number} ${build_status}"

    if [[ ${build_status} != "Successful" ]]; then
      # iteratively find last successful build if latest is "failed"
      buildNotSuccessful=$( curl "${BAMBOO_REST_API_URL}/result/${plan_branch_key}-latest" -H "${USER_AUTH}" -H "Accept: application/json" | jq '.buildNumber' )
      buildN=
      while [[ -z $buildN ]]; do
        (( buildNotSuccessful-- ))
        resBuildN=$( curl "${BAMBOO_REST_API_URL}/result/${plan_branch_key}-${buildNotSuccessful}" -H "${USER_AUTH}" -H "Accept: application/json" | jq 'select(.state=="Successful") | .buildNumber' )
        if [[ -z ${resBuildN} ]]; then
          continue
        fi
        buildN=${resBuildN}
      done
      echo "Found last successful build number: ${buildN}"

      latest_build_number=${buildN}
    fi

    # create new release version
    release_deploy_version_id="$( createNewReleaseVersion "${deployment_project_id}" "${plan_branch_key}" "${latest_build_number}" "${branch_name}" )"

    # trigger the deployment
    result_id="$( getDeploymentResultId "${environment_id}" "${release_deploy_version_id}" )"
}


function getDeploymentResultId() {
  local environment_id=${1}
  local deployment_release_version_id=${2}
  local deployment_result_id=
  deployment_result_id=$( curl -sX POST "${BAMBOO_REST_API_URL}/queue/deployment.json?environmentId=${environment_id}&versionId=${deployment_release_version_id}" -H "${USER_AUTH}" | jq '.deploymentResultId' )
  echo "${deploymentResultId}"
}

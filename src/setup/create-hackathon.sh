#!/bin/bash

#
# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution

source ./hackathon.sh

### File with the list of user names and passwords
USER_LIST=$TMP/users.csv

###############################################################################
# Add user to the domain: https://developers.google.com/admin-sdk/directory/v1/guides/manage-users
# Input:
#   1 - user number
#   2 - team number
###############################################################################
add_user() {
    local USER_NUM=$1
    local TEAM_NUM=$2
    # echo "add_user(): Creating user #$USER_NUM for team #$TEAM_NUM..."

    local PASSWORD=$(generate_password)
    $GAM create user $(user_name $USER_NUM $TEAM_NUM) firstname "User$USER_NUM" lastname "Member of Team $TEAM_NUM" password $PASSWORD

    echo "$(user_name $USER_NUM $TEAM_NUM)@$DOMAIN,$PASSWORD" >> $USER_LIST
}

###############################################################################
# Add new team to the domain
# Input:
#   1 - team number
###############################################################################
create_team() {
    local TEAM_NUM=$1
    echo_my "create_team(): Creating team #$TEAM_NUM..."

    $GAM create group "$(team_name $TEAM_NUM)" name "Car team $TEAM_NUM" description "Developers working on the car # $TEAM_NUM" | true # ignore if error

    for j in `seq 1 $NUM_PEOPLE_PER_TEAM`;
    do
        add_user $j $TEAM_NUM
        $GAM update group "$(team_name $TEAM_NUM)" add member $(user_name $j $TEAM_NUM)@$DOMAIN
    done

}

###############################################################################
# Create all groups
###############################################################################
create_groups_and_users() {
    echo_my "create_groups_and_users(): started..."

    # Create empty file and overwrite the existing one
    echo "Email,Password" > $USER_LIST

    for i in `seq $TEAM_START_NUM $NUM_TEAMS`;
    do
        create_team $i
    done
}

###############################################################################
# Create folders and projects in GCP
###############################################################################
create_folders() {
    echo_my "create_folders(): started..."

    # echo_my "When prompted below, please login as CloudDerby.io superuser to continue. This is required in order for you to add users and teams to the domain..."
    # pause
    # gcloud init --project $ADMIN_PROJECT
    # gcloud auth application-default login

    # echo_my "Creating event parent folder..."
    gcloud alpha resource-manager folders create --display-name=$TOP_FOLDER --organization=$ORGANIZATION_ID | true # ignore if already exists

    echo_my "Creating children folders for each car team..."
    local PARENT_FOLDER_ID=$(find_top_folder_id $TOP_FOLDER)
    
    for i in `seq $TEAM_START_NUM $NUM_TEAMS`;
    do
        gcloud alpha resource-manager folders create --display-name=$(team_folder_name $i) --folder=$PARENT_FOLDER_ID

        local NEW_FOLDER_ID=$(find_folder_id $(team_folder_name $i) $PARENT_FOLDER_ID)
        echo "NEW_FOLDER_ID=$NEW_FOLDER_ID"

        # See docs: https://cloud.google.com/iam/docs/understanding-roles
        local COMMAND="gcloud alpha resource-manager folders add-iam-policy-binding $NEW_FOLDER_ID --member=group:$(team_name $i)@$DOMAIN --role=roles/"

        eval ${COMMAND}resourcemanager.projectCreator
        eval ${COMMAND}resourcemanager.folderEditor
        eval ${COMMAND}resourcemanager.folderIamAdmin
        eval ${COMMAND}resourcemanager.projectIamAdmin
        eval ${COMMAND}resourcemanager.folderCreator
        eval ${COMMAND}resourcemanager.projectDeleter
        eval ${COMMAND}appengine.appAdmin
        eval ${COMMAND}dialogflow.admin
        eval ${COMMAND}ml.admin
        eval ${COMMAND}pubsub.admin
        eval ${COMMAND}storage.admin
        eval ${COMMAND}iam.serviceAccountAdmin
        eval ${COMMAND}iam.serviceAccountKeyAdmin
        eval ${COMMAND}iam.serviceAccountTokenCreator
        eval ${COMMAND}iam.serviceAccountUser
        eval ${COMMAND}iam.securityReviewer
        eval ${COMMAND}servicemanagement.quotaAdmin
        eval ${COMMAND}errorreporting.admin
        eval ${COMMAND}logging.admin
        eval ${COMMAND}monitoring.admin
        eval ${COMMAND}cloudiot.admin
        eval ${COMMAND}compute.instanceAdmin.v1
        eval ${COMMAND}compute.imageUser
        eval ${COMMAND}compute.networkAdmin
        eval ${COMMAND}compute.securityAdmin
        eval ${COMMAND}source.admin
        eval ${COMMAND}clouddebugger.user

        ### Permissions for things outside the team folder
        COMMAND="gcloud projects add-iam-policy-binding $REPO_PROJECT_ID --member=group:$(team_name $i)@$DOMAIN --role=roles/"
        eval ${COMMAND}source.reader
        eval ${COMMAND}storage.objectViewer
    done
}

###############################################################################
# MAIN
###############################################################################
print_header "Creating workshop users, folders, etc..."

setup

create_groups_and_users

create_folders

print_footer "SUCCESS: New workshop configuration created."

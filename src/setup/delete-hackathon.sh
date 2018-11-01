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

###############################################################################
# Remove all folders and projects under a designated folder ID
# Input
#   1 - folder ID under which all content is to be deleted
###############################################################################
delete_folders() {
    local PARENT_FOLDER_ID=$1
    local FOLDER_ID

    echo_my "Deleting folders under folder '$PARENT_FOLDER_ID'..."

    local FOLDER_LIST=`gcloud alpha resource-manager folders list --folder=$PARENT_FOLDER_ID --format="value(name)"`

    while read -r FOLDER_ID; do
        if [[ ! -z "$FOLDER_ID" ]] ; then
            echo_my "Processing folder id '$FOLDER_ID'..."
            delete_projects $FOLDER_ID
            if [ $DELETE_VM_ONLY = false ] ; then
                gcloud alpha resource-manager folders delete $FOLDER_ID | true # Ignore if error and proceed
            fi
        fi
    done <<< "$FOLDER_LIST"

    echo_my "Finally deleting the top folder '$PARENT_FOLDER_ID'..."
    gcloud alpha resource-manager folders delete $PARENT_FOLDER_ID
}

###############################################################################
# Remove all projects under a given folder
# Inputs
#   1 - Folder ID
###############################################################################
delete_projects() {
    echo_my "Deleting projects for folder '$1'..."
    local PROJECT_LIST=`gcloud projects list --filter="parent.id=$1" --format="value(projectId)"`
    local PROJ_ID

    while read -r PROJ_ID; do
        if [[ ! -z "$PROJ_ID" ]] ; then
            echo_my "Processing project id '$PROJ_ID'..."
            if [ $DELETE_VM_ONLY = false ] ; then
                yes | gcloud projects delete $PROJ_ID | true # Ignore if error and proceed
            else
                delete_vms $PROJ_ID
            fi
        fi
    done <<< "$PROJECT_LIST"
}

###############################################################################
# Remove all VMs in a project
# Inputs
#   1 - project ID
###############################################################################
delete_vms() {
    local VM_ID
    echo_my "Deleting VMs for project '$1'..."

    local VM_LIST=`gcloud compute instances list --project $1`

    while read -r VM_ID; do
        if [[ ! -z "$VM_ID" ]] ; then
            echo_my "Deleting VM id '$VM_ID'..."
            # gcloud compute delete $VM_ID | true # Ignore if error and proceed
        else
            echo_my "No more VMs found in this project"
        fi
    done <<< "$VM_LIST"
}

###############################################################################
# Reset all passwords for all auto-generated users
###############################################################################
reset_passwords() {
    # Create empty file and overwrite the existing one
    echo "Email,Password" > $USER_LIST

    for i in `seq $TEAM_START_NUM $NUM_TEAMS`;
    do
        for j in `seq 1 $NUM_PEOPLE_PER_TEAM`;
        do
            local PASSWORD=$(generate_password)
            $GAM update user $(user_name $j $i) password $PASSWORD
            echo "$(user_name $j $i),$PASSWORD" >> $USER_LIST
        done
    done
}

###############################################################################
# Remove all users and groups
###############################################################################
delete_everybody() {
    for i in `seq $TEAM_START_NUM $NUM_TEAMS`;
    do
        for j in `seq 1 $NUM_PEOPLE_PER_TEAM`;
        do
            $GAM delete user $(user_name $j $i) | true # ignore if error
        done

        $GAM delete group "$(team_name $i)" | true # ignore if error
    done
}


###############################################################################
# MAIN
###############################################################################
print_header "Delete workshop users, folders, etc."

echo_my "\nATTENTION!!!!!!!!!!!\nATTENTION!!!!!!!!!!!\nATTENTION!!!!!!!!!!!\n"
echo_my "This will remove all Users, Projects, Folders under the folder --- '$TOP_FOLDER' ---. Are you sure you want to proceed?" $ECHO_WARNING
pause
echo_my "\nAre you sure you want to delete all USERS, PROJECTS and FOLDERS???????" $ECHO_WARNING
pause

setup

# reset_passwords

delete_everybody

# IF this is true, then folders and projects will not be deleted - only VMs
DELETE_VM_ONLY=false

if [ $DELETE_VM_ONLY = false ] ; then
    echo_my "DELETE_VM_ONLY=$DELETE_VM_ONLY - this means all projects, folders and VMs will be deleted."
else
    echo_my "DELETE_VM_ONLY=$DELETE_VM_ONLY - this means only VMs will be deleted."
fi

FOLDER_TO_BE_DELETED=923234939824

delete_folders $FOLDER_TO_BE_DELETED

print_footer "SUCCESS: Workshop resources have been removed."

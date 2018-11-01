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

##################################################################################
# Global environment settings that are unique to ones development machine - these
# do not get committed into repo and allow multi-user development. Example of this
# can be found in robot-derby/src/project-setup folder.
##################################################################################

set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution

echo "setenv-dev-workspace.sh: start"

### Project user home dir
export BASE_PATH=$HOME

### Automatically generate unique project ID for the first run and save it into a file. Later read it from file
export PROJECT_NAME_FILE=$HOME/project-id.sh
if [ -f $PROJECT_NAME_FILE ] ; then
    echo "Sourcing existing project file '$PROJECT_NAME_FILE'..."
    cat $PROJECT_NAME_FILE
    source $PROJECT_NAME_FILE
else
    # Try to infer current project ID from the environment
    export PROJECT=$(gcloud info | grep "Project:" | sed -n -e "s/Project: \[//p" | sed -n -e "s/\]//p")
fi

echo "PROJECT='$PROJECT'"
gcloud config set project $PROJECT

### These are Region and Zone where you want to run your car controller - feel free to change as you see fit
### It is important that these are done with the "export"
export REGION=us-central1
export ZONE=us-central1-f
export REGION_LEGACY=us-central # there are corner cases where gcloud still references the legacy nomenclature
export BILLING_ACCOUNT_ID=01A70D-5A9618-8ECB01

### Serial number of the car to distinguish it from all other cars possibly on the same project
export CAR_ID=car1
# export CAR_ID=car5

### Camera resolution
# export HORIZONTAL_RESOLUTION_PIXELS=1280
# export VERTICAL_RESOLUTION_PIXELS=720
export HORIZONTAL_RESOLUTION_PIXELS=1024
export VERTICAL_RESOLUTION_PIXELS=576

# Used for cases when we want multiple ML models to be deployed and compared against each other
export VERSION=45

### This folder will host the project - you can lookup ID in the GCP Console
export PARENT_FOLDER=1081904530671

### This is the project that hosts the Git Repo with source code
export REPO_PROJECT_ID=administration-203923
export GIT_REPO_NAME=cloud-derby-source-oct30

### Git Repo will be cloned into this directory
export PROJECT_PATH=$BASE_PATH/robot-derby

### We store service account private key here
export SERVICE_ACCOUNT_DIR=$BASE_PATH/.secrets
export SERVICE_ACCOUNT_SECRET=$SERVICE_ACCOUNT_DIR/service-account-secret.json
export SERVICE_ACCOUNT="robot-derby-dev"
export ALLMIGHTY_SERVICE_ACCOUNT="${SERVICE_ACCOUNT}@${PROJECT}.iam.gserviceaccount.com"

### BigQuery Export Details
export BQ_PROJECT_ID=$REPO_PROJECT_ID
export BQ_DATASET="cloudderby"
export BQ_SENSOR_MESSAGE_TABLE="sensor_messages"
export BQ_DRIVE_MESSAGE_TABLE="drivemessages"

### Name of the source bucket with images of colored balls (this is one source for all other projects)
export GCS_SOURCE_IMAGES=robot-derby-io-images

### Name of the destination bucket with images of colored balls and whatever other objects
export GCS_IMAGES=${PROJECT}-images-for-training-v-${VERSION}

### External IP address of the inference VM (this handles REST calls for object detection)
export INFERENCE_VM_IP=35.208.26.54

echo "setenv-dev-workspace.sh: done"

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

###############################################
# Car Driving Controller
###############################################

set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution
# set -x # Print trace of commands after their arguments are expanded

source ../../setenv-global.sh

### Where do we want this Driving Controller to be deployed?
# Deploy Controller in the current VM or App Engine Flex?
DEPLOY_LOCAL=true
# DEPLOY_LOCAL=false

### Defines the name of the App Engine Flex App and forms part of URL
APP_NAME=driving-controller

### Credentials to call Inference App
export INFERENCE_USER_NAME=robot
export INFERENCE_PASSWORD=gcp4all

### Configuration of the deployment for 
YAML_FILE=app-generated.yml

###############################################
# This is run once after creating new environment
###############################################
setup_once()
{
    echo_my "Downloading 'node'..."
    curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
    echo_my "Installing 'node'..."
    sudo apt-get install nodejs
    node -v
    npm -v

    cd js
    echo_my "Install npm modules..."
    npm install
    # npm install --save @google-cloud/debug-agent @google-cloud/bigquery
}

###############################################
# This generates proper YAML connfig for the app
###############################################
generate_yaml()
{
    echo_my "Generating YAML config..."
# Create 'app.yaml' file for the deployment configuration
cat << EOF > $YAML_FILE
# This file is auto-generated from setup.sh
# Please do not update it manually as it will be overriden
# Docs: https://cloud.google.com/appengine/docs/standard/nodejs/config/appref

# for App Engine Flex
# runtime: nodejs

# for App Engine Standard
runtime: nodejs8

# This makes it run in App Engine Flex
# env: flex

manual_scaling:
  instances: 1

env_variables:
  SENSOR_SUBSCRIPTION: $SENSOR_SUBSCRIPTION
  COMMAND_TOPIC: $COMMAND_TOPIC
  INFERENCE_USER_NAME: $INFERENCE_USER_NAME
  INFERENCE_PASSWORD: $INFERENCE_PASSWORD
  INFERENCE_VM_IP: $INFERENCE_VM_IP
  INFERENCE_URL: $INFERENCE_URL
  HTTP_PORT: $HTTP_PORT
  CAR_ID: $CAR_ID
  BQ_PROJECT_ID: $BQ_PROJECT_ID
  BQ_DATASET: $BQ_DATASET
  BQ_SENSOR_MESSAGE_TABLE: $BQ_SENSOR_MESSAGE_TABLE
  BQ_DRIVE_MESSAGE_TABLE: $BQ_DRIVE_MESSAGE_TABLE
EOF
}

###############################################
# MAIN
###############################################
print_header "Start application '$APP_NAME' in DEPLOY_LOCAL='$DEPLOY_LOCAL' (set it to false to deploy on GCP) in project '$PROJECT'"

mkdir -p tmp
CWD=`pwd`
# Location where the install flag is set to avoid repeated installs
INSTALL_FLAG=$CWD/tmp/install.marker
if [ -f "$INSTALL_FLAG" ]; then
    echo_my "File '$INSTALL_FLAG' was found = > no need to do the install since it already has been done."
else
    setup_once
    touch $INSTALL_FLAG
fi

create_resources

cd $CWD/js
if [ -f "nohup.out" ] ; then
    rm -rf nohup.out
fi

if $DEPLOY_LOCAL ;
then
    echo_my "Running on local machine..."
    # nohup npm start &
    npm start
else
    generate_yaml
    URL=https://${APP_NAME}-dot-${PROJECT}.appspot.com/
    echo_my "Deploying into GCP..."
    yes | gcloud app deploy $YAML_FILE --project $PROJECT
    # gcloud app browse
    # Ping the app to see if it is available
    curl -G $URL
    echo_my "Running on GCP URL=$URL"
fi

print_footer "Controller has been started."

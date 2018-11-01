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
# Car driving receiver simulator
###############################################

set -u # This prevents running the script if any of the variables have not been set
# set -x # Print trace of commands after their arguments are expanded
set -e # Exit if error is detected during pipeline execution

source ../../setenv-global.sh

TEMP_DATA=$(pwd)/tmp
INSTALL_FLAG=$TEMP_DATA/install.marker  # Location where the install flag is set to avoid repeated installs

###############################################
# This is run once after creating new environment
###############################################
setup_once()
{
    echo_my "Installing 'python'..."
    sudo apt-get install python
    sudo apt-get install python-pip
    sudo pip install --upgrade pip
    sudo pip install --upgrade google-cloud
}

TEST_COMMAND_SUBSCRIPTION=simulator_driving_command_subscription
echo_my "Using subscription $TEST_COMMAND_SUBSCRIPTION to read data from the cloud driving controller..."

if gcloud pubsub subscriptions list | grep $TEST_COMMAND_SUBSCRIPTION; then
	echo_my "Subscription $TEST_COMMAND_SUBSCRIPTION already exists..."
else
	echo_my "Creating a subscription '$TEST_COMMAND_SUBSCRIPTION' to topic '$COMMAND_TOPIC'..."
	gcloud pubsub subscriptions create $TEST_COMMAND_SUBSCRIPTION --topic $COMMAND_TOPIC | true
fi

###############################################
# MAIN
###############################################
mkdir -p $TEMP_DATA
CDIR=`pwd`

if [ -f "$INSTALL_FLAG" ]; then
    echo_my "File '$INSTALL_FLAG' was found = > no need to do the install since it already has been done."
else    
    setup_once
    touch $INSTALL_FLAG
fi

cd py
./drive.py $PROJECT $TEST_COMMAND_SUBSCRIPTION

# gcloud pubsub subscriptions delete $TEST_COMMAND_SUBSCRIPTION

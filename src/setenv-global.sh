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

#############################################################################
# Shared environment variables and utility functions for entire project
#############################################################################
echo "setenv-global.sh ..."

command -v bc >/dev/null 2>&1 || { echo >&2 "'bc' is not installed."; yes | sudo apt-get --assume-yes install bc; }

source $HOME/setenv-dev-workspace.sh

set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution

### Topic where cloud logic sends driving commands to and car reads them from here
export COMMAND_TOPIC=driving-commands-topic-$CAR_ID

### Topic where the car sends its sensor data and cloud logic reads it from
export SENSOR_TOPIC=sensor-data-topic-$CAR_ID

### Subscription on the above sensor topic for cloud logic to read data from the car
export SENSOR_SUBSCRIPTION=sensor-data-subscription-$CAR_ID

### GCS bucket for car to post its images to and for cloud logic to read it from here
export CAR_CAMERA_BUCKET=camera-${CAR_ID}-${PROJECT}

### IOT Core registry where the car sends its sensor data and cloud logic reads it from
export IOT_CORE_REGISTRY=car-iot-registry

### IOT Core Device ID
export IOT_CORE_DEVICE_ID=iot-car-${CAR_ID}

### Name of the4 VM that runs inference and serves prediction requests
export INFERENCE_VM=ml-inference

### This URL will be appended to the VM IP address to call Inference Vision API
export INFERENCE_URL="/v1/objectInference"

### Firewal tags
# HTTP_PORT is used to run Inference VM app to serve REST requests
export HTTP_PORT=8082
export HTTP_TAG=http-from-all
export SSH_TAG=ssh-from-all

### VM network name for diagnostics and debug
export VM_NAME=`uname -n`

### Labels and IDs of objects to be recognized
export NUM_CLASSES=8
export BLUE_BALL_ID=1
export BLUE_BALL_LABEL=BlueBall
export RED_BALL_ID=2
export RED_BALL_LABEL=RedBall
export YELLOW_BALL_ID=3
export YELLOW_BALL_LABEL=YellowBall
export GREEN_BALL_ID=4
export GREEN_BALL_LABEL=GreenBall
export BLUE_HOME_ID=5
export BLUE_HOME_LABEL=BlueHome
export RED_HOME_ID=6
export RED_HOME_LABEL=RedHome
export YELLOW_HOME_ID=7
export YELLOW_HOME_LABEL=YellowHome
export GREEN_HOME_ID=8
export GREEN_HOME_LABEL=GreenHome

###############################################
# Wait for user input
###############################################
pause ()
{
	read -p "Press Enter to continue or Ctrl-C to stop..."
}

###############################################
# Fail processing
###############################################
die()
{
	echo Error: $?
	exit 1
}

###############################################
# Fail processing
# Input - any text
###############################################
log_error()
{
	echo "Error: $?. Details: $1" >> errors.log
	exit 1
}

###############################################
# Starts measurements of time
###############################################
start_timer()
{
	START_TIME=`date +%s.%N`
}

###############################################
# Stop timer and write data into the log file
###############################################
measure_timer()
{
	if [ -z ${START_TIME+x} ]; then
		MEASURED_TIME=0
	else
		END_TIME=`date +%s.%N`
		local TIMER=`echo "$END_TIME - $START_TIME" | bc`
		MEASURED_TIME=`printf "%.2f\n" $TIMER`
	fi
}

###############################################
# Print starting headlines of the scrit
# Params:
#	1 - text to show
###############################################
SEPARATOR="*************************************************************************"
CALLER="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
COLOR='\033[32m'
NORMAL='\033[0m'
print_header()
{
	start_timer
	printf "\n${COLOR}$SEPARATOR${NORMAL}"
	printf "\n${COLOR}STARTED: $1 ($CALLER)${NORMAL}"
	printf "\n${COLOR}$SEPARATOR${NORMAL}\n"
}

###############################################
# Print closing footer of the scrit
###############################################
print_footer()
{
	measure_timer
	printf "\n${COLOR}$SEPARATOR${NORMAL}"
	printf "\n${COLOR}$1${NORMAL}"
	printf "\n${COLOR}FINISHED: in $MEASURED_TIME seconds ($CALLER).${NORMAL}"
	printf "\n${COLOR}$SEPARATOR${NORMAL}\n"
}

##############################################################################
# Replace standard ECHO function with custom output
# PARAMS:		1 - Text to show (mandatory)
# 				2 - Logging level (optional) - see levels below
##############################################################################
# Available logging levels (least to most verbose)
ECHO_NONE=0
ECHO_NO_PREFIX=1
ECHO_ERROR=2
ECHO_WARNING=3
ECHO_INFO=4
ECHO_DEBUG=5
# Default logging level
ECHO_LEVEL=$ECHO_DEBUG

echo_my()
{
	local RED='\033[0;31m'
	local GREEN='\033[32m'
	local ORANGE='\033[33m'
	local NORMAL='\033[0m'
	# local PREFIX="[`hostname`] "
	local PREFIX="$CALLER->"

	if [ $# -gt 1 ]; then
		local ECHO_REQUESTED=$2
	else
		local ECHO_REQUESTED=$ECHO_INFO
	fi

	if [ $ECHO_REQUESTED -gt $ECHO_LEVEL ]; then return; fi
	if [ $ECHO_REQUESTED = $ECHO_NONE ]; then return; fi
	if [ $ECHO_REQUESTED = $ECHO_ERROR ]; then PREFIX="${RED}[ERROR] ${PREFIX}"; fi
	if [ $ECHO_REQUESTED = $ECHO_WARNING ]; then PREFIX="${RED}[WARNING] ${PREFIX}"; fi
	if [ $ECHO_REQUESTED = $ECHO_INFO ]; then PREFIX="${GREEN}[INFO] ${PREFIX}"; fi
	if [ $ECHO_REQUESTED = $ECHO_DEBUG ]; then PREFIX="${ORANGE}[DEBUG] ${PREFIX}"; fi
	if [ $ECHO_REQUESTED = $ECHO_NO_PREFIX ]; then PREFIX="${GREEN}"; fi

	measure_timer
	printf "${PREFIX}$1 ($MEASURED_TIME seconds)${NORMAL}\n"
}

###############################################
# Open proper ports on a firewall
###############################################
configure_firewall()
{
    # We will have user create this firewall rule manually
    # open_http_firewall_port $HTTP_PORT

    # Deep Learning VM has pre-installed Python Lab on port 8080
    open_http_firewall_port 8080

    open_ssh_firewall_port
}

###############################################
# Open HTTP port on a firewall
# Input:
#   1 - HTTP port to open
###############################################
open_http_firewall_port()
{
    local PORT=$1
    echo_my "Create firewall rule for port '$PORT'..."
    gcloud compute --project="$PROJECT" firewall-rules create \
        allow-http-$PORT --direction=INGRESS --priority=1000 \
        --network=default --action=ALLOW --rules=tcp:$PORT \
        --source-ranges=0.0.0.0/0 --target-tags=${HTTP_TAG} | true # Ignore if the firewall rules already exists
}

###############################################
# Open SSH port on a firewall
###############################################
open_ssh_firewall_port()
{
    echo_my "Create firewall rule for '$SSH_TAG'..."
    gcloud compute --project="$PROJECT" firewall-rules create \
        allow-${SSH_TAG} --direction=INGRESS --priority=1000 \
        --network=default --action=ALLOW --rules=tcp:22 \
        --source-ranges=0.0.0.0/0 --target-tags=${SSH_TAG} | true # Ignore if the firewall rules already exists
}

###############################################
# Copy files to remote GCE host. It will try
# several times if the host is not started yet
# or not responding.
# Input:
#   - Local Dir
#   - Remote Dir
#   - Zone
#   - Destination Host
###############################################
remote_copy()
{
    local LOCAL_DIR=$1
    local REMOTE_DIR=$2
    local ZONE=$3
    local TARGET_HOST=$4
    local SLEEP=1
    echo_my "Copying files from local path '$LOCAL_DIR' to remote path '$REMOTE_DIR' in zone '$ZONE' to the host '$TARGET_HOST'..."
    COUNTER=0
    MAX_WAIT=30
    while [ true ]; do
        if gcloud compute scp --zone $ZONE $LOCAL_DIR/* $TARGET_HOST:${REMOTE_DIR} ; then
            echo_my "File copy from '$LOCAL_DIR' succeeded."
            break
        else
            SLEEP=`echo "$SLEEP * 2" | bc`
            echo_my "Remote VM hasn't started yet, waiting for $SLEEP more seconds..."
            sleep $SLEEP
            let COUNTER=COUNTER+1
        fi

        if [ $COUNTER -gt $MAX_WAIT ]; then
            echo_my "Remote VM was not started in reasonable amount of time. Aborting the script." $ECHO_ERROR
            exit 1
        fi
    done
}

###############################################
# This creates proper resources for Cloud to Car communication
###############################################
create_resources()
{
    echo_my "Create Topics and Subscriptions for car to cloud communication..."

    # echo_my "Remove GCS bucket for images: '$CAR_CAMERA_BUCKET'..."
    # gsutil rm -r gs://${CAR_CAMERA_BUCKET}/ | true # Ignore error if bucket does not exist

    if gcloud pubsub topics list | grep $COMMAND_TOPIC; then
	    echo_my "Topic $COMMAND_TOPIC found OK"
    else
        echo_my "Create PubSub topic '$COMMAND_TOPIC'..."
        gcloud pubsub topics create $COMMAND_TOPIC
    fi

    if gcloud pubsub topics list | grep $SENSOR_TOPIC; then
	    echo_my "Topic $SENSOR_TOPIC found OK"
    else
        echo_my "Create PubSub topic '$SENSOR_TOPIC'..."
	    gcloud pubsub topics create $SENSOR_TOPIC
    fi

    if gcloud pubsub subscriptions list | grep $SENSOR_SUBSCRIPTION; then
        echo_my "Drop and create subscription for sensor data to avoid processing of old messages..."
    	gcloud pubsub subscriptions delete $SENSOR_SUBSCRIPTION
    fi

    echo_my "Creating a subscription '$SENSOR_SUBSCRIPTION'..."
    gcloud pubsub subscriptions create $SENSOR_SUBSCRIPTION --topic $SENSOR_TOPIC
}

echo "... setenv-global.sh"

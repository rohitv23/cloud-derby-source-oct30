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

##################################################
# Build and train TensorFlow Transferred Learning model. This is based on:
# https://github.com/tensorflow/models/blob/master/research/object_detection/g3doc/running_pets.md
# Also see this tutorial: https://cloud.google.com/solutions/creating-object-detection-application-tensorflow
##################################################

set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution

#############################################
# MAIN
#############################################
CWD=`pwd`
mkdir -p $CWD/tmp
INSTALL_FLAG=$CWD/tmp/install.marker
  
yes | sudo apt-get update
yes | sudo apt-get --assume-yes install bc
yes | sudo apt-get install apt-transport-https unzip zip

source ./setenv.sh
print_header "Setting up TF VM for transferred learning"

if [ -f "$INSTALL_FLAG" ]; then
  echo_my "Marker file '$INSTALL_FLAG' was found = > no need to do the install."
else    
  echo_my "Marker file '$INSTALL_FLAG' was NOT found = > starting one time install."
  setup_models
  touch $INSTALL_FLAG
fi

print_footer "Training VM setup has completed"

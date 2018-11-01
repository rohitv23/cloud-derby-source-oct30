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
# For transferred learning object detection to work we need a GPU enabled VM on GCE.
# This script creates such a VM
###############################################

set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution

source ./setenv.sh

print_header "Create new Object Detection Training VM"

# if [ -f "$SERVICE_ACCOUNT_SECRET" ]; then
#   echo_my "Activating service account..."
#   gcloud auth activate-service-account --key-file=$SERVICE_ACCOUNT_SECRET
# fi

configure_firewall

GPU_COUNT=1
create_gpu_vm $TRAINING_VM $GPU_COUNT

print_footer "ML training VM Creation has completed."

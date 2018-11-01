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

###########################################################
# Shared environment variables for Transferred Learning module
###########################################################

set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution

source ../../../setenv-global.sh
source ../setenv-ml.sh

### How many training steps to take
TRAINING_STEPS=8000
CMLE_RUNTIME_VERSION=1.9

### What model to use for training
### Model zoo: https://github.com/tensorflow/models/blob/master/research/object_detection/g3doc/detection_model_zoo.md

# MODEL=ssd_inception_v2_coco_11_06_2017
# MODEL=rfcn_resnet101_coco_11_06_2017
# MODEL=faster_rcnn_inception_resnet_v2_atrous_coco_11_06_2017
# MODEL=ssd_mobilenet_v1_coco_11_06_2017
# Model that has been used in June 2018 event
# MODEL=faster_rcnn_resnet101_coco_11_06_2017
MODEL=faster_rcnn_resnet101_coco_2018_01_28

# TODO !!!!!!!!!!!!! - try TensorFlow SSD MobileNet - should be faster and more accurate

### Which pre-trained model to use
MODEL_CONFIG=${MODEL}-robot-derby.config

### Name of the GCE VM that runs local ML training job
TRAINING_VM=ml-training-$VERSION

### Which dataset to use
TL_MODULE_PATH=`pwd`
MODEL_CONFIG_PATH=$TL_MODULE_PATH

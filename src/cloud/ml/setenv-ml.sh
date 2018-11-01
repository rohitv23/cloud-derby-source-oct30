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
# Shared environment variables for Machine Learning Module
#############################################################################

set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution

### Where to store all training data in flight for ML
export GCS_ML_BUCKET=gs://${PROJECT}-ml-$VERSION

### Where to export the final inference graph for predictions
export ML_EXPORT_BUCKET=gs://${PROJECT}-ml-export-$VERSION
export FROZEN_INFERENCE_GRAPH_GCS=$ML_EXPORT_BUCKET/frozen_inference_graph.pb

### Where to export automatically generated label map - from training into predictions
export LABEL_MAP=robot_derby_label_map.pbtxt
export LABEL_MAP_GCS=$ML_EXPORT_BUCKET/$LABEL_MAP

### Version of TensorFlow to use
### Also used as parameter for Cloud Machine Learning, see https://cloud.google.com/ml-engine/docs/tensorflow/runtime-version-list
# export TF_VERSION=1.6
export TF_VERSION=1.10

### Model configuration
# How many objects of the same class to be found in the image
# Default is 100
max_detections_per_class=90
# How many total detections per image for all classes
# Default is 300
max_total_detections=250
# Filter all objects with the confidence score lower than this
score_threshold=0.0000001
# How many proposals to have after the first stage
# Default is 300
first_stage_max_proposals=300

### TF settings
export TF_PATH=~/tensorflow
export TF_MODEL_DIR=$BASE_PATH/tensorflow-models
export MODEL_BASE=$TF_MODEL_DIR/models/research
export TMP=$(pwd)/tmp

###############################################
# Activates TF environment in Virtualenv
###############################################
activate()
{
    set +u # This prevents running the script if any of the variables have not been set
    source $TF_PATH/bin/activate
    set -u # This prevents running the script if any of the variables have not been set
}

###############################################
# Install CUDE, TF, etc. See: https://www.tensorflow.org/install/install_linux
# Also see: https://docs.google.com/document/d/1GAtuQd6AYVCyHCEhNCPCqVpxxUcAd89bB0HcRMAtDNQ/edit?usp=sharing
###############################################
install_tf_gpu()
{
    echo_my "Setting up VM image..."
    sudo apt-get update
    sudo apt-get install unzip

    echo_my "Download NVIDIA packages..."
    mkdir -p $TMP
    cd $TMP
    mkdir -p nvidia
    gsutil cp gs://tsaikevin-data/nvidia/cuda-repo-ubuntu1704-9-0-local_9.0.176-1_amd64.deb ./nvidia
    gsutil cp gs://tsaikevin-data/nvidia/libcudnn7_7.0.5.15-1+cuda9.0_amd64.deb ./nvidia

    echo_my "Add Cuda repo..."
    sudo dpkg -i ./nvidia/cuda-repo-ubuntu1704-9-0-local_9.0.176-1_amd64.deb
    echo_my "Add Cuda lib..."
    sudo dpkg -i ./nvidia/libcudnn7_7.0.5.15-1+cuda9.0_amd64.deb
    echo_my "Add CUDA GPG key..."
    sudo apt-key add /var/cuda-repo-9-0-local/7fa2af80.pub
    sudo apt-get update
    echo_my "Installing NVIDIA CUDA - this takes several minutes..."
    yes | sudo apt-get install cuda
    # rm -rf ./nvidia

    echo_my "Install Python and other libraries..."
    yes | sudo apt-get install python-pip python-dev python-virtualenv \
                python-lxml protobuf-compiler python-pil python-tk git
    sudo -H pip install --upgrade Pillow matplotlib
    # sudo -H pip install --upgrade pip pyopenssl ndg-httpsclient pyasn1 jupyter matplotlib

    virtualenv --system-site-packages $TF_PATH
    activate
    easy_install -U pip
    echo_my "Install TF..."
    pip install --upgrade tensorflow-gpu==$TF_VERSION

    echo_my "Check version of TF..."
    python -c 'import tensorflow as tf; print(tf.__version__)'
}

##################################################
# Installing TF using pip
##################################################
install_tensorflow_pip() {
  echo_my "install_tensorflow_pip()..."
  sudo apt-get update

  echo_my "Installing Python libraries..."
  sudo apt-get install -y libffi-dev libssl-dev protobuf-compiler python-pil python-lxml python-pip python-tk python-dev git

  echo_my "Install/upgrade pip..."
  sudo -H pip install --upgrade pip pyopenssl ndg-httpsclient pyasn1 jupyter matplotlib tensorboard

  echo_my "Un-Installing TensorFlow..."
  sudo pip uninstall tensorflow

  echo_my "Installing non-GPU version of TensorFlow..."
  sudo pip install --upgrade tensorflow==$CMLE_RUNTIME_VERSION

  # tfBinaryURL=https://storage.googleapis.com/tensorflow/linux/cpu/tensorflow-1.2.0-cp27-none-linux_x86_64.whl
  # sudo -H pip install --upgrade $tfBinaryURL
}

##################################################
# Configuring TF research models
# Based on this tutorial: https://cloud.google.com/solutions/creating-object-detection-application-tensorflow
##################################################
setup_models() {
    echo_my "Setting up Proto and TensorFlow Models..."

	if [ -d "$TF_MODEL_DIR" ]; then
	    rm -rf $TF_MODEL_DIR
	fi
	mkdir -p $TF_MODEL_DIR
	cd $TF_MODEL_DIR

    ### Configure dev environment - pull down TF models
    git clone https://github.com/tensorflow/models.git
    cd models
    # object detection master branch has a bug as of 9/21/2018
    # checking out a commit we know works
    git reset --hard 256b8ae622355ab13a2815af326387ba545d8d60
    cd ..
    # tf_hacks

    PROTO_V=3.3
    PROTO_SUFFIX=0-linux-x86_64.zip

	if [ -d "protoc_${PROTO_V}" ]; then
	    rm -rf protoc_${PROTO_V}
	fi
    mkdir protoc_${PROTO_V}
    cd protoc_${PROTO_V}

    echo_my "Download PROTOC..."
    wget https://github.com/google/protobuf/releases/download/v${PROTO_V}.0/protoc-${PROTO_V}.${PROTO_SUFFIX}
    chmod 775 protoc-${PROTO_V}.${PROTO_SUFFIX}
    unzip protoc-${PROTO_V}.${PROTO_SUFFIX}
    rm -rf protoc-${PROTO_V}.${PROTO_SUFFIX}

    echo_my "Compiling protos..."
    cd $TF_MODEL_DIR/models/research
    bash object_detection/dataset_tools/create_pycocotools_package.sh /tmp/pycocotools
    python setup.py sdist
    (cd slim && python setup.py sdist)

    PROTOC=$TF_MODEL_DIR/protoc_${PROTO_V}/bin/protoc
    $PROTOC object_detection/protos/*.proto --python_out=.
}

##################################################
# Setup Python path and check TF version
##################################################
set_python_path() {
  echo_my "set_python_path()..."
  local CWD=`pwd`
  cd $TF_MODEL_DIR/models/research
  export PYTHONPATH=`pwd`:`pwd`/slim:`pwd`/object_detection
  echo_my "PYTHONPATH=$PYTHONPATH"
  cd $CWD

  echo_my "Testing if TensorFlow is installed and configured... `python -c 'import tensorflow as tf; print(tf.__version__)'`"
  # python $TF_MODEL_DIR/models/research/object_detection/builders/model_builder_test.py
}


##################################################
# Copy temporary TF hacks
# See fix: https://github.com/tensorflow/models/issues/2739
##################################################
tf_hacks() {
  # echo_my "Install temporary fixes for TF code (warning - this is a hack and may not be necessary when TensorFlow fixes its Obj Detection API sample !)..."
  local FROM=$PROJECT_PATH/src/cloud/machine-learning/tf-hacks
  local TO=$TF_MODEL_DIR/models/research

  # cp $FROM/setup.py $TO
  # cp $FROM/visualization_utils.py $TO/object_detection/utils
  # cp $FROM/evaluator.py $TO/object_detection
  # # cp $FROM/optimizer_builder.py $TO/object_detection/builders
  # cp $FROM/export_inference_graph.py $TO/object_detection/export_inference_graph.py
}

###############################################
# Create a VM on GCE with a certain number of GPUs
# Inputs:
#   1 - name of the VM
#   2 - number of GPUs
###############################################
create_gpu_vm()
{
    local VM_NAME=$1
    local GPU_COUNT=$2
    echo_my "Create VM instance '$VM_NAME' with '$GPU_COUNT' GPUs in a project '$PROJECT'..."
    gcloud compute --project="$PROJECT" instances create $VM_NAME \
        --zone $ZONE \
        --boot-disk-size=50GB \
        --boot-disk-type=pd-ssd \
        --machine-type n1-highmem-2 \
        --accelerator type=nvidia-tesla-v100,count=$GPU_COUNT \
        --image-family=tf-latest-cu92 \
        --image-project=deeplearning-platform-release \
        --service-account $ALLMIGHTY_SERVICE_ACCOUNT \
        --maintenance-policy TERMINATE \
        --restart-on-failure \
        --subnet "default" \
        --tags "$HTTP_TAG","$SSH_TAG" \
        --metadata="install-nvidia-driver=True" \
        --scopes=default,storage-rw,https://www.googleapis.com/auth/source.read_only

    echo_my "List of my instances..."
    gcloud compute --project="$PROJECT" instances list

    echo_my "Copy basic project files to the VM so it is easier to clone the repo later..."
    local LOCAL_DIR=$TMP/host-files
    mkdir -p $LOCAL_DIR
    # Dynamicaly generate correct scripts so we can copy those scripts to the remote VM
    echo source setenv-dev-workspace.sh > $LOCAL_DIR/clone-repo.sh
    # echo gcloud init --project=$PROJECT >> $LOCAL_DIR/clone-repo.sh
    # Note that we want $PROJECT_PATH to be written as such and not substituted with a real value
    echo gcloud source repos clone $GIT_REPO_NAME '$PROJECT_PATH' --project=$REPO_PROJECT_ID >> $LOCAL_DIR/clone-repo.sh
    cp $HOME/setenv-dev-workspace.sh $LOCAL_DIR
    # cp ../../../../../project-id.sh $LOCAL_DIR
    chmod u+x $LOCAL_DIR/*.sh
    REMOTE_DIR="~/"
    remote_copy $LOCAL_DIR $REMOTE_DIR $ZONE $VM_NAME
}

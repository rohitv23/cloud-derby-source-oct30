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
# Build and run TensorFlow Transferred Learning model. This is based on:
# https://github.com/tensorflow/models/blob/master/research/object_detection/g3doc/running_pets.md
# Also see this tutorial: https://cloud.google.com/solutions/creating-object-detection-application-tensorflow
##################################################

set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution

source ./setenv.sh

### Shall we run training locally on this VM or on the Google Cloud ML Engine?
LOCAL_TRAINING=true

##################################################
# Generate JSON file with list of IDs and labels
# Inputs:
#   - full path and file name for the pbtxt file to be generated
##################################################
generate_pbtxt_file() {
  local PBTXT_FILE=$1
  echo_my "generate_pbtxt_file(): PBTXT_FILE=$PBTXT_FILE..."

cat << EOF > $PBTXT_FILE
item {
  id: $BLUE_BALL_ID
  name: '$BLUE_BALL_LABEL'
}
item {
  id: $RED_BALL_ID
  name: '$RED_BALL_LABEL'
}
item {
  id: $YELLOW_BALL_ID
  name: '$YELLOW_BALL_LABEL'
}
item {
  id: $GREEN_BALL_ID
  name: '$GREEN_BALL_LABEL'
}
item {
  id: $YELLOW_HOME_ID
  name: '$YELLOW_HOME_LABEL'
}
item {
  id: $RED_HOME_ID
  name: '$RED_HOME_LABEL'
}
item {
  id: $BLUE_HOME_ID
  name: '$BLUE_HOME_LABEL'
}
item {
  id: $GREEN_HOME_ID
  name: '$GREEN_HOME_LABEL'
}
EOF
}

##################################################
# Generate map of files to ids in the current folder
# Files to be generated: list.txt, trainval.txt, test.txt
# Note that list is a concatenation of the other two
##################################################
generate_id_map_file() {
  echo_my "generate_id_map_file()..."
  touch list.txt

# cat << EOF > list.txt
# #Image CLASS_ID KIND_ID TYPE_ID
# #Image name
# #CLASS_ID: 1:6 Class ids
# #KIND_ID: 1:Ball 2:Other
# #TYPE_ID: 1-4:Ball 1:2:Other
# EOF

  cd xmls
  for file in *.xml
  do
      local NAME=`echo $file | sed -n -e "s/.xml//p"`
      local KIND=1
      local TYPE=1
      local CLASS=undefined
      # truncate everything starting with '_*' - just keep the color
      local CLASS_STRING=`echo $file | sed -n -e "s/_.*$//p"`
      # convert to lower case
      CLASS_STRING=`echo $CLASS_STRING | sed -e 's/\(.*\)/\L\1/'`
      case $CLASS_STRING in
          blueball)
            CLASS=$BLUE_BALL_ID
            ;;
          redball)
            CLASS=$RED_BALL_ID
            ;;
          yellowball)
            CLASS=$YELLOW_BALL_ID
            ;;
          greenball)
            CLASS=$GREEN_BALL_ID
            ;;
          bluehome)
            CLASS=$BLUE_HOME_ID
            ;;
          redhome)
            CLASS=$RED_HOME_ID
            ;;
          yellowhome)
            CLASS=$YELLOW_HOME_ID
            ;;
          greenhome)
            CLASS=$GREEN_HOME_ID
            ;;
          *)
            echo_my "Found an unknown type of file: '$file'" $ECHO_ERROR
            # skip writing this file into the list file
            continue
            ;;
      esac

      echo "$NAME $CLASS $KIND $TYPE" >> ../list.txt
  done

  # Split the file generated above into two files "test.txt" and "trainval.txt"
  cd ..
  touch test.txt
  touch trainval.txt

  local flag=0
  while IFS='' read -r line || [[ -n "$line" ]]; do
      if ((flag)) # every other line goes into a separate file
      then
          echo "$line" >> test.txt
      else
          echo "$line" >> trainval.txt
      fi
      flag=$((1-flag))
  done < "list.txt"
}

##################################################
# Prepare Object Detection API
##################################################
setup_object_detection() {
  echo_my "Setting up Tensor Flow Object Detection API for training..."

  # Prepare images and annotations
  LOCAL_TMP=$TMP/object_detection
  rm -rf $LOCAL_TMP
  mkdir -p $LOCAL_TMP
  cd $LOCAL_TMP
  local CWD=`pwd`

  IMAGES_ZIP=images-for-training.zip
  ANNOTATIONS_ZIP=annotations.zip
  # IMAGES_ZIP=images_small_set.zip
  # ANNOTATIONS_ZIP=annotations_small_set.zip

  echo_my "Download training images..."
  gsutil cp gs://$GCS_IMAGES/$IMAGES_ZIP ./

  echo_my "Download annotations..."
  gsutil cp gs://$GCS_IMAGES/$ANNOTATIONS_ZIP ./
  mkdir -p annotations/xmls
  mkdir -p images

  echo_my "Extract all into flat directory and ignore subdirectories"
  unzip -q -j $ANNOTATIONS_ZIP -d annotations/xmls
  unzip -q -j $IMAGES_ZIP -d images

  echo_my "Free up space since we dont need zip files anymore"
  rm -rf $ANNOTATIONS_ZIP
  rm -rf $IMAGES_ZIP

  cd $CWD/annotations
  generate_id_map_file

  cd $CWD
  local LABEL_MAP_FILE=`pwd`/annotations/robot_derby_label_map.pbtxt
  generate_pbtxt_file $LABEL_MAP_FILE

  echo_my "Convert training data to TFRecords..."
  cd $CWD
  python $TL_MODULE_PATH/python/create_robot_derby_tf_record.py \
      --label_map_path=$LABEL_MAP_FILE \
      --data_dir=$CWD \
      --output_dir=$CWD

  echo_my "Removing existing objects and bucket '$GCS_ML_BUCKET' from GCS..."
  gsutil -m rm -r $GCS_ML_BUCKET/* | true
  gsutil rb $GCS_ML_BUCKET | true # ignore the error if bucket does not exist

  echo_my "Upload dataset to GCS..."
  gsutil mb -l $REGION -c regional $GCS_ML_BUCKET
  gsutil cp robot_derby_train.record $GCS_ML_BUCKET/data/robot_derby_train.record
  gsutil cp robot_derby_val.record $GCS_ML_BUCKET/data/robot_derby_val.record
  gsutil cp $LABEL_MAP_FILE $GCS_ML_BUCKET/data/robot_derby_label_map.pbtxt

  echo_my "Upload pretrained COCO Model for Transfer Learning..."
  wget https://storage.googleapis.com/download.tensorflow.org/models/object_detection/${MODEL}.tar.gz
  tar -xf ${MODEL}.tar.gz
  gsutil cp $MODEL/model.ckpt.* $GCS_ML_BUCKET/data/
  rm -rf ${MODEL}.tar.gz

  # This will update model config for our custom project settings
  # echo_my "Configure TF pipeline..."
  # sed -i "s|PATH_TO_BE_CONFIGURED|"${GCS_ML_BUCKET}"/data|g" $MODEL_CONFIG_PATH/${MODEL_CONFIG}

  gsutil cp $MODEL_CONFIG_PATH/$MODEL_CONFIG \
  $GCS_ML_BUCKET/data/$MODEL_CONFIG

  echo_my "Packaging the TensorFlow Object Detection API and TF Slim..."
  cd $TF_MODEL_DIR/models/research
  python setup.py sdist
  (cd slim && python setup.py sdist)
}

##################################################
# Generate CLOUD.YML file
# Inputs:
#   - file to be generated
##################################################
generate_cloud_yml_file() {
  local YML_FILE=$1
  echo_my "generate_cloud_yml_file(): YML_FILE=$YML_FILE..."

cat << EOF > $YML_FILE
# Please do not edit this file by hand - it is auto-generated by script
# See details here: https://cloud.google.com/ml-engine/docs/training-overview
# masterType: complex_model_m_p100
# workerType: complex_model_m_p100

trainingInput:
  scaleTier: CUSTOM
  masterType: standard_gpu
  workerCount: 1
  workerType: standard_gpu
  parameterServerCount: 1
  parameterServerType: standard
EOF
}

#############################################
# Generate Model Config file.
# ssd_mobilenet_v1_coco_11_06_2017
# Consider this material: http://www.frank-dieterle.de/phd/2_8_1.html
#############################################
# generate_ssd_mobilenet_model_config() {
#   local MODEL_CONFIG=$1
#   echo_my "generate_ssd_mobilenet_model_config(): MODEL_CONFIG=$MODEL_CONFIG..."
# cat << EOF > $MODEL_CONFIG
# # SSD with Mobilenet v1, configured for Oxford-IIIT Pets Dataset.
# # Users should configure the fine_tune_checkpoint field in the train config as
# # well as the label_map_path and input_path fields in the train_input_reader and
# # eval_input_reader. Search for "PATH_TO_BE_CONFIGURED" to find the fields that
# # should be configured.
# model {
#   ssd {
#     num_classes: 8
#     box_coder {
#       faster_rcnn_box_coder {
#         y_scale: 10.0
#         x_scale: 10.0
#         height_scale: 5.0
#         width_scale: 5.0
#       }
#     }
#     matcher {
#       argmax_matcher {
#         matched_threshold: 0.5
#         unmatched_threshold: 0.5
#         ignore_thresholds: false
#         negatives_lower_than_unmatched: true
#         force_match_for_each_row: true
#       }
#     }
#     similarity_calculator {
#       iou_similarity {
#       }
#     }
#     anchor_generator {
#       ssd_anchor_generator {
#         num_layers: 6
#         min_scale: 0.2
#         max_scale: 0.95
#         aspect_ratios: 1.0
#         aspect_ratios: 2.0
#         aspect_ratios: 0.5
#         aspect_ratios: 3.0
#         aspect_ratios: 0.3333
#       }
#     }
#     image_resizer {
#       fixed_shape_resizer {
#         height: 300
#         width: 300
#       }
#     }
#     box_predictor {
#       convolutional_box_predictor {
#         min_depth: 0
#         max_depth: 0
#         num_layers_before_predictor: 0
#         use_dropout: false
#         dropout_keep_probability: 0.8
#         kernel_size: 1
#         box_code_size: 4
#         apply_sigmoid_to_scores: false
#         conv_hyperparams {
#           activation: RELU_6,
#           regularizer {
#             l2_regularizer {
#               weight: 0.00004
#             }
#           }
#           initializer {
#             truncated_normal_initializer {
#               stddev: 0.03
#               mean: 0.0
#             }
#           }
#           batch_norm {
#             train: true,
#             scale: true,
#             center: true,
#             decay: 0.9997,
#             epsilon: 0.001,
#           }
#         }
#       }
#     }
#     feature_extractor {
#       type: 'ssd_mobilenet_v1'
#       min_depth: 16
#       depth_multiplier: 1.0
#       conv_hyperparams {
#         activation: RELU_6,
#         regularizer {
#           l2_regularizer {
#             weight: 0.00004
#           }
#         }
#         initializer {
#           truncated_normal_initializer {
#             stddev: 0.03
#             mean: 0.0
#           }
#         }
#         batch_norm {
#           train: true,
#           scale: true,
#           center: true,
#           decay: 0.9997,
#           epsilon: 0.001,
#         }
#       }
#     }
#     loss {
#       classification_loss {
#         weighted_sigmoid {
#         }
#       }
#       localization_loss {
#         weighted_smooth_l1 {
#         }
#       }
#       hard_example_miner {
#         num_hard_examples: 3000
#         iou_threshold: 0.99
#         loss_type: CLASSIFICATION
#         max_negatives_per_positive: 3
#         min_negatives_per_image: 0
#       }
#       classification_weight: 1.0
#       localization_weight: 1.0
#     }
#     normalize_loss_by_num_matches: true
#     post_processing {
#       batch_non_max_suppression {
#         score_threshold: 1e-8
#         iou_threshold: 0.6
#         max_detections_per_class: 100
#         max_total_detections: 100
#       }
#       score_converter: SIGMOID
#     }
#   }
# }
# train_config: {
#   batch_size: 24
#   optimizer {
#     rms_prop_optimizer: {
#       learning_rate: {
#         exponential_decay_learning_rate {
#           initial_learning_rate: 0.004
#           decay_steps: 800720
#           decay_factor: 0.95
#         }
#       }
#       momentum_optimizer_value: 0.9
#       decay: 0.9
#       epsilon: 1.0
#     }
#   }
#   fine_tune_checkpoint: "${GCS_ML_BUCKET}/data/model.ckpt"
#   from_detection_checkpoint: true
#   # Note: The below line limits the training process to 200K steps, which we
#   # empirically found to be sufficient enough to train the pets dataset. This
#   # effectively bypasses the learning rate schedule (the learning rate will
#   # never decay). Remove the below line to train indefinitely.
#   num_steps: $TRAINING_STEPS
#   # More info about different augmentation options: https://stackoverflow.com/questions/44906317/what-are-possible-values-for-data-augmentation-options-in-the-tensorflow-object
# #   data_augmentation_options {
# #     random_horizontal_flip {
# #     }
# #     random_image_scale {
# #     }
# #     random_adjust_brightness {
# #     }
# #     random_adjust_contrast {
# #     }
# #     random_pad_image {
# #     }
# #     random_crop_image {
# #     }
#   data_augmentation_options {
#     random_horizontal_flip {
#     }
#   }
#   data_augmentation_options {
#     ssd_random_crop {
#     }
#   }
# }
# train_input_reader: {
# tf_record_input_reader {
#   input_path: "${GCS_ML_BUCKET}/data/robot_derby_train.record"
# }
# label_map_path: "${GCS_ML_BUCKET}/data/robot_derby_label_map.pbtxt"
# }
# eval_config: {
#   num_examples: 2000
#   # Note: The below line limits the evaluation process to 10 evaluations.
#   # Remove the below line to evaluate indefinitely.
#   max_evals: 10
# }
# eval_input_reader: {
#   tf_record_input_reader {
#     input_path: "${GCS_ML_BUCKET}/data/robot_derby_val.record"
#   }
#   label_map_path: "${GCS_ML_BUCKET}/data/robot_derby_label_map.pbtxt"
#   shuffle: false
#   num_readers: 1
# }
# EOF
# }

#############################################
# Generate Model Config file for
# faster_rcnn_resnet101_coco_11_06_2017
# Consider this material: http://www.frank-dieterle.de/phd/2_8_1.html
#############################################
generate_model_config_faster_rcnn_resnet101() {
  local MODEL_CONFIG=$1
  echo_my "generate_model_config_faster_rcnn_resnet101(): MODEL_CONFIG=$MODEL_CONFIG..."

cat << EOF > $MODEL_CONFIG
# Faster R-CNN with Resnet-101 (v1) configured for the Oxford-IIIT Pet Dataset.
# Users should configure the fine_tune_checkpoint: "${GCS_ML_BUCKET}/data/model.ckpt"
# well as the label_map_path and input_path fields in the train_input_reader and
# eval_input_reader. Search for "${GCS_ML_BUCKET}/data" to find the fields that
# should be configured.
model {
  faster_rcnn {
    num_classes: ${NUM_CLASSES}
    image_resizer {
      keep_aspect_ratio_resizer {
        min_dimension: 600
        max_dimension: ${HORIZONTAL_RESOLUTION_PIXELS}
      }
    }
    feature_extractor {
      type: 'faster_rcnn_resnet101'
      first_stage_features_stride: 16
    }
    first_stage_anchor_generator {
      grid_anchor_generator {
        scales: [0.25, 0.5, 1.0, 2.0]
        aspect_ratios: [0.5, 1.0, 2.0]
        height_stride: 16
        width_stride: 16
      }
    }
    first_stage_box_predictor_conv_hyperparams {
      op: CONV
      regularizer {
        l2_regularizer {
          weight: 0.0
        }
      }
      initializer {
        truncated_normal_initializer {
          stddev: 0.01
        }
      }
    }
    first_stage_nms_score_threshold: 0.0
    first_stage_nms_iou_threshold: 0.7
    first_stage_max_proposals: ${first_stage_max_proposals}
    first_stage_localization_loss_weight: 2.0
    first_stage_objectness_loss_weight: 1.0
    initial_crop_size: 14
    maxpool_kernel_size: 2
    maxpool_stride: 2
    second_stage_box_predictor {
      mask_rcnn_box_predictor {
        use_dropout: false
        dropout_keep_probability: 1.0
        fc_hyperparams {
          op: FC
          regularizer {
            l2_regularizer {
              weight: 0.0
            }
          }
          initializer {
            variance_scaling_initializer {
              factor: 1.0
              uniform: true
              mode: FAN_AVG
            }
          }
        }
      }
    }
    second_stage_post_processing {
      batch_non_max_suppression {
        score_threshold: ${score_threshold}
        iou_threshold: 0.6
        max_detections_per_class: ${max_detections_per_class}
        max_total_detections: ${max_total_detections}
      }
      score_converter: SOFTMAX
    }
    second_stage_localization_loss_weight: 2.0
    second_stage_classification_loss_weight: 1.0
  }
}
train_config: {
  batch_size: 1
  optimizer {
    momentum_optimizer: {
      learning_rate: {
        manual_step_learning_rate {
          initial_learning_rate: 0.0003
          schedule {
            step: 900000
            learning_rate: .00003
          }
          schedule {
            step: 1200000
            learning_rate: .000003
          }
        }
      }
      momentum_optimizer_value: 0.9
    }
    use_moving_average: false
  }
  gradient_clipping_by_norm: 10.0
  fine_tune_checkpoint: "${GCS_ML_BUCKET}/data/model.ckpt"
  from_detection_checkpoint: true

  # Note: The below line limits the training process to $TRAINING_STEPS number of steps, which we
  # empirically found to be sufficient enough to train our dataset. This
  # effectively bypasses the learning rate schedule (the learning rate will
  # never decay). Remove the below line to train indefinitely.

  num_steps: ${TRAINING_STEPS}

  # More info about different augmentation options: https://stackoverflow.com/questions/44906317/what-are-possible-values-for-data-augmentation-options-in-the-tensorflow-object
  data_augmentation_options {
    random_horizontal_flip {
    }
    random_image_scale {
    }
    random_adjust_brightness {
    }
    random_adjust_contrast {
    }
    random_pad_image {
    }
    random_crop_image {
    }
  }
}
train_input_reader: {
  tf_record_input_reader {
    input_path: "${GCS_ML_BUCKET}/data/robot_derby_train.record"
  }
  label_map_path: "${GCS_ML_BUCKET}/data/robot_derby_label_map.pbtxt"
}
eval_config: {
  num_examples: 2000
  # Note: The below line limits the evaluation process to 10 evaluations.
  # Remove the below line to evaluate indefinitely.
  max_evals: 10
}
eval_input_reader: {
  tf_record_input_reader {
    input_path: "${GCS_ML_BUCKET}/data/robot_derby_val.record"
  }
  label_map_path: "${GCS_ML_BUCKET}/data/robot_derby_label_map.pbtxt"
  shuffle: false
  num_readers: 1
}
EOF
}

##################################################
# Start TF training
##################################################
train_model() {
  echo_my "train_model(): TF version `python -c 'import tensorflow as tf; print(tf.__version__)'`"
  cd $CWD

  if ( $LOCAL_TRAINING ); then
    echo_my "Start LOCAL training job..."
    # gcloud auth application-default login
    rm nohup.out | true # ignore error

    nohup gcloud ml-engine local train \
    --job-dir=$GCS_ML_BUCKET/train \
    --package-path $TF_MODEL_DIR/models/research/object_detection \
    --module-name object_detection.legacy.train \
    -- \
    --train_dir=$GCS_ML_BUCKET/train \
    --pipeline_config_path=$GCS_ML_BUCKET/data/$MODEL_CONFIG &

    # Wait few seconds before showing output
    sleep 5
    tail -f nohup.out

  else
    echo_my "Start REMOTE training job..."
    YML=$TMP/cloud.yml
    generate_cloud_yml_file $YML
    # See details here: https://cloud.google.com/ml-engine/docs/training-overview

    gcloud ml-engine jobs submit training `whoami`_object_detection_`date +%s` \
      --job-dir=$GCS_ML_BUCKET/train \
      --packages $TF_MODEL_DIR/models/research/dist/object_detection-0.1.tar.gz,$TF_MODEL_DIR/models/research/slim/dist/slim-0.1.tar.gz,/tmp/pycocotools/pycocotools-2.0.tar.gz \
      --module-name object_detection.legacy.train \
      --region $REGION \
      --runtime-version $CMLE_RUNTIME_VERSION \
      --config $YML \
      -- \
      --train_dir=$GCS_ML_BUCKET/train \
      --pipeline_config_path=$GCS_ML_BUCKET/data/$MODEL_CONFIG

    echo_my "Start evaluation job concurrently with training..."

    gcloud ml-engine jobs submit training `whoami`_object_detection_eval_`date +%s` \
      --job-dir=$GCS_ML_BUCKET/train \
      --packages $TF_MODEL_DIR/models/research/dist/object_detection-0.1.tar.gz,$TF_MODEL_DIR/models/research/slim/dist/slim-0.1.tar.gz,/tmp/pycocotools/pycocotools-2.0.tar.gz \
      --module-name object_detection.legacy.train \
      --runtime-version $CMLE_RUNTIME_VERSION \
      --region $REGION \
      --scale-tier BASIC_GPU \
      -- \
      --checkpoint_dir=$GCS_ML_BUCKET/train \
      --eval_dir=$GCS_ML_BUCKET/eval \
      --pipeline_config_path=$GCS_ML_BUCKET/data/$MODEL_CONFIG

      echo_my "Now check the ML dashboard: https://console.cloud.google.com/mlengine/jobs."
      echo_my "It may take up to 3 hours to complete the training job."
      echo_my "Go to the [GCP Console]->[GCE]->[VMs]->[tensorboard-dev]."
      echo_my "SSH into this VM and run tensorboard.sh script.\n"
  fi
}

#############################################
# MAIN
#############################################
print_header "TensorFlow transferred learning"

CWD=`pwd`
TMP=$CWD/tmp
mkdir -p $TMP

if [ -f "$SERVICE_ACCOUNT_SECRET" ]; then
  echo_my "Activating service account..."
  gcloud auth activate-service-account --key-file=$SERVICE_ACCOUNT_SECRET
fi

generate_model_config_faster_rcnn_resnet101 $MODEL_CONFIG_PATH/$MODEL_CONFIG
set_python_path
setup_object_detection
train_model

print_footer "Once the training is completed, run this script: export_tf_checkpoint.sh"

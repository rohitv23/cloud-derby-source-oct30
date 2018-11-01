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
# ******************************************************* 
# Usage: ./collect.sh <event folder-id> 
# ie. ./collect.sh 683286859878
# The script will collect all photos from any cloudderby event into a defined bucket under Source and Administration project
# by scanning all folders and projects and buckets to download user images
# change gs://dc-event-2018 to your specific bucket

echo Folder ID $1
myarr=($(gcloud alpha resource-manager folders list --folder $1 | awk '{ print $3 }'))

for i in "${myarr[@]}"
do
    :
    if [ $i != ID ]
    then
     folder_arr=($(gcloud projects list --filter=" parent.id: '$i' " | awk '{ print $1 }'))
     for x in "${folder_arr[@]}"
     do
	    :
	    if [ $x != PROJECT_ID ] 
	    then  
               gcloud config set project $x 
               subdir_arr=($(gsutil ls gs://))
               for y in "${subdir_arr[@]}"
	           do
		          :
		          echo $y
                  # change gs://dc-event-2018 to your specific bucket
		          gsutil -m cp $y*.jpg gs://dc-event-2018
		          gsutil -m cp $y*.zip gs://dc-event-2018
	           done
	    fi
    done
    fi
done
echo "Collection has completed successfully."

rem
rem  Copyright 2018 Google LLC
rem
rem  Licensed under the Apache License, Version 2.0 (the "License");
rem  you may not use this file except in compliance with the License.
rem  You may obtain a copy of the License at
rem
rem      https://www.apache.org/licenses/LICENSE-2.0
rem
rem  Unless required by applicable law or agreed to in writing, software
rem  distributed under the License is distributed on an "AS IS" BASIS,
rem  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
rem  See the License for the specific language governing permissions and
rem  limitations under the License.
rem

rem --------------------------------------------------------------------
rem This script uploads user created annotations into GCS for future merge
rem with images from other users.
rem --------------------------------------------------------------------

rem Put unique GCS bucket name here - must be the same for all team members
set GCS_BUCKET=annotated-images-<PROJECT>-version-<VERSION>

rem Put file name here - different for each team member - DO NOT include "zip" extention in the name...
set ZIP_FILE=userXXX

cd C:\a-robot-images

rem --- Create archive with user provided annotations and images
"c:\Program Files\7-Zip\7z.exe" a -tzip -r %ZIP_FILE% *.xml *.jpg

rem --- Upload annotations and images to GCS for transferred learning
call gsutil cp %ZIP_FILE%.zip gs://%GCS_BUCKET%

del %ZIP_FILE%.zip

cd C:\robot-derby\src\cloud\ml\annotation
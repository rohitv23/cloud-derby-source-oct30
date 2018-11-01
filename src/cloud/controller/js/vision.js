/**
 * Copyright 2018, Google, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

'use strict';
var process = require('process'); // Required for mocking environment variables
const request = require('request');

// User credentials to authenticate to remote Inference VM service
const INFERENCE_USER_NAME = process.env.INFERENCE_USER_NAME;
const INFERENCE_PASSWORD = process.env.INFERENCE_PASSWORD;

//const APP_URL = `http:\/\/10.142.0.2:8080`;
// const APP_URL = `https://${process.env.GOOGLE_CLOUD_PROJECT}.appspot.com`;
const APP_URL = `http://${process.env.INFERENCE_VM_IP}`;
const HTTP_PORT = process.env.HTTP_PORT;
const INFERENCE_URL = process.env.INFERENCE_URL;
const OBJECT_INFERENCE_API_URL = APP_URL + ':' + HTTP_PORT + INFERENCE_URL;

require('dotenv').config();
var VisionResponse = require('./vision-response');
var BoundingBox = require('./bounding-box');

// Initialize simulation engine (it may be On or Off)
var VisionSimulator = require('./simulation').VisionSimulator;
let visionSimulator = new VisionSimulator();

/**************************************************************************
  Vision class calls Object Detection API to figure out where are all the
  balls in the image so navigation logic can use it for driving decisions
 **************************************************************************/
module.exports = class Vision {

  constructor() {
    // Whatever needs to be done here...
  }

  /************************************************************
    Send image to ML and parse it
    Input:
      - sensorMessage - includes GCS URL to the Image (gs://...)
    Ouput:
      - VisionResponse - Coordinates of various objects that were recognized
   ************************************************************/
  recognizeObjects(sensorMessage) {
    console.log("recognizeObjects()...");
    if (visionSimulator.simulate) {
      // Are we in a simulation mode? If so, return fake series of responses
      return Promise.resolve()
        .then(() => {
          console.log("recognizeObjects()...returning a simulated response");
          return visionSimulator.nextVisionResponse();
        });
    }

    // Call REST API - Object Detection - ML Engine or TensorFlow
    // this returns a Promise which when resolved returns the VisionResponse object
    return this.recognizeObjectAPIAsync(sensorMessage)
      .then((response) => {
        return Promise.resolve()
          .then(() => {
            // console.log("Returning a vision response from recognizeObjectAPIAsync in recognizeObjects");
            return this.createVisionResponse(response);
          });
      });
  }

  createVisionResponse(jsonAPIResponse) {
    // console.log("createVisionResponse(): start");
    let response = new VisionResponse();
    var objResponse = JSON.parse(jsonAPIResponse);
    for (var key in objResponse) {
      //console.log("key: "+key+", val:"+JSON.stringify(objResponse[key]));
      for (var i = 0; i < objResponse[key].length; i++) {
        //console.log("objResponse[key]["+i+"]: "+JSON.stringify(objResponse[key][i]));
        var bBox = new BoundingBox(
          key,
          objResponse[key][i]["x"],
          objResponse[key][i]["y"],
          objResponse[key][i]["w"],
          objResponse[key][i]["h"],
          objResponse[key][i]["score"]
        );
        response.addBox(bBox);
      }
    }
    // console.log("createVisionResponse(): end");
    return response;
  }


  recognizeObjectAPIAsync(sensorMessage) {
    return new Promise(function(resolve, reject) {
      var gcsURI = sensorMessage.sensors.frontCameraImagePathGCS;
      if (!gcsURI) {
        reject("No gcURI found in sensorMessage");
        return;
      } else if (!gcsURI.startsWith("gs://")) {
        reject("gcsURI must start with gs://");
        return;
      } else {
        var apiUrl = OBJECT_INFERENCE_API_URL + "?gcs_uri=" + encodeURIComponent(gcsURI);
        console.log("apiUrl: " + apiUrl);
        var visionResponse = new VisionResponse();
        const auth = { user: INFERENCE_USER_NAME, pass: INFERENCE_PASSWORD };
        // Measure time it takes to call inference API
        var startTime = Date.now();
        request({ uri: apiUrl, auth: auth }, function(err, response, body) {
          // console.log("Response received: ");
          if (err) {
            reject(err);
          } else {

            console.log("Vision response took "+(Date.now() - startTime)+" ms:" + body);
            // console.log("now...moving on");
            if (response.statusCode != 200) {
              reject("Received " + response.statusCode + " from API");
              return;
            } else {
              resolve(body);
            }
          }
        });
      }
    });
  }
};

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
const APP = 'DRIVING-CONTROL-APP';
const express = require('express');

console.log(`***${APP} is starting up***`);
var process = require('process'); // Required for mocking environment variables
var PubSub = require('@google-cloud/pubsub');
var bodyParser = require('body-parser');
var path = require('path');
var Navigation = require('./navigation');
var manualDrivingForm = require('./manual-driving').manualDrivingForm;
var manualCommand = require('./manual-driving').manualCommand;
var DriveMessage = require('./drive-message').DriveMessage;
const MANUAL_MODE = require('./drive-message').MANUAL_MODE;
const AUTOMATIC_MODE = require('./drive-message').AUTOMATIC_MODE;
const DEBUG_MODE = require('./drive-message').DEBUG_MODE;


// Confiure external URL for help output
const APP_URL = `https://${process.env.GOOGLE_CLOUD_PROJECT}.appspot.com/`;

// By default, the client will authenticate using the service account file
// specified by the GOOGLE_APPLICATION_CREDENTIALS environment variable and use
// the project specified by the GCLOUD_PROJECT environment variable. See
// https://googlecloudplatform.github.io/gcloud-node/#/docs/google-cloud/latest/guides/authentication
// These environment variables are set automatically on Google App Engine
// Instantiate a pubsub client
const pubsub = PubSub();
// References an existing subscription
const command_topic = pubsub.topic(process.env.COMMAND_TOPIC);
const sensorSubscription = pubsub.subscription(process.env.SENSOR_SUBSCRIPTION);
const carId = process.env.CAR_ID;
// Any sensor message with the time stamp older than this will be discarded as useless
const MAX_MSG_AGE_SEC = 60;

// BigQuery Variables
const BQprojectId = process.env.BQ_PROJECT_ID;
const datasetId = process.env.BQ_DATASET;
const sensorMessageTable = process.env.BQ_SENSOR_MESSAGE_TABLE;
const driveMessageTable = process.env.BQ_DRIVE_MESSAGE_TABLE;
const PROJECT_NAME = process.env.GOOGLE_CLOUD_PROJECT;

// Instantiate Express runtime
var app = express();
app.set('view engine', 'pug');
app.set('views', path.join(__dirname, 'views'));
//support parsing of application/json type post data
app.use(bodyParser.json());
//support parsing of application/x-www-form-urlencoded post data
app.use(bodyParser.urlencoded({ extended: true }));
require('@google-cloud/debug-agent').start({ allowExpressions: true });

/************************************************************
  Car and game settings
 ************************************************************/
// Color of the ball that this car controller will be after. It can be changed via control panel at run time
let ballColor = "red";
/************************************************************
  Keeping track of stats
 ************************************************************/
let totalMessagesReceived = 0;
let rejectedOutOfOrderMessages = 0;
let rejectedFormatMessages = 0;
let totalMessagesSent = 0;
// Tracking errors of any kind
let totalErrors = 0;
// Is inbound listener Up or Down now?
let listenerStatus = false;
// Value of the message with the maximum time stamp seen so far
let maxMsgTimeStampMs = 0;
// History of received messages
let inboundMsgHistory = [];
// Maximum size of received Msg history as # of messages stored - one msg per second for full hour
const MAX_INBOUND_HISTORY = 60 * 60;
// History of sent command messages
let outboundMsgHistory = [];
// Maximum size of sent command history as # of messages stored
const MAX_OUTBOUND_HISTORY = 60 * 60;
// Here we will keep the next driving command to be send to the car in debug mode
let nextDrivingCommand;
// Current driving mode of the car
let currentDrivingMode = MANUAL_MODE;
// Initialize Navigation logic
let navigation = new Navigation(outboundMsgHistory);

/************************************************************
  Error handler for PubSub inbound
 ************************************************************/
const errorHandler = function(error) {
  totalErrors++;
  console.error(`ERROR: ${error}`);
};

/************************************************************
  Event handler to handle inbound PubSub messages
 ************************************************************/
const inboudMessageHandler = function(message) {
  // "Ack" (acknowledge receipt of) the message
  message.ack();
  totalMessagesReceived++;
  console.log("inboudMessageHandler(carId=" + carId + "): <<<<<<<<<<<<<<<<<<<<<< Received " + totalMessagesReceived + " messages");

  let data = JSON.parse(message.data);
  // Ignore invalid messages
  if (!isMessageValid(data)) {
    totalErrors++;
    console.error("ERROR: inboudMessageHandler(): Skipping this message since it did not pass validity check");
    return;
  }

  // Save message for posterity
  saveInboundMessage(message);

  // Publish Message to BigQuery
  // insertRowsAsStream(sensorMessageTable,data);

  // Do not process inbound messages in manual driving mode
  if (currentDrivingMode == MANUAL_MODE) {
    return;
  }

  // Call navigation logic based on the sensor data and send new command to the car
  navigation.nextMove(data)
    .then((response) => {
      if (!(currentDrivingMode == DEBUG_MODE)) {
        publishCommand(response);
      } else {
        nextDrivingCommand = response;
      }
    });
};

/************************************************************
  Send prepared command message to the car via PubSub.
  Input:
    - Command object
  Output:
    - none, but the result of the function is that single PubSub message is sent
 ************************************************************/
function publishCommand(command) {
  if (command === undefined) {
    console.log("publishCommand(): Command is not defined - ignoring");
    return;
  }
  let txtMessage = JSON.stringify(command);
  // Only send a message when it is not empty
  if (txtMessage.length > 0) {
    command_topic.publish(txtMessage, (err) => {
      if (err) {
        console.log(err);
        totalErrors++;
        return;
      }
      totalMessagesSent++;
      console.log("publishCommand(carId=" + carId + "): >>>>>>>>>>>>>>>>>>>>>>>>> Message #" + totalMessagesSent + " " + txtMessage);
      saveOutboundMessage(command);
    });
  } else {
    console.log("publishCommand(): Command is empty - Nothing to send");
  }
}

/************************************************************
  Validate the message from the car based on certain criteria

  Example input message:
  {"carId":1,"msgId":8,"version":"1.0","timestampMs":1519509836918,"carState":{"ballsCollected":2,"batteryLeft":55,"sensors":{"frontLaserDistanceMm":11,"frontCameraImagePath":"gs://robot-derby-camera-1/images/image8.jpg"}}
 ************************************************************/
function isMessageValid(msg) {
  console.log("isMessageValid():" + JSON.stringify(msg));

  // Does this message carry timestamp field with it?
  if (!msg.timestampMs) {
    console.error("ERROR: isMessageValid(): msg.timestampMs is undefined");
    rejectedFormatMessages++;
    return false;
  }

  // Reject message if it has older timestamp than we have seen earlier
  if (maxMsgTimeStampMs > msg.timestampMs) {
    console.error("ERROR: isMessageValid(): msg.timestampMs is older than we have already seen by " + (maxMsgTimeStampMs - msg.timestampMs) + " ms");
    rejectedOutOfOrderMessages++;
    return false;
  }
  // Now we know this new message is more recent than anything we have seen so far
  maxMsgTimeStampMs = msg.timestampMs;

  // Reject very old messages
  let oldestAllowedMs = new Date().getTime() - MAX_MSG_AGE_SEC * 1000;
  if (msg.timestampMs < oldestAllowedMs) {
    console.error("ERROR: isMessageValid(): msg.timestampMs is older than max allowed age of " + MAX_MSG_AGE_SEC + "(sec) the message by " + (oldestAllowedMs - msg.timestampMs) + " ms");
    rejectedOutOfOrderMessages++;
    return false;
  }

  // Message has been successfully validated
  return true;
}

/************************************************************
  Save history of inbound messages
 ************************************************************/
function saveInboundMessage(message) {
  // Check for max size of history
  if (inboundMsgHistory.length >= MAX_INBOUND_HISTORY) {
    // Truncate 10% of the oldest history log
    inboundMsgHistory.splice(0, inboundMsgHistory.length / 10);
  }
  // Add message to history
  inboundMsgHistory.push(message);
}

/************************************************************
  Save history of outbound messages
 ************************************************************/
function saveOutboundMessage(message) {
  // Check for max size of history
  if (outboundMsgHistory.length >= MAX_OUTBOUND_HISTORY) {
    // Truncate 10% of the oldest history log
    outboundMsgHistory.splice(0, outboundMsgHistory.length / 10);
  }
  // Add message to history
  outboundMsgHistory.push(message);
}

/************************************************************
  Read sensor data from the car - used by the worker to listen to pubsub messages.
  When more than one worker is running they will all share the same
  subscription, which means that pub/sub will evenly distribute messages to each worker.
 ************************************************************/
function startListener() {
  // console.log("startListener()...");
  if (listenerStatus) {
    console.log("Listener is already running, nothing to do.");
    return;
  }
  // Listen for new messages
  sensorSubscription.on(`message`, inboudMessageHandler);
  sensorSubscription.on(`error`, errorHandler);
  listenerStatus = true;
  console.log("startListener()...done");
}

/************************************************************
  Stop listening for messages and reset counters
 ************************************************************/
function stopListener() {
  // console.log("stopListener()...");
  if (listenerStatus) {
    sensorSubscription.removeListener(`message`, inboudMessageHandler);
    sensorSubscription.removeListener(`error`, errorHandler);
    console.log("Message listener stopped");
    listenerStatus = false;
  } else {
    console.log("No need to stop Message listener since it was not running");
  }
}

/************************************************************
  Setup environment before we run the server
 ************************************************************/
function reset() {
  // Reset all counters back to zero
  totalMessagesReceived = 0;
  rejectedOutOfOrderMessages = 0;
  rejectedFormatMessages = 0;
  totalMessagesSent = 0;
  totalErrors = 0;
  nextDrivingCommand = undefined;
  inboundMsgHistory = [];
  outboundMsgHistory = [];
  // Will ignore any messages up until now
  maxMsgTimeStampMs = new Date().getTime();
}

/************************************************************
  Change color form
 ************************************************************/
function changeColorForm() {
  // console.log("changeColorForm()...");

  let form = `<a href="/">Home</a>
    <h1>Change target ball color</h1>
    <form action="/color_change_submit" method="post">
    <br>
    <label for="ball_color">New ball color for car to search:</label><br>
    <input type="radio" name="ball_color" value="Red"> Red<br>
    <input type="radio" name="ball_color" value="Blue"> Blue<br>
    <input type="radio" name="ball_color" value="Green"> Green<br>
    <input type="radio" name="ball_color" value="Yellow"> Yellow<br><br>
    <input type="submit" name="change_color" value="Submit"></form>`;
  return form;
}

/************************************************************
  Debugger form
 ************************************************************/
function debugDrivingForm() {
  // console.log("debugDrivingForm()...");
  let drivingCommandString;
  let mostRecentCarMessage;
  let imageUrl;

  if (nextDrivingCommand === undefined) {
    drivingCommandString = "nextDrivingCommand is undefined. No driving command to be sent to the car";
  } else {
    drivingCommandString = JSON.stringify(nextDrivingCommand);
  }

  if (inboundMsgHistory.length == 0) {
    mostRecentCarMessage = "No messages have been received from the car";
  } else {
    let msg = inboundMsgHistory[inboundMsgHistory.length - 1];
    mostRecentCarMessage = JSON.stringify(msg);

    if ((!(msg.data === undefined)) && (!(JSON.parse(msg.data).sensors === undefined)) &&
      (!(JSON.parse(msg.data).sensors.frontCameraImagePath === undefined))) {
      imageUrl = JSON.parse(msg.data).sensors.frontCameraImagePath;
    }
  }

  console.log("debugDrivingForm(): drivingCommandString='" + drivingCommandString + "', mostRecentCarMessage='" + mostRecentCarMessage + "'");
  let debug_header = "Debugger is OFF";
  if (currentDrivingMode == DEBUG_MODE) {
    debug_header = "Debugger is ON";
  }

  let form = `<a href="/">Home</a>
    <form action="/debug_submit" method="post">
    <h1>${debug_header}</h1>
    <b>Sensor message:</b><br>${mostRecentCarMessage}<br><br>
    <b>Driving message:</b><br>${drivingCommandString}<br><br>
    <input type="submit" name="send_command" value="Send driving message to the car"><br><br>
    <input type="submit" name="next_sensor_message" value="Ask car to send new sensor message"><br><br>
    <input type="submit" name="refresh" value="Refresh page"></form>`;

  // <p><a href="/debugger_off">Turn OFF debug mode</a> / <a href="/debugger_on">Turn ON debug mode</a></p>

  // Add an image to the form
  if (!(imageUrl === undefined)) {
    form = form + '<img src="' + imageUrl + '" alt="picture of the ball" style="width:700px;"/>';
  }

  return form;
}

/************************************************************
 Streaming insert into BigQuery
 Input:
 - tableId - destination table ID
 - row - an array representing the data
 Ouput:
 - none
 ************************************************************/
function insertRowsAsStream(tableId, rows) {
  // [START bigquery_table_insert_rows]
  // Imports the Google Cloud client library
  const BigQuery = require('@google-cloud/bigquery');

  rows.projectId = PROJECT_NAME;

  // Creates a client
  const bigquery = new BigQuery({
    projectId: BQprojectId,
    keyFilename: 'bigquery-service-account.json'
  });

  // Inserts data into a table
  bigquery
      .dataset(datasetId)
      .table(tableId)
      .insert(rows)
      .then(() => {
        console.log(`insertRowsAsStream: ${rows.length} rows`);
      })
      .catch(err => {
        if (err && err.name === 'PartialFailureError') {
          if (err.errors && err.errors.length > 0) {
            console.log('insertRowsAsStream errors:');
            err.errors.forEach(err => console.error(err));
          }
        } else {
          console.error('ERROR:', err);
        }
      });
  // [END bigquery_table_insert_rows]
}

/************************************************************
  Changing the color of the ball
 ************************************************************/
app.post('/color_change_submit', (req, res) => {
  console.log(`***${APP}.GET.color_change_submit***`);

  if (req.body.ball_color) {
    ballColor = req.body.ball_color;
    let command;
    command = new DriveMessage();
    command.setColor(ballColor);
    publishCommand(command);
  }

  res.redirect('/');
});

/************************************************************
  Show history of inbound messages
 ************************************************************/
app.get('/inbound_history', (req, res) => {
  let status_message = '<a href="/">Home</a><p><h1>Inbound Message History</h1>' +
    '<p># of messages in history: <b>' + inboundMsgHistory.length + '</b></p>' +
    '<p>' + JSON.stringify(inboundMsgHistory) + '</b></p>';
  console.log(`***${APP}.GET.inbound_history***`);
  res.status(200).send(status_message);
});

/************************************************************
  Show history of outbound messages
 ************************************************************/
app.get('/outbound_history', (req, res) => {
  let status_message = '<a href="/">Home</a><p><h1>Outbound Message History</h1>' +
    '<p># of messages in history: <b>' + outboundMsgHistory.length + '</b></p>' +
    '<p>' + JSON.stringify(outboundMsgHistory) + '</b></p>';
  console.log(`***${APP}.GET.outbound_history***`);
  res.status(200).send(status_message);
});

/************************************************************
  Changing the color of the ball to chase
 ************************************************************/
app.get('/change_color', (req, res) => {
  console.log(`***${APP}.GET.change_color***`);

  let formPage = changeColorForm();
  res.status(200).send(formPage);
});

/************************************************************
  Debug mode - human control over sending driving commands to the car
 ************************************************************/
app.get('/debugger', (req, res) => {
  console.log(`***${APP}.GET.debugger***`);
  // First step is to send a command to the car to prevent non-stop streaming of messages
  // let command = new DriveMessage();
  // command.setOnDemandSensorRate();
  // command.sendSensorMessage();
  // publishCommand(command);

  let formPage = debugDrivingForm();
  res.status(200).send(formPage);
});

/************************************************************
  Debug step - send message to the car
 ************************************************************/
app.post('/debug_submit', (req, res) => {
  console.log(`***${APP}.GET.debug_submit***`);
  let command;

  if (!(req.body.refresh === undefined)) {
    console.log('debug_submit(): User wants to ignore the current command and wait for the next mesage from the car');
    res.redirect('/debugger');
    return;
  }

  if (!(req.body.next_sensor_message === undefined)) {
    console.log('debug_submit(): User wants to ask for a new sensor message');
    command = new DriveMessage();
    command.setModeDebug();
    command.sendSensorMessage();
    publishCommand(command);
    res.redirect('/debugger');
    return;
  }

  console.log('debug_submit(): User wants to send current command to the car');

  // Before we send the current message to the car, we need to make sure we add one action - that is to send sensor message after processing other actions
  if (nextDrivingCommand === undefined) {
    // If there were no instructions to begin with, then we will create an empty command
    command = new DriveMessage();
  } else {
    command = nextDrivingCommand;
  }
  // Reset nextDrivingCommand to zero so it is not shown in the UI, unless we process another message
  nextDrivingCommand = undefined;

  command.setModeDebug();
  // Tell the car to send sensor message after acting on other actions
  command.setOnDemandSensorRate();
  // command.sendSensorMessage();
  // Push this command to the car
  publishCommand(command);
  // Now we send user back to the human control page so he can repeat
  res.redirect('/debugger');
});

/************************************************************
  Turn ON DEBUG mode
 ************************************************************/
app.get('/debugger_on', (req, res) => {
  console.log(`***${APP}.GET.debugger_on***`);
  startListener();
  currentDrivingMode = DEBUG_MODE;
  let command = new DriveMessage();
  command.setModeDebug();
  command.setOnDemandSensorRate();
  publishCommand(command);
  res.status(200).redirect('/debugger');
});

// /************************************************************
//   Turn OFF DEBUG mode
// ************************************************************/
// app.get('/debugger_off', (req, res) => {
//   console.log(`***${APP}.GET.debugger_off*** - turning debug mode OFF`);
//   currentDrivingMode = MANUAL_MODE;
//   let command = new DriveMessage();
//   command.setContinuousSensorRate();
//   publishCommand(command);
//   res.status(200).redirect('/debugger');
// });

/************************************************************
  Turn ON Self Driving mode
 ************************************************************/
app.get('/self_driving_mode', (req, res) => {
  console.log(`***${APP}.GET.self_driving_mode***`);
  startListener();
  currentDrivingMode = AUTOMATIC_MODE;
  let command = new DriveMessage();
  command.setModeAutomatic();
  command.setOnDemandSensorRate();
  // We want to do all the driving with a closed gripper to prevent random balls from getting into the grip
  command.gripperClose();
  command.sendSensorMessage();
  publishCommand(command);
  res.status(200).send('<a href="/">Home</a><p>Self driving mode is turned ON.');
});

/************************************************************
  Reset all statistics
 ************************************************************/
app.get('/reset', (req, res) => {
  console.log(`***${APP}.GET.reset***`);
  reset();
  res.status(200).send('<a href="/">Home</a></p>Statistics reset complete.');
});

/************************************************************
  Turn ON Manual driving mode
 ************************************************************/
app.get('/manual_mode', (req, res) => {
  console.log(`***${APP}.GET.manual_mode***`);
  // stopListener();
  currentDrivingMode = MANUAL_MODE;
  let command = new DriveMessage();
  command.setModeManual();
  // command.setOnDemandSensorRate();
  command.sendSensorMessage();
  publishCommand(command);

  let formPage = manualDrivingForm(inboundMsgHistory);
  res.status(200).send(formPage);
});

/************************************************************
  Manual car control (as submitted from manual_control.html)
 ************************************************************/
app.post('/manual_control_action', (req, res) => {
  console.log(`***${APP}.GET.manual_control_action***`);
  publishCommand(manualCommand(req));
  // Now we send user back to the manual control page so he can repeat
  res.redirect('/manual_mode');
});

/************************************************************
  Start listener
 ************************************************************/
app.get('/start', (req, res) => {
  reset();
  startListener();
  console.log(`***${APP}.GET.start_listener***`);
  res.status(200).send('<a href="/">Home</a><p>Listener has been (re)started');
});

/************************************************************
  Stop listener
 ************************************************************/
app.get('/stop', (req, res) => {
  res.status(200).send('<a href="/">Home</a><p>Listener has been stopped');
});

/************************************************************
  Show stats HTML page
 ************************************************************/
app.get('/', (req, res) => {
  console.log(`***${APP}.GET.main_page***`);
  let html = "<h1>Robot Derby Driving Controller</h1>" +
    "<p>Current driving mode: <b>" + currentDrivingMode + "</b></p>" +
    "<p>Set driving mode to: <a href='/self_driving_mode'>Self driving</a> / <a href='/manual_mode'>Manual</a> / <a href='/debugger_on'>Debug</a></p>" +
    "<p>Car color (<a href='/change_color'>change it</a>): <b>" + ballColor + "</b></p>" +
    "<p>Message history: <a href='/inbound_history'>Inbound sensor data</a> / <a href='/outbound_history'>Outbound driving commands</a></p>" +
    "<p>Errors: <b>" + totalErrors + "</b></p>" +
    "<p>Messages received: <b>" + totalMessagesReceived + "</b></p>" +
    "<p>Messages sent: <b>" + totalMessagesSent + "</b></p>" +
    "<p>Rejected out of order or old messages: <b>" + rejectedOutOfOrderMessages + "</b></p>" +
    "<p>Rejected format messages: <b>" + rejectedFormatMessages + "</b></p>" +
    "<p>Most recent message: <b>" + new Date(maxMsgTimeStampMs).toUTCString() + "</b></p>" +
    "<p>Listener status <a href='/start'>Start</a>/<a href='/stop'>Stop</a>: <b>" + listenerStatus + "</b></p>" +
    "<p>Statistics: <a href='/reset'>Reset</a></p>" +
    "<p>Command topic: <b>" + process.env.COMMAND_TOPIC + "</b></p>" +
    "<p>Sensor subscription: <b>" + process.env.SENSOR_SUBSCRIPTION + "</b></p>";

  let imageUrl;
  if (inboundMsgHistory.length > 0) {
    let msg = inboundMsgHistory[inboundMsgHistory.length - 1];
    if ((!(msg.data === undefined)) && (!(JSON.parse(msg.data).sensors === undefined)) &&
      (!(JSON.parse(msg.data).sensors.frontCameraImagePath === undefined))) {
      imageUrl = JSON.parse(msg.data).sensors.frontCameraImagePath;
    }
  }

  // Add an image to the form
  if (!(imageUrl === undefined)) {
    html = html + '<img src="' + imageUrl + '" alt="picture of the ball" style="width:600px;"/>';
  }

  html = html + '<p style="color:LightGray"><small>Version 0.67<br>' + new Date().toUTCString() + '</small></p>';
  // html = html + '<p style="color:LightGray"><small>' + new Date().toUTCString() + '</small><br><img src="./images/google_cloud.png" alt="google cloud logo" style="width:400px;"></p>';

  // console.log(`***${APP}.GET*** - ${html}`);
  res.status(200).send(html);
});

/************************************************************
  Start server
 ************************************************************/
const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log("Listening on port " + PORT + ". Press Ctrl+C to quit.");
  startListener();
});

module.exports = app;

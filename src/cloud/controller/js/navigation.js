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
var Settings = require('./game-settings');
var Vision = require('./vision');
var DriveMessage = require('./drive-message').DriveMessage;
const SEEK_BALL_TURN = require('./drive-message').SEEK_BALL_TURN;
const CHECK_GRIP = require('./drive-message').CHECK_GRIP;
const GO2BASE = require('./drive-message').GO2BASE;
const SEEK_HOME_TURN = require('./drive-message').SEEK_HOME_TURN;

// Initialize simulation engine (it may be On or Off)
var DriveMessageSimulator = require('./simulation').DriveMessageSimulator;
let driveSimulation = new DriveMessageSimulator();
const TURN_SPEED = Settings.MAX_SPEED / 10;

// Highest allowed Y coordinate of the top of the ball in the picture - if it is above this, we will discard the image as false positive for low confidence result
// because balls should not fly in the air. Note that the coordinates of (0,0) are in the top left corner
const HIGH_BALL_TOP_BOUND = 0.2;
// If the inference confidence score is higher than this, we will still accept this as a real ball
const HIGH_BALL_SCORE = 0.5;

/************************************************************
	Navigation class has logic for generating drive commands based on data in a sensor
 ************************************************************/
module.exports = class Navigation {

	// Reference to the outbound command history (useful for navigation decisions)
	constructor(commandHistory) {
		this.commandHistory = commandHistory;
	}

	/************************************************************
		Create command message to the car based on the sensor data
		Input:
			- message from the sensor
		Output:
			- driving message command to be sent to the car
		Example input:
			{"carId":1,"cloudTimestampMs":1519671071945,"carState":{"ballsCollected":0,"color":"red","batteryLeft":99},"sensors":{"frontLaserDistanceMm":90,"frontCameraImagePath":"https://storage.googleapis.com/camera-2-robot-derby-ndg3njzh/image2018-05-27025001.151062.jpg","frontCameraImagePathGCS":"gs://robot-derby-camera-1/images/image0.jpg"}}
	 ************************************************************/
	nextMove(sensorMessage) {
		return Promise.resolve()
			.then(() => {
				console.log("nextMove(): Car has " + sensorMessage.carState.ballsCollected + " balls onboard.");

				if ((this.countGoals(GO2BASE) > 0) || (this.countGoals(SEEK_HOME_TURN) > 0)) {
					console.log("nextMove(): looking for the home base");
					return Promise.resolve()
						.then(() => {
							return this.navigate2home(sensorMessage);
						});
				} else if (sensorMessage.carState.ballsCollected < Settings.BALLS_NEEDED) {
					console.log("nextMove(): looking for the ball");
					return this.navigate2ball(sensorMessage);
				} else {
					console.log("nextMove(): All balls collected and brought home - I guess we are done then :-))).");
					return this.gameOver(sensorMessage);
				}
			});
	}

	/************************************************************
		Finding home base
		Input:
			- Sensor message
		Output:
			- driving command
	 ************************************************************/
	navigate2home(sensorMessage) {
		console.log(`navigate2home()...`);

		// Run image recognition on the image we got from the car sensors
		return (new Vision()).recognizeObjects(sensorMessage)
			.then((response) => {
				// Compose the object label as identified by Object Detection API (aka "red_home", etc.)
				// console.log("navigate2home(): Getting the objectLabel...");
				let objectLabel = sensorMessage.carState.color + Settings.HOME_LABEL_SUFFIX;

				// Find the base of this car
				// console.log("navigate2home(): Finding nearest object");
				let bBox = this.findNearestObject(objectLabel, response);

				let command;

        let obstacle_found = false;
        if (sensorMessage.carState.obstacleFound != undefined && sensorMessage.carState.obstacleFound) {
          obstacle_found = true;
        }

				if (bBox != undefined) {
					// We found the home base in the image and need to go towards it
					command = this.calculateHomeDirections(bBox, obstacle_found, response);
				} else {
					// The home base was not found in the image. Need a strategy to seek the base,
					// get it into the image frame and then navigate towards it
					console.log("navigate2home()... no object of proper type was found in the image.");
					command = this.homeSearchStrategy(response);
				}

				// console.log("navigate2home(): setting the correlation ID");
				command.setCorrelationID(sensorMessage.timestampMs);
				return Promise.resolve(command)
					.then((command) => {
						console.log("navigate2home(): done");
						command.sendSensorMessage();
						return command;
					});
			});
	}

	/************************************************************
		Finding next ball
		Input:
			- Sensor message
		Output:
			- driving command
	 ************************************************************/
	navigate2ball(sensorMessage) {
		console.log("navigate2ball()...");

		// Are we in a simulation mode?
		if (driveSimulation.simulate) {
			// If so, return fake series of commands
			return Promise.resolve()
				.then(() => {
					console.log("navigate2ball...using driveSimulation");
					return driveSimulation.nextDrivingCommand();
				});
		}

		// Run image recognition on the image we got from the car sensors
		return (new Vision()).recognizeObjects(sensorMessage)
			.then((response) => {
				// Compose the object label as identified by Object Detection API (aka "red_ball", etc.)
				// console.log("navigate2ball(): Getting the objectLabel...");
				let objectLabel = sensorMessage.carState.color + Settings.BALL_LABEL_SUFFIX;

				// Find the ball nearest to the car by using the label we composed above
				// Note that Vision API needs to be using proper image labels so we can find what we need
				// console.log("navigate2ball(): Finding nearest object");
				let bBox = this.findNearestObject(objectLabel, response);

				let command;

				let obstacle_found = false;
        if (sensorMessage.carState.obstacleFound != undefined && sensorMessage.carState.obstacleFound) {
        	obstacle_found = true;
        }

				if (bBox != undefined) {
					// We found the ball in the image and need to go towards it
					command = this.calculateBallDirections(bBox, obstacle_found, response);
				} else {
					// The ball was not found in the image. Need a strategy to seek the ball,
					// get it into the image frame and then navigate towards it
					console.log("navigate2ball()... no object of proper type was found in the image.");
					command = this.ballSearchStrategy(response);
				}

				// console.log("navigate2ball(): setting the correlation ID");
				command.setCorrelationID(sensorMessage.timestampMs);
				return Promise.resolve(command)
					.then((command) => {
						console.log("navigate2ball(): done");
						command.sendSensorMessage();
						return command;
					});
			});
	}

	/************************************************************
		End of game
		Input:
			- Sensor message
		Output:
			- driving command
	 ************************************************************/
	gameOver(sensorMessage) {
		console.log("***********************************************************************");
		console.log("**************************** gameOver() *******************************");
		console.log("***********************************************************************");
		let command = new DriveMessage();
		command.setCorrelationID(sensorMessage.timestampMs);
		command.setGoalGameEnd();
		command.sendSensorMessage();
		return command;
	}

	/************************************************************
		The required ball is not in the picture frame - need to
		formulate strategy to move the car to ball appears in the frame in the future
		Input:
			- list of object bounding boxes found by Object Detection
		Ouput:
			- Driving commands for car to execute in pusuit of search for the ball
	 ************************************************************/
	ballSearchStrategy(visionResponse) {
		console.log("ballSearchStrategy()... Object was not in the frame");
		let command = new DriveMessage();
		command.setModeAutomatic();

		// Since the needed ball was not in the frame, need to turn the car to be able to take a new picture
		if (this.countGoals(SEEK_BALL_TURN) < 5) {
			let angle = 67;
			console.log("ballSearchStrategy(): turning by " + angle + " degrees for the '" + this.countGoals(SEEK_BALL_TURN) + "'th time");
			// Try to put a ball in a picture frame
			command.setGoalSeekBallTurn();
			command.setSpeed(TURN_SPEED);
			command.makeTurn(angle);
		} else {
			// However if after several turns the ball was still not found, need to drive somewhere
			// to change car position and take new pictures from there
			// Try to put a ball in a picture frame
			command.setGoalSeekBallMove();
			let minDistanceMm = 100;
			let maxRandomDistanceMm = 600;
			let distance = minDistanceMm + Math.floor(Math.random() * maxRandomDistanceMm);
			if (Math.random() < 0.25) {
				// On random rare occasion drive backward
				distance = -distance;
			}

			console.log("ballSearchStrategy()... moving by random distance of " + distance);
			// Since we do not need high precision - can turn very quickly here
			command.setSpeed(TURN_SPEED);
			command.drive(distance);
		}

		return command;
	}

	/************************************************************
			The required home base is not in the picture frame - need to
			formulate strategy to find the home base
			Input:
				- list of object bounding boxes found by Object Detection
			Ouput:
				- Driving commands for car to execute in pusuit of search for the object
		 ************************************************************/
	homeSearchStrategy(visionResponse) {
		console.log("homeSearchStrategy(): Home base was not in the frame");
		let command = new DriveMessage();
		command.setModeAutomatic();

		// Since the needed home base was not in the frame, need to turn the car to be able to take a new picture
		let homeTurns = this.countGoals(SEEK_HOME_TURN);
		if (homeTurns < 5) {
			let angle = 60;
			console.log("homeSearchStrategy()... turning by " + angle + " degrees for the '" + homeTurns + "'th time");
			// Try to put a ball in a picture frame
			command.setGoalSeekHomeTurn();
			command.setSpeed(Settings.MAX_SPEED);
			command.makeTurn(angle);
		} else {
			// However if after several turns the home base was still not found, need to drive somewhere
			// to change car position and take new pictures from there
			command.setGoalGo2Base();
			let minDistanceMm = 200;
			let maxRandomDistanceMm = 700;
			let distance = minDistanceMm + Math.floor(Math.random() * maxRandomDistanceMm);

			console.log("homeSearchStrategy()... moving by random distance of " + distance);
			// Since we do not need high precision - can turn very quickly here
			command.setSpeed(Settings.MAX_SPEED);
			command.drive(distance);
		}

		return command;
	}

	/************************************************************
		Looks into the recent command history and returns the number of most recent
		sequential Ball Seeking turns without movement
		Input:
			- Goal to search for
		Ouput:
			- Number 0 to N - how many sequential turns
	 ************************************************************/
	countGoals(goal) {
		// Searching from the bottom of command history - aka most recent commands
		let i = this.commandHistory.length;
		let result = 0;

		while (i > 0 && this.commandHistory[i - 1].goal == goal) {
			i--;
			result++;
		}

		console.log("countGoals(): goal '" + goal + "' was found " + result + " times");
		return result;
	}
	/************************************************************
			Based on the list of object locations, find the object closest to observer.
			This assumes that all objects of this label are the same size
			Input:
				- object label
				- list of object bounding boxes found by Object Detection
			Ouput:
				- Bounding box for the nearest object (may be undefined if object not found)
		 ************************************************************/
	findNearestObject(objectType, visionResponse) {
		// TODO - need to take into account the confidence score of the inference to decide which ball to go after
		console.log("findNearestObject(): Looking for an object of type <" + objectType + ">");
		// At the start, no object of this type is found yet, hence the size is 0
		let foundSize = 0;
		let nearestObject = undefined;

		// Iterate over all of the bjects in the list and find and compare all of the needed type
		for (var i = visionResponse.bBoxes.length; i--;) {
			let obj = visionResponse.bBoxes[i];
			console.log("findNearestObject(): Considering object type <" + obj.label + ">");

			// TODO - this needs to be tested - false positive ball detection
			// For object type of "ball" its upper border should never be above certain heigh of the image with low confidence score
			if ((obj.label.toLocaleLowerCase().indexOf(Settings.BALL_LABEL_SUFFIX.toLocaleLowerCase()) >= 0) &
				(obj.score < HIGH_BALL_SCORE) & (obj.y < HIGH_BALL_TOP_BOUND)) {
				console.log("findNearestObject(): likely a false positive - confidence score of " + obj.score + "is below threshold of " + HIGH_BALL_SCORE + " with upper boundary of the ball being " + (obj.y + obj.h) + " above threshold of " + HIGH_BALL_TOP_BOUND);
				continue;
			}

			// Is this the right object type?
			if (obj.label.toLocaleLowerCase().indexOf(objectType.toLowerCase()) >= 0) {
				// Consider the largest size - vertical or horizontal (object may be covered partially) - and multiply this by the confidence score
				let thisSize = Math.max(obj.w, obj.h) * obj.score;
				// Is current object bigger and more likely than the one found earlier?
				if (foundSize < thisSize) {
					foundSize = thisSize;
					nearestObject = obj;
				}
			}
		}

		console.log("findNearestObject(): done: " + JSON.stringify(nearestObject));
		return nearestObject;
	}

	/************************************************************
		Calculates sequence of directions to the specified ball as defined by the bounding box
		Input:
			- bBox - bounding box with coordinates of the nearest ball
	 		- obstacleFound - did we detect an obstacle
		Ouput:
			- Initialized command object with sequence of actions/directions
	 ************************************************************/
	calculateBallDirections(bBox, obstacleFound, response) {
		console.log("calculateBallDirections(): start");
		let angle = this.findAngle(bBox);
		let distance = this.findDistanceMM(bBox, Settings.BALL_SIZE_MM);
		let command = new DriveMessage();
		command.setModeAutomatic();
		// At this distance or closer we need to be moving slow not to kick the ball out too far
		const slowApproachZoneMm = 250;
		// At this distance we can close gripper and have our ball
		// TODO - this works for the original camera
		// const ballCaptureDistanceMm = 35;
		const ballCaptureDistanceMm = 70;
		// We can grasp the ball within this angle spread to each side
		const ballCaptureAngle = 10;
		// This is how far the car will drive super slowly to make sure ball is really in the gripper
		const EXTRA_DISTANCE = 30;

		if (Math.abs(angle) <= ballCaptureAngle && distance <= ballCaptureDistanceMm) {
			// If we came here second time after gripping the ball, this means we really have it in the gripper and can now go to the base
			if (this.commandHistory[this.commandHistory.length - 1].goal == CHECK_GRIP) {
				command.setGoalGo2Base();
				return command;
			}
			// We are close enough and at the proper angle so that we can capture the ball (yay!)
			console.log("calculateBallDirections(): initiate ball capture protocol");
			// command.setGoalCaptureBall();
			command.gripperClose();
			// We set the goal to check grip so that we come into this second time we know what we wanted to do - see code above
			command.setGoalCheck4Grip();
			// Drive backwards so we can make sure next time we still have the ball in the grip
			command.setSpeed(Settings.MAX_SPEED / 2);
			command.drive(-slowApproachZoneMm);
			// It is more likely that the base is behind us - hence the turn
			// command.setSpeed(Settings.MAX_SPEED);
			// command.makeTurn(Math.floor(Math.random() * 90));
			return command;
		}

		/* This was the legacy method before obstacle detection

		console.log("calculateBallDirections(): ball is either too far or is not aligned by angle.");
		command.setGoalGo2Ball();
		// Since we do need high precision - need to turn slowly
		command.setSpeed(Settings.MAX_SPEED * 0.05);
		command.makeTurn(angle);
    */

		// First part of the distance go at max speed
		let speed = Settings.MAX_SPEED;

    if (distance < slowApproachZoneMm) {
      console.log("calculateBallDirections(): ball is close! Let's slow down the car and adjust angle on approach.");
      command.setGoalGo2Ball();
      command.makeTurn(angle);
      command.gripperOpen();
			// Last part of the journey we need to slow down as to not kick the ball away
			speed = Settings.MAX_SPEED * 0.05;
			// Always drive extre few cm to make sure we have the ball in the gripper
			distance = distance + EXTRA_DISTANCE;
		}
		else if (obstacleFound) {
      console.log("calculateBallDirections(): these aren't the droids you're looking for. navigating around the obstacle");
			return this.ballSearchStrategy(response);
    }
		else {
      console.log("calculateBallDirections(): ball is either too far or is not aligned by angle.");
      command.setGoalGo2Ball();
      command.makeTurn(angle);
      distance = distance - slowApproachZoneMm * 0.5;
		}

		command.setSpeed(speed);
		command.drive(distance);

		console.log("calculateBallDirections(): done");
		return command;
	}

	/************************************************************
			Calculates sequence of directions to the specified ball as defined by the bounding box
			Input:
				- bBox - bounding box with coordinates of the nearest ball
			Ouput:
				- Initialized command object with sequence of actions/directions
		 ************************************************************/
	calculateHomeDirections(bBox, obstacleFound, response) {
		console.log("calculateHomeDirections(): start...");
		let angle = this.findAngle(bBox);
		let distance = this.findDistanceMM(bBox, Settings.HOME_SIZE_MM);
		let command = new DriveMessage();
		command.setModeAutomatic();
		// How far from the home base sign can we release the ball
		const BALL_RELEASE_DISTANCE = 850;
		// How far the car will drive to make sure it is really at the home base
		const EXTRA_DISTANCE = 100;

		if (distance < BALL_RELEASE_DISTANCE) {
			console.log("calculateHomeDirections(): We are close enough to the home base - release the ball");
			command.addBallCount();
			command.gripperOpen();
			command.setSpeed(Settings.MAX_SPEED / 10);
			command.drive(-100);
			command.setSpeed(Settings.MAX_SPEED);
			command.drive(-1000);
			command.setSpeed(TURN_SPEED);
			command.turnRight(90);
			// After we release the ball and go back for more, we want to do all the driving with a closed gripper to prevent random balls from getting into the grip
			command.gripperClose();
			command.setGoalGo2Ball();
			return command;
		}

		if (obstacleFound) {
      console.log("calculateHomeDirections(): there is an object in our way. navigating around the obstacle");
      return this.homeSearchStrategy(response);
    }

		// We are close enough and at the proper angle so that we can capture the ball (yay!)
		console.log("calculateHomeDirections(): moving towards the home base");
		command.setGoalGo2Base();
		command.setSpeed(TURN_SPEED);
		command.makeTurn(angle);
		command.setSpeed(Settings.MAX_SPEED);
		command.drive(distance - BALL_RELEASE_DISTANCE + EXTRA_DISTANCE);
		return command;
	}

	/************************************************************
		Calculate the angle of the object off center of the image
		Input:
			- Coordinates of the object
			- Image metadata with info about the dimensions of the image
		Ouput:
			- Angle where the object is located - positive means turn right, negative is turn left
	 ************************************************************/
	findAngle(bBox) {
		const ANGLE_CALIBRATION_MULTIPLIER = 0.75;

		// Find horizontal center of the object
		let centerX = parseFloat(bBox.x) + (parseFloat(bBox.w) / 2);
		// console.log("findAngle(): centerX=" + centerX);

		// Find offset of the center of the object relative to the middle of the image
		// Negative offset means to the left, positive to the right

		// ------- This is if using pixels
		// Calculate angle of the object center relative to the image center
		// let offsetPixels = centerX - Settings.camera.HORIZONTAL_RESOLUTION_PIXELS / 2;
		// let angle = (Settings.camera.H_FIELD_OF_VIEW / 2) *
		//   (offsetPixels / (Settings.camera.HORIZONTAL_RESOLUTION_PIXELS / 2));


		// -------- This is using relative coordinates
		// console.log("findAngle(): Settings.camera.H_FIELD_OF_VIEW=" + parseFloat(Settings.camera.H_FIELD_OF_VIEW));
		let angle = (centerX - 0.5) * parseFloat(Settings.camera.H_FIELD_OF_VIEW) * ANGLE_CALIBRATION_MULTIPLIER;

		console.log("findAngle(): " + angle.toFixed(0));
		return Math.round(angle);
	}

	/************************************************************
		Calculate the distance to the object
		Input:
			- bounding box with the dimensions of the image
			- Vertical Object size
		Ouput:
			- Distance to the object in mm
	 ************************************************************/
	findDistanceMM(bBox, realObjectVerticalSizeMm) {
		// Calibration constant - this is used to adjust and calibrate distance calculation based on specifics of camera, ball, etc.
		const CALIBRATION_MULTIPLIER = 1;
		const CALIBRATION_ADDON_MM = 0;

		// Since we are navigating to round balls - use the largest dimension (ball can be only partially visible)
		let relative_object_size = Math.max(bBox.h, bBox.w);

		// This uses relative coordinates - 0 to 1 relative to the overall image size
		let distanceMM = (Settings.camera.FOCAL_LENGTH_MM * realObjectVerticalSizeMm / (relative_object_size *
			Settings.camera.SENSOR_HEIGHT_MM)) - Settings.MIN_DISTANCE_TO_CAMERA_MM;

		console.log("findDistance(): Calculated: " + distanceMM.toFixed(0) + " mm");
		// This part below really should have been done by non-linear regression, but as a hack do it manually for now
		if (distanceMM < 95) {
			distanceMM = 20;
		} else if (distanceMM < 325) {
			distanceMM = distanceMM - 35;
		}

		console.log("findDistance(): Corrected: " + distanceMM.toFixed(0) + " mm");
		return Math.round(distanceMM);
	}
};

#!/usr/bin/env python

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

import easygopigo3
import time

class RobotDerbyCar(easygopigo3.EasyGoPiGo3):
    """
    This class is used for controlling a `RobotDerbyCar`_ robot.
    With this class you can do the following things with your `RobotDerbyCar`_:
     * Drive your robot while avoiding obstacles
     * Inheriting all EasyGoPiGo3 functionality: https://github.com/DexterInd/GoPiGo3/blob/master/Software/Python/easygopigo3.py
     * Inheriting all GoPiGo3 functionality: https://github.com/DexterInd/GoPiGo3/blob/master/Software/Python/gopigo3.py
     * Set the grippers of the robot to Open or Close positions
    """

    def __init__(self):
        """
        This constructor sets the variables to the following values:
        :var int CONST_GRIPPER_FULL_OPEN = 90: Position of gripper servo when open
        :var int CONST_GRIPPER_FULL_CLOSE = 20: Position of gripper servo when closed
        :var int CONST_GRIPPER_FULL_OPEN = 40: Position of gripper servo to grab ball
        :var easygopigo3.EasyGoPiGo3 Easy_GPG: Initialization of EasyGoPiGo3
        :var easygopigo3 Easy_GPG: Initialization of EasyGoPiGo3
        :var easygopigo3.Servo gpgGripper: Initialization of Gripper Servo on Servo Pin 1
        :var init_distance_sensor my_distance_sensor: Initialization of Distance Sensor
        :raises IOError: When the GoPiGo3 is not detected. It also debugs a message in the terminal.
        :raises gopigo3.FirmwareVersionError: If the GoPiGo3 firmware needs to be updated. It also debugs a message in the terminal.
        :raises Exception: For any other kind of exceptions.
        """

        # super(RobotDerbyCar, self).__init__(self)

        self.Easy_GPG = easygopigo3.EasyGoPiGo3()  # Create an instance of the GoPiGo3 class. GPG will be the GoPiGo3 object.
        self.gpgGripper = easygopigo3.Servo("SERVO1", self.Easy_GPG)
        # TODO - these settings for cars in US REston Office
        # self.CONST_GRIPPER_FULL_OPEN = 90
        # self.CONST_GRIPPER_FULL_CLOSE = 0
        # self.CONST_GRIPPER_GRAB_POSITION = 20
        
        # TODO - these settings for cars in London Office
        self.CONST_GRIPPER_FULL_OPEN = 180
        self.CONST_GRIPPER_FULL_CLOSE = 20
        self.CONST_GRIPPER_GRAB_POSITION = 120
        self.gpgGripper = easygopigo3.Servo("SERVO1", self.Easy_GPG)
        self.my_distance_sensor = self.Easy_GPG.init_distance_sensor()
        self.SetLEDsGreen()

    def SetLEDsYellow(self):
        self.Easy_GPG.set_left_eye_color((255,255,0))
        self.Easy_GPG.set_right_eye_color((255,255,0))
        self.Easy_GPG.open_left_eye()
        self.Easy_GPG.open_right_eye()

    def SetLEDsGreen(self):
        self.Easy_GPG.set_left_eye_color((1,255,1))
        self.Easy_GPG.set_right_eye_color((1,255,1))
        self.Easy_GPG.open_left_eye()
        self.Easy_GPG.open_right_eye()

    def SetLEDsRed(self):
        self.Easy_GPG.set_left_eye_color((255,1,1))
        self.Easy_GPG.set_right_eye_color((255,1,1))
        self.Easy_GPG.open_left_eye()
        self.Easy_GPG.open_right_eye()

    def GripperClose(self):
        self.SetLEDsRed()
        self.gpgGripper.rotate_servo(self.CONST_GRIPPER_GRAB_POSITION)
        self.SetLEDsGreen()

    def GripperOpen(self):
        self.SetLEDsRed()
        self.gpgGripper.rotate_servo(self.CONST_GRIPPER_FULL_OPEN)
        self.SetLEDsGreen()

    def ReadDistanceMM(self):
        return self.my_distance_sensor.read_mm()

    def ReadBatteryVoltage(self):
        return self.Easy_GPG.get_voltage_battery()

    def set_speed(self,speed):
        self.SetLEDsRed()
        self.Easy_GPG.set_speed(speed)
        self.SetLEDsGreen()

    def drive_cm(self,distance):
        self.SetLEDsRed()
        self.Easy_GPG.drive_cm(distance,True)
        self.SetLEDsGreen()

    def turn_degrees(self,degress):
        self.SetLEDsRed()
        self.Easy_GPG.turn_degrees(degress,True)
        self.SetLEDsGreen()

    def drive(self,dist_requested,dist_limit):
        """
        Move the `GoPiGo3`_ forward / backward for ``dist`` amount of miliimeters.
        | For moving the `GoPiGo3`_ robot forward, the ``dist`` parameter has to be *positive*.
        | For moving the `GoPiGo3`_ robot backward, the ``dist`` parameter has to be *negative*.
        """

        # Have we found any obstacles in the path
        ObstaclesFound = False

        # the number of degrees each wheel needs to turn
        WheelTurnDegrees = ((dist_requested / self.Easy_GPG.WHEEL_CIRCUMFERENCE) * 360)

        # get the starting position of each motor
        CurrentPositionLeft = self.Easy_GPG.get_motor_encoder(self.Easy_GPG.MOTOR_LEFT)
        CurrentPositionRight = self.Easy_GPG.get_motor_encoder(self.Easy_GPG.MOTOR_RIGHT)

        # determine the end position of each motor
        EndPositionLeft = CurrentPositionLeft + WheelTurnDegrees
        EndPositionRight = CurrentPositionRight + WheelTurnDegrees

        self.SetLEDsRed()
        self.Easy_GPG.set_motor_position(self.Easy_GPG.MOTOR_LEFT, EndPositionLeft)
        self.Easy_GPG.set_motor_position(self.Easy_GPG.MOTOR_RIGHT, EndPositionRight)

        while self.Easy_GPG.target_reached(EndPositionLeft, EndPositionRight) is False:
            # read the distance of the laser sensor
            dist_read = self.ReadDistanceMM()

            # stop car if there is an object within the limit
            if ((dist_read is not None) and (int(dist_read) <= int(dist_limit)) and (int(dist_requested) > int(dist_limit))):
                print("RobotDerbyCar.drive(): Obstacle Found. Stopping Car before requested distance. Object distance: " + str(dist_read))
                ObstaclesFound = True
                CurrentPositionLeft = self.Easy_GPG.get_motor_encoder(self.Easy_GPG.MOTOR_LEFT)
                CurrentPositionRight = self.Easy_GPG.get_motor_encoder(self.Easy_GPG.MOTOR_RIGHT)
                self.Easy_GPG.set_motor_position(self.Easy_GPG.MOTOR_LEFT, CurrentPositionLeft)
                self.Easy_GPG.set_motor_position(self.Easy_GPG.MOTOR_RIGHT, CurrentPositionRight)
                break

            time.sleep(0.05)

        self.SetLEDsGreen()
        return ObstaclesFound
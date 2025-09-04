# 🧪 Control Application for a Didactic Level Test Bench (Final Project)
## 📄 About the Project
This repository contains the source code for the mobile application and embedded firmware developed as part of a Final Course Project for the Faculty of Mechanical Engineering (FEMEC) at the Federal University of Uberlândia (UFU).

The main objective of this project is to enable remote and local control of a didactic water level control test bench, applying the theory of State-Space Feedback Control. The complete solution consists of a Flutter application for the user interface and firmware for the ESP32 microcontroller that manages the test bench.

## 🏛️ System Architecture
The system was designed with a flexible architecture that allows for two distinct operating modes, using different communication technologies:

Frontend (Mobile): A cross-platform application developed in Flutter, with adaptable themes (light/dark) and distinct user flows for Professor and Student profiles.

Hardware (Test Bench): An ESP32 microcontroller is the brain of the test bench, responsible for reading sensors, activating the water pump, controlling visual feedback with LEDs, and managing all communication.

Local Communication (Setup): The initial configuration of the test bench (Wi-Fi and MQTT server credentials) is securely done by the professor via Bluetooth Low Energy (BLE).

Remote Communication (Experiment): During the experiment, real-time data exchange between the student's application and the test bench is carried out via the MQTT protocol, allowing for remote control and monitoring.

## ✨ Features
### For the Professor:
Secure Configuration: Connects to the test bench via BLE to privately send Wi-Fi network and MQTT broker credentials.

Real-Time Monitoring: Accesses a monitoring screen that dynamically subscribes to the active student's topics.

Complete Overview: Views both the control parameters sent by the student and the telemetry data (level, voltage, etc.) published by the test bench.

### For the Student:
Remote Connection: Connects to the test bench remotely by providing only the MQTT broker address.

Parameter Submission: Enters the calculated gains (K, Ke, Nx, Nu) and the reference (ref) for the control law.

Experiment Control: Has commands to start, pause, and stop the experiment execution.

Graphical Visualization: Monitors the system's performance through a real-time chart that plots the water level and the control action (pump voltage).

Data Export: At the end of the experiment, can save all collected data (time, level, voltage) to a .txt file for later analysis.

## 🚀 How to Use
### Flow 1: Professor Configures the Test Bench
Log in as a Professor.

Navigate to the "Test Bench Configuration" screen.

The application will connect to the test bench via Bluetooth (BLE).

Send the Wi-Fi network credentials.

Send the MQTT Broker credentials.

The test bench will be online and ready to receive a student connection.

### Flow 2: Student Runs the Experiment
Log in as a Student.

Navigate to the "Configure Connections" screen.

Enter the MQTT Broker's IP address and connect. The app will register with the test bench.

Navigate to the "Control Parameters" screen.

Enter the calculated values for the gains and the desired reference.

Click "Send Parameters" to load the configuration onto the test bench.

The experiment screen will be displayed. Use the buttons to start, pause, and stop the control.

After stopping the experiment, the "Print Results" button will be enabled to save the data.

## 🔢 Control Parameters (Example Values)
The following gains were calculated and tested for the test bench model, serving as a starting point for the experiments:

Parameter

Description

Suggested Value

K

State Regulator Gain

50.4975

Ke

State Observer Gain

9.9948

Nx

State Scaling Factor

1.0

Nu

Input Scaling Factor

0.264

## 🛠️ Technologies Used
### Hardware:

ESP32 Microcontroller

HC-SR04 Ultrasonic Sensor

L298N H-Bridge Motor Driver

12V Submersible Water Pump

12V LED Strip for status feedback

### Software and Protocols:

Flutter (Dart)

C++ (Arduino Framework with FreeRTOS)

MQTT Protocol

Bluetooth Low Energy (BLE)
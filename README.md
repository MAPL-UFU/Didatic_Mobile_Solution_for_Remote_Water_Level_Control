# IoT-Based State-Space Water Level Controller

This project is a complete Internet of Things (IoT) system designed to remotely monitor and control the water level in a physical tank. It was developed as a practical application for the "Special Topics in Mechatronics II - IoT" course at the Federal University of Uberlândia, demonstrating the integration of embedded hardware, a mobile frontend, and cloud communication to implement a state-space controller.

The system is designed to operate on a water tank test bench used in Linear Control studies at the Mechatronics Teaching Laboratory (LEM3).

## System Architecture

The project is decoupled into layers, communicating via an MQTT broker, which ensures scalability and modularity.

1.  **Mobile Application (Client):** A cross-platform application built with Flutter/Dart allows the user to configure, operate, and monitor the experiment from anywhere.
2.  **MQTT Broker:** An MQTT broker (like Eclipse Mosquitto) orchestrates the communication between the mobile app and the embedded hardware, relaying commands and data through specific topics.
3.  **Embedded Hardware (Firmware):**
    * An **ESP32** microcontroller serves as the single point of control. It connects to Wi-Fi, subscribes to MQTT topics, directly interfaces with the pump and sensors, executes the control law, and performs data acquisition.

## Key Features

* **Remote Broker Connection:** Securely connect to any MQTT broker by providing an IP address, port, and user credentials.
* **Dynamic Control Parameter Configuration:** Remotely set and publish state-space controller parameters, including the observer gain (`Ke`), regulator gain (`K`), and state-space model scaling factors (`Nx`, `Nu`).
* **Real-Time Monitoring:** View a live data stream from the experiment, including time, water level (cm), control voltage (V), and the estimated state, displayed in a data table.
* **Set-Point Control:** Publish a new reference (set-point) for the water level at any time during the experiment.
* **Emergency Stop:** Immediately terminate the experiment and deactivate the pump from the app.

## Technology Stack

### **Software & Communication**
* **Mobile App:** Flutter & Dart
* **Communication Protocol:** MQTT
* **Embedded Firmware:** C/C++ (Arduino Framework) 

### **Hardware**
* **Primary Controller:** ESP32-WROOM-32 
* **Physical Plant:** Water tank system with a 12V DC pump and an ultrasonic level sensor.

## How It Works

1.  The **Flutter Application** provides the user interface. The user enters the MQTT broker details, controller parameters, and desired water level reference. These are published to specific topics on the MQTT broker.
2.  The **ESP32**, connected to the same broker, listens to these topics. It directly runs the main control loop by reading the current water level from the ultrasonic sensor, calculating the control signal `u(t)` using the state-space control law ($u(t) = -Kx(t) + N_ur_{ss}$), and applying the corresponding voltage to the water pump.
3.  The **ESP32** constantly publishes its real-time data (level, estimated state, control signal) to the MQTT broker for the mobile app to display.

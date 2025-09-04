import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class AppGlobals {
  static PageController pageController = PageController();

  static final ValueNotifier<int> currentPageIndex = ValueNotifier<int>(0);

  static MqttServerClient? mqttClient;

  static String? nomeUsuario;
  static String? tipoUsuario;
  static String? numeroMatricula;
  static String? ipBrokerMQTT;

  static String statusBluetooth = "Desconectado";
  static String statusBroker = "Offline";
  static String statusExperimento = "Nenhum";

  static bool isBleConnected = false;
  static bool isMqttConnected = false;
  static String connectedWifiNetwork = "Nenhuma";

  static final ValueNotifier<bool> isLoggedIn = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> connectionStatusNotifier =
      ValueNotifier<bool>(false);

  static double? refValue;
  static double? kValue;
  static double? keValue;
  static double? nuValue;
  static double? nxValue;

  static void clearUser() {
    mqttClient?.disconnect();
    mqttClient = null;

    nomeUsuario = null;
    tipoUsuario = null;
    numeroMatricula = null;
    statusBluetooth = "Desconectado";
    statusBroker = "Offline";
    statusExperimento = "Nenhum";
    isBleConnected = false;
    isMqttConnected = false;
    connectedWifiNetwork = "Nenhuma";

    refValue = null;
    kValue = null;
    keValue = null;
    nuValue = null;
    nxValue = null;

    isLoggedIn.value = false;
    connectionStatusNotifier.value = !connectionStatusNotifier.value;
    pageController.jumpToPage(0);
  }
}

class BleConstants {
  static const String BLE_AUTH_KEY = "LAB_CONTROLE_UFU_2025";
  static final Guid ESP_SERVICE_UUID = Guid(
    "4fafc201-1fb5-459e-8fcc-c5c9c331914b",
  );
  static final Guid APP_TO_ESP_CHARACTERISTIC_UUID = Guid(
    "beb5483e-36e1-4688-b7f5-ea07361b26a8",
  );
  static final Guid ESP_TO_APP_CHARACTERISTIC_UUID = Guid(
    "cba1d466-344c-4be3-ab3f-189f80dd7518",
  );
  static const String MQTT_ID_TOPIC = "entradaid";
  static const String MQTT_HEARTBEAT_TOPIC = "bancada/heartbeat";
}

class WifiNetwork {
  final String ssid;
  final int rssi;
  WifiNetwork({required this.ssid, required this.rssi});
  factory WifiNetwork.fromJson(Map<String, dynamic> json) {
    return WifiNetwork(ssid: json['ssid'] ?? '', rssi: json['rssi'] ?? -100);
  }
}

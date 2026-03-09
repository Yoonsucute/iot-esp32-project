// Web implementation
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

MqttClient createMqttClient(String broker, String clientId) {
  final wsUrl = 'wss://$broker:8084/mqtt';
  final client = MqttBrowserClient(wsUrl, clientId);
  client.port = 8084;
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  return client;
}

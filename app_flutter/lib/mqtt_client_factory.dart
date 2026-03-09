// Factory để tạo MQTT client phù hợp với platform
import 'package:mqtt_client/mqtt_client.dart';

// Stub - sẽ được override bởi platform-specific implementation
MqttClient createMqttClient(String broker, String clientId) {
  throw UnsupportedError('Platform not supported');
}

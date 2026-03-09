import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import 'package:mqtt_client/mqtt_client.dart';

import 'supabase_service.dart';

// Conditional import - tự động chọn implementation phù hợp
import 'mqtt_client_factory.dart'
    if (dart.library.html) 'mqtt_client_factory_web.dart'
    if (dart.library.io) 'mqtt_client_factory_mobile.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SupabaseService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const IotControllerPage(),
    );
  }
}

class IotControllerPage extends StatefulWidget {
  const IotControllerPage({super.key});
  @override
  State<IotControllerPage> createState() => _IotControllerPageState();
}

class _IotControllerPageState extends State<IotControllerPage> {
  // ==================== TELEGRAM ====================
  static const String tgBotToken = "8536114256:AAFfol7xK5Axru4l8e_Vat8Hy-uQa3h2U40";
  static const String tgChatId = "5112384733";

  static const Duration tgCooldown = Duration(seconds: 20);
  DateTime? _lastTgSentAt;
  String _lastTgKey = "";
  
  final Dio _dio = Dio();

  bool _tgConfigured() =>
      !tgBotToken.contains("PUT_") && !tgChatId.contains("PUT_");

  String _fmtTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return "${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}  ${two(dt.day)}/${two(dt.month)}/${dt.year}";
  }

  Future<void> sendTelegram({
    required String key,
    required String htmlText,
  }) async {
    if (!_tgConfigured()) {
      debugPrint("⚠️ Telegram chưa set BOT_TOKEN / CHAT_ID");
      return;
    }

    final now = DateTime.now();
    final withinCooldown =
        _lastTgSentAt != null && now.difference(_lastTgSentAt!) < tgCooldown;

    if (_lastTgKey == key && withinCooldown) {
      debugPrint("⏳ Telegram cooldown - skip ($key)");
      return;
    }

    try {
      final res = await _dio.post(
        'https://api.telegram.org/bot$tgBotToken/sendMessage',
        data: {
          'chat_id': tgChatId,
          'text': htmlText,
          'parse_mode': 'HTML',
          'disable_web_page_preview': true,
        },
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      debugPrint("📨 Telegram status=${res.statusCode} body=${res.data}");

      if (res.statusCode == 200) {
        _lastTgSentAt = now;
        _lastTgKey = key;
        debugPrint("✅ Telegram sent ($key)");
      }
    } catch (e) {
      debugPrint("❌ Telegram error: $e");
    }
  }

  // ==================== MQTT ====================
  MqttClient? client;
  bool connected = false;
  bool _connecting = false;
  StreamSubscription? _sub;

  final broker = 'broker.emqx.io';

  // ✅ ĐÚNG với ESP32 bạn gửi
  final topicCmd = 'esp32/light/cmd';
  final topicDht = 'esp32/dht22/data';
  final topicMq = 'esp32/mqsensor/data';
  final topicState = 'esp32/device/state'; // optional (ESP32 có thì dùng)

  // Devices
  bool lightOn = false;
  bool fanOn = false;

  // DHT UI
  String temp = '--';
  String hum = '--';

  // GAS UI
  String mqAo = '--';
  String mqTh = '--';
  String gasText = '--';
  bool _gasAlarmLatched = false;

  // Schedule (đèn)
  TimeOfDay? lightOnTime;
  TimeOfDay? lightOffTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    connectToMqtt();
    _startTimerCheck();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    client?.disconnect();
    super.dispose();
  }

  Future<void> connectToMqtt() async {
    if (_connecting) return;
    _connecting = true;

    final clientId = 'flutter_${DateTime.now().millisecondsSinceEpoch}';

    try {
      _sub?.cancel();
      client?.disconnect();

      // ✅ Tự động chọn client phù hợp: Web = WebSocket, Mobile = TCP
      client = createMqttClient(broker, clientId);

      client!
        ..keepAlivePeriod = 30
        ..setProtocolV311()
        ..logging(on: false);

      client!.onConnected = () {
        debugPrint("✅ MQTT connected");
        _setConnected(true);
      };

      client!.onDisconnected = () {
        debugPrint("❌ MQTT disconnected");
        _setConnected(false);
        _retryConnect();
      };

      client!.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atMostOnce);

      await client!.connect();
    } catch (e) {
      debugPrint('❌ MQTT connection failed: $e');
      client?.disconnect();
      _setConnected(false);
      _connecting = false;
      _retryConnect();
      return;
    }

    if (client!.connectionStatus?.state == MqttConnectionState.connected) {
      _setConnected(true);

      client!.subscribe(topicDht, MqttQos.atMostOnce);
      client!.subscribe(topicMq, MqttQos.atMostOnce);
      client!.subscribe(topicState, MqttQos.atMostOnce);

      _listenMessages();
    } else {
      client?.disconnect();
      _setConnected(false);
      _retryConnect();
    }

    _connecting = false;
  }

  void _retryConnect() {
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (connected) return;
      connectToMqtt();
    });
  }

  void _setConnected(bool v) {
    if (!mounted) return;
    setState(() => connected = v);
  }

  Map<String, dynamic> _safeDecode(String s) {
    try {
      final d = jsonDecode(s);
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }

  void _listenMessages() {
    _sub?.cancel();

    _sub = client!.updates?.listen((events) async {
      if (events == null || events.isEmpty) return;

      final rec = events.first;
      final msg = rec.payload;
      if (msg is! MqttPublishMessage) return;

      final topic = rec.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(msg.payload.message);

      debugPrint("📩 [$topic] $payload");

      final data = _safeDecode(payload);

      // ✅ DHT: ESP32 bạn đang gửi {temp, hum} (mình support thêm temp_c/hum_pct luôn)
      if (topic == topicDht) {
        final t = data['temp'] ?? data['temp_c'];
        final h = data['hum'] ?? data['hum_pct'];

        setState(() {
          temp = (t is num) ? "${t.toStringAsFixed(1)} °C" : "--";
          hum = (h is num) ? "${h.toStringAsFixed(0)} %" : "--";
        });

        // Lưu dữ liệu DHT lên Supabase
        if (t is num && h is num) {
          try {
            await SupabaseService.saveDhtData(
              temperature: t.toDouble(),
              humidity: h.toDouble(),
            );
          } catch (e) {
            debugPrint('❌ Lỗi lưu DHT lên Supabase: $e');
          }
        }
      }

      // ✅ MQ: ESP32 bạn đang gửi {mq_ao, threshold, gas_alarm}
      if (topic == topicMq) {
        final ao = (data['mq_ao'] is num) ? (data['mq_ao'] as num).toInt() : null;
        final th = (data['threshold'] is num) ? (data['threshold'] as num).toInt() : null;

        // ưu tiên gas_alarm bool, fallback gas string
        final bool gasAlarmBool = data['gas_alarm'] == true;
        final gasStr = (data['gas'] ?? '').toString().toUpperCase().trim();
        final bool gasAlarmStr = gasStr.isNotEmpty && gasStr != "NORMAL";

        final isAlarm = gasAlarmBool || gasAlarmStr;

        setState(() {
          mqAo = ao?.toString() ?? "--";
          mqTh = th?.toString() ?? "--";
          gasText = isAlarm ? "ALARM" : "NORMAL";
        });

        // Lưu dữ liệu gas lên Supabase
        if (ao != null && th != null) {
          try {
            await SupabaseService.saveGasData(
              mqAo: ao,
              threshold: th,
              gasAlarm: isAlarm,
            );
          } catch (e) {
            debugPrint('❌ Lỗi lưu gas lên Supabase: $e');
          }
        }

        // ✅ Telegram gas alert (NORMAL -> ALARM gửi 1 lần)
        if (isAlarm && !_gasAlarmLatched) {
          _gasAlarmLatched = true;

          final now = DateTime.now();
          await sendTelegram(
            key: "gas_alarm",
            htmlText: """
<b>🚨 CẢNH BÁO KHÍ GAS</b>
<i>Phát hiện vượt ngưỡng</i>

<b>• MQ(AO):</b> <code>$mqAo</code>
<b>• Ngưỡng:</b> <code>$mqTh</code>
<b>• Trạng thái:</b> <b>ALARM</b>

<b>🕒 Thời gian:</b> ${_fmtTime(now)}
<b>📍 Thiết bị:</b> ESP32 SmartHome
""",
          );
        } else if (!isAlarm && _gasAlarmLatched) {
          _gasAlarmLatched = false;
        }
      }

      // Optional sync state (nếu ESP32 publish)
      if (topic == topicState) {
        bool parseOn(dynamic v) =>
            v == true || v == 1 || v == "1" || v == "on" || v == "ON";

        final newLight =
            data.containsKey("light") ? parseOn(data["light"]) : lightOn;
        final newFan = data.containsKey("fan") ? parseOn(data["fan"]) : fanOn;

        // ✅ Chỉ cập nhật nếu có thay đổi (tránh loop)
        if (mounted && (newLight != lightOn || newFan != fanOn)) {
          setState(() {
            lightOn = newLight;
            fanOn = newFan;
          });
          debugPrint('🔄 Đồng bộ từ MQTT: Đèn=${lightOn ? "BẬT" : "TẮT"}, Quạt=${fanOn ? "BẬT" : "TẮT"}');
        }
      }
    });
  }

  Future<bool> _sendCmd(Map<String, dynamic> cmd) async {
    if (!connected || client == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ MQTT chưa kết nối")),
        );
      }
      return false;
    }

    final msg = jsonEncode(cmd);
    try {
      final b = MqttClientPayloadBuilder()..addString(msg);
      client!.publishMessage(topicCmd, MqttQos.atMostOnce, b.payload!);
      debugPrint("📤 CMD: $msg");
      return true;
    } catch (e) {
      debugPrint("❌ Publish error: $e");
      return false;
    }
  }

  Future<void> _toggleLight(bool v) async {
    final prev = lightOn;
    setState(() => lightOn = v);

    final ok = await _sendCmd({"light": v ? "on" : "off"});
    if (!ok) {
      setState(() => lightOn = prev);
      return;
    }

    // ✅ Publish trạng thái lên MQTT để đồng bộ với các client khác
    _publishDeviceState('light', v);

    // Lưu trạng thái đèn lên Supabase
    try {
      await SupabaseService.saveDeviceState(
        deviceName: 'light',
        state: v,
      );
    } catch (e) {
      debugPrint('❌ Lỗi lưu đèn lên Supabase: $e');
    }

    final now = DateTime.now();
    await sendTelegram(
      key: v ? "light_on" : "light_off",
      htmlText: """
<b>💡 THIẾT BỊ: ĐÈN</b>
<b>• Trạng thái:</b> <b>${v ? "BẬT" : "TẮT"}</b>
<b>🕒 Thời gian:</b> ${_fmtTime(now)}
<b>📍 Thiết bị:</b> ESP32 SmartHome
""",
    );
  }

  Future<void> _toggleFan(bool v) async {
    final prev = fanOn;
    setState(() => fanOn = v);

    final ok = await _sendCmd({"fan": v ? "on" : "off"});
    if (!ok) {
      setState(() => fanOn = prev);
      return;
    }

    // ✅ Publish trạng thái lên MQTT để đồng bộ với các client khác
    _publishDeviceState('fan', v);

    // Lưu trạng thái quạt lên Supabase
    try {
      await SupabaseService.saveDeviceState(
        deviceName: 'fan',
        state: v,
      );
    } catch (e) {
      debugPrint('❌ Lỗi lưu quạt lên Supabase: $e');
    }

    final now = DateTime.now();
    await sendTelegram(
      key: v ? "fan_on" : "fan_off",
      htmlText: """
<b>🌀 THIẾT BỊ: QUẠT</b>
<b>• Trạng thái:</b> <b>${v ? "BẬT" : "TẮT"}</b>
<b>🕒 Thời gian:</b> ${_fmtTime(now)}
<b>📍 Thiết bị:</b> ESP32 SmartHome
""",
    );
  }

  // ✅ Publish trạng thái thiết bị lên MQTT để đồng bộ realtime
  void _publishDeviceState(String device, bool state) {
    if (!connected || client == null) return;

    try {
      final msg = jsonEncode({
        device: state,
        'source': 'flutter_app', // Đánh dấu từ app/web
      });
      final b = MqttClientPayloadBuilder()..addString(msg);
      client!.publishMessage(topicState, MqttQos.atMostOnce, b.payload!);
      debugPrint("📤 Published state: $msg");
    } catch (e) {
      debugPrint("❌ Publish state error: $e");
    }
  }

  void _startTimerCheck() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final now = TimeOfDay.now();

      if (lightOnTime != null &&
          now.hour == lightOnTime!.hour &&
          now.minute == lightOnTime!.minute) {
        _toggleLight(true);
      }

      if (lightOffTime != null &&
          now.hour == lightOffTime!.hour &&
          now.minute == lightOffTime!.minute) {
        _toggleLight(false);
      }
    });
  }

  Future<void> _pickTime(bool isOn) async {
    final picked =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked == null) return;

    setState(() {
      if (isOn) lightOnTime = picked;
      else lightOffTime = picked;
    });
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    final alarm = gasText == "ALARM";

    return Scaffold(
      appBar: AppBar(title: const Text('🏠 IoT Controller'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _statusTile("MQTT", connected, Icons.cloud_done)),
                const SizedBox(width: 12),
                Expanded(child: _statusTile("ESP32", connected, Icons.memory)),
              ],
            ),
            const SizedBox(height: 14),

            _deviceTile("Đèn", "Bật/Tắt đèn", Icons.lightbulb, lightOn, _toggleLight),
            const SizedBox(height: 10),

            _scheduleRow(context),
            const SizedBox(height: 10),

            _deviceTile("Quạt", "Bật/Tắt quạt", Icons.toys, fanOn, _toggleFan),
            const SizedBox(height: 14),

            _sectionCard(
              title: "Cảm biến DHT22",
              icon: Icons.thermostat,
              child: Column(children: [_kv("Nhiệt độ", temp), _kv("Độ ẩm", hum)]),
            ),
            const SizedBox(height: 12),

            _sectionCard(
              title: "Cảm biến khí gas (MQ)",
              icon: Icons.local_fire_department,
              headerRight: _badge(alarm ? "ALARM" : "NORMAL",
                  alarm ? Icons.warning_amber_rounded : Icons.verified),
              child: Column(
                children: [
                  _kv("MQ(AO)", mqAo),
                  _kv("Ngưỡng", mqTh),
                  _kv("Trạng thái", gasText),
                ],
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: connected ? null : connectToMqtt,
                icon: const Icon(Icons.refresh),
                label: Text(_connecting ? "Đang kết nối..." : "Kết nối lại MQTT"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusTile(String title, bool ok, IconData icon) {
    final color = ok ? Colors.green : Colors.grey;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.12),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(ok ? "Connected" : "Disconnected", style: TextStyle(color: color)),
                  const SizedBox(height: 2),
                  Text(kIsWeb ? "WebSocket" : "TCP",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceTile(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final c = value ? Colors.orange : Colors.grey;
    return Card(
      elevation: 3,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: c.withOpacity(0.12),
          child: Icon(icon, color: c),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }

  Widget _scheduleRow(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.blue.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () => _pickTime(true),
                icon: const Icon(Icons.schedule),
                label: Text("Hẹn bật: ${lightOnTime != null ? lightOnTime!.format(context) : "--:--"}"),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: () => _pickTime(false),
                icon: const Icon(Icons.timer_off),
                label: Text("Hẹn tắt: ${lightOffTime != null ? lightOffTime!.format(context) : "--:--"}"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    Widget? headerRight,
    required Widget child,
  }) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.withOpacity(0.12),
                  child: Icon(icon, color: Colors.blue),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
                if (headerRight != null) headerRight,
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(color: Colors.grey.shade700)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _badge(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

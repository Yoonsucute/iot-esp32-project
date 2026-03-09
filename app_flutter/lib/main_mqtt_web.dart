import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const _Bootstrap(),
    );
  }
}

// =================== BOOTSTRAP ===================
class _Bootstrap extends StatelessWidget {
  const _Bootstrap({super.key});
  @override
  Widget build(BuildContext context) {
    final savedTopic = html.window.localStorage['topic'];
    final savedName = html.window.localStorage['device_name'];
    if (savedTopic != null && savedTopic.isNotEmpty) {
      return IoTDashboard(topic: savedTopic, name: savedName ?? 'Device');
    }
    return const RegisterDevicePage();
  }
}

// =================== REGISTER ===================
class RegisterDevicePage extends StatefulWidget {
  const RegisterDevicePage({super.key});
  @override
  State<RegisterDevicePage> createState() => _RegisterDevicePageState();
}

class _RegisterDevicePageState extends State<RegisterDevicePage> {
  final _nameCtrl = TextEditingController();
  final _topicCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _register() async {
    final name = _nameCtrl.text.trim();
    final topic = _topicCtrl.text.trim();
    if (name.isEmpty || topic.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('⚠️ Nhập tên và topic MQTT')));
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await html.HttpRequest.request(
        'http://localhost:8080/api/device',
        method: 'POST',
        sendData: jsonEncode({'device_name': name, 'topic': topic}),
        requestHeaders: {'Content-Type': 'application/json'},
      );
      if (res.status == 200) {
        html.window.localStorage['topic'] = topic;
        html.window.localStorage['device_name'] = name;
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => IoTDashboard(topic: topic, name: name)),
        );
      }
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('❌ Không thể lưu thiết bị')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🛰️ Đăng ký thiết bị MQTT')),
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Nhập tên & topic MQTT (vd: demo/room1 hoặc demoled)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Tên thiết bị', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _topicCtrl,
                decoration: const InputDecoration(
                    labelText: 'Topic MQTT', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loading ? null : _register,
                icon: const Icon(Icons.save),
                label: Text(_loading ? 'Đang lưu...' : 'Lưu & Mở Dashboard'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// =================== DASHBOARD ===================
class IoTDashboard extends StatefulWidget {
  final String topic;
  final String name;
  const IoTDashboard({super.key, required this.topic, required this.name});
  @override
  State<IoTDashboard> createState() => _IoTDashboardState();
}

class _IoTDashboardState extends State<IoTDashboard> {
  bool _mqttConnected = false;
  bool _deviceOnline = false;
  String _light = 'off', _fan = 'off';
  String _fw = '--', _rssi = '--', _temp = '--', _hum = '--';
  String _voiceText = '';
  static const String defaultNs = 'demo/room1';
  Timer? _timerLight;

  @override
  void initState() {
    super.initState();
    _initMQTT();
    Future.delayed(const Duration(seconds: 1), _initVoiceContinuous);
  }

  // ---------- MQTT ----------
  void _initMQTT() {
    final s = html.ScriptElement()
      ..src = 'https://unpkg.com/mqtt/dist/mqtt.min.js'
      ..onLoad.listen((_) => _connectMQTT());
    html.document.head!.append(s);
  }

  void _connectMQTT() {
    final ns = widget.topic;
    js.context.callMethod('eval', ['''
      if (window.mqttClient) try { window.mqttClient.end(true); } catch(e){}
      window.mqttClient = mqtt.connect('wss://broker.emqx.io:8084/mqtt', {
        clientId: 'flutter_' + Math.random().toString(16).substr(2,8),
        reconnectPeriod: 2000, keepalive: 30
      });
      window.mqttClient.on('connect', function(){
        window.dispatchEvent(new CustomEvent('mqtt_connected'));
        window.mqttClient.subscribe('$ns/device/state');
        window.mqttClient.subscribe('$ns/sensor/state');
        window.mqttClient.subscribe('$ns/sys/online');
      });
      window.mqttClient.on('message', function(t,m){
        window.dispatchEvent(new CustomEvent('mqtt_msg',{detail:{t:t,m:m.toString()}}));
      });
    ''']);

    html.window.addEventListener('mqtt_connected', (_) {
      setState(() => _mqttConnected = true);
    });
    html.window.addEventListener('mqtt_msg', (e) {
      final d = (e as html.CustomEvent).detail;
      _handleMessage(d['t'], d['m']);
    });
  }

  void _handleMessage(String topic, String payload) {
    try {
      final data = jsonDecode(payload);
      if (topic.endsWith('/device/state')) {
        setState(() {
          _light = data['light'] ?? _light;
          _fan = data['fan'] ?? _fan;
          _fw = data['fw'] ?? _fw;
          _rssi = data['rssi']?.toString() ?? _rssi;
        });
      } else if (topic.endsWith('/sensor/state')) {
        setState(() {
          _temp = '${data['temp_c'] ?? '--'}';
          _hum = '${data['hum_pct'] ?? '--'}';
        });
      } else if (topic.endsWith('/sys/online')) {
        setState(() => _deviceOnline = (data['online'] ?? false) == true);
      }
    } catch (_) {}
  }

  // ---------- GỬI LỆNH ----------
  void _sendMQTT(String device, String action) {
    if (!_mqttConnected) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('⚠️ MQTT chưa kết nối')));
      return;
    }
    final isDefault = widget.topic == defaultNs;
    final cmdTopic = isDefault ? '${widget.topic}/device/cmd' : widget.topic;
    final payload = jsonEncode({device: action});
    js.context.callMethod('eval', [
      "window.mqttClient.publish('$cmdTopic', '$payload');"
    ]);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('📤 $payload → $cmdTopic')));
  }

  // ---------- GIỌNG NÓI (LIÊN TỤC) ----------
  void _initVoiceContinuous() {
    try {
      js.context.callMethod('eval', ['''
        (function(){
          const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
          if(!SR) { console.log("SpeechRecognition không hỗ trợ."); return; }
          const rec = new SR();
          rec.lang = 'vi-VN';
          rec.interimResults = false;
          rec.continuous = true;
          rec.onresult = (e) => {
            const t = e.results[e.results.length-1][0].transcript.toLowerCase();
            window.dispatchEvent(new CustomEvent('voice_cmd',{detail:t}));
          };
          rec.onend = () => { setTimeout(()=>rec.start(),500); }; // 🔁 Tự khởi động lại sau 0.5s
          rec.onerror = (e) => { console.log("Voice error:", e.error); setTimeout(()=>rec.start(),1000); };
          rec.start();
          window._voiceRec = rec;
        })();
      ''']);
      html.window.addEventListener('voice_cmd', (e) {
        final cmd = (e as html.CustomEvent).detail.toString();
        setState(() => _voiceText = '🗣️ $cmd');
        if (cmd.contains('bật đèn')) _sendMQTT('light', 'on');
        else if (cmd.contains('tắt đèn')) _sendMQTT('light', 'off');
        else if (cmd.contains('bật quạt')) _sendMQTT('fan', 'on');
        else if (cmd.contains('tắt quạt')) _sendMQTT('fan', 'off');
      });
    } catch (err) {
      print('⚠️ Voice init error: $err');
    }
  }

  // ---------- HẸN GIỜ ----------
  void _scheduleLight(bool turnOn) async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: now,
      helpText: turnOn ? 'Chọn giờ bật đèn' : 'Chọn giờ tắt đèn',
    );
    if (picked != null) {
      final nowDate = DateTime.now();
      final scheduleTime = DateTime(
        nowDate.year,
        nowDate.month,
        nowDate.day,
        picked.hour,
        picked.minute,
      );
      Duration diff = scheduleTime.difference(nowDate);
      if (diff.isNegative) diff += const Duration(days: 1);

      _timerLight?.cancel();
      _timerLight = Timer(diff, () {
        _sendMQTT('light', turnOn ? 'on' : 'off');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('💡 Đã ${turnOn ? "bật" : "tắt"} đèn theo lịch.')));
      });

      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('⏰ Sẽ ${turnOn ? "bật" : "tắt"} đèn lúc $h:$m')));
    }
  }

  // ---------- ĐĂNG XUẤT ----------
  void _logout() {
    html.window.localStorage.remove('topic');
    html.window.localStorage.remove('device_name');
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RegisterDevicePage()),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.name} (${widget.topic})'),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(children: [
          Row(children: [
            Expanded(child: _statusCard('MQTT', _mqttConnected, Icons.cloud)),
            const SizedBox(width: 12),
            Expanded(child: _statusCard('ESP32', _deviceOnline, Icons.memory)),
          ]),
          const SizedBox(height: 20),
          _deviceTile('💡 Light', _light, 'light'),
          _deviceTile('🌀 Fan', _fan, 'fan'),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () => _scheduleLight(true),
                icon: const Icon(Icons.alarm_on),
                label: const Text('Hẹn bật đèn'),
              ),
              ElevatedButton.icon(
                onPressed: () => _scheduleLight(false),
                icon: const Icon(Icons.alarm_off),
                label: const Text('Hẹn tắt đèn'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sensorCard(),
          const SizedBox(height: 12),
          Text(_voiceText, style: const TextStyle(color: Colors.deepPurple)),
        ]),
      ),
    );
  }

  Widget _statusCard(String title, bool ok, IconData icon) {
    final c = ok ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          border: Border.all(color: c, width: 2),
          borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Icon(icon, color: c),
        Text(title, style: TextStyle(color: c, fontWeight: FontWeight.bold)),
        Text(ok ? 'Connected' : 'Disconnected', style: TextStyle(color: c))
      ]),
    );
  }

  Widget _deviceTile(String title, String state, String device) {
    final on = state == 'on';
    return Card(
      elevation: 4,
      child: SwitchListTile(
        secondary: Icon(Icons.power, color: on ? Colors.orange : Colors.grey),
        title: Text(title,
            style: TextStyle(
                color: on ? Colors.orange : Colors.black,
                fontWeight: FontWeight.bold)),
        subtitle: Text('Status: ${state.toUpperCase()}'),
        value: on,
        onChanged: (_) => _sendMQTT(device, on ? 'off' : 'on'),
      ),
    );
  }

  Widget _sensorCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Text('🌡️ Sensor Data',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const Divider(),
            _kv('Temperature', '$_temp °C'),
            _kv('Humidity', '$_hum %'),
            _kv('WiFi RSSI', '$_rssi dBm'),
            _kv('Firmware', _fw),
          ]),
        ),
      );

  Widget _kv(String k, String v) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k),
        Text(v),
      ]);
}

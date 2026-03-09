import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String supabaseUrl = 'https://pzzxyobutvlbmwjtnqpm.supabase.co';
  static const String supabaseAnonKey = 
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB6enh5b2J1dHZsYm13anRucXBtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMjAzNTcsImV4cCI6MjA4ODU5NjM1N30.7CeL1DLn8TAKCNm5hophcYGmv8ufDTKcN5q1SRjcViw';

  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      debugPrint('✅ Supabase initialized successfully');
      debugPrint('✅ URL: $supabaseUrl');
    } catch (e) {
      debugPrint('❌ Supabase initialization failed: $e');
    }
  }

  static SupabaseClient get client => Supabase.instance.client;

  // Lưu dữ liệu DHT22 (nhiệt độ, độ ẩm)
  static Future<bool> saveDhtData({
    required double temperature,
    required double humidity,
  }) async {
    try {
      debugPrint('🔄 Đang lưu DHT: temp=$temperature, hum=$humidity');
      
      final response = await client.from('dht_data').insert({
        'temperature': temperature,
        'humidity': humidity,
      }).select();
      
      debugPrint('✅ DHT data saved: $response');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Error saving DHT data: $e');
      debugPrint('   Stack: $stackTrace');
      return false;
    }
  }

  // Lưu dữ liệu cảm biến khí gas
  static Future<bool> saveGasData({
    required int mqAo,
    required int threshold,
    required bool gasAlarm,
  }) async {
    try {
      debugPrint('🔄 Đang lưu Gas: mqAo=$mqAo, threshold=$threshold, alarm=$gasAlarm');
      
      final response = await client.from('gas_data').insert({
        'mq_ao': mqAo,
        'threshold': threshold,
        'gas_alarm': gasAlarm,
      }).select();
      
      debugPrint('✅ Gas data saved: $response');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Error saving gas data: $e');
      debugPrint('   Stack: $stackTrace');
      return false;
    }
  }

  // Lưu trạng thái thiết bị (đèn, quạt)
  static Future<bool> saveDeviceState({
    required String deviceName,
    required bool state,
  }) async {
    try {
      debugPrint('🔄 Đang lưu $deviceName = ${state ? "BẬT" : "TẮT"}...');
      
      final response = await client.from('device_states').insert({
        'device_name': deviceName,
        'state': state,
      }).select();
      
      debugPrint('✅ Đã lưu Supabase thành công: $deviceName = ${state ? "BẬT" : "TẮT"}');
      debugPrint('📊 Response: $response');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ LỖI LƯU SUPABASE:');
      debugPrint('   Device: $deviceName');
      debugPrint('   State: $state');
      debugPrint('   Error: $e');
      debugPrint('   Stack: $stackTrace');
      return false;
    }
  }

  // Lấy lịch sử dữ liệu DHT22
  static Future<List<Map<String, dynamic>>> getDhtHistory({int limit = 50}) async {
    try {
      final response = await client
          .from('dht_data')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error fetching DHT history: $e');
      return [];
    }
  }

  // Lấy lịch sử dữ liệu gas
  static Future<List<Map<String, dynamic>>> getGasHistory({int limit = 50}) async {
    try {
      final response = await client
          .from('gas_data')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error fetching gas history: $e');
      return [];
    }
  }

  // Lấy lịch sử trạng thái thiết bị
  static Future<List<Map<String, dynamic>>> getDeviceHistory({int limit = 50}) async {
    try {
      final response = await client
          .from('device_states')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error fetching device history: $e');
      return [];
    }
  }
}

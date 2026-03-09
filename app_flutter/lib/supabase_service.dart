import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

class SupabaseService {
  static const String supabaseUrl = 'https://pzzxyobutvlbmwjtnqpm.supabase.co';
  static const String supabaseAnonKey = 
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB6enh5b2J1dHZsYm13anRucXBtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMjAzNTcsImV4cCI6MjA4ODU5NjM1N30.7CeL1DLn8TAKCNm5hophcYGmv8ufDTKcN5q1SRjcViw';

  static late Dio _dio;

  static void initialize() {
    _dio = Dio(BaseOptions(
      baseUrl: '$supabaseUrl/rest/v1',
      headers: {
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer $supabaseAnonKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    debugPrint('✅ Supabase REST API ready');
    debugPrint('✅ URL: $supabaseUrl');
  }

  // Lưu dữ liệu DHT22 (nhiệt độ, độ ẩm)
  static Future<bool> saveDhtData({
    required double temperature,
    required double humidity,
  }) async {
    try {
      debugPrint('🔄 Đang lưu DHT: temp=$temperature, hum=$humidity');
      
      final response = await _dio.post('/dht_data', data: {
        'temperature': temperature,
        'humidity': humidity,
      });
      
      debugPrint('✅ DHT data saved: ${response.data}');
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
      
      final response = await _dio.post('/gas_data', data: {
        'mq_ao': mqAo,
        'threshold': threshold,
        'gas_alarm': gasAlarm,
      });
      
      debugPrint('✅ Gas data saved: ${response.data}');
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
      
      final response = await _dio.post('/device_states', data: {
        'device_name': deviceName,
        'state': state,
      });
      
      debugPrint('✅ Đã lưu Supabase thành công: $deviceName = ${state ? "BẬT" : "TẮT"}');
      debugPrint('📊 Response: ${response.data}');
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
      final response = await _dio.get('/dht_data', queryParameters: {
        'order': 'created_at.desc',
        'limit': limit,
      });
      
      final List<dynamic> data = response.data;
      return data.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('❌ Error fetching DHT history: $e');
      return [];
    }
  }

  // Lấy lịch sử dữ liệu gas
  static Future<List<Map<String, dynamic>>> getGasHistory({int limit = 50}) async {
    try {
      final response = await _dio.get('/gas_data', queryParameters: {
        'order': 'created_at.desc',
        'limit': limit,
      });
      
      final List<dynamic> data = response.data;
      return data.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('❌ Error fetching gas history: $e');
      return [];
    }
  }

  // Lấy lịch sử trạng thái thiết bị
  static Future<List<Map<String, dynamic>>> getDeviceHistory({int limit = 50}) async {
    try {
      final response = await _dio.get('/device_states', queryParameters: {
        'order': 'created_at.desc',
        'limit': limit,
      });
      
      final List<dynamic> data = response.data;
      return data.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('❌ Error fetching device history: $e');
      return [];
    }
  }

  // ✅ Lấy trạng thái mới nhất của từng thiết bị (để đồng bộ)
  static Future<List<Map<String, dynamic>>> getLatestDeviceStates() async {
    try {
      // Lấy 2 record mới nhất (1 cho light, 1 cho fan)
      final response = await _dio.get('/device_states', queryParameters: {
        'order': 'created_at.desc',
        'limit': 2,
      });
      
      final List<dynamic> data = response.data;
      return data.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('❌ Error fetching latest device states: $e');
      return [];
    }
  }
}

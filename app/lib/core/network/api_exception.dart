import 'package:dio/dio.dart';

/// A normalized error surfaced to the UI layer, derived from a [DioException].
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isPaymentRequired => statusCode == 402;

  factory ApiException.fromDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    String message = 'Something went wrong. Please try again.';
    if (data is Map && data['detail'] is String) {
      message = data['detail'] as String;
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      message = 'Could not reach the server. Check your connection.';
    }

    return ApiException(message, statusCode: statusCode);
  }

  @override
  String toString() => message;
}

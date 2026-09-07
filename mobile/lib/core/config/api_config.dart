import '../network/api_error.dart';

class ApiConfig {
  ApiConfig({required String baseUrl}) : baseUrl = _normalize(baseUrl);

  factory ApiConfig.fromEnvironment() =>
      ApiConfig(baseUrl: const String.fromEnvironment('API_BASE_URL'));

  final String baseUrl;

  static String _normalize(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (normalized.isEmpty ||
        uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ApiException.configuration('API_BASE_URL is missing or invalid.');
    }
    return normalized;
  }
}

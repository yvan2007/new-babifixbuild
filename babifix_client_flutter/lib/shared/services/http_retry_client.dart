import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class RetryOptions {
  final int maxRetries;
  final Duration initialDelay;
  final double backoffMultiplier;
  final bool retryOnTimeout;

  const RetryOptions({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.retryOnTimeout = true,
  });
}

class HttpRetryClient {
  final http.Client _inner;
  final RetryOptions _options;

  HttpRetryClient(this._inner, {RetryOptions? options})
    : _options = options ?? const RetryOptions();

  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    return _withRetry(() => _inner.get(url, headers: headers));
  }

  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return _withRetry(() => _inner.post(url, headers: headers, body: body));
  }

  Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return _withRetry(() => _inner.put(url, headers: headers, body: body));
  }

  Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return _withRetry(() => _inner.patch(url, headers: headers, body: body));
  }

  Future<http.Response> delete(Uri url, {Map<String, String>? headers}) async {
    return _withRetry(() => _inner.delete(url, headers: headers));
  }

  Future<http.Response> _withRetry(
    Future<http.Response> Function() request,
  ) async {
    int attempt = 0;
    Duration delay = _options.initialDelay;

    while (true) {
      try {
        final response = await request();

        // Retry on 5xx errors only
        if (response.statusCode >= 500 && attempt < _options.maxRetries) {
          attempt++;
          await Future.delayed(delay);
          delay *= _options.backoffMultiplier;
          continue;
        }

        return response;
      } on TimeoutException {
        if (!_options.retryOnTimeout || attempt >= _options.maxRetries) {
          rethrow;
        }
        attempt++;
        await Future.delayed(delay);
        delay *= _options.backoffMultiplier;
      } on http.ClientException {
        if (attempt >= _options.maxRetries) {
          rethrow;
        }
        attempt++;
        await Future.delayed(delay);
        delay *= _options.backoffMultiplier;
      }
    }
  }

  void close() {
    _inner.close();
  }
}

class ApiClient {
  static const _defaultBaseUrl = 'http://localhost:8000';

  final String baseUrl;
  final http.Client _client;
  final RetryOptions _retryOptions;

  ApiClient({String? baseUrl, http.Client? client, RetryOptions? retryOptions})
    : baseUrl = baseUrl ?? _defaultBaseUrl,
      _client = client ?? http.Client(),
      _retryOptions = retryOptions ?? const RetryOptions();

  HttpRetryClient get client =>
      HttpRetryClient(_client, options: _retryOptions);

  Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParams,
  }) async {
    final uri = _buildUri(path, queryParams);
    return client.get(uri, headers: headers);
  }

  Future<http.Response> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Map<String, String>? queryParams,
  }) async {
    final uri = _buildUri(path, queryParams);
    return client.post(uri, headers: headers, body: body);
  }

  Uri _buildUri(String path, Map<String, String>? queryParams) {
    final uri = Uri.parse('$baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      return uri.replace(queryParameters: queryParams);
    }
    return uri;
  }

  void close() {
    _client.close();
  }
}

extension ApiResponseExtension on http.Response {
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  Map<String, dynamic>? get json {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String? get errorMessage => json?['error'] as String?;
}

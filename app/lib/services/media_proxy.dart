import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'api.dart';

/// Loopback-only HTTP bridge for media players that cannot attach an
/// Authorization header (the audio backend).
///
/// The proxy listens on `127.0.0.1` with an ephemeral port and a random path
/// secret, so only this app can reach it. Requests are forwarded to the real
/// server with the session token, and the response body is streamed straight
/// through: media is never written to the device, and the platform player can
/// still seek because range requests and `206` responses are preserved.
class MediaProxy {
  MediaProxy._(this._server, this._api, this._secret);

  final HttpServer _server;
  final Api _api;
  final String _secret;

  static const _requestHeaders = {
    'range',
    'if-range',
    'if-modified-since',
    'if-none-match',
  };

  static const _responseHeaders = {
    'accept-ranges',
    'cache-control',
    'content-length',
    'content-range',
    'content-type',
    'etag',
    'last-modified',
  };

  /// Starts a proxy for [api]. Call [close] when the player is disposed.
  static Future<MediaProxy> start(Api api) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = MediaProxy._(server, api, _newSecret());
    server.listen(
      proxy._handle,
      onError: (Object _) {
        // A single broken connection must not take the proxy down.
      },
    );
    return proxy;
  }

  /// URL the platform player should open for [remotePath].
  String urlFor(String remotePath) {
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _server.port,
      pathSegments: [_secret],
      queryParameters: {'path': remotePath},
    ).toString();
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  static String _newSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      if (segments.length != 1 || segments.first != _secret) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final remotePath = request.uri.queryParameters['path'];
      if (remotePath == null || remotePath.isEmpty) {
        response.statusCode = HttpStatus.badRequest;
        await response.close();
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }

      final outgoing =
          http.Request(request.method, _api.fileDownloadUri(remotePath));
      outgoing.headers.addAll(_api.authHeaders);
      for (final name in _requestHeaders) {
        final value = request.headers.value(name);
        if (value != null) outgoing.headers[name] = value;
      }

      final upstream = await _api.rawClient.send(outgoing).timeout(
            const Duration(seconds: 30),
          );
      response.statusCode = upstream.statusCode;
      upstream.headers.forEach((name, value) {
        if (_responseHeaders.contains(name.toLowerCase())) {
          response.headers.set(name, value);
        }
      });
      if (request.method == 'HEAD') {
        await response.close();
        await upstream.stream.drain<void>();
        return;
      }
      await upstream.stream.pipe(response);
    } catch (_) {
      try {
        response.statusCode = HttpStatus.badGateway;
        await response.close();
      } catch (_) {
        // The client disconnected before headers were sent; nothing to do.
      }
    }
  }
}

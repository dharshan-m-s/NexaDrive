import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/media_proxy.dart';
import 'package:nexadrive/services/session.dart';

void main() {
  late HttpServer upstream;
  late MediaProxy proxy;
  late http.Client client;
  final bytes = List<int>.generate(4096, (i) => i % 251);
  String? seenToken;

  setUp(() async {
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final response = request.response;
      seenToken = request.headers.value('authorization');
      if (request.uri.path != '/api/files/download' ||
          request.uri.queryParameters['path'] != 'Music/song.mp3') {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final range = request.headers.value('range');
      response.headers.contentType = ContentType('audio', 'mpeg');
      response.headers.set('accept-ranges', 'bytes');
      if (range == null) {
        response.headers.contentLength = bytes.length;
        response.add(bytes);
        await response.close();
        return;
      }
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      final slice = bytes.sublist(start, end + 1);
      response.statusCode = HttpStatus.partialContent;
      response.headers
          .set('content-range', 'bytes $start-$end/${bytes.length}');
      response.headers.contentLength = slice.length;
      response.add(slice);
      await response.close();
    });

    final session = Session()
      ..serverUrl = 'http://127.0.0.1:${upstream.port}'
      ..token = 'test-token';
    proxy = await MediaProxy.start(Api(session));
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await proxy.close();
    await upstream.close(force: true);
  });

  test('forwards the session token without exposing it in the URL', () async {
    final response =
        await client.get(Uri.parse(proxy.urlFor('Music/song.mp3')));
    expect(response.statusCode, HttpStatus.ok);
    expect(response.bodyBytes, bytes);
    expect(seenToken, 'Bearer test-token');
    expect(proxy.urlFor('Music/song.mp3'), isNot(contains('test-token')));
  });

  test('preserves range requests for seeking', () async {
    final response = await client.get(
      Uri.parse(proxy.urlFor('Music/song.mp3')),
      headers: {'range': 'bytes=100-199'},
    );
    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.bodyBytes, bytes.sublist(100, 200));
    expect(response.headers['content-range'], 'bytes 100-199/4096');
  });

  test('rejects requests that do not know the path secret', () async {
    final response = await client.get(
      Uri.parse(
        'http://127.0.0.1:${Uri.parse(proxy.urlFor('Music/song.mp3')).port}'
        '/not-the-secret?path=Music/song.mp3',
      ),
    );
    expect(response.statusCode, HttpStatus.notFound);
  });

  test('relays server errors without inventing a success', () async {
    final response =
        await client.get(Uri.parse(proxy.urlFor('Music/missing.mp3')));
    expect(response.statusCode, HttpStatus.notFound);
  });
}

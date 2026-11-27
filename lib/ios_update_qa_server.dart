import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<void> startUpdateQaServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8768);
  server.listen((request) async {
    final path = request.uri.path == '/' ? '/index.html' : request.uri.path;
    if (request.method != 'GET' ||
        !RegExp(r'^/[a-zA-Z0-9_./-]+$').hasMatch(path) ||
        path.contains('..')) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      final data = await rootBundle.load('assets/update_qa$path');
      final extension = path.split('.').last;
      final type = {
        'html': 'text/html',
        'js': 'application/javascript',
        'json': 'application/json',
        'wasm': 'application/wasm',
        'png': 'image/png',
      }[extension];
      if (type != null) request.response.headers.contentType = ContentType.parse(type);
      request.response.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } on FlutterError {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
}

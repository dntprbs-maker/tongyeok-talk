import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'mobile_web_navigation.dart';

const _channel = MethodChannel('tongyeok/app_update');
const _appleId = '6834760087';

bool isAppUpdatePage(Uri? page) =>
    page != null &&
    isTrustedTongyeokPage(page) &&
    (isTongyeokMobilePage(page) || socialLocalPreview);

Future<List<String>?> readInstalledVersion(bool android) async {
  try {
    if (android) {
      final version = await _channel.invokeListMethod<String>('installed');
      return version?.length == 2 ? version : null;
    }
    const version = String.fromEnvironment('TONGYEOK_BUILD_NAME');
    const build = String.fromEnvironment('TONGYEOK_BUILD_NUMBER');
    return version.isNotEmpty && build.isNotEmpty ? [version, build] : null;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

int compareAppVersions(String left, String right) {
  List<int> parse(String version) {
    if (!RegExp(r'^\d+(\.\d+){0,2}$').hasMatch(version)) {
      throw const FormatException('Invalid app version');
    }
    return version.split('.').map(int.parse).toList();
  }

  final a = parse(left);
  final b = parse(right);
  for (var i = 0; i < 3; i++) {
    final comparison = (i < a.length ? a[i] : 0).compareTo(
      i < b.length ? b[i] : 0,
    );
    if (comparison != 0) return comparison;
  }
  return 0;
}

class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({
    super.key,
    required this.android,
    required this.mongolian,
    required this.installed,
  });

  final bool android;
  final bool mongolian;
  final List<String> installed;

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  late Future<String?> _available = _check();
  bool _opening = false;

  String _text(String ko, String mn) => widget.mongolian ? mn : ko;

  Future<String?> _check() async {
    const timeout = Duration(seconds: 10);
    if (widget.android) {
      final build = await _channel
          .invokeMethod<String>('check')
          .timeout(timeout);
      return build != null && int.parse(build) > int.parse(widget.installed[1])
          ? build
          : null;
    }
    final response = await http
        .get(
          Uri.https('itunes.apple.com', '/lookup', {
            'id': _appleId,
            'country': 'kr',
          }),
        )
        .timeout(timeout);
    if (response.statusCode != 200) throw StateError('App Store lookup failed');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final listing = (data['results'] as List).single as Map<String, dynamic>;
    if (listing['trackId'].toString() != _appleId) {
      throw const FormatException('Unexpected app');
    }
    final version = listing['version'] as String;
    return compareAppVersions(version, widget.installed.first) > 0
        ? version
        : null;
  }

  Future<void> _openStore() async {
    setState(() => _opening = true);
    try {
      final page =
          widget.android
              ? Uri.https('play.google.com', '/store/apps/details', {
                'id': 'com.tongyeoktalk',
              })
              : Uri.https('apps.apple.com', '/kr/app/id$_appleId');
      final opened =
          widget.android
              ? await _channel.invokeMethod<bool>('openStore') == true
              : await launchUrl(
                page.replace(scheme: 'itms-apps'),
                mode: LaunchMode.externalApplication,
              );
      if (!opened &&
          !await launchUrl(page, mode: LaunchMode.externalApplication)) {
        throw StateError('Store unavailable');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text('스토어를 열 수 없어요.', 'Аппын дэлгүүрийг нээж чадсангүй.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_text('앱 업데이트', 'Апп шинэчлэх'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: ListTile(
                title: Text(_text('현재 설치 버전', 'Суулгасан хувилбар')),
                subtitle: Text(
                  _text(
                    '${widget.installed[0]} · 빌드 ${widget.installed[1]}',
                    '${widget.installed[0]} · Билд ${widget.installed[1]}',
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FutureBuilder<String?>(
              future: _available,
              builder: (context, snapshot) {
                final waiting =
                    snapshot.connectionState != ConnectionState.done;
                final latest = waiting ? null : snapshot.data;
                final error = !waiting && snapshot.hasError;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      waiting
                          ? _text(
                            '새 버전을 확인하고 있어요',
                            'Шинэ хувилбар шалгаж байна',
                          )
                          : error
                          ? _text(
                            '새 버전을 확인하지 못했어요',
                            'Шинэ хувилбарыг шалгаж чадсангүй',
                          )
                          : latest == null
                          ? _text('최신 버전입니다', 'Хамгийн сүүлийн хувилбар байна')
                          : _text('새 버전이 있어요', 'Шинэ хувилбар гарсан байна'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (latest != null)
                      Text(
                        widget.android
                            ? _text('새 빌드 $latest', 'Шинэ билд $latest')
                            : _text('새 버전 $latest', 'Шинэ хувилбар $latest'),
                      ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed:
                          error
                              ? () {
                                setState(() {
                                  _available = _check();
                                });
                              }
                              : latest == null || _opening
                              ? null
                              : _openStore,
                      child: Text(
                        error
                            ? _text('다시 확인', 'Дахин шалгах')
                            : _text('업데이트 하기', 'Шинэчлэх'),
                      ),
                    ),
                    if (latest != null)
                      Text(
                        widget.android
                            ? _text(
                              '구글 플레이에서 업데이트할 수 있어요.',
                              'Google Play-ээс шинэчилнэ үү.',
                            )
                            : _text(
                              '앱스토어에서 업데이트할 수 있어요.',
                              'App Store-оос шинэчилнэ үү.',
                            ),
                        textAlign: TextAlign.center,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

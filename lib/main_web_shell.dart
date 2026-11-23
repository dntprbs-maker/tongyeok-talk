// Isolated prototype. Advertising and notifications are not yet wired.
// Do not use as a release entry point until device and bridge tests pass.
import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'ios_reward_ad_probe.dart';
import 'mobile_web_navigation.dart';
import 'native_push_bridge_device.dart';
import 'native_push_bridge_protocol.dart';
import 'native_push_bridge_script.dart';
import 'native_reward_bridge_device.dart';
import 'native_reward_bridge_protocol.dart';
import 'native_reward_bridge_script.dart';

void main() => runApp(
  const MaterialApp(
    debugShowCheckedModeBanner: false,
    supportedLocales: [Locale('ko'), Locale('mn'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: TongyeokWebShell(),
  ),
);

class TongyeokWebShell extends StatefulWidget {
  const TongyeokWebShell({super.key});
  @override
  State<TongyeokWebShell> createState() => _TongyeokWebShellState();
}

class _TongyeokWebShellState extends State<TongyeokWebShell> {
  static const _buildNumber = String.fromEnvironment('TONGYEOK_BUILD_NUMBER');
  // Keep disabled until the Apple push profile/key and device tests are ready.
  static const _nativePushEnabled = bool.fromEnvironment(
    'TONGYEOK_IOS_NATIVE_PUSH',
  );
  static const _nativeRewardEnabled = bool.fromEnvironment(
    'TONGYEOK_IOS_NATIVE_REWARDS',
  );
  static const _nativeRewardTestMode = bool.fromEnvironment(
    'TONGYEOK_ADS_TEST_MODE',
    defaultValue: true,
  );
  static final _entry = Uri.https('dntprbs-maker.github.io', '/tongyeok-talk/');
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;
  final _pushDevice = NativePushBridgeDevice();
  String _pageNonce = '';
  Future<void> _pushQueue = Future.value();
  int _queuedPushRequests = 0;
  final _rewardDevice = NativeRewardBridgeDevice();
  bool _rewardBusy = false;
  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'TongyeokNativeReward',
        onMessageReceived: (message) {
          if (!_nativeRewardEnabled ||
              kIsWeb ||
              defaultTargetPlatform != TargetPlatform.iOS) {
            return;
          }
          _handleReward(message.message, _pageNonce);
        },
      )
      ..addJavaScriptChannel(
        'TongyeokNativePush',
        onMessageReceived: (message) {
          if (!_nativePushEnabled ||
              kIsWeb ||
              defaultTargetPlatform != TargetPlatform.iOS ||
              _queuedPushRequests >= 4) {
            return;
          }
          final nonce = _pageNonce;
          _queuedPushRequests++;
          _pushQueue = _pushQueue
              .then((_) => _handlePush(message.message, nonce))
              .catchError((Object _) {})
              .whenComplete(() => _queuedPushRequests--);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return uri != null && isTrustedTongyeokPage(uri)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            _pageNonce = base64UrlEncode(
              List.generate(32, (_) => Random.secure().nextInt(256)),
            );
            if (mounted) {
              setState(() {
                _loading = true;
                _failed = false;
              });
            }
          },
          onPageFinished: (url) async {
            if (_nativeRewardEnabled &&
                !kIsWeb &&
                defaultTargetPlatform == TargetPlatform.iOS &&
                isTrustedTongyeokPage(Uri.parse(url))) {
              await _controller.runJavaScript(
                nativeRewardBridgeScript(
                  _pageNonce,
                  testMode: _nativeRewardTestMode,
                ),
              );
            }
            if (_nativePushEnabled &&
                !kIsWeb &&
                defaultTargetPlatform == TargetPlatform.iOS &&
                isTrustedTongyeokPage(Uri.parse(url))) {
              await _controller.runJavaScript(
                nativePushBridgeScript(_pageNonce),
              );
            }
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() {
                _failed = true;
                _loading = false;
              });
            }
          },
        ),
      );
    _openPublishedApp();
  }

  Future<void> _handleReward(String raw, String nonce) async {
    if (!mounted || nonce != _pageNonce) return;
    try {
      final url = await _controller.currentUrl();
      final request = NativeRewardRequest.parse(
        raw,
        nonce,
        url == null ? null : Uri.tryParse(url),
        testMode: _nativeRewardTestMode,
      );
      if (request == null || nonce != _pageNonce) return;
      String? value, error;
      if (_rewardBusy) {
        error = 'adUnavailable';
      } else {
        _rewardBusy = true;
        try {
          value = await _rewardDevice.run(request);
        } catch (_) {
          error = 'adLoadFailed';
        } finally {
          _rewardBusy = false;
        }
      }
      final current = await _controller.currentUrl();
      if (!mounted ||
          nonce != _pageNonce ||
          current == null ||
          !isTrustedTongyeokPage(Uri.parse(current))) {
        return;
      }
      await _controller.runJavaScript(
        'window.__tongyeokNativeRewardComplete?.('
        '${jsonEncode(nonce)},${jsonEncode(request.id)},${jsonEncode(value)},${jsonEncode(error)});',
      );
    } catch (_) {
      // The web promise has a deadline. Do not expose native or account errors.
    }
  }

  Future<void> _handlePush(String raw, String nonce) async {
    if (!mounted || nonce != _pageNonce) return;
    final url = await _controller.currentUrl();
    final request = NativePushRequest.parse(
      raw,
      nonce,
      url == null ? null : Uri.tryParse(url),
    );
    if (request == null || nonce != _pageNonce) return;
    String? value, error;
    try {
      value = await _pushDevice.run(request.action, request.uid);
    } catch (failure) {
      final code = failure is FirebaseException
          ? failure.code
          : failure is PlatformException
          ? failure.code
          : failure.runtimeType.toString();
      debugPrint('TT_IOS_PUSH_FAILED code=$code');
      error = 'push_failed';
    }
    final current = await _controller.currentUrl();
    if (!mounted ||
        nonce != _pageNonce ||
        current == null ||
        !isTrustedTongyeokPage(Uri.parse(current))) {
      return;
    }
    await _controller.runJavaScript(
      'window.__tongyeokNativePushComplete?.('
      '${jsonEncode(nonce)},${jsonEncode(request.id)},${jsonEncode(value)},${jsonEncode(error)});',
    );
  }

  Future<void> _openPublishedApp() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      // Revalidate the web entry, keeping the session and versioned assets.
      await _controller.loadRequest(
        _entry,
        headers: const {'Cache-Control': 'no-cache'},
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mongolian = Localizations.localeOf(context).languageCode == 'mn';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (_buildNumber.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 16,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    mongolian ? 'Хувилбар $_buildNumber' : '빌드 $_buildNumber',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loading)
                    const Center(child: CircularProgressIndicator()),
                  if (_failed)
                    ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              mongolian
                                  ? 'Хуудсыг нээж чадсангүй. Интернэтээ шалгана уу.'
                                  : '화면을 불러오지 못했습니다. 인터넷 연결을 확인해 주세요.',
                            ),
                            TextButton(
                              onPressed: _openPublishedApp,
                              child: Text(
                                mongolian ? 'Дахин оролдох' : '다시 시도',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (iosAdProbeEnabled &&
                      !kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.iOS)
                    const Align(
                      alignment: Alignment.bottomCenter,
                      child: IosRewardAdProbe(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

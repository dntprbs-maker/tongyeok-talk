import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_update_screen.dart';
import 'ios_reward_ad_probe.dart';
import 'mobile_web_navigation.dart';
import 'native_push_bridge_device.dart';
import 'native_push_bridge_protocol.dart';
import 'native_push_bridge_script.dart';
import 'native_reward_bridge_device.dart';
import 'native_reward_bridge_protocol.dart';
import 'native_reward_bridge_script.dart';
import 'native_social_login_bridge.dart';
import 'native_social_login_device.dart';
import 'native_contact_names.dart';
import 'referral_invite.dart';

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
  // Keep disabled until the Apple push profile/key and device tests are ready.
  static const _nativePushEnabled = bool.fromEnvironment(
    'TONGYEOK_IOS_NATIVE_PUSH',
  );
  static const _nativeRewardEnabled = bool.fromEnvironment(
    'TONGYEOK_IOS_NATIVE_REWARDS',
  );
  static const _androidBridgeEnabled = bool.fromEnvironment(
    'TONGYEOK_ANDROID_WEB_BRIDGES',
  );
  static const _socialEnabled = bool.fromEnvironment('TONGYEOK_SOCIAL_ONLY');
  static const _nativeRewardTestMode = bool.fromEnvironment(
    'TONGYEOK_ADS_TEST_MODE',
    defaultValue: true,
  );
  static final _entry =
      socialLocalPreview
          ? Uri.parse('http://127.0.0.1:8768/')
          : _socialEnabled
          ? Uri.https('tongyeok-talk-lab-20261024.web.app', '/mobile/')
          : Uri.https('dntprbs-maker.github.io', '/tongyeok-talk/');
  late final WebViewController _controller;
  late final Future<List<String>?> _installedVersion = readInstalledVersion(_android);
  bool _updateOpen = false;
  bool _inviteOpen = false;
  bool _loading = true;
  bool _failed = false;
  final _pushDevice = NativePushBridgeDevice();
  String _pageNonce = '';
  Future<void> _pushQueue = Future.value();
  int _queuedPushRequests = 0;
  final _rewardDevice = NativeRewardBridgeDevice();
  final _socialDevice = NativeSocialLoginDevice();
  final _contactNames = NativeContactNames();
  bool _contactsBusy = false;
  bool _rewardBusy = false;
  bool _socialBusy = false;
  bool _backBusy = false;
  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;
  bool get _canReward =>
      !kIsWeb &&
      (_ios && _nativeRewardEnabled || _android && _androidBridgeEnabled);
  bool get _canPush =>
      !kIsWeb &&
      (_ios && _nativePushEnabled || _android && _androidBridgeEnabled);
  bool get _canUseContacts => !kIsWeb && (_android || _ios) && _socialEnabled;
  bool _isContactsPage(String? url) {
    final uri = Uri.tryParse(url ?? '');
    return uri != null && isTrustedTongyeokPage(uri) &&
        (uri.host == 'tongyeok-talk-lab-20261024.web.app' || socialLocalPreview);
  }
  @override
  void initState() {
    super.initState();
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..addJavaScriptChannel(
            'TongyeokNativeContactNames',
            onMessageReceived: (message) {
              if (_canUseContacts) _handleContactNames(message.message, _pageNonce);
            },
          )
          ..addJavaScriptChannel(
            'TongyeokNativeSocialLogin',
            onMessageReceived: (message) {
              if (_socialEnabled && !kIsWeb && (_ios || _android)) {
                _handleSocial(message.message, _pageNonce);
              }
            },
          )
          ..addJavaScriptChannel(
            'TongyeokNativeReward',
            onMessageReceived: (message) {
              if (!_canReward) {
                return;
              }
              _handleReward(message.message, _pageNonce);
            },
          )
          ..addJavaScriptChannel(
            'TongyeokNativePush',
            onMessageReceived: (message) {
              if (!_canPush || _queuedPushRequests >= 4) {
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
          ..addJavaScriptChannel(
            'TongyeokAppUpdate',
            onMessageReceived: (message) => _openUpdate(message.message),
          )
          ..addJavaScriptChannel(
            'TongyeokReferralSms',
            onMessageReceived: (message) => _composeReferralSms(message.message),
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
                final nonce = _pageNonce;
                final trusted = isTrustedTongyeokPage(Uri.parse(url));
                if (_canUseContacts && _isContactsPage(url)) {
                  await _controller.runJavaScript(nativeContactNamesScript(_pageNonce));
                }
                if (_socialEnabled && trusted) {
                  await _controller.runJavaScript(
                    nativeSocialLoginScript(_pageNonce),
                  );
                }
                if (_canReward && trusted) {
                  await _controller.runJavaScript(
                    nativeRewardBridgeScript(
                      _pageNonce,
                      testMode: _nativeRewardTestMode,
                      android: _android,
                    ),
                  );
                }
                if (_canPush && trusted) {
                  await _controller.runJavaScript(
                    nativePushBridgeScript(_pageNonce),
                  );
                }
                if ((_ios || _android) && trusted && nonce == _pageNonce) {
                  await _controller.runJavaScript('''
                    if (window === window.top) {
                      let nextId = 0;
                      const pending = new Map();
                      const compose = (phone, code, language) =>
                        new Promise(resolve => {
                          const id = ++nextId;
                          const timer = setTimeout(() => {
                            pending.delete(id);
                            resolve(false);
                          }, 15000);
                          pending.set(id, ok => {
                            clearTimeout(timer);
                            resolve(ok === true);
                          });
                          window.TongyeokReferralSms.postMessage(JSON.stringify({
                            id, phone, code, language, nonce: ${jsonEncode(nonce)}
                          }));
                        });
                      window.tongyeokComposeReferralSms = (phone, code) => compose(phone, code);
                      window.tongyeokComposeLocalizedReferralSms = compose;
                      window.tongyeokReferralSmsResult = (nonce, id, ok) => {
                        if (nonce !== ${jsonEncode(nonce)}) return;
                        const finish = pending.get(id);
                        pending.delete(id);
                        if (finish) finish(ok);
                      };
                    }
                  ''');
                }
                if (mounted) setState(() => _loading = false);
                final installed = await _installedVersion;
                if (!mounted || installed == null || nonce != _pageNonce ||
                    !isAppUpdatePage(Uri.tryParse(await _controller.currentUrl() ?? '')) ||
                    nonce != _pageNonce) {
                  return;
                }
                await _controller.runJavaScript("""
                  if (window === window.top) {
                    window.tongyeokInstalledVersion = ${jsonEncode(installed)};
                    window.tongyeokOpenAppUpdate = (mn) =>
                      window.TongyeokAppUpdate.postMessage(${jsonEncode(nonce)} + (mn ? ':mn' : ':ko'));
                    window.dispatchEvent(new Event('tongyeok-app-update-ready'));
                  }
                """);
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

  Future<void> _composeReferralSms(String message) async {
    if (!mounted || (!_ios && !_android) || message.length > 256) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final nonce = _pageNonce;
    final id = decoded['id'];
    final phone = decoded['phone'];
    final code = decoded['code'];
    final language = decoded['language'];
    if (language != null && language != 'ko' && language != 'mn') return;
    if (nonce.isEmpty || decoded['nonce'] != nonce || id is! int || id < 1 ||
        phone is! String || !isReferralPhone(phone) ||
        code is! String || !isReferralCode(code)) {
      return;
    }
    final page = Uri.tryParse(await _controller.currentUrl() ?? '');
    if (!mounted || nonce != _pageNonce || page == null || !isTrustedTongyeokPage(page)) return;
    var opened = false;
    if (!_inviteOpen) {
      _inviteOpen = true;
      try {
        await const MethodChannel('tongyeok/invite').invokeMethod<void>(
          'composeSms', {'phone': phone, 'body': referralMessage(code, language: language as String?)},
        );
        opened = true;
      } on PlatformException {
        opened = false;
      } on MissingPluginException {
        opened = false;
      } finally {
        _inviteOpen = false;
      }
    }
    if (!mounted || nonce != _pageNonce) return;
    await _controller.runJavaScript(
      'window.tongyeokReferralSmsResult?.(${jsonEncode(nonce)}, $id, $opened)',
    );
  }

  Future<void> _openUpdate(String message) async {
    final nonce = _pageNonce;
    if (!mounted || _updateOpen || nonce.isEmpty ||
        (message != '$nonce:ko' && message != '$nonce:mn')) {
      return;
    }
    if (!isAppUpdatePage(Uri.tryParse(await _controller.currentUrl() ?? '')) ||
        !mounted || nonce != _pageNonce || _updateOpen) {
      return;
    }
    final installed = await _installedVersion;
    if (!mounted || installed == null || nonce != _pageNonce || _updateOpen) return;
    _updateOpen = true;
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => AppUpdateScreen(
          android: _android,
          mongolian: message.endsWith(':mn'),
          installed: installed,
        ),
      ));
    } finally {
      _updateOpen = false;
    }
  }

  Future<void> _handleContactNames(String raw, String nonce) async {
    if (!mounted || _contactsBusy || nonce.isEmpty || raw.length > 14000) return;
    if (!_isContactsPage(await _controller.currentUrl()) ||
        !mounted || _contactsBusy || nonce != _pageNonce) {
      return;
    }
    Map<String, dynamic> request;
    try {
      request = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final id = request['id'];
    if (request['nonce'] != nonce || id is! String ||
        !RegExp(r'^\d{1,10}$').hasMatch(id)) {
      return;
    }
    _contactsBusy = true;
    Object? result;
    try {
      result = await _contactNames.request(request);
    } catch (_) {
      // Neither account tokens nor contact data belong in diagnostics.
    } finally {
      _contactsBusy = false;
    }
    if (!mounted || nonce != _pageNonce ||
        !_isContactsPage(await _controller.currentUrl()) || nonce != _pageNonce) {
      return;
    }
    await _controller.runJavaScript(
      'window.__tongyeokContactNamesResult?.('
      '${jsonEncode(nonce)},${jsonEncode(id)},${jsonEncode(result)});',
    );
  }

  Future<void> _handleSocial(String raw, String nonce) async {
    if (!mounted || _socialBusy || nonce != _pageNonce) return;
    final current = await _controller.currentUrl();
    final request = NativeSocialRequest.parse(
      raw,
      nonce,
      Uri.tryParse(current ?? ''),
    );
    if (request == null || nonce != _pageNonce || _socialBusy) return;
    _socialBusy = true;
    String? token;
    try {
      token = await _socialDevice.signIn(request);
    } catch (_) {
      // Account credentials and provider errors stay out of WebView logs.
    } finally {
      _socialBusy = false;
    }
    final page = Uri.tryParse(await _controller.currentUrl() ?? '');
    if (!mounted ||
        nonce != _pageNonce ||
        page == null ||
        !isTrustedTongyeokPage(page)) {
      return;
    }
    await _controller.runJavaScript(
      'window.__tongyeokSocialLoginComplete?.('
      '${jsonEncode(nonce)},${jsonEncode(request.id)},${jsonEncode(token)});',
    );
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
        android: _android,
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
      final code =
          failure is FirebaseException
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

  Future<void> _handleAndroidBack() async {
    if (_backBusy) return;
    _backBusy = true;
    try {
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        return;
      }
      if (!mounted) return;
      final (question, yes, no) = switch (Localizations.localeOf(
        context,
      ).languageCode) {
        'mn' => ('Аппаас гарах уу?', 'Тийм', 'Үгүй'),
        'en' => ('Exit Tongyeok Talk?', 'Yes', 'No'),
        _ => ('앱을 종료하시겠습니까?', '예', '아니요'),
      };
      final exit = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(question),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(no),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(yes),
                ),
              ],
            ),
      );
      if (mounted && exit == true) await SystemNavigator.pop();
    } finally {
      _backBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mongolian = Localizations.localeOf(context).languageCode == 'mn';
    final shell = Scaffold(
      body: SafeArea(
        child: Column(
          children: [
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
    if (!_android) {
      return shell;
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleAndroidBack();
      },
      child: shell,
    );
  }
}

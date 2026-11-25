import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'reward_platform.dart' as native_reward;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;

const rewardAdsTestMode = bool.fromEnvironment(
  'TONGYEOK_ADS_TEST_MODE',
  defaultValue: true,
);
const rewardPlaybackTest =
    kDebugMode &&
    rewardAdsTestMode &&
    bool.fromEnvironment('TONGYEOK_AD_PLAYBACK_TEST');
const _androidTestUnit = 'ca-app-pub-3940256099942544/5224354917';
const _localBackend = String.fromEnvironment('TONGYEOK_REWARD_BACKEND');
const _liveBackend =
    'https://asia-northeast3-tongyeok-talk-lab-20261024.cloudfunctions.net/rewardApi';
const _hostedAppOrigin = 'https://tongyeok-talk-lab-20261024.web.app';
bool get rewardAdsSupported => kIsWeb
    ? native_reward.supported
    : defaultTargetPlatform == TargetPlatform.android;
bool get effectiveRewardTestMode =>
    kIsWeb ? native_reward.testMode : rewardAdsTestMode;
bool get rewardPreviewOnly =>
    rewardPlaybackTest || (kIsWeb && effectiveRewardTestMode);
String get rewardBackend {
  if (_localBackend.isEmpty) {
    return kIsWeb && Uri.base.origin == _hostedAppOrigin
        ? _hostedAppOrigin
        : _liveBackend;
  }
  final uri = Uri.tryParse(_localBackend);
  if (kReleaseMode ||
      !rewardAdsTestMode ||
      uri == null ||
      uri.scheme != 'http' ||
      uri.host != '127.0.0.1') {
    throw StateError('adUnavailable');
  }
  return _localBackend;
}

class RewardSession {
  final String id, adUnitId;
  const RewardSession(this.id, this.adUnitId);
  factory RewardSession.fromJson(Map<String, dynamic> data) {
    final id = data['sessionId'] as String? ?? '';
    final unit = data['adUnitId'] as String? ?? '';
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        !unit.startsWith('ca-app-pub-')) {
      throw StateError('adUnavailable');
    }
    return RewardSession(id, unit);
  }
}

class RewardAdService {
  static bool _showing = false;
  static Future<void>? _initialization;
  static Future<void> _consent() async {
    final updated = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => updated.complete(),
      (error) => updated.completeError(StateError('adConsentFailed')),
    );
    await updated.future.timeout(const Duration(seconds: 30));
    final form = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error == null) {
        form.complete();
      } else {
        form.completeError(StateError('adConsentFailed'));
      }
    });
    await form.future.timeout(const Duration(seconds: 60));
    if (!await ConsentInformation.instance.canRequestAds()) {
      throw StateError('adConsentFailed');
    }
    _initialization ??= MobileAds.instance.initialize().then((_) {});
    await _initialization;
  }

  static Future<RewardSession> _session(User user) async {
    try {
      final token = await user.getIdToken();
      final response = await http
          .post(
            Uri.parse('$rewardBackend/sessions'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'testAds': effectiveRewardTestMode,
              'platform': kIsWeb ? native_reward.platform : 'android',
            }),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final code = data['error'];
        throw StateError(
          code == 'reward_rate_limited' || code == 'reward_daily_limit'
              ? 'adRateLimited'
              : code == 'reward_account_not_enabled'
              ? 'adNotEnabled'
              : 'adBackendUnavailable',
        );
      }
      return RewardSession.fromJson(data);
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('adBackendUnavailable');
    }
  }

  static Future<void> _completeLocalTest(User user, String sessionId) async {
    // A loopback-only developer fixture. Never sends this request in release,
    // on a public server, or for real ad units. Real rewards require Google SSV.
    if (kReleaseMode || !rewardAdsTestMode || _localBackend.isEmpty) return;
    final base = Uri.parse(rewardBackend);
    if (base.host != '127.0.0.1' || base.scheme != 'http') return;
    final token = await user.getIdToken();
    final response = await http
        .post(
          Uri.parse('$rewardBackend/test-completions'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'sessionId': sessionId}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError('adBackendUnavailable');
  }

  /// The client callback only updates the waiting UI. It NEVER writes rewards.
  static Future<bool> watch({
    required User user,
    required void Function(String) onSession,
  }) async {
    if (!rewardAdsSupported || _showing) throw StateError('adUnavailable');
    _showing = true;
    RewardedAd? ad;
    try {
      if (kIsWeb) {
        await native_reward.prepare(user.uid);
        if (effectiveRewardTestMode) {
          // Sample playback never creates a payable server session.
          final random = Random.secure();
          final previewId = List.generate(
            32,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
          return await native_reward.show(
            user.uid,
            previewId,
            'ca-app-pub-3940256099942544/1712485313',
            true,
          );
        }
        final session = await _session(user);
        onSession(session.id);
        return await native_reward.show(
          user.uid,
          session.id,
          session.adUnitId,
          effectiveRewardTestMode,
        );
      }
      await _consent();
      final session = rewardPlaybackTest ? null : await _session(user);
      final unit = session?.adUnitId ?? _androidTestUnit;
      if (rewardAdsTestMode && unit != _androidTestUnit) {
        throw StateError('adUnavailable');
      }
      final loaded = Completer<RewardedAd>();
      var abandoned = false;
      RewardedAd.load(
        adUnitId: unit,
        request: const AdRequest(nonPersonalizedAds: true),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (value) {
            if (abandoned) {
              value.dispose();
            } else {
              loaded.complete(value);
            }
          },
          onAdFailedToLoad: (_) {
            if (!loaded.isCompleted) {
              loaded.completeError(StateError('adLoadFailed'));
            }
          },
        ),
      );
      try {
        ad = await loaded.future.timeout(const Duration(seconds: 45));
      } catch (_) {
        abandoned = true;
        rethrow;
      }
      if (session != null) {
        await ad.setServerSideOptions(
          ServerSideVerificationOptions(
            userId: user.uid,
            customData: session.id,
          ),
        );
        onSession(session.id);
      }
      final dismissed = Completer<bool>();
      var earned = false;
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (_) {
          if (!dismissed.isCompleted) dismissed.complete(earned);
        },
        onAdFailedToShowFullScreenContent: (_, error) {
          if (!dismissed.isCompleted) {
            dismissed.completeError(StateError('adLoadFailed'));
          }
        },
      );
      await ad.show(
        onUserEarnedReward: (_, reward) {
          earned = true;
          if (kDebugMode) debugPrint('TT_AD_REWARD_EARNED');
        },
      );
      final completed = await dismissed.future;
      if (completed && session != null) {
        await _completeLocalTest(user, session.id);
      }
      return completed;
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('adLoadFailed');
    } finally {
      ad?.dispose();
      _showing = false;
    }
  }

  static Future<void> privacyOptions() async {
    if (!rewardAdsSupported) return;
    if (kIsWeb) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('adUnavailable');
      await native_reward.privacy(user.uid);
      return;
    }
    final complete = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error == null) {
        complete.complete();
      } else {
        complete.completeError(StateError('adConsentFailed'));
      }
    });
    await complete.future;
  }
}

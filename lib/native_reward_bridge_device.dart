import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'native_reward_bridge_protocol.dart';

class NativeRewardBridgeDevice {
  static const _diagnostics = bool.fromEnvironment(
    'TONGYEOK_IOS_AD_DIAGNOSTICS',
  );
  bool _ready = false;
  final Set<String> _used = {};
  Future<void>? _initialization;

  Future<void> _prepare() async {
    // Keep ads contextual and disable the SDK's publisher first-party ID.
    await MobileAds.instance.setSameAppKeyEnabled(false);
    final updated = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => updated.complete(),
      (error) {
        debugPrint('TT_IOS_AD_CONSENT_UPDATE_FAILED code=${error.errorCode}');
        updated.completeError(StateError('adConsentFailed'));
      },
    );
    await updated.future.timeout(const Duration(seconds: 30));
    final form = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error == null) {
        form.complete();
      } else {
        debugPrint('TT_IOS_AD_CONSENT_FORM_FAILED');
        form.completeError(StateError('adConsentFailed'));
      }
    });
    await form.future.timeout(const Duration(seconds: 60));
    if (!await ConsentInformation.instance.canRequestAds()) {
      debugPrint('TT_IOS_AD_CONSENT_NOT_READY');
      throw StateError('adConsentFailed');
    }
    _initialization ??= MobileAds.instance.initialize().then((_) {});
    await _initialization;
    _ready = true;
    if (kDebugMode) debugPrint('TT_IOS_NATIVE_REWARD_READY');
  }

  Future<String> run(NativeRewardRequest request) async {
    if (request.action == 'prepare') {
      await _prepare();
      return 'ready';
    }
    if (request.action == 'privacy') {
      final done = Completer<void>();
      ConsentForm.showPrivacyOptionsForm((error) {
        if (error == null) {
          done.complete();
        } else {
          done.completeError(StateError('adConsentFailed'));
        }
      });
      await done.future.timeout(const Duration(seconds: 60));
      return 'done';
    }
    if (!_ready || !_used.add(request.sessionId!)) {
      throw StateError('adUnavailable');
    }
    if (_used.length > 64) _used.remove(_used.first);
    RewardedAd? ad;
    var abandoned = false;
    try {
      final loaded = Completer<RewardedAd>();
      RewardedAd.load(
        adUnitId: request.adUnitId!,
        request: const AdRequest(nonPersonalizedAds: true),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (value) {
            if (kDebugMode) debugPrint('TT_IOS_NATIVE_REWARD_LOADED');
            if (abandoned) {
              value.dispose();
            } else if (!loaded.isCompleted) {
              loaded.complete(value);
            }
          },
          onAdFailedToLoad: (error) {
            debugPrint(
              'TT_IOS_AD_LOAD_FAILED domain=${error.domain} code=${error.code}',
            );
            if (_diagnostics) {
              debugPrint('TT_IOS_AD_LOAD_MESSAGE ${error.message}');
            }
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
      await ad.setServerSideOptions(
        ServerSideVerificationOptions(
          userId: request.uid,
          customData: request.sessionId,
        ),
      );
      final dismissed = Completer<bool>();
      var earned = false;
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (_) {
          if (kDebugMode) debugPrint('TT_IOS_NATIVE_REWARD_SHOWN');
        },
        onAdDismissedFullScreenContent: (_) {
          if (!dismissed.isCompleted) dismissed.complete(earned);
        },
        onAdFailedToShowFullScreenContent: (_, error) {
          debugPrint(
            'TT_IOS_AD_SHOW_FAILED domain=${error.domain} code=${error.code}',
          );
          if (!dismissed.isCompleted) {
            dismissed.completeError(StateError('adLoadFailed'));
          }
        },
      );
      await ad.show(
        onUserEarnedReward: (_, reward) {
          earned = true;
          if (kDebugMode) {
            debugPrint(
              request.testAds
                  ? 'TT_IOS_NATIVE_REWARD_SAMPLE_EARNED_NO_CREDIT'
                  : 'TT_IOS_NATIVE_REWARD_EARNED_WAIT_SERVER',
            );
          }
        },
      );
      // This result only updates the waiting UI. Google SSV grants all credit.
      return await dismissed.future.timeout(const Duration(minutes: 2))
          ? 'earned'
          : 'dismissed';
    } finally {
      ad?.dispose();
    }
  }
}

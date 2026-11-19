// Developer-only sample ad. This probe cannot grant rewards and is never
// included in the normal shell unless an explicit compile-time flag is set.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'native_reward_bridge_device.dart';
import 'native_reward_bridge_protocol.dart';

const iosAdProbeEnabled = bool.fromEnvironment('TONGYEOK_IOS_AD_PROBE');
const iosAdAutoProbe = bool.fromEnvironment('TONGYEOK_IOS_AD_AUTO_TEST');
const iosNativeRewardProbe = bool.fromEnvironment('TONGYEOK_IOS_REWARD_BRIDGE_PROBE');
const iosSampleRewardUnit = 'ca-app-pub-3940256099942544/1712485313';

class IosRewardAdProbe extends StatefulWidget {
  const IosRewardAdProbe({super.key});
  @override
  State<IosRewardAdProbe> createState() => _IosRewardAdProbeState();
}

class _IosRewardAdProbeState extends State<IosRewardAdProbe> {
  bool busy = false;
  String message = '';
  @override
  void initState() {
    super.initState();
    if (kDebugMode && iosAdProbeEnabled && iosAdAutoProbe) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) showSample(); });
    }
  }
  Future<void> showSample() async {
    if (!kDebugMode || !iosAdProbeEnabled || busy) return;
    setState(() { busy = true; message = ''; });
    RewardedAd? ad;
    try {
      if (iosNativeRewardProbe) {
        // Debug-only SDK integration probe. It uses Google's sample unit and
        // a synthetic session, with no backend request or entitlement writes.
        const nonce = 'simulator_reward_nonce_12345678901234567890';
        const uid = 'QA_simulator_reward_20261119';
        final page = Uri.https('dntprbs-maker.github.io', '/tongyeok-talk/');
        final device = NativeRewardBridgeDevice();
        final prepare = NativeRewardRequest.parse(jsonEncode({
          'id':'r1','action':'prepare','nonce':nonce,'uid':uid,
        }), nonce, page, testMode:true)!;
        await device.run(prepare);
        final show = NativeRewardRequest.parse(jsonEncode({
          'id':'r2','action':'show','nonce':nonce,'uid':uid,
          'sessionId':'a'*64,'adUnitId':iosRewardSampleUnit,'testAds':true,
        }), nonce, page, testMode:true)!;
        await device.run(show);
        return;
      }
      await MobileAds.instance.initialize();
      final loaded = Completer<RewardedAd>();
      var abandoned = false;
      await RewardedAd.load(
        adUnitId: iosSampleRewardUnit,
        request: const AdRequest(nonPersonalizedAds: true),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (value) { debugPrint('TT_IOS_AD_LOADED'); if (abandoned) { value.dispose(); } else if (!loaded.isCompleted) { loaded.complete(value); } },
          onAdFailedToLoad: (_) { if (!loaded.isCompleted) loaded.completeError(StateError('load')); },
        ),
      );
      try { ad = await loaded.future.timeout(const Duration(seconds: 30)); }
      on TimeoutException { abandoned = true; rethrow; }
      final closed = Completer<void>();
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (_) => debugPrint('TT_IOS_AD_SHOWN'),
        onAdDismissedFullScreenContent: (_) { debugPrint('TT_IOS_AD_DISMISSED'); if (!closed.isCompleted) closed.complete(); },
        onAdFailedToShowFullScreenContent: (_, __) { if (!closed.isCompleted) closed.completeError(StateError('show')); },
      );
      await ad.show(onUserEarnedReward: (_, __) {
        debugPrint('TT_IOS_AD_EARNED_NO_REWARD');
        if (mounted) setState(() => message = '시험 광고 시청을 확인했습니다. 이용권은 지급하지 않습니다.');
      });
      await closed.future;
    } catch (_) {
      debugPrint('TT_IOS_AD_FAILED');
      if (mounted) setState(() => message = '시험 광고를 표시하지 못했습니다.');
    } finally {
      ad?.dispose();
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || !iosAdProbeEnabled) return const SizedBox.shrink();
    return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      FilledButton(onPressed: busy ? null : showSample, child: const Text('시험 광고 보기')),
      if (message.isNotEmpty) Text(message),
    ]));
  }
}

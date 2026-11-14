// Developer-only sample ad. This probe cannot grant rewards and is never
// included in the normal shell unless an explicit compile-time flag is set.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const iosAdProbeEnabled = bool.fromEnvironment('TONGYEOK_IOS_AD_PROBE');
const iosSampleRewardUnit = 'ca-app-pub-3940256099942544/1712485313';

class IosRewardAdProbe extends StatefulWidget {
  const IosRewardAdProbe({super.key});
  @override
  State<IosRewardAdProbe> createState() => _IosRewardAdProbeState();
}

class _IosRewardAdProbeState extends State<IosRewardAdProbe> {
  bool busy = false;
  String message = '';
  Future<void> showSample() async {
    if (!iosAdProbeEnabled || busy) return;
    setState(() { busy = true; message = ''; });
    RewardedAd? ad;
    try {
      await MobileAds.instance.initialize();
      final loaded = Completer<RewardedAd>();
      var abandoned = false;
      await RewardedAd.load(
        adUnitId: iosSampleRewardUnit,
        request: const AdRequest(nonPersonalizedAds: true),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (value) { if (abandoned) { value.dispose(); } else if (!loaded.isCompleted) { loaded.complete(value); } },
          onAdFailedToLoad: (_) { if (!loaded.isCompleted) loaded.completeError(StateError('load')); },
        ),
      );
      try { ad = await loaded.future.timeout(const Duration(seconds: 30)); }
      on TimeoutException { abandoned = true; rethrow; }
      final closed = Completer<void>();
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (_) { if (!closed.isCompleted) closed.complete(); },
        onAdFailedToShowFullScreenContent: (_, __) { if (!closed.isCompleted) closed.completeError(StateError('show')); },
      );
      await ad.show(onUserEarnedReward: (_, __) {
        if (mounted) setState(() => message = '시험 광고 시청을 확인했습니다. 이용권은 지급하지 않습니다.');
      });
      await closed.future;
    } catch (_) {
      if (mounted) setState(() => message = '시험 광고를 표시하지 못했습니다.');
    } finally {
      ad?.dispose();
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    if (!iosAdProbeEnabled) return const SizedBox.shrink();
    return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      FilledButton(onPressed: busy ? null : showSample, child: const Text('시험 광고 보기')),
      if (message.isNotEmpty) Text(message),
    ]));
  }
}

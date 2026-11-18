import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_language.dart';
import 'brand.dart';
import 'reward_ad_service.dart';
import 'reward_platform.dart' as reward_platform;

bool isRewardLeader(Map<String, dynamic>? profile) =>
    profile?['rewardQaRole'] != 'member' && AppLanguage.instance.code != 'mn';

DateTime? lastPassMinute(DateTime? expiration) => expiration
    ?.toUtc()
    .add(const Duration(hours: 9))
    .subtract(const Duration(microseconds: 1));

class RewardAdsSection extends StatefulWidget {
  const RewardAdsSection({super.key});
  @override
  State<RewardAdsSection> createState() => _RewardAdsSectionState();
}

class _RewardAdsSectionState extends State<RewardAdsSection> {
  late final void Function() _stopRewardListener;
  @override
  void initState() {
    super.initState();
    _stopRewardListener = reward_platform.listenAvailability(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stopRewardListener();
    super.dispose();
  }

  final _user = FirebaseAuth.instance.currentUser!;
  late final _profile =
      FirebaseFirestore.instance.doc('users/${_user.uid}').snapshots();
  late final _wallet =
      FirebaseFirestore.instance
          .doc('translationWallets/${_user.uid}')
          .snapshots();
  bool _busy = false;
  String? _message;
  String? _session;
  Future<void> _watch() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!rewardPlaybackTest) {
        await FirebaseFirestore.instance.doc('users/${_user.uid}').update({
          'preferredLanguage': AppLanguage.instance.profileLanguage,
        });
      }
      final earned = await RewardAdService.watch(
        user: _user,
        onSession: (id) {
          if (mounted) setState(() => _session = id);
        },
      );
      if (mounted) {
        setState(() {
          _message =
              !earned
                  ? 'adNotCompleted'
                  : rewardPreviewOnly
                  ? 'adPreviewCompleted'
                  : 'adVerifying';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _message =
                  error is StateError
                      ? error.message.toString()
                      : 'adLoadFailed',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _profile,
    builder: (context, profile) {
      final value = profile.data?.data();
      if (!rewardPlaybackTest && value?['rewardAdEnabled'] != true) {
        return const SizedBox.shrink();
      }
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _wallet,
        builder:
            (
              context,
              wallet,
            ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream:
                  _session == null
                      ? null
                      : FirebaseFirestore.instance
                          .doc('users/${_user.uid}/adRewardReceipts/$_session')
                          .snapshots(),
              builder: (context, receipt) {
                final w = wallet.data?.data() ?? {};
                final latest = receipt.data?.data();
                return RewardAdsPanel(
                  role: isRewardLeader(value) ? 'leader' : 'member',
                  availableCredits:
                      ((w['balance'] as num? ?? 0) -
                          (w['reserved'] as num? ?? 0)),
                  passUntil: (w['leaderPassUntil'] as Timestamp?)?.toDate(),
                  leaderAdProgress: w['leaderRewardAdProgress'] == 1 ? 1 : 0,
                  balanceLoading: !wallet.hasData && !wallet.hasError,
                  balanceError: wallet.hasError,
                  busy: _busy,
                  supported: rewardAdsSupported,
                  testMode: effectiveRewardTestMode,
                  message:
                      latest?['status'] == 'granted' &&
                              _message == 'adVerifying'
                          ? (latest?['amount'] == 0
                              ? 'adLeaderHalfway'
                              : 'adGranted')
                          : _message,
                  onWatch: _watch,
                  onPrivacy: () async {
                    try {
                      await RewardAdService.privacyOptions();
                    } catch (_) {
                      if (mounted) setState(() => _message = 'adConsentFailed');
                    }
                  },
                );
              },
            ),
      );
    },
  );
}

class RewardAdsPanel extends StatelessWidget {
  final String role;
  final num availableCredits;
  final DateTime? passUntil;
  final int leaderAdProgress;
  final bool busy, supported, testMode, balanceLoading, balanceError;
  final String? message;
  final VoidCallback onWatch, onPrivacy;
  const RewardAdsPanel({
    super.key,
    required this.role,
    required this.availableCredits,
    this.passUntil,
    this.leaderAdProgress = 0,
    this.balanceLoading = false,
    this.balanceError = false,
    required this.busy,
    required this.supported,
    required this.testMode,
    this.message,
    required this.onWatch,
    required this.onPrivacy,
  });
  @override
  Widget build(BuildContext context) {
    final leader = role == 'leader';
    final lastUsableMinute = lastPassMinute(passUntil);
    final theme = Theme.of(context);
    final balance =
        leader
            ? lastUsableMinute == null
                ? tr(context, 'adNoPass')
                : tr(context, 'adPassUntil', {
                  'month': '${lastUsableMinute.month}',
                  'day': '${lastUsableMinute.day}',
                  'hour': '${lastUsableMinute.hour}',
                  'minute': lastUsableMinute.minute.toString().padLeft(2, '0'),
                })
            : tr(context, 'adCreditCount', {'count': '$availableCredits'});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F1FE),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(Icons.translate, color: brandColor, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        context,
                        leader ? 'adKoreanProduct' : 'adMongolianProduct',
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (balanceLoading)
                      const LinearProgressIndicator()
                    else ...[
                      Text(
                        balanceError
                            ? tr(context, 'creditUnavailable')
                            : balance,
                        style: (leader
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.headlineMedium)
                            ?.copyWith(
                              color: brandColor,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!leader) ...[
          const SizedBox(height: 8),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const RadialGradient(
                      colors: [Color(0xFFDEE6FF), Colors.transparent],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(
                        'assets/images/reward-ticket.png',
                        excludeFromSemantics: true,
                      ),
                      Text(
                        tr(context, 'adCreditCount', {'count': '50'}),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          shadows: [
                            Shadow(color: Color(0x660F175C), blurRadius: 8),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ] else
          const SizedBox(height: 24),
        Text(
          tr(context, leader ? 'adLeaderOffer' : 'adMemberOffer'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        if (testMode)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              tr(context, 'adTestMode'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: brandColor,
            minimumSize: const Size.fromHeight(54),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: busy || !supported ? null : onWatch,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(
            tr(
              context,
              busy
                  ? 'adLoading'
                  : leader
                  ? (leaderAdProgress == 1 ? 'adWatchSecond' : 'adWatchDay')
                  : 'adWatchCredits',
            ),
            textAlign: TextAlign.center,
          ),
        ),
        if (!supported) Text(tr(context, 'adAndroidOnly')),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(tr(context, message!), textAlign: TextAlign.center),
          ),
        if (supported)
          TextButton(
            onPressed: busy ? null : onPrivacy,
            child: Text(tr(context, 'adPrivacyOptions')),
          ),
      ],
    );
  }
}

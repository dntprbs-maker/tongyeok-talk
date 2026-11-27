import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_language.dart';
import 'credit_warning.dart';
import 'reward_ads_section.dart' show lastPassMinute;

import 'package:intl/intl.dart';

class TranslationWallet extends StatefulWidget {
  final bool compact;
  final bool balanceOnly;
  final bool showLeaderPass;
  const TranslationWallet({
    super.key,
    this.compact = false,
    this.balanceOnly = false,
    this.showLeaderPass = false,
  });
  @override
  State<TranslationWallet> createState() => _TranslationWalletState();
}

class _TranslationWalletState extends State<TranslationWallet> {
  late final _wallet = FirebaseFirestore.instance
      .collection('translationWallets')
      .doc(FirebaseAuth.instance.currentUser!.uid)
      .snapshots();
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _wallet,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Text(tr(context, 'creditUnavailable'));
      if (!snapshot.hasData) {
        return widget.balanceOnly
            ? const SizedBox(width: 80, child: LinearProgressIndicator())
            : const LinearProgressIndicator();
      }
      final data = snapshot.data!.data() ?? {},
          balance = data['balance'] as num? ?? 0,
          reserved = data['reserved'] as num? ?? 0;
      final available = balance - reserved;
      final formattedBalance = NumberFormat('0.###').format(available);
      if (widget.compact) {
        if (widget.balanceOnly) {
          if (widget.showLeaderPass) {
            return HomePassSummary(
              expiry: (data['leaderPassUntil'] as Timestamp?)?.toDate(),
            );
          }
          final label = tr(context, 'translationCredits');
          final value = tr(context, 'adCreditCount', {
            'count': formattedBalance,
          });
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    color: available <= creditUrgentThreshold
                        ? Colors.red.shade700
                        : const Color(0xFF101A3D),
                  ),
                ),
              ),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Text(
            '${tr(context, 'translationCredits')}: $formattedBalance${available <= creditWarningThreshold ? ' · ${tr(context, creditWarningKey(available))}' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: available <= creditUrgentThreshold
                  ? Colors.red.shade700
                  : Colors.black87,
            ),
          ),
        );
      }
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.translate),
        title: Text('${tr(context, 'translationCredits')}: $formattedBalance'),
        subtitle: Text(
          '${tr(context, snapshot.data!.exists ? creditWarningKey(available) : 'creditNotActive')}${reserved > 0 ? '\n${tr(context, 'creditReserved')}' : ''}',
          style: TextStyle(
            color: available <= creditUrgentThreshold
                ? Colors.red.shade700
                : available <= creditWarningThreshold
                ? Colors.orange.shade900
                : null,
            fontWeight: available <= creditWarningThreshold
                ? FontWeight.w600
                : null,
          ),
        ),
      );
    },
  );
}

class HomePassSummary extends StatefulWidget {
  const HomePassSummary({super.key, required this.expiry, this.now});

  final DateTime? expiry;
  final DateTime? now;

  @override
  State<HomePassSummary> createState() => _HomePassSummaryState();
}

int remainingPassDays(DateTime? expiry, DateTime now) {
  if (expiry == null || !expiry.isAfter(now)) return 0;
  final last = lastPassMinute(expiry);
  if (last == null) return 0;
  final kstNow = now.toUtc().add(const Duration(hours: 9));
  final today = DateTime.utc(kstNow.year, kstNow.month, kstNow.day);
  final lastDay = DateTime.utc(last.year, last.month, last.day);
  final diff = lastDay.difference(today).inDays;
  if (diff < 0) return 0;
  return diff + 1;
}

class _HomePassSummaryState extends State<HomePassSummary>
    with WidgetsBindingObserver {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = widget.now ?? DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant HomePassSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiry != widget.expiry || oldWidget.now != widget.now) {
      _now = widget.now ?? DateTime.now();
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _now = widget.now ?? DateTime.now());
      _schedule();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (widget.now != null) return;
    if (remainingPassDays(widget.expiry, _now) <= 0) return;

    final nowUtc = DateTime.now().toUtc();
    final kst = nowUtc.add(const Duration(hours: 9));
    var target = DateTime.utc(
      kst.year,
      kst.month,
      kst.day,
    ).add(const Duration(days: 1)).subtract(const Duration(hours: 9));

    final expiry = widget.expiry?.toUtc();
    if (expiry != null && expiry.isAfter(nowUtc) && expiry.isBefore(target)) {
      target = expiry;
    }

    final delay = target.difference(nowUtc);
    if (delay <= Duration.zero) return;
    _timer = Timer(delay, _onTick);
  }

  void _onTick() {
    if (!mounted) return;
    setState(() => _now = widget.now ?? DateTime.now());
    _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = remainingPassDays(widget.expiry, _now);
    final last = lastPassMinute(widget.expiry);

    final String title;
    if (days <= 0) {
      title = '${tr(context, 'passPeriod')} · ${tr(context, 'adNoPass')}';
    } else if (days == 1) {
      title = '${tr(context, 'passPeriod')} · ${tr(context, 'passUntilToday')}';
    } else {
      title =
          '${tr(context, 'passPeriod')} '
          '${tr(context, 'passDaysLeft', {'days': '$days'})}';
    }

    final titleStyle =
        (theme.textTheme.headlineSmall ??
                theme.textTheme.titleLarge ??
                const TextStyle())
            .copyWith(fontSize: 20, fontWeight: FontWeight.w800);

    final dateStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          textAlign: TextAlign.left,
          softWrap: true,
          style: titleStyle,
        ),
        if (days > 0 && last != null) ...[
          const SizedBox(height: 2),
          Text(
            tr(context, 'passUntilFullDate', {
              'year': '${last.year}',
              'month': '${last.month}',
              'day': '${last.day}',
            }),
            textAlign: TextAlign.left,
            softWrap: true,
            style: dateStyle,
          ),
        ],
      ],
    );
  }
}

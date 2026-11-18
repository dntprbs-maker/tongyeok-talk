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
  late final _wallet =
      FirebaseFirestore.instance
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
          final pass = (data['leaderPassUntil'] as Timestamp?)?.toDate();
          final lastDay = lastPassMinute(pass);
          final leader = widget.showLeaderPass;
          final label = tr(
            context,
            leader ? 'adPassDeadline' : 'translationCredits',
          );
          final value =
              !leader
                  ? tr(context, 'adCreditCount', {'count': formattedBalance})
                  : lastDay == null || !pass!.isAfter(DateTime.now())
                  ? tr(context, 'adNoPass')
                  : tr(context, 'adPassDay', {
                    'month': '${lastDay.month}',
                    'day': '${lastDay.day}',
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
                    fontSize: leader ? 22 : 28,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    color:
                        !leader && available <= creditUrgentThreshold
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
              color:
                  available <= creditUrgentThreshold
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
            color:
                available <= creditUrgentThreshold
                    ? Colors.red.shade700
                    : available <= creditWarningThreshold
                    ? Colors.orange.shade900
                    : null,
            fontWeight:
                available <= creditWarningThreshold ? FontWeight.w600 : null,
          ),
        ),
      );
    },
  );
}

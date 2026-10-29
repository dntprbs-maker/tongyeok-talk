import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_language.dart';
import 'credit_warning.dart';

class TranslationWallet extends StatefulWidget {
  final bool compact;
  const TranslationWallet({super.key, this.compact = false});
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
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final data = snapshot.data!.data() ?? {},
          balance = (data['balance'] as num? ?? 0).toInt(),
          reserved = (data['reserved'] as num? ?? 0).toInt();
      final available = balance - reserved;
      if (widget.compact) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Text(
            '${tr(context, 'translationCredits')}: $available${available <= creditWarningThreshold ? ' · ${tr(context, creditWarningKey(available))}' : ''}',
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
        title: Text(
          '${tr(context, 'translationCredits')}: ${balance - reserved}',
        ),
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

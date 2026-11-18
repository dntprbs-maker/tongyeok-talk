import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_language.dart';
import 'reward_ads_section.dart';

/// Keeps the tested charging panel separate from unrelated account settings.
class RewardAdsScreen extends StatelessWidget {
  const RewardAdsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'watchAds'))),
    body:
        FirebaseAuth.instance.currentUser == null
            ? Center(child: Text(tr(context, 'profileMissing')))
            : const Center(
              child: SizedBox(
                width: 700,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: RewardAdsSection(),
                ),
              ),
            ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'auth_screen.dart';
import 'recent_conversations_screen.dart';
import 'new_conversation_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'app_language.dart';
import 'brand.dart';
import 'read_receipts.dart';

final _navigatorKey = GlobalKey<NavigatorState>();
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLanguage.instance.initialize();
  await initializeDateFormatting('ko');
  await initializeDateFormatting('mn');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  var user = await FirebaseAuth.instance.authStateChanges().first;
  if (user != null &&
      !(await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get())
          .exists) {
    await FirebaseAuth.instance.signOut();
    user = null;
  }
  runApp(MyApp(isLoggedIn: user != null));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});
  @override
  Widget build(BuildContext context) => LanguageScope(
    child: AnimatedBuilder(
      animation: AppLanguage.instance,
      builder:
          (context, _) => MaterialApp(
            navigatorKey: _navigatorKey,
            navigatorObservers: [chatRouteObserver],
            title: AppLanguage.instance.text('app'),
            debugShowCheckedModeBanner: false,
            locale: Locale(AppLanguage.instance.code),
            supportedLocales: const [Locale('ko'), Locale('mn')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            onGenerateInitialRoutes:
                (_) => [
                  MaterialPageRoute<void>(
                    settings: RouteSettings(
                      name: isLoggedIn ? '/recentConversations' : '/',
                    ),
                    builder:
                        (_) =>
                            isLoggedIn
                                ? RecentConversationsScreen()
                                : const HomeScreen(),
                  ),
                ],
            initialRoute: isLoggedIn ? '/recentConversations' : '/',
            routes: {
              '/': (_) => const HomeScreen(),
              '/auth':
                  (context) => AuthScreen(
                    isSignUp:
                        ModalRoute.of(context)?.settings.arguments as bool? ??
                        false,
                  ),
              '/recentConversations': (_) => RecentConversationsScreen(),
              '/newConversation': (_) => const NewConversationScreen(),
              '/settings': (_) => const SettingsScreen(),
            },
            builder:
                (context, child) => Column(
                  children: [
                    Material(
                      color: const Color(0xFFF0F2FC),
                      child: SafeArea(
                        bottom: false,
                        child: SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            child: Text(
                              tr(context, 'preview'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF414967),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: child ?? const SizedBox()),
                  ],
                ),
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: brandColor),
              scaffoldBackgroundColor: Colors.white,
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.white,
              ),
              inputDecorationTheme: InputDecorationTheme(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
              ),
            ),
          ),
    ),
  );
}

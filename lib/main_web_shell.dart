// Isolated prototype. Advertising and notifications are not yet wired.
// Do not use as a release entry point until device and bridge tests pass.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'mobile_web_navigation.dart';

void main() => runApp(const MaterialApp(
  supportedLocales: [Locale('ko'), Locale('mn'), Locale('en')],
  home: TongyeokWebShell(),
));

class TongyeokWebShell extends StatefulWidget {
  const TongyeokWebShell({super.key});
  @override
  State<TongyeokWebShell> createState() => _TongyeokWebShellState();
}

class _TongyeokWebShellState extends State<TongyeokWebShell> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          return uri != null && isTrustedTongyeokPage(uri)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onPageStarted: (_) { if (mounted) setState(() { _loading = true; _failed = false; }); },
        onPageFinished: (_) { if (mounted) setState(() => _loading = false); },
        onWebResourceError: (error) {
          if (mounted && error.isForMainFrame == true) {
            setState(() { _failed = true; _loading = false; });
          }
        },
      ))
      ..loadRequest(Uri.parse('https://dntprbs-maker.github.io/tongyeok-talk/'));
  }
  @override
  Widget build(BuildContext context) {
    final mongolian = Localizations.localeOf(context).languageCode == 'mn';
    return Scaffold(body: SafeArea(child: Stack(children: [
      WebViewWidget(controller: _controller),
      if (_loading) const Center(child: CircularProgressIndicator()),
      if (_failed) ColoredBox(color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(mongolian ? 'Хуудсыг нээж чадсангүй. Интернэтээ шалгана уу.' : '화면을 불러오지 못했습니다. 인터넷 연결을 확인해 주세요.'),
          TextButton(onPressed: () => _controller.reload(), child: Text(mongolian ? 'Дахин оролдох' : '다시 시도')),
        ]))),
    ])));
  }
}

import 'package:flutter/material.dart';
import 'app_language.dart';

const brandColor = Color(0xFF3346B8);
const _brandImage = 'assets/images/interpreter-talk.png';

class BrandBarTitle extends StatelessWidget {
  const BrandBarTitle({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.asset(
          _brandImage,
          width: 26,
          height: 26,
          excludeFromSemantics: true,
        ),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            tr(context, 'app'),
            maxLines: 1,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    ],
  );
}

class BrandHeader extends StatelessWidget {
  final bool compact;
  const BrandHeader({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 24 : 32),
        child: Image.asset(
          _brandImage,
          width: compact ? 88 : 132,
          height: compact ? 88 : 132,
          semanticLabel: tr(context, 'app'),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        tr(context, 'app'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: compact ? 26 : 34,
          fontWeight: FontWeight.w800,
          color: brandColor,
        ),
      ),
      const Text(
        'Interpreter Talk',
        style: TextStyle(color: Colors.black54, fontSize: 14),
      ),
    ],
  );
}

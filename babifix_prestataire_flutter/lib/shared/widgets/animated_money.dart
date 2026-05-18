/// AnimatedMoney — affiche un montant en FCFA avec tween smooth + format
/// "12 345 F CFA" + emphase visuelle sur l'incrément.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AnimatedMoney extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final Duration duration;
  final String suffix;

  const AnimatedMoney({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 650),
    this.suffix = ' F CFA',
  });

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat.decimalPattern('fr_FR');
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(
        '${f.format(v.round())}$suffix',
        style: style,
      ),
    );
  }
}

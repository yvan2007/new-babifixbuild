import 'package:flutter/material.dart';
import '../../babifix_design_system.dart';

/// Fenetre modale inferieure unifiee BABIFIX (poignee, bordure fine, safe area).
Future<T?> showBabifixModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  Color? backgroundColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.54),
    builder: (ctx) => BabifixSheetFrame(
      backgroundColor: backgroundColor,
      child: builder(ctx),
    ),
  );
}

class BabifixSheetFrame extends StatelessWidget {
  const BabifixSheetFrame({
    super.key,
    required this.child,
    this.backgroundColor,
    this.padding,
  });

  final Widget child;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? BabifixDesign.elevatedSurfaceOf(context);
    final border = BabifixDesign.borderOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: BabifixDesign.textMutedOf(context).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Flexible(
                child: Padding(
                  padding: padding ?? EdgeInsets.zero,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

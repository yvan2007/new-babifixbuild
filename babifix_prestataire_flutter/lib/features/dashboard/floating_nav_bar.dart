import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

class MessagesNavBadge extends StatelessWidget {
  const MessagesNavBadge({super.key, this.notifier});

  final ValueNotifier<int>? notifier;

  @override
  Widget build(BuildContext context) {
    final n = notifier;
    if (n == null) {
      return const Icon(Icons.chat_bubble_outline_rounded);
    }
    return ValueListenableBuilder<int>(
      valueListenable: n,
      builder: (context, count, _) {
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded),
            if (count > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: count > 9 ? 5 : 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Barre de navigation inf\u00e9rieure \u00ab pilule \u00bb \u2014 m\u00eame principe que l\u2019app client BABIFIX.
class PrestataireFloatingNavBar extends StatelessWidget {
  const PrestataireFloatingNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.isLight,
    this.unreadChat,
    this.onMessagesOpened,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool isLight;
  final ValueNotifier<int>? unreadChat;
  final VoidCallback? onMessagesOpened;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isLight
                    ? const [Color(0xEEF8FAFF), Color(0xEEEFF4FF)]
                    : const [Color(0xE6232A3A), Color(0xE1161B2A)],
              ),
              border: Border.all(
                color: isLight ? const Color(0x220F172A) : const Color(0x55FFFFFF),
              ),
              boxShadow: [
                BoxShadow(
                  color: isLight ? const Color(0x220F172A) : const Color(0x66000000),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                _PrestataireFloatingNavItem(
                  selected: selectedIndex == 0,
                  isLight: isLight,
                  icon: Icons.home_rounded,
                  label: 'Accueil',
                  onTap: () => onSelect(0),
                ),
                _PrestataireFloatingNavItem(
                  selected: selectedIndex == 1,
                  isLight: isLight,
                  icon: Icons.calendar_month_rounded,
                  label: 'Exigences',
                  onTap: () => onSelect(1),
                ),
                _PrestataireFloatingNavItem(
                  selected: selectedIndex == 2,
                  isLight: isLight,
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Gains',
                  onTap: () => onSelect(2),
                ),
                _PrestataireFloatingNavItem(
                  selected: selectedIndex == 3,
                  isLight: isLight,
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Messages',
                  onTap: () {
                    onMessagesOpened?.call();
                    onSelect(3);
                  },
                  iconOverride: MessagesNavBadge(notifier: unreadChat),
                ),
                _PrestataireFloatingNavItem(
                  selected: selectedIndex == 4,
                  isLight: isLight,
                  icon: Icons.person,
                  label: 'Profil',
                  onTap: () => onSelect(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrestataireFloatingNavItem extends StatelessWidget {
  const _PrestataireFloatingNavItem({
    required this.selected,
    required this.isLight,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconOverride,
  });

  final bool selected;
  final bool isLight;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? iconOverride;

  @override
  Widget build(BuildContext context) {
    final iconOff = isLight ? const Color(0xFF475569) : const Color(0xFFB4BAC7);
    final textOff = isLight ? const Color(0xFF334155) : const Color(0xFFB4BAC7);
    final textOn = isLight ? const Color(0xFF0F172A) : Colors.white;
    final iconOn = isLight ? const Color(0xFF0369A1) : const Color(0xFF9FE6FF);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x4D8FE3FF), Color(0x1F8FE3FF)],
                  )
                : null,
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x440EB8FF),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 18 : 0,
                height: 3,
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: isLight ? const Color(0xFF0284C7) : const Color(0xFFA6EBFF),
                ),
              ),
              iconOverride != null
                  ? SizedBox(
                      height: 21,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: iconOverride!,
                      ),
                    )
                  : Icon(
                      icon,
                      size: 21,
                      color: selected ? iconOn : iconOff,
                    ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? textOn : textOff,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

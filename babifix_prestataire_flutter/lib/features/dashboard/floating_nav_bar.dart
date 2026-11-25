import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Compteur global de NOUVELLES demandes (exigences) — alimenté par main.dart
/// (FCM + chargement) et remis à 0 quand l'onglet Exigences est ouvert. Lu
/// directement par la nav bar → pas besoin de le câbler dans chaque écran.
final ValueNotifier<int> babifixNewRequestsCount = ValueNotifier<int>(0);

/// « Tick » global de rafraîchissement des réservations. Incrémenté par main.dart
/// à CHAQUE événement temps réel touchant une réservation (statut, devis,
/// acompte, démarrage, fin…). Les écrans ouverts (Demandes, Dashboard) l'écoutent
/// et rechargent leurs données → plus besoin de tirer pour rafraîchir.
final ValueNotifier<int> babifixReservationsTick = ValueNotifier<int>(0);

/// Référence de réservation à OUVRIR (détail) après un tap sur une notification.
/// main.dart la positionne (clic notif → section Demandes) et l'écran Demandes
/// l'écoute pour ouvrir directement la bonne réservation, puis la remet à null.
final ValueNotifier<String?> babifixOpenReservationRef =
    ValueNotifier<String?>(null);

class MessagesNavBadge extends StatelessWidget {
  const MessagesNavBadge({
    super.key,
    this.notifier,
    this.icon = Icons.chat_bubble_outline_rounded,
    this.iconColor,
    this.iconSize = 21,
  });

  final ValueNotifier<int>? notifier;
  final IconData icon;
  final Color? iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final n = notifier;
    if (n == null) {
      return Icon(icon, size: iconSize, color: iconColor);
    }
    return ValueListenableBuilder<int>(
      valueListenable: n,
      builder: (context, count, _) {
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, size: iconSize, color: iconColor),
            if (count > 0)
              Positioned(
                right: -8,
                top: -6,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: count > 9 ? 4.5 : 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
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

/// Barre de navigation inferieure flottante BABIFIX PRO.
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
    final isWhiteBg =
        Theme.of(context).scaffoldBackgroundColor == const Color(0xFFFFFFFF);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              color: isWhiteBg
                  ? const Color(0xFAFFFFFF)
                  : (isLight
                      ? const Color(0xF5FFFFFF)
                      : const Color(0xEC101F3B)),
              border: Border.all(
                color: isLight
                    ? const Color(0x140F172A)
                    : const Color(0x24FFFFFF),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isLight
                      ? const Color(0x120B1B34)
                      : const Color(0x52000000),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
                    icon: Icons.assignment_rounded,
                    label: 'Missions',
                    onTap: () => onSelect(1),
                    badgeNotifier: babifixNewRequestsCount,
                  ),
                  _PrestataireFloatingNavItem(
                    selected: selectedIndex == 2,
                    isLight: isLight,
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Wallet',
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
                    badgeNotifier: unreadChat,
                  ),
                  _PrestataireFloatingNavItem(
                    selected: selectedIndex == 4,
                    isLight: isLight,
                    icon: Icons.person_outline_rounded,
                    label: 'Profil',
                    onTap: () => onSelect(4),
                  ),
                ],
              ),
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
    this.badgeNotifier,
  });

  final bool selected;
  final bool isLight;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ValueNotifier<int>? badgeNotifier;

  @override
  Widget build(BuildContext context) {
    final iconOff = isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
    final textOff = isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8);
    final textOn = isLight ? const Color(0xFF0B1B34) : Colors.white;
    final iconOn = isLight ? const Color(0xFFE87722) : const Color(0xFF4CC9F0);
    final activeIconColor = selected ? iconOn : iconOff;
    final pillFill = selected
        ? (isLight
            ? const Color(0xFF0B1B34).withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.08))
        : Colors.transparent;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: const Cubic(0.23, 1, 0.32, 1),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: pillFill,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 18 : 0,
                height: 2.5,
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: iconOn,
                ),
              ),
              badgeNotifier != null
                  ? MessagesNavBadge(
                      notifier: badgeNotifier,
                      icon: icon,
                      iconColor: activeIconColor,
                      iconSize: 21,
                    )
                  : Icon(
                      icon,
                      size: 21,
                      color: activeIconColor,
                    ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
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

/// Rendu unifié des messages de chat BABIFIX (Phase C).
///
/// Distingue 3 types :
/// - USER       : bulle classique (gauche/droite selon expéditeur)
/// - DEVIS_CARD : carte large rendue par [DevisCardWidget]
/// - SYSTEM     : événement centré rendu par [SystemEventWidget]
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../babifix_design_system.dart';
import '../../models/babifix_models.dart';
import 'babifix_phase_widgets.dart';

class ChatMessageRenderer extends StatelessWidget {
  final ChatMessage message;
  final int currentUserId;

  const ChatMessageRenderer({
    super.key,
    required this.message,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    switch (message.kind) {
      case MessageKind.system:
        return SystemEventWidget.fromMessage(message);
      case MessageKind.devisCard:
        if (message.payloadJson != null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: DevisCardWidget.fromPayload(
              message.payloadJson!,
              compact: true,
            ),
          );
        }
        return _userBubble();
      case MessageKind.user:
        return _userBubble();
    }
  }

  Widget _userBubble() {
    final mine = message.senderId == currentUserId;
    final f = DateFormat('HH:mm');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!mine) const SizedBox(width: 4),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: mine
                    ? BabifixDesign.ciBlue
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(mine ? 14 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.body,
                    style: TextStyle(
                      color: mine ? Colors.white : Colors.grey.shade900,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                  if (message.createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      f.format(message.createdAt!.toLocal()),
                      style: TextStyle(
                        color: (mine
                                ? Colors.white
                                : Colors.grey.shade600)
                            .withValues(alpha: 0.85),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (mine) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

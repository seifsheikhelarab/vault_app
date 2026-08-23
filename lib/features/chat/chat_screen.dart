import 'package:flutter/material.dart';

import '../../core/ui/empty_state.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: EmptyState(
          icon: Icons.chat_bubble_outline,
          title: 'Turn words into an expense',
          message:
              'Type a purchase and Vault drafts it for you. Parsing ships soon.',
        ),
      ),
    );
  }
}

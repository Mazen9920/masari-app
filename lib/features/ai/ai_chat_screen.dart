import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../l10n/app_localizations.dart';

class AiChatScreen extends StatefulWidget {
  final String contextType;

  const AiChatScreen({super.key, required this.contextType});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _ChatMessage {
  final String text;
  final bool isUser;

  _ChatMessage({required this.text, required this.isUser});
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  
  final List<_ChatMessage> _messages = [];
  bool _initialized = false;

  List<String> _suggestions(AppLocalizations l10n) {
    switch (widget.contextType) {
      case 'CashFlow':
        return [
          l10n.aiSuggestCashFlow1,
          l10n.aiSuggestCashFlow2,
          l10n.aiSuggestCashFlow3,
        ];
      case 'ProfitLoss':
        return [
          l10n.aiSuggestProfit1,
          l10n.aiSuggestProfit2,
          l10n.aiSuggestProfit3,
        ];
      case 'Categories':
        return [
          l10n.aiSuggestCategory1,
          l10n.aiSuggestCategory2,
          l10n.aiSuggestCategory3,
        ];
      default:
        return [
          l10n.aiSuggestDefault1,
          l10n.aiSuggestDefault2,
          l10n.aiSuggestDefault3,
        ];
    }
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    
    setState(() {
      _messages.add(_ChatMessage(text: text.trim(), isUser: true));
      _msgCtrl.clear();
    });
    
    _scrollToBottom();
    
    // Simulate AI typing delay
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            text: AppLocalizations.of(context)!.aiPreviewResponse,
            isUser: false,
          ));
        });
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!_initialized) {
      _initialized = true;
      _messages.add(_ChatMessage(text: l10n.aiGreeting, isUser: false));
    }
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFFE67E22), size: 20),
            const SizedBox(width: 8),
            Text(l10n.aiTitle, style: AppTypography.h3),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE67E22).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                l10n.aiPreview,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE67E22),
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.primaryNavy),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: AppColors.borderLight, height: 1.0),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Chat History
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildMessageBubble(msg);
                },
              ),
            ),
            
            // Smart Suggestions
            if (_messages.length == 1) // Only show at the start
              SizedBox(
                height: 48,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _suggestions(l10n).length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions(l10n)[index];
                    return ActionChip(
                      label: Text(suggestion, style: const TextStyle(fontSize: 13)),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: AppColors.borderLight),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _sendMessage(suggestion);
                      },
                    );
                  },
                ),
              ),
            
            // Input Area
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _msgCtrl,
                              decoration: InputDecoration(
                                hintText: l10n.aiHint,
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              style: const TextStyle(fontSize: 15),
                              onSubmitted: _sendMessage,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.mic_none_rounded, color: Colors.grey),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.aiVoiceSoon)));
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _sendMessage(_msgCtrl.text);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE67E22), // Orange
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!msg.isUser) ...[
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE67E22).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: Color(0xFFE67E22), size: 16),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: msg.isUser ? AppColors.primaryNavy : Colors.white,
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomRight: msg.isUser ? const Radius.circular(4) : const Radius.circular(20),
                  topLeft: !msg.isUser ? const Radius.circular(4) : const Radius.circular(20),
                ),
                border: msg.isUser ? null : Border.all(color: AppColors.borderLight),
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  color: msg.isUser ? Colors.white : AppColors.textPrimary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (msg.isUser) const SizedBox(width: 24), // Spacer for user message
        ],
      ),
    );
  }
}

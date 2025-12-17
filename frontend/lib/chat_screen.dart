import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_math_fork/flutter_math.dart';

class ChatScreen extends StatefulWidget {
  // --- NEW PARAMETERS ADDED HERE ---
  final String baseUrl;
  final String problemContext;
  final String historyId;
  final String? initialMessage;
  final bool isHintMode; 

  const ChatScreen({
    super.key, 
    required this.baseUrl,      // <--- Fixes the 'baseUrl' error
    required this.problemContext, 
    required this.historyId,
    this.initialMessage,
    this.isHintMode = false,    // <--- Fixes the 'isHintMode' error
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchChatHistory();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _fetchChatHistory() async {
    try {
      // Use the passed baseUrl
      final response = await http.get(Uri.parse("${widget.baseUrl}/api/history/${widget.historyId}"));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List history = data['chat_history'] ?? [];
        
        setState(() {
          _messages = List<Map<String, dynamic>>.from(history);
          _isLoading = false;
        });
        bool _initialHintSent = false;
        // If history is empty and we have an initial message (Hint Mode), send it automatically
if (_messages.isEmpty && widget.initialMessage != null && !_initialHintSent) {
  _initialHintSent = true;
  _sendMessage(manualText: widget.initialMessage, isHidden: true);
} else {
           _scrollToBottom();
        }
      }
    } catch (e) {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _clearChat() async {
    setState(() { _messages.clear(); });
    try {
      await http.delete(Uri.parse("${widget.baseUrl}/api/history/${widget.historyId}/chat"));
    } catch (e) {
      // Handle error silently
    }
  }

  // isHidden = true means we don't show the user's prompt in the bubble (good for "Give me a hint")
  Future<void> _sendMessage({String? manualText, bool isHidden = false}) async {
    final text = manualText ?? _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      if (!isHidden) {
        _messages.add({"role": "user", "text": text});
      }
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final response = await http.put(
      Uri.parse("${widget.baseUrl}/api/history/${widget.historyId}"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
      "chat_history": _messages,
      "mode": widget.isHintMode ? "hint" : "tutor"
      }),
      );

      
      final data = jsonDecode(response.body);
      final reply = data['reply'] ?? "Error connecting to AI.";

      setState(() {
        _messages.add({"role": "model", "text": reply});
        _isLoading = false;
      });
      _scrollToBottom();

      // Sync with DB
      await http.put(
        Uri.parse("${widget.baseUrl}/api/history/${widget.historyId}"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({ "chat_history": _messages }),
      );

    } catch (e) {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Theme Colors based on Mode
    final Color themeColor = widget.isHintMode ? Colors.orange : const Color(0xFF5C87FF);
    final String title = widget.isHintMode ? "AI Hint Helper" : "AI Tutor";

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: themeColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _clearChat,
            tooltip: "Reset Chat",
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && !_isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(widget.isHintMode ? Icons.lightbulb_outline : Icons.chat_bubble_outline, size: 60, color: Colors.grey[300]),
                        const SizedBox(height: 10),
                        Text(
                          widget.isHintMode ? "Asking for a hint..." : "Ask me anything about the math!",
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(15),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg['role'] == "user";
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(16),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                          decoration: BoxDecoration(
                            color: isUser ? themeColor : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(20),
                              topRight: const Radius.circular(20),
                              bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(0),
                              bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(20),
                            ),
                            boxShadow: [
                              BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))
                            ],
                          ),
                          child: isUser 
                            ? Text(msg['text']!, style: const TextStyle(color: Colors.white, fontSize: 16))
                            : ChatMathRenderer(text: msg['text']!), 
                        ),
                      );
                    },
                  ),
          ),
          
          if (_isLoading) 
             Padding(
               padding: const EdgeInsets.all(8.0),
               child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: themeColor),
             ),
          
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller, 
                    decoration: InputDecoration(
                      hintText: widget.isHintMode ? "Ask for clarification..." : "Type your question...",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FloatingActionButton(
                  mini: true,
                  onPressed: () => _sendMessage(),
                  backgroundColor: themeColor,
                  child: const Icon(Icons.send, color: Colors.white, size: 20),
                  elevation: 2,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// Math Renderer for Chat (reused logic)
class ChatMathRenderer extends StatelessWidget {
  final String text;
  const ChatMathRenderer({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    List<InlineSpan> spans = [];
    List<String> parts = text.split(r'$');

    for (int i = 0; i < parts.length; i++) {
      String part = parts[i];
      if (i % 2 == 1 && part.trim().isNotEmpty) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              part,
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          )
        ));
      } else {
        spans.add(TextSpan(
          text: part,
          style: const TextStyle(fontSize: 16, color: Colors.black87, height: 1.4),
        ));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }
}
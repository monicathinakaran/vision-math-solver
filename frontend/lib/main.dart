import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'chat_screen.dart'; 

// --- CONFIGURATION ---
class Config {
  // Use 'http://10.0.2.2:8000' for Android Emulator
  // Use 'https://xolver-backend.onrender.com' for Production
  static const String baseUrl = "http://192.168.1.13:8000"; 
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xolver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF5C87FF), 
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFE0E7FF),
          onPrimaryContainer: Color(0xFF00215E),
          secondary: Color(0xFFFF5EB3), 
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFFFD6ED),
          onSecondaryContainer: Color(0xFF3E001D),
          tertiary: Color(0xFFFFCA28), 
          onTertiary: Colors.black,
          surface: Colors.white,
          onSurface: Color(0xFF1C1B1F),
          error: Color(0xFFBA1A1A),
          onError: Colors.white,
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  XFile? _image;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _equationController = TextEditingController();

  bool _isUploading = false;
  bool _isSolving = false;
  bool _isStartingHint = false; // Loading state for hint button
  bool _showEditor = false;
  
  String? _solution;
  String? _explanation;
  String? _errorMessage;
  String? _currentHistoryId;

  // --- HELPER: CLEAN MATH STRING ---
  String cleanMath(String input) {
    return input.replaceAll(r'$', '').replaceAll(r'\[', '').replaceAll(r'\]', '');
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _image = pickedFile;
        _equationController.text = "";
        _solution = null;
        _explanation = null;
        _errorMessage = null;
        _currentHistoryId = null;
        _showEditor = false;
      });
      _processImage(pickedFile);
    }
  }

  Future<void> _processImage(XFile image) async {
    setState(() { _isUploading = true; _errorMessage = null; });
    
    try {
      var request = http.MultipartRequest("POST", Uri.parse("${Config.baseUrl}/api/extract"));
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('error')) {
           setState(() { _errorMessage = "AI Error: ${data['error']}"; _isUploading = false; });
        } else {
           setState(() {
             _equationController.text = data['equation'] ?? "";
             _showEditor = true;
             _isUploading = false;
           });
        }
      } else {
        setState(() { _errorMessage = "Server Error: ${response.statusCode}"; _isUploading = false; });
      }
    } catch (e) {
      setState(() { _errorMessage = "Connection Error: $e"; _isUploading = false; });
    }
  }

  // --- MODE A: SOLVE FULLY ---
  Future<void> _solveEquation() async {
    setState(() { _isSolving = true; _errorMessage = null; });
    try {
      // 1. Calculate
      final response = await http.post(
        Uri.parse("${Config.baseUrl}/api/calculate"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({ "equation": _equationController.text }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('error')) {
           setState(() { _errorMessage = "Solver Error: ${data['error']}"; _isSolving = false; });
           return;
        }

        final solution = data['solution'];
        final explanation = data['explanation'];

        // 2. Save (Get ID)
        final historyResponse = await http.post(
           Uri.parse("${Config.baseUrl}/api/history"),
           headers: {"Content-Type": "application/json"},
           body: jsonEncode({
             "equation": _equationController.text,
             "solution": solution,
             "explanation": explanation
           })
        );

        String? newHistoryId;
        if (historyResponse.statusCode == 200) {
           final historyData = jsonDecode(historyResponse.body);
           newHistoryId = historyData['id']; 
        }

        setState(() {
          _solution = solution;
          _explanation = explanation;
          _currentHistoryId = newHistoryId;
          _isSolving = false;
        });

      } else {
        setState(() { _errorMessage = "Server Error: ${response.statusCode}"; _isSolving = false; });
      }
    } catch (e) {
      setState(() { _errorMessage = "Connection Error: $e"; _isSolving = false; });
    }
  }

Future<void> _startHintSession() async {
    setState(() { _isStartingHint = true; _errorMessage = null; });

    try {
      // We don't solve it. We just register the problem in DB to get an ID for the chat.
      final historyResponse = await http.post(
         Uri.parse("${Config.baseUrl}/api/history"),
         headers: {"Content-Type": "application/json"},
         body: jsonEncode({
           "equation": _equationController.text,
           "solution": "Hint Session", 
           "explanation": "User requested hints only."
         })
      );

      if (historyResponse.statusCode == 200) {
         final historyData = jsonDecode(historyResponse.body);
         String hintId = historyData['id'];
         
         // Navigate immediately
         if (mounted) {
           _openChat(forcedId: hintId, isHint: true);
         }
      } else {
        setState(() { _errorMessage = "Could not start hint session"; });
      }
    } catch (e) {
      // --- CRITICAL LOGGING ADDED HERE ---
      print("CRITICAL CONNECTION ERROR: $e"); 
      setState(() { _errorMessage = "Connection Error: $e"; });
    } finally {
      setState(() { _isStartingHint = false; });
    }
  }

  // Helper to open chat
  void _openChat({String? forcedId, bool isHint = false}) {
    final idToUse = forcedId ?? _currentHistoryId;

    if (idToUse == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: No Session ID.")));
      return;
    }
    
    String? initialMsg = isHint 
        ? "I am stuck on this problem: ${_equationController.text}. Please give me a small hint for the first step. Do NOT solve it completely." 
        : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          baseUrl: Config.baseUrl,
          problemContext: "Problem: ${_equationController.text}\nSolution: $_solution",
          historyId: idToUse,
          initialMessage: initialMsg,
          isHintMode: isHint,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final Color brandColor = colors.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: brandColor),
              accountName: const Text("Xolver Student"),
              accountEmail: const Text("student@xolver.ai"),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Color(0xFF5C87FF)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text("Dashboard"),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text("Ask AI to Solve"),
              selected: true,
              selectedColor: brandColor,
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text("History"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryScreen()));
              },
            ),
          ],
        ),
      ),

      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.white, 
            foregroundColor: Colors.black87,
            centerTitle: true,
            toolbarHeight: 100,
            title: Text("Xolver", style: TextStyle(color: brandColor, fontWeight: FontWeight.bold, fontSize: 28)),
            pinned: true,
            elevation: 1,
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // IMAGE PREVIEW
                  if (_image != null)
                    Container(
                      height: 200, 
                      margin: const EdgeInsets.only(bottom: 20, top: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 8))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(File(_image!.path), fit: BoxFit.cover),
                      ),
                    ),

                  if (_image == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 40.0, bottom: 40.0),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.add_a_photo_outlined, size: 60, color: Colors.grey[300]),
                            const SizedBox(height: 10),
                            Text("Tap Snap to Start", style: TextStyle(color: Colors.grey[400]))
                          ],
                        ),
                      ),
                    ),

                  if (_isUploading) 
                      const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),

                  // --- EDITOR SECTION ---
                  if (_showEditor && !_isUploading) ...[
                    TextField(
                      controller: _equationController,
                      maxLines: 5, 
                      minLines: 1, 
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(fontSize: 18, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        labelText: "Edit Equation",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // --- TWO BUTTONS: SOLVE & HINT ---
                    Row(
                      children: [
                        // SOLVE BUTTON
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 55,
                            child: FilledButton.icon(
                              onPressed: !_isSolving && !_isStartingHint ? _solveEquation : null,
                              icon: _isSolving 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                                : const Icon(Icons.auto_awesome),
                              label: Text(_isSolving ? "Solving..." : "SOLVE", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              style: FilledButton.styleFrom(backgroundColor: brandColor),
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        
                        // GET HINT BUTTON (Orange)
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 55,
                            child: ElevatedButton.icon(
                              onPressed: !_isSolving && !_isStartingHint ? _startHintSession : null,
                              icon: _isStartingHint 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                                : const Icon(Icons.lightbulb, color: Colors.white),
                              label: const Text("HINT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],

                  // --- RESULTS SECTION ---
                  if (_solution != null) ...[
                    Card(
                      elevation: 4,
                      color: const Color(0xFFE8F5E9), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            const Text("FINAL ANSWER", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green, letterSpacing: 1.5)),
                            const SizedBox(height: 15),
                            ...cleanMath(_solution!).split(r'\\').map((line) {
                              if (line.trim().isEmpty) return const SizedBox.shrink();
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Math.tex(
                                  line.trim(), 
                                  textStyle: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
                                  onErrorFallback: (err) => Text(line, style: const TextStyle(color: Colors.red)),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: MathExplanation(text: _explanation!),
                    ),
                    
                    const SizedBox(height: 25),

                    // --- ASK TUTOR BUTTON (Only appears after solving) ---
                    SizedBox(
                      height: 55,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openChat(isHint: false),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text("Ask AI Tutor for Doubts", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: brandColor, width: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 50),
                  ],

                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
          )
        ],
      ),
      
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickImage,
        label: const Text("SNAP"),
        icon: const Icon(Icons.camera_alt),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
      ),
    );
  }
}

// --- HISTORY SCREEN ---
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final response = await http.get(Uri.parse("${Config.baseUrl}/api/history"));
      if (response.statusCode == 200) {
        setState(() {
          _history = jsonDecode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("History"), backgroundColor: Colors.white, foregroundColor: Colors.black),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _history.isEmpty 
          ? const Center(child: Text("No history yet"))
          : ListView.builder(
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final item = _history[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  child: ListTile(
                    title: Text(item['equation'] ?? "Unknown Equation", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(item['timestamp'] ?? ""),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  ),
                );
              },
            ),
    );
  }
}

class MathExplanation extends StatelessWidget {
  final String text;
  const MathExplanation({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    double maxWidth = MediaQuery.of(context).size.width - 80;
    List<InlineSpan> spans = [];
    List<String> parts = text.split(r'$');

    for (int i = 0; i < parts.length; i++) {
      String part = parts[i];
      if (i % 2 == 1) { 
        if (part.trim().isNotEmpty) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Math.tex(
                    part,
                    textStyle: const TextStyle(fontSize: 16, color: Colors.black87),
                    onErrorFallback: (err) => Text(part, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                ),
              ),
            ),
          ));
        }
      } else { 
        List<String> boldParts = part.split(r'**');
        for (int j = 0; j < boldParts.length; j++) {
            bool isBold = (j % 2 == 1);
            spans.add(TextSpan(
              text: boldParts[j],
              style: TextStyle(
                fontSize: 16, 
                height: 1.5,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: isBold ? Theme.of(context).colorScheme.primary : Colors.black87,
              ),
            ));
        }
      }
    }
    return RichText(text: TextSpan(children: spans));
  }
}
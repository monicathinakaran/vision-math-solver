import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'chat_screen.dart'; // Make sure you import your ChatScreen file

// --- CONFIGURATION ---
class Config {
  // OPTION A: Android Emulator
  static const String baseUrl = "http://10.0.2.2:8000"; 
  
  // OPTION B: Physical Device (Use your PC's IP, e.g., 192.168.1.5)
  // static const String baseUrl = "http://192.168.1.X:8000"; 

  // OPTION C: Cloud (Render/AWS)
  // static const String baseUrl = "https://your-app.onrender.com"; 
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
  bool _showEditor = false;
  
  String? _solution;
  String? _explanation;
  String? _errorMessage;
  String? _currentHistoryId; // Storing ID for Chat

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
           setState(() { 
             _errorMessage = "AI Error: ${data['error']}"; 
             _isUploading = false; 
           });
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

  Future<void> _solveEquation() async {
    setState(() { _isSolving = true; _errorMessage = null; });
    
    try {
      // 1. Calculate Solution
      final response = await http.post(
        Uri.parse("${Config.baseUrl}/api/calculate"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({ "equation": _equationController.text }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data.containsKey('error')) {
           setState(() { 
             _errorMessage = "Solver Error: ${data['error']}"; 
             _isSolving = false; 
           });
           return;
        }

        final solution = data['solution'];
        final explanation = data['explanation'];

        // 2. Save to History (To get ID)
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

  void _openChat({bool isHint = false}) {
    if (_currentHistoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: No History ID found. Try solving again.")));
      return;
    }

    // If Hint Mode: Send a preset prompt
    // If Tutor Mode: Send null (so the user types their own question)
    String? initialMsg = isHint 
        ? "I am stuck. Please give me a small hint for the next step. Do not solve it completely." 
        : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          baseUrl: Config.baseUrl, // Pass config
          problemContext: "Problem: ${_equationController.text}\nSolution: $_solution",
          historyId: _currentHistoryId!,
          initialMessage: initialMsg,
          isHintMode: isHint, // Pass mode
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
      
      body: CustomScrollView(
        slivers: [
          // --- HEADER ---
          SliverAppBar(
            backgroundColor: Colors.white, 
            foregroundColor: Colors.black87,
            centerTitle: true,
            toolbarHeight: 120, // Adjusted height
            title: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                 // Replace with Image.asset('assets/Logo1.png') if you have it
                 Text("Xolver", style: TextStyle(color: brandColor, fontWeight: FontWeight.bold, fontSize: 28)),
                 const SizedBox(height: 5),
                 Text("Snap & Solve", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              ],
            ),
            pinned: true,
            elevation: 1,
          ),

          // --- MAIN CONTENT ---
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

                  // WELCOME PLACEHOLDER
                  if (_image == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 40.0, bottom: 40.0),
                      child: Center(
                        child: Icon(Icons.add_a_photo_outlined, size: 60, color: Colors.grey[300]),
                      ),
                    ),

                  // LOADING
                  if (_isUploading) 
                      const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),

                  // EDITOR
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
                    SizedBox(
                      height: 55,
                      child: FilledButton.icon(
                        onPressed: !_isSolving ? _solveEquation : null,
                        icon: _isSolving 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                          : const Icon(Icons.auto_awesome),
                        label: Text(_isSolving ? "Thinking..." : "SOLVE WITH AI", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(backgroundColor: brandColor),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],

                  // RESULTS
                  if (_solution != null) ...[
                    // Solution Card
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
                    
                    // Explanation
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

                    // --- ACTION BUTTONS (HINT & TUTOR) ---
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _openChat(isHint: true),
                            icon: const Icon(Icons.lightbulb, color: Colors.white),
                            label: const Text("Get Hint", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              elevation: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _openChat(isHint: false),
                            icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                            label: const Text("Ask Tutor", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: brandColor,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
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

// --- ROBUST MATH EXPLANATION WIDGET ---
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
        // Math Part
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
        // Text Part
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
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_math_fork/flutter_math.dart';

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
        
        // --- COLOR PALETTE (From Xolver Logo) ---
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          
          // 1. PRIMARY BLUE
          primary: Color(0xFF5C87FF), 
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFE0E7FF),
          onPrimaryContainer: Color(0xFF00215E),
          
          // 2. SECONDARY PINK
          secondary: Color(0xFFFF5EB3), 
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFFFD6ED),
          onSecondaryContainer: Color(0xFF3E001D),
          
          // 3. TERTIARY YELLOW
          tertiary: Color(0xFFFFCA28), 
          onTertiary: Colors.black,
          
          // 4. BACKGROUNDS
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

  // --- HELPER: CLEAN MATH STRING ---
  String cleanMath(String input) {
    // Removes $, \[, \] so the renderer doesn't crash
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
        _showEditor = false;
      });
      _processImage(pickedFile);
    }
  }

  Future<void> _processImage(XFile image) async {
    setState(() { _isUploading = true; _errorMessage = null; });
    // Use 10.0.2.2 for Android Emulator, or your PC's Local IP for real device
    const String apiUrl = "http://10.0.2.2:8000/api/extract";
    
    try {
      var request = http.MultipartRequest("POST", Uri.parse(apiUrl));
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
    const String apiUrl = "http://10.0.2.2:8000/api/calculate";
    
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
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
        } else {
           setState(() {
             _solution = data['solution'];
             _explanation = data['explanation'];
             _isSolving = false;
           });
        }
      } else {
        setState(() { _errorMessage = "Server Error: ${response.statusCode}"; _isSolving = false; });
      }
    } catch (e) {
      setState(() { _errorMessage = "Connection Error: $e"; _isSolving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final Color brandColor = colors.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      
      body: CustomScrollView(
        slivers: [
          // --- HEADER (White & Tall) ---
          SliverAppBar(
            backgroundColor: Colors.white, 
            foregroundColor: Colors.black87,
            centerTitle: true,
            
            // Increase height to fit the logo nicely
            toolbarHeight: 200, 
            
            title: Image.asset(
              'assets/Logo1.png', 
              height: 200, 
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                 return Text("Xolver", style: TextStyle(color: brandColor, fontWeight: FontWeight.bold, fontSize: 28));
              },
            ),
            
            expandedHeight: 0, 
            pinned: true,
            elevation: 1,
            shadowColor: Colors.grey.withOpacity(0.1),
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
                        color: Colors.white, 
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.15),
                            spreadRadius: 2,
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(File(_image!.path), fit: BoxFit.cover),
                      ),
                    ),

                  // WELCOME SCREEN
                  if (_image == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 60.0),
                      child: Column(
                        children: [
                          Icon(Icons.auto_awesome, size: 80, color: brandColor.withOpacity(0.5)),
                          const SizedBox(height: 30),
                          Text("Snap & Solve", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueGrey[800])),
                          const SizedBox(height: 10),
                          const Text("Your AI Math Companion", style: TextStyle(color: Colors.grey, fontSize: 16)),
                        ],
                      ),
                    ),

                  // LOADING
                  if (_isUploading) 
                     const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),

                  // EDITOR SECTION
                  if (_showEditor && !_isUploading) ...[
                    Row(
                      children: [
                        Icon(Icons.edit_note, color: Colors.blueGrey[700]),
                        const SizedBox(width: 8),
                        Text("CONFIRM EQUATION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey[700])),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _equationController,
                      // --- MULTI-LINE ENABLED ---
                      maxLines: 8, 
                      minLines: 1, 
                      keyboardType: TextInputType.multiline,
                      // --------------------------
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.all(20),
                        suffixIcon: const Icon(Icons.edit),
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
                        style: FilledButton.styleFrom(
                          backgroundColor: brandColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],

                  // RESULTS SECTION
                  if (_solution != null) ...[
                    // Solution Card
                    Card(
                      elevation: 4,
                      shadowColor: Colors.green.withOpacity(0.3),
                      color: const Color(0xFFE8F5E9), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            const Text("FINAL ANSWER", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green, letterSpacing: 1.5)),
                            const SizedBox(height: 15),
                            
                            // --- MULTI-LINE MATH RENDERER ---
                            ...cleanMath(_solution!).split(r'\\').map((line) {
                              if (line.trim().isEmpty) return const SizedBox.shrink();
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12.0),
                                width: double.infinity,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Math.tex(
                                    line.trim(), 
                                    textStyle: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
                                    onErrorFallback: (err) => Text(line, style: const TextStyle(color: Colors.red)),
                                  ),
                                ),
                              );
                            }).toList(),
                            // --------------------------------
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Explanation Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: MathExplanation(text: _explanation!),
                    ),
                    const SizedBox(height: 80),
                  ],

                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(top: 20),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red[900]))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          )
        ],
      ),
      
      // --- FAB ---
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickImage,
        label: const Text("SNAP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        icon: const Icon(Icons.camera_alt),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        elevation: 4,
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
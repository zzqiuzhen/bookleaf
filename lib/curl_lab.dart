// Web-only "shader lab": renders the page-curl shader over real page
// snapshots so the geometry can be tuned visually. Not part of the iOS app.
//
// Build:  flutter build web -t lib/curl_lab.dart -o build/web_lab
// Serve :  python -m http.server 8125 -d build/web_lab
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'ui/reader/curl.dart';

Future<ui.Image> _load(String url) {
  final completer = Completer<ui.Image>();
  final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
  stream.addListener(ImageStreamListener(
    (info, _) => completer.complete(info.image),
    onError: (e, _) => completer.completeError(e),
  ));
  return completer.future;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final p1 = await _load('pages/p1.png');
  final p2 = await _load('pages/p2.png');
  runApp(Lab(p1: p1, p2: p2));
}

class Lab extends StatefulWidget {
  const Lab({super.key, required this.p1, required this.p2});
  final ui.Image p1;
  final ui.Image p2;

  @override
  State<Lab> createState() => _LabState();
}

class _LabState extends State<Lab> {
  double radius = 0.030;
  double tilt = 0.10;
  bool forward = true;

  @override
  Widget build(BuildContext context) {
    const progresses = [0.06, 0.18, 0.32, 0.5, 0.7, 0.88];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF15161A),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    const Text('band',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: radius,
                        min: 0.03,
                        max: 0.24,
                        onChanged: (v) => setState(() => radius = v),
                      ),
                    ),
                    const Text('tilt',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: tilt,
                        min: -0.4,
                        max: 0.4,
                        onChanged: (v) => setState(() => tilt = v),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => forward = !forward),
                      child: Text(forward ? 'forward' : 'backward',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final p in progresses)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            children: [
                              SizedBox(
                                width: 240,
                                height: 519,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CustomPaint(
                                    painter: CurlPainter(
                                      current: forward ? widget.p1 : widget.p2,
                                      next: forward ? widget.p2 : widget.p1,
                                      progress: p,
                                      forward: forward,
                                      paperColor: const Color(0xFFFBF7EF),
                                      radiusFactor: radius,
                                      tilt: tilt,
                                    ),
                                  ),
                                ),
                              ),
                              Text('p=$p',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

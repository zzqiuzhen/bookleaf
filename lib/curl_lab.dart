// Dev-only "curl lab": renders the page-curl painter over real page snapshots
// so the geometry can be eyeballed without a device. Not part of the iOS app.
//
//   flutter build web -t lib/curl_lab.dart -o build/web_lab
//   python -m http.server 8125 -d build/web_lab
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'ui/reader/curl.dart';

Future<ui.Image> _load(String url) {
  final completer = Completer<ui.Image>();
  NetworkImage(url).resolve(ImageConfiguration.empty).addListener(
        ImageStreamListener(
          (info, _) => completer.complete(info.image),
          onError: (e, _) => completer.completeError(e),
        ),
      );
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
  double tilt = 0.0;

  static const progresses = [0.10, 0.30, 0.50, 0.72, 0.90];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF14151A),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    const Text('radius',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: radius,
                        min: 0.015,
                        max: 0.14,
                        onChanged: (v) => setState(() => radius = v),
                      ),
                    ),
                    const Text('tilt',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: tilt,
                        min: -0.35,
                        max: 0.35,
                        onChanged: (v) => setState(() => tilt = v),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('forward', true),
                      _row('backward', false),
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

  Widget _row(String label, bool fwd) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, top: 4, bottom: 2),
          child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        SizedBox(
          height: 300,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final p in progresses)
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: SizedBox(
                    width: 138,
                    height: 298,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CustomPaint(
                        painter: CurlPainter(
                          current: fwd ? widget.p1 : widget.p2,
                          next: fwd ? widget.p2 : widget.p1,
                          progress: ValueNotifier<double>(p),
                          forward: fwd,
                          paperColor: const Color(0xFFFBF7EF),
                          radiusFactor: radius,
                          tilt: tilt,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/sign_image_service.dart';

class WatchSignOverlayApp extends StatelessWidget {
  final SignImageService signImageService;

  const WatchSignOverlayApp({
    super.key,
    required this.signImageService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        textTheme: GoogleFonts.nunitoTextTheme(ThemeData.dark().textTheme),
      ),
      home: _OverlayBody(signImageService: signImageService),
    );
  }
}

class _OverlayBody extends StatefulWidget {
  final SignImageService signImageService;

  const _OverlayBody({
    required this.signImageService,
  });

  @override
  State<_OverlayBody> createState() => _OverlayBodyState();
}

class _OverlayBodyState extends State<_OverlayBody> {
  List<SignImageSegment> _segments = [];
  String _rawText = '';
  StreamSubscription<dynamic>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = FlutterOverlayWindow.overlayListener.listen(_handleData);
  }

  void _handleData(dynamic raw) {
    if (raw == null) return;

    try {
      final map = jsonDecode(raw.toString()) as Map<String, dynamic>;
      if (map['cmd'] == 'stop') {
        FlutterOverlayWindow.closeOverlay();
        return;
      }

      final keywords = map['text'] as String? ?? '';
      final rawText = map['rawText'] as String? ?? '';

      setState(() {
        _rawText = rawText;
        _segments = widget.signImageService.textToSegments(keywords);
      });
    } catch (_) {}
  }

  Future<void> _closeOverlay() async {
    try {
      await FlutterOverlayWindow.shareData(jsonEncode({'cmd': 'stop'}));
    } catch (_) {}

    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.sign_language_rounded,
                    color: Color(0xFFA29BFE),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _rawText.isEmpty ? 'VAANI Signs' : _rawText,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _closeOverlay,
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (_segments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Listening for audio…',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              )
            else
              SizedBox(
                height: 92,
                child: _CompactSignStrip(segments: _segments),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

// ── Compact horizontal sign strip for the overlay ────────────────────────────

class _CompactSignStrip extends StatelessWidget {
  final List<SignImageSegment> segments;

  const _CompactSignStrip({required this.segments});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: segments.length,
      separatorBuilder: (_, __) => const SizedBox(width: 4),
      itemBuilder: (_, i) {
        final seg = segments[i];
        if (seg.isWordSpace) return const SizedBox(width: 14);

        if (seg.isGif) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  seg.gifAssetPath!,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 64, height: 64),
                ),
              ),
              Text(
                seg.word!,
                style: const TextStyle(color: Color(0xFFA29BFE), fontSize: 9),
              ),
            ],
          );
        }

        if (seg.imageBytes == null) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.memory(
                seg.imageBytes!,
                width: 56,
                height: 56,
                fit: BoxFit.contain,
              ),
            ),
            Text(
              seg.char ?? '',
              style: const TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ],
        );
      },
    );
  }
}

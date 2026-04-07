import 'package:flutter/material.dart';

// Curated list of confirmed .gif assets in assets/sign_videos/
const List<({String gifPath, String label})> _kPanelSigns = [
  (gifPath: 'assets/sign_videos/Hello.gif',      label: 'Hello'),
  (gifPath: 'assets/sign_videos/ok.gif',         label: 'OK'),
  (gifPath: 'assets/sign_videos/Food.gif',       label: 'Food'),
  (gifPath: 'assets/sign_videos/Water.gif',      label: 'Water'),
  (gifPath: 'assets/sign_videos/Need.gif',       label: 'Need'),
  (gifPath: 'assets/sign_videos/think.gif',      label: 'Think'),
  (gifPath: 'assets/sign_videos/talk.gif',       label: 'Talk'),
  (gifPath: 'assets/sign_videos/know.gif',       label: 'Know'),
  (gifPath: 'assets/sign_videos/like.gif',       label: 'Like'),
  (gifPath: 'assets/sign_videos/feel.gif',       label: 'Feel'),
  (gifPath: 'assets/sign_videos/mad.gif',        label: 'Mad'),
  (gifPath: 'assets/sign_videos/funny.gif',      label: 'Funny'),
  (gifPath: 'assets/sign_videos/cool.gif',       label: 'Cool'),
  (gifPath: 'assets/sign_videos/beautiful.gif',  label: 'Beautiful'),
  (gifPath: 'assets/sign_videos/same.gif',       label: 'Same'),
  (gifPath: 'assets/sign_videos/say.gif',        label: 'Say'),
  (gifPath: 'assets/sign_videos/will.gif',       label: 'Will'),
  (gifPath: 'assets/sign_videos/see.gif',        label: 'See'),
  (gifPath: 'assets/sign_videos/up.gif',         label: 'Up'),
  (gifPath: 'assets/sign_videos/your.gif',       label: 'Your'),
];

class SignLanguagePanel extends StatelessWidget {
  final void Function(String gifPath, String label) onSignSelected;

  const SignLanguagePanel({super.key, required this.onSignSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111B21),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF2A3942),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.sign_language, color: Color(0xFF25D366), size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Sign Language',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, color: Color(0xFF8696A0), size: 22),
                ),
              ],
            ),
          ),
          // 3-column grid of signs
          SizedBox(
            height: 320,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
              ),
              itemCount: _kPanelSigns.length,
              itemBuilder: (context, index) {
                final sign = _kPanelSigns[index];
                return _SignPanelTile(
                  gifPath: sign.gifPath,
                  label: sign.label,
                  onTap: () => onSignSelected(sign.gifPath, sign.label),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SignPanelTile extends StatelessWidget {
  final String gifPath;
  final String label;
  final VoidCallback onTap;

  const _SignPanelTile({
    required this.gifPath,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F2C34),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A3942)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Image.asset(
                  gifPath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.sign_language,
                    color: Color(0xFF25D366),
                    size: 36,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

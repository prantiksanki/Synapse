import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  // Replace with your actual store URL when ready.
  static const String _buyUrl = 'https://synapse.app/shop';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConfig.obBackground,
      appBar: AppBar(
        backgroundColor: AppConfig.obBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppConfig.obPrimaryDark,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Shop',
          style: TextStyle(
            color: AppConfig.obTextPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Product card ──────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppConfig.obCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppConfig.obBorder, width: 1.3),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Product image
                    Container(
                      color: Colors.black,
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: Image.asset(
                        'assets/Product.jpeg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          height: 220,
                          child: Center(
                            child: Icon(Icons.image_not_supported_rounded,
                                color: Colors.white24, size: 56),
                          ),
                        ),
                      ),
                    ),

                    // Product details
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppConfig.obPrimary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppConfig.obPrimary.withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'VAANI Hardware',
                              style: TextStyle(
                                color: AppConfig.obPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Product name
                          const Text(
                            'VAANI Sign Language Device',
                            style: TextStyle(
                              color: AppConfig.obTextPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Short description
                          const Text(
                            'Real-time sign language detection hardware — worn on the hand. Works with the VAANI app over Wi-Fi for seamless communication between deaf and hearing users.',
                            style: TextStyle(
                              color: AppConfig.obTextSecondary,
                              fontSize: 13.5,
                              height: 1.55,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Feature pills
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: const [
                              _FeaturePill(
                                  icon: Icons.wifi_rounded, label: 'Wi-Fi'),
                              _FeaturePill(
                                  icon: Icons.battery_charging_full_rounded,
                                  label: 'Rechargeable'),
                              _FeaturePill(
                                  icon: Icons.sensors_rounded,
                                  label: 'On-Device AI'),
                              _FeaturePill(
                                  icon: Icons.handshake_rounded,
                                  label: 'ISL / ASL'),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Buy Now button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final uri = Uri.parse(_buyUrl);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri,
                                      mode: LaunchMode.externalApplication);
                                }
                              },
                              icon: const Icon(
                                  Icons.shopping_cart_checkout_rounded,
                                  size: 20),
                              label: const Text(
                                'Buy Now',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppConfig.obPrimary,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Info section ──────────────────────────────────────────────
              _InfoCard(
                icon: Icons.info_outline_rounded,
                title: 'About the Device',
                body:
                    'The VAANI hardware unit pairs with this app to capture hand gestures using on-device sensors. It streams landmark data over a local Wi-Fi hotspot, enabling real-time sign-to-text translation without any cloud dependency.',
              ),
              const SizedBox(height: 12),
              _InfoCard(
                icon: Icons.local_shipping_outlined,
                title: 'Shipping & Availability',
                body:
                    'Currently available for pre-order. Units will ship to verified addresses. Contact us at support@synapse.app for bulk or institutional orders.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Feature Pill ──────────────────────────────────────────────────────────────

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppConfig.obBorder.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppConfig.obBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppConfig.obPrimary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppConfig.obTextSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info Card ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard(
      {required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConfig.obCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppConfig.obBorder, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppConfig.obPrimary, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppConfig.obTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: AppConfig.obTextSecondary,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

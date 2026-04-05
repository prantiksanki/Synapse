import 'package:flutter/material.dart';

import '../config/app_config.dart';

class GradientScreen extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const GradientScreen({super.key, required this.child, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppConfig.premiumBackgroundTop, AppConfig.premiumBackgroundBottom],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class GlowButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final Color glowColor;
  final double height;

  const GlowButton({
    super.key,
    required this.child,
    required this.onTap,
    this.color = AppConfig.premiumPrimary,
    this.glowColor = AppConfig.premiumAccentCyan,
    this.height = 58,
  });

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.0,
      upperBound: 0.05,
    );
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  Future<void> _onTapDown(TapDownDetails details) async {
    await _animation.forward();
  }

  Future<void> _onTapUp(TapUpDetails details) async {
    await _animation.reverse();
  }

  Future<void> _onTapCancel() async {
    await _animation.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final scale = 1 - _animation.value;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: Transform.scale(
        scale: scale,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [widget.color, widget.glowColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withOpacity(0.45),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}

class SegmentItem<T> {
  final T value;
  final String label;
  final IconData icon;

  SegmentItem({required this.value, required this.label, required this.icon});
}

class SegmentedControl<T> extends StatelessWidget {
  final T selected;
  final List<SegmentItem<T>> segments;
  final ValueChanged<T> onValueChanged;

  const SegmentedControl({
    super.key,
    required this.selected,
    required this.segments,
    required this.onValueChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppConfig.premiumCard2,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppConfig.premiumBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: segments.map((segment) {
          final isActive = selected == segment.value;
          return Expanded(
            child: InkWell(
              onTap: () => onValueChanged(segment.value),
              borderRadius: BorderRadius.circular(24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: isActive ? AppConfig.premiumGreen : AppConfig.premiumCard,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(segment.icon,
                        size: 18,
                        color: isActive ? Colors.black : AppConfig.premiumTextSecondary),
                    const SizedBox(width: 6),
                    Text(
                      segment.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: isActive ? Colors.black : AppConfig.premiumTextSecondary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const PremiumCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppConfig.premiumCard, AppConfig.premiumCard2],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppConfig.premiumBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }
}

class ProfileCard extends StatelessWidget {
  final String displayName;
  final String username;
  final VoidCallback onEdit;

  const ProfileCard({super.key, required this.displayName, required this.username, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppConfig.premiumPrimary, AppConfig.premiumPurple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppConfig.premiumPurple.withOpacity(0.35),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -4,
                right: -4,
                child: GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppConfig.premiumCard2,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.2),
                    ),
                    child: const Icon(Icons.edit, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName.isNotEmpty ? displayName : 'Unnamed',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(height: 2),
                Text('@$username',
                    style: const TextStyle(
                        color: AppConfig.premiumTextSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const SettingRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppConfig.premiumCard2,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppConfig.premiumBorder, width: 1.0),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppConfig.premiumBackgroundTop.withOpacity(0.28),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppConfig.premiumPrimary, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                          color: AppConfig.premiumTextSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppConfig.premiumTextSecondary),
          ],
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final bool isOnline;
  final String label;

  const StatusBadge({super.key, required this.isOnline, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppConfig.premiumGreen : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNav({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavItem(icon: Icons.home_rounded, color: AppConfig.premiumGold, label: 'Home'),
      _NavItem(icon: Icons.call_rounded, color: AppConfig.premiumAccentCyan, label: 'Call'),
      _NavItem(icon: Icons.school_rounded, color: AppConfig.premiumPurple, label: 'Learn'),
      _NavItem(icon: Icons.storefront_rounded, color: AppConfig.premiumPink, label: 'Shop'),
      _NavItem(icon: Icons.settings_rounded, color: AppConfig.premiumTextSecondary, label: 'Settings'),
    ];

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8, top: 8),
      decoration: BoxDecoration(
        color: AppConfig.premiumBackgroundBottom.withOpacity(0.72),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22)),
        border: Border.all(color: AppConfig.premiumBorder, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final active = index == currentIndex;
          return GestureDetector(
            onTap: () => onTap(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              padding: EdgeInsets.symmetric(horizontal: active ? 14 : 10, vertical: 8),
              decoration: BoxDecoration(
                color: active ? item.color.withOpacity(0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon,
                      size: active ? 28 : 24,
                      color: active ? item.color : AppConfig.premiumTextSecondary.withOpacity(0.72)),
                  const SizedBox(height: 2),
                  if (active)
                    Text(item.label,
                        style: TextStyle(
                            color: item.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4)),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final Color color;
  final String label;

  _NavItem({required this.icon, required this.color, required this.label});
}

class SignCard extends StatelessWidget {
  final String label;
  final ImageProvider? image;
  final VoidCallback? onTap;

  const SignCard({super.key, required this.label, this.image, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 92,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppConfig.premiumCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppConfig.premiumBorder, width: 1),
        ),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                image: image != null ? DecorationImage(image: image!, fit: BoxFit.cover) : null,
                color: AppConfig.premiumBackgroundBottom.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: image == null
                  ? Icon(Icons.image_not_supported_rounded,
                      color: AppConfig.premiumMuted, size: 28)
                  : null,
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                  color: AppConfig.premiumTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const FeatureChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppConfig.premiumCard.withOpacity(0.84),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppConfig.premiumBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppConfig.premiumPrimary, size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                color: AppConfig.premiumTextSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

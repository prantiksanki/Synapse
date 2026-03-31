import 'package:flutter/material.dart';

enum NavTab { home, call, watch, tutorial, eeg, shop, settings }

class LiquidGlassNavBar extends StatefulWidget {
  final NavTab currentTab;
  final ValueChanged<NavTab> onTabChanged;

  const LiquidGlassNavBar({
    super.key,
    required this.currentTab,
    required this.onTabChanged,
  });

  @override
  State<LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<LiquidGlassNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _bubbleAnim;
  static const _tabs = [
    (tab: NavTab.home,     icon: Icons.home_rounded,              label: 'Home'),
    (tab: NavTab.call,     icon: Icons.call_rounded,              label: 'Call'),
    (tab: NavTab.watch,    icon: Icons.sign_language_rounded,     label: 'Watch'),
    (tab: NavTab.tutorial, icon: Icons.play_circle_outline_rounded, label: 'Tutorial'),
    (tab: NavTab.eeg,      icon: Icons.psychology_rounded,        label: 'EEG'),
    (tab: NavTab.shop,     icon: Icons.shopping_bag_rounded,      label: 'Shop'),
    (tab: NavTab.settings, icon: Icons.settings_rounded,          label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _bubbleAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(LiquidGlassNavBar old) {
    super.didUpdateWidget(old);
    if (old.currentTab != widget.currentTab) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomPad),
      decoration: const BoxDecoration(
        color: Color(0xFF1B1B20),
        border: Border(
          top: BorderSide(color: Color(0xFF2A2A32), width: 1),
        ),
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          children: _tabs.map((t) {
            final isSelected = widget.currentTab == t.tab;
            return Expanded(
              child: GestureDetector(
                onTap: () => widget.onTabChanged(t.tab),
                behavior: HitTestBehavior.opaque,
                child: AnimatedBuilder(
                  animation: _bubbleAnim,
                  builder: (context, _) {
                    return _NavItem(
                      icon: t.icon,
                      label: t.label,
                      isSelected: isSelected,
                      animValue: isSelected ? _bubbleAnim.value : 1.0,
                    );
                  },
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final double animValue;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.animValue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutBack,
          width: isSelected ? 52 : 40,
          height: isSelected ? 36 : 32,
          decoration: isSelected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFF58CC02),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF58CC02).withValues(alpha: 0.40),
                      blurRadius: 10,
                      spreadRadius: 0,
                      offset: const Offset(0, 3),
                    ),
                  ],
                )
              : null,
          child: Center(
            child: Transform.scale(
              scale: isSelected ? (0.85 + 0.15 * animValue) : 1.0,
              child: Icon(
                icon,
                size: isSelected ? 20 : 22,
                color: isSelected
                    ? Colors.white
                    : const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(
            fontSize: isSelected ? 10 : 9.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            color: isSelected ? Colors.white : const Color(0xFF6B7280),
            letterSpacing: isSelected ? 0.3 : 0,
          ),
          child: Text(label),
        ),
      ],
    );
  }
}

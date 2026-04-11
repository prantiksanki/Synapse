import 'package:flutter/material.dart';

enum NavTab { home, call, emergency, tutorial, shop, settings }

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
  late Animation<double> _scaleAnim;

  static const _tabs = [
    (tab: NavTab.home,     icon: Icons.home_rounded,                 color: Color(0xFFE8433A)),
    (tab: NavTab.call,     icon: Icons.phone_rounded,                color: Color(0xFF4CAF82)),
    (tab: NavTab.emergency, icon: Icons.warning_rounded,             color: Color(0xFFDC2626)),
    (tab: NavTab.tutorial, icon: Icons.play_lesson_rounded,          color: Color(0xFFB5651D)),
    (tab: NavTab.shop,     icon: Icons.shopping_bag_rounded,         color: Color(0xFFD63384)),
    (tab: NavTab.settings, icon: Icons.settings_rounded,             color: Color(0xFF9E9E9E)),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scaleAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
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
      color: const Color(0xFF1B1B20),
      child: SizedBox(
        height: 80,
        child: Row(
          children: _tabs.map((t) {
            final isSelected = widget.currentTab == t.tab;
            return Expanded(
              child: GestureDetector(
                onTap: () => widget.onTabChanged(t.tab),
                behavior: HitTestBehavior.opaque,
                child: AnimatedBuilder(
                  animation: _scaleAnim,
                  builder: (context, _) {
                    final scale = isSelected ? (0.80 + 0.20 * _scaleAnim.value) : 1.0;
                    return Center(
                      child: Transform.scale(
                        scale: scale,
                        child: _NavItem(
                          icon: t.icon,
                          iconColor: t.color,
                          isSelected: isSelected,
                        ),
                      ),
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
  final Color iconColor;
  final bool isSelected;

  const _NavItem({
    required this.icon,
    required this.iconColor,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      width: isSelected ? 72 : 52,
      height: isSelected ? 72 : 52,
      decoration: isSelected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: const Color(0xFF252529),
              border: Border.all(
                color: const Color(0xFF4CAF50),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.30),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            )
          : null,
      child: Center(
        child: Icon(
          icon,
          size: isSelected ? 40 : 34,
          color: isSelected ? iconColor : iconColor.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

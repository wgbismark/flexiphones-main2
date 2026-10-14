import 'package:flexiphones/shared_widgets/flexi_nav_bar.dart';
import 'package:flutter/material.dart';

/// Customer bottom bar (Home / Browse / Cart / Orders / Profile, plus an
/// Agent shortcut for agents). Guests get the first three, flat, next to
/// the "Buy Now" button.
class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final bool ofl;
  final Function(int) onTap;
  final List cartItems;
  final bool showAgentTab;
  final VoidCallback? onAgentTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.cartItems,
    required this.ofl,
    this.showAgentTab = false,
    this.onAgentTap,
  });

  @override
  Widget build(BuildContext context) {
    final includeAgentTab = showAgentTab && !ofl;
    return FlexiNavBar(
      floating: !ofl,
      currentIndex: currentIndex,
      onTap: (i) => onTap(i),
      items: [
        const FlexiNavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: "Home",
        ),
        const FlexiNavItem(
          icon: Icons.grid_view_outlined,
          activeIcon: Icons.grid_view_rounded,
          label: "Browse",
        ),
        FlexiNavItem(
          icon: Icons.shopping_bag_outlined,
          activeIcon: Icons.shopping_bag_rounded,
          label: "Bag",
          badge: cartItems.length,
        ),
        if (!ofl) ...[
          const FlexiNavItem(
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long_rounded,
            label: "Orders",
          ),
          const FlexiNavItem(
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            label: "Profile",
          ),
        ],
        if (includeAgentTab)
          FlexiNavItem(
            icon: Icons.workspace_premium_outlined,
            activeIcon: Icons.workspace_premium_rounded,
            label: "Agent",
            onTap: onAgentTap,
          ),
      ],
    );
  }
}

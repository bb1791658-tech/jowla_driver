import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jowla_driver/core/theme/app_theme.dart';
import 'package:jowla_driver/features/home/application/driver_home_controller.dart';
import 'package:jowla_driver/features/earnings/presentation/earnings_screen.dart';
import 'package:jowla_driver/features/home/presentation/home_screen.dart';
import 'package:jowla_driver/features/notifications/presentation/notifications_screen.dart';
import 'package:jowla_driver/features/profile/presentation/profile_screen.dart';

class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({super.key});

  @override
  ConsumerState<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<DriverShell> {
  var _index = 0;

  static const _screens = [
    HomeScreen(),
    EarningsScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(driverHomeControllerProvider);
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: _DriverBottomBar(
        selectedIndex: _index,
        state: home,
        onDestinationSelected: (value) => setState(() => _index = value),
        onWorkPressed: () => _toggleWork(home),
      ),
    );
  }

  void _toggleWork(DriverHomeState state) {
    final controller = ref.read(driverHomeControllerProvider.notifier);
    if (state.isOnline) {
      unawaited(controller.goOffline());
    } else {
      unawaited(controller.goOnline());
    }
  }
}

class _DriverBottomBar extends StatelessWidget {
  const _DriverBottomBar({
    required this.selectedIndex,
    required this.state,
    required this.onDestinationSelected,
    required this.onWorkPressed,
  });

  final int selectedIndex;
  final DriverHomeState state;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onWorkPressed;

  @override
  Widget build(BuildContext context) {
    final isBusy = state.connection == HomeConnection.connecting;
    return Material(
      color: Colors.white,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 112,
          child: Row(
            children: [
              _BottomBarItem(
                icon: Icons.map_outlined,
                selectedIcon: Icons.map_rounded,
                label: 'الرئيسية',
                selected: selectedIndex == 0,
                onTap: () => onDestinationSelected(0),
              ),
              _BottomBarItem(
                icon: Icons.bar_chart_outlined,
                selectedIcon: Icons.bar_chart_rounded,
                label: 'الأرباح',
                selected: selectedIndex == 1,
                onTap: () => onDestinationSelected(1),
              ),
              SizedBox(
                width: 112,
                child: _WorkPowerButton(
                  state: state,
                  isBusy: isBusy,
                  onPressed: isBusy ? null : onWorkPressed,
                ),
              ),
              _BottomBarItem(
                icon: Icons.notifications_none_rounded,
                selectedIcon: Icons.notifications_rounded,
                label: 'الإشعارات',
                selected: selectedIndex == 2,
                onTap: () => onDestinationSelected(2),
              ),
              _BottomBarItem(
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                label: 'حسابي',
                selected: selectedIndex == 3,
                onTap: () => onDestinationSelected(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  const _BottomBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primaryGreen : const Color(0xFF6E766F);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 104,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? selectedIcon : icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkPowerButton extends StatelessWidget {
  const _WorkPowerButton({
    required this.state,
    required this.isBusy,
    required this.onPressed,
  });

  final DriverHomeState state;
  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isOnline = state.isOnline;
    final color = isOnline ? AppTheme.primaryGreen : const Color(0xFFE53935);
    final label = isOnline ? 'متصل' : 'متوقف';

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 104,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: isBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.power_settings_new_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isBusy ? 'جارٍ الاتصال' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1F2C24),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

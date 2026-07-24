import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jowla_driver/core/theme/app_theme.dart';
import 'package:jowla_driver/features/home/application/driver_home_controller.dart';
import 'package:jowla_driver/features/earnings/presentation/earnings_screen.dart';
import 'package:jowla_driver/features/home/presentation/home_screen.dart';
import 'package:jowla_driver/features/notifications/presentation/notifications_screen.dart';
import 'package:jowla_driver/features/profile/presentation/profile_screen.dart';
import 'package:jowla_driver/features/rides/domain/models/ride.dart';
import 'package:jowla_driver/features/trip/application/trip_controller.dart';

class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({super.key});

  @override
  ConsumerState<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<DriverShell> {
  var _index = 0;
  String? _openedRideId;

  static const _screens = [
    HomeScreen(),
    EarningsScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(driverHomeControllerProvider);
    final activeRide = ref.watch(tripControllerProvider).value;
    _openActiveRideOnce(activeRide);
    ref.listen(tripControllerProvider, (previous, next) {
      _openActiveRideOnce(next.value);
    });
    final hasIncomingOffer = home.activeOffer != null;
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: hasIncomingOffer
            ? const SizedBox.shrink(key: ValueKey('offers-hide-bottom-bar'))
            : _DriverBottomBar(
                key: const ValueKey('driver-bottom-bar'),
                selectedIndex: _index,
                state: home,
                onDestinationSelected: (value) =>
                    setState(() => _index = value),
                onWorkPressed: () => unawaited(_toggleWork(home)),
              ),
      ),
    );
  }

  Future<void> _toggleWork(DriverHomeState state) async {
    final controller = ref.read(driverHomeControllerProvider.notifier);
    if (state.isOnline) {
      unawaited(controller.goOffline());
    } else {
      if (state.services.length == 1 &&
          state.activeService?.code != state.services.first.code) {
        await controller.chooseActiveService(state.services.first.code);
      } else if (state.services.length > 1) {
        final selected = await _pickService(state);
        if (selected == null) return;
        await controller.chooseActiveService(selected);
      }
      unawaited(controller.goOnline());
    }
  }

  Future<String?> _pickService(DriverHomeState state) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'اختر نوع العمل',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              for (final service in state.services)
                ListTile(
                  leading: Icon(
                    service.code == 'intercity'
                        ? Icons.route_rounded
                        : Icons.location_city_rounded,
                  ),
                  title: Text(service.name),
                  trailing: state.activeService?.code == service.code
                      ? const Icon(Icons.check_circle_rounded)
                      : null,
                  onTap: () => Navigator.of(context).pop(service.code),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openActiveRideOnce(Ride? ride) {
    if (ride == null || !ride.status.isActiveForDriver) return;
    if (_openedRideId == ride.id) return;
    _openedRideId = ride.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.push('/trip');
    });
  }
}

class _DriverBottomBar extends StatelessWidget {
  const _DriverBottomBar({
    required this.selectedIndex,
    required this.state,
    required this.onDestinationSelected,
    required this.onWorkPressed,
    super.key,
  });

  final int selectedIndex;
  final DriverHomeState state;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onWorkPressed;

  @override
  Widget build(BuildContext context) {
    final isBusy = state.connection == HomeConnection.connecting;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 16,
      shadowColor: colors.shadow.withValues(alpha: 0.16),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 112,
          child: Row(
            children: [
              _BottomBarItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
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
    final colors = Theme.of(context).colorScheme;
    final color = selected ? colors.primary : colors.onSurfaceVariant;
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
    final foreground = Theme.of(context).colorScheme.onSurface;

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
              width: 78,
              height: 78,
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
                        size: 38,
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isBusy ? 'جارٍ الاتصال' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
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

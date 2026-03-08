import 'package:flutter/material.dart';
import '../models/invoice_group.dart';
import '../models/route_info.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import 'group_detail_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;

  List<RouteInfo> _routes = [];
  RouteInfo? _selectedRoute;

  List<InvoiceGroup> _groups = [];
  bool _loading = true;
  bool _routesLoading = true;
  String? _error;

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
    _loadRoutes();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadInvoices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    setState(() => _routesLoading = true);
    try {
      final routes = await ApiService.instance.getDriverRoutes();
      setState(() {
        _routes = routes;
        // Auto-select the most recent route
        _selectedRoute = routes.isNotEmpty ? routes.first : null;
      });
    } catch (_) {
      // If routes fail, still try to load invoices without filter
    } finally {
      if (mounted) setState(() => _routesLoading = false);
      await _loadInvoices();
    }
  }

  Future<void> _loadInvoices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await ApiService.instance.getGroupedInvoices(
        routeNumber: _selectedRoute?.routeNumber,
        createdDate: _selectedRoute?.createdDate,
      );
      setState(() => _groups = groups);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load deliveries. Pull to refresh.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onRouteChanged(RouteInfo? route) async {
    setState(() => _selectedRoute = route);
    await _loadInvoices();
  }

  Future<void> _logout() async {
    await stopLocationTracking();
    await ApiService.instance.logout();
    await AuthService.instance.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  List<InvoiceGroup> _filtered(String status) {
    final byStatus = _groups.where((g) => g.status == status);
    if (_searchQuery.isEmpty) return byStatus.toList();
    return byStatus
        .where((g) => g.customerName.toLowerCase().contains(_searchQuery))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userName = AuthService.instance.user?.name ?? 'Driver';
    final pending = _filtered('pending');
    final delivered = _filtered('delivered');

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        title: Text(
          userName,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(148),
          child: Column(
            children: [
              // Route picker
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: _routesLoading
                    ? const SizedBox(
                        height: 44,
                        child: Center(
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      )
                    : _RoutePicker(
                        routes: _routes,
                        selected: _selectedRoute,
                        onChanged: _onRouteChanged,
                      ),
              ),
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: 'Search Shops',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 15),
                      prefixIcon: Icon(Icons.search,
                          color: Colors.white.withValues(alpha: 0.7), size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close,
                                  color: Colors.white.withValues(alpha: 0.7),
                                  size: 18),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.15),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              // Tabs
              TabBar(
                controller: _tabController,
                indicatorColor: theme.colorScheme.onPrimary,
                labelColor: theme.colorScheme.onPrimary,
                unselectedLabelColor:
                    theme.colorScheme.onPrimary.withValues(alpha: 0.6),
                tabs: [
                  Tab(text: 'Pending (${pending.length})'),
                  Tab(text: 'Delivered (${delivered.length})'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _loadInvoices)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _GroupList(
                        groups: pending,
                        onRefresh: _loadInvoices,
                        emptyMessage: 'No pending deliveries'),
                    _GroupList(
                        groups: delivered,
                        onRefresh: _loadInvoices,
                        emptyMessage: 'No delivered items yet'),
                  ],
                ),
    );
  }
}

class _RoutePicker extends StatelessWidget {
  final List<RouteInfo> routes;
  final RouteInfo? selected;
  final ValueChanged<RouteInfo?> onChanged;

  const _RoutePicker({
    required this.routes,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) {
      return Container(
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'No routes available',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<RouteInfo?>(
          value: selected,
          isExpanded: true,
          dropdownColor: const Color(0xFF1565C0),
          iconEnabledColor: Colors.white,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          hint: const Text('All Routes',
              style: TextStyle(color: Colors.white70, fontSize: 15)),
          items: [
            const DropdownMenuItem<RouteInfo?>(
              value: null,
              child: Text('All Routes',
                  style: TextStyle(color: Colors.white)),
            ),
            ...routes.map((r) => DropdownMenuItem<RouteInfo?>(
                  value: r,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.routeDisplay,
                          style: const TextStyle(color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PendingBadge(route: r),
                    ],
                  ),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _PendingBadge extends StatelessWidget {
  final RouteInfo route;
  const _PendingBadge({required this.route});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${route.invoiceCount}',
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _GroupList extends StatelessWidget {
  final List<InvoiceGroup> groups;
  final Future<void> Function() onRefresh;
  final String emptyMessage;

  const _GroupList({
    required this.groups,
    required this.onRefresh,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.28),
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: groups.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => _GroupCard(group: groups[i]),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final InvoiceGroup group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delivered = group.isDelivered;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupDetailScreen(group: group),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.customerName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  _StatusChip(delivered: delivered),
                ],
              ),
              if (group.shopAddress != null && group.shopAddress!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          group.shopAddress!,
                          style: TextStyle(
                              color: Colors.grey.shade700, fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _InfoPill(
                    icon: Icons.receipt_long_outlined,
                    label:
                        '${group.invoiceCount} invoice${group.invoiceCount != 1 ? 's' : ''}',
                  ),
                  const SizedBox(width: 8),
                  if (group.routeDisplay != null)
                    _InfoPill(
                      icon: Icons.route_outlined,
                      label: group.routeDisplay!,
                    ),
                  const Spacer(),
                  Text(
                    '₹${group.totalAmount.toStringAsFixed(2)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool delivered;
  const _StatusChip({required this.delivered});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: delivered ? Colors.green.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        delivered ? 'DELIVERED' : 'PENDING',
        style: TextStyle(
          color:
              delivered ? Colors.green.shade800 : Colors.orange.shade800,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 52, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

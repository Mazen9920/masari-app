import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDashboardConfig = 'dashboard_section_config';

class DashboardSectionConfig {
  final String id;
  final String label;
  final IconData icon;
  bool visible;

  DashboardSectionConfig({
    required this.id,
    required this.label,
    required this.icon,
    this.visible = true,
  });

  DashboardSectionConfig copy() => DashboardSectionConfig(
        id: id,
        label: label,
        icon: icon,
        visible: visible,
      );

  Map<String, dynamic> toJson() => {'id': id, 'visible': visible};
}

class DashboardConfig {
  final List<DashboardSectionConfig> sections;
  const DashboardConfig({required this.sections});
}

final _defaultSections = [
  DashboardSectionConfig(
    id: 'profit_margins',
    label:  'Profit Margins',
    icon: Icons.pie_chart_rounded,
  ),
  DashboardSectionConfig(
    id: 'top_products',
    label:  'Top Products',
    icon: Icons.star_rounded,
  ),
  DashboardSectionConfig(
    id: 'inventory_valuation',
    label:  'Inventory Valuation',
    icon: Icons.inventory_2_rounded,
  ),
  DashboardSectionConfig(
    id: 'low_stock',
    label:  'Low Stock Alerts',
    icon: Icons.warning_amber_rounded,
  ),
  DashboardSectionConfig(
    id: 'accounts',
    label:  'Accounts (AR / AP)',
    icon: Icons.account_balance_wallet_rounded,
  ),
  DashboardSectionConfig(
    id: 'recent_transactions',
    label:  'Recent Transactions',
    icon: Icons.receipt_long_rounded,
  ),
];

class DashboardConfigNotifier extends Notifier<DashboardConfig> {
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  String _key() => '${_uid!}_$_kDashboardConfig';

  @override
  DashboardConfig build() {
    _loadFromPrefs();
    return DashboardConfig(
        sections: _defaultSections.map((s) => s.copy()).toList());
  }

  Future<void> _loadFromPrefs() async {
    if (_uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key());
    if (raw == null) return;

    final List<dynamic> saved = jsonDecode(raw) as List<dynamic>;
    final savedMap = {
      for (final item in saved) (item as Map<String, dynamic>)['id']: item
    };

    // Rebuild in saved order, preserving visibility
    final ordered = <DashboardSectionConfig>[];
    final defaults = {for (final s in _defaultSections) s.id: s};

    for (final item in saved) {
      final id = item['id'] as String;
      final template = defaults[id];
      if (template != null) {
        ordered.add(DashboardSectionConfig(
          id: id,
          label: template.label,
          icon: template.icon,
          visible: item['visible'] as bool? ?? true,
        ));
      }
    }
    // Append any new defaults not in saved config
    for (final d in _defaultSections) {
      if (!savedMap.containsKey(d.id)) {
        ordered.add(d.copy());
      }
    }

    state = DashboardConfig(sections: ordered);
  }

  Future<void> updateSections(List<DashboardSectionConfig> sections) async {
    state = DashboardConfig(
        sections: sections.map((s) => s.copy()).toList());
    final prefs = await SharedPreferences.getInstance();
    final json = sections.map((s) => s.toJson()).toList();
    await prefs.setString(_key(), jsonEncode(json));
  }

  Future<void> reset() async {
    state = DashboardConfig(
        sections: _defaultSections.map((s) => s.copy()).toList());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key());
  }
}

final dashboardConfigProvider =
    NotifierProvider<DashboardConfigNotifier, DashboardConfig>(
  DashboardConfigNotifier.new,
);

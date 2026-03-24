import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

const _kPinnedActions = 'pinned_actions_order';

/// A single quick-action item on the Manage Hub.
class PinnedAction {
  final String id;
  final IconData icon;
  final String label;
  final Color iconBg;
  final Color iconColor;

  const PinnedAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.iconBg,
    required this.iconColor,
  });

  /// Returns the localized label for this action.
  String localizedLabel(AppLocalizations l10n) => switch (id) {
    'add_product'     => l10n.addProduct,
    'new_supplier'    => l10n.newSupplier,
    'record_purchase' => l10n.recordPurchaseAction,
    'create_category' => l10n.createCategory,
    'record_payment'  => l10n.recordPaymentAction,
    'adjust_stock'    => l10n.adjustStock,
    _                 => label,
  };
}

/// Default ordered list of all available actions.
const defaultPinnedActions = [
  PinnedAction(
    id: 'add_product',
    icon: Icons.add_circle_rounded,
    label: 'Add Product',
    iconBg: Color(0xFFFFF7ED),
    iconColor: Color(0xFFE67E22),
  ),
  PinnedAction(
    id: 'new_supplier',
    icon: Icons.person_add_rounded,
    label: 'New Supplier',
    iconBg: Color(0xFFEFF6FF),
    iconColor: AppColors.primaryNavy,
  ),
  PinnedAction(
    id: 'record_purchase',
    icon: Icons.receipt_long_rounded,
    label: 'Record Purchase',
    iconBg: Color(0xFFEFF6FF),
    iconColor: AppColors.primaryNavy,
  ),
  PinnedAction(
    id: 'create_category',
    icon: Icons.category_rounded,
    label: 'Create Category',
    iconBg: Color(0xFFFFF7ED),
    iconColor: Color(0xFFE67E22),
  ),
  PinnedAction(
    id: 'record_payment',
    icon: Icons.payments_rounded,
    label: 'Record Payment',
    iconBg: Color(0xFFEFF6FF),
    iconColor: AppColors.primaryNavy,
  ),
  PinnedAction(
    id: 'adjust_stock',
    icon: Icons.inventory_2_rounded,
    label: 'Adjust Stock',
    iconBg: Color(0xFFEFF6FF),
    iconColor: AppColors.primaryNavy,
  ),
];

/// State: ordered list of action IDs + the visible count threshold.
class PinnedActionsState {
  final List<String> orderedIds;
  final int visibleCount;

  const PinnedActionsState({
    this.orderedIds = const [],
    this.visibleCount = 4,
  });

  /// Resolve the full PinnedAction objects from the ordered IDs.
  List<PinnedAction> get actions {
    final map = {for (final a in defaultPinnedActions) a.id: a};
    return orderedIds.where((id) => map.containsKey(id)).map((id) => map[id]!).toList();
  }

  List<PinnedAction> get visibleActions => actions.take(visibleCount).toList();
  List<PinnedAction> get hiddenActions => actions.skip(visibleCount).toList();
}

class PinnedActionsNotifier extends Notifier<PinnedActionsState> {
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  bool get _isAuth => _uid != null;
  String get _key => '${_uid!}_$_kPinnedActions';

  @override
  PinnedActionsState build() {
    _load();
    return PinnedActionsState(
      orderedIds: defaultPinnedActions.map((a) => a.id).toList(),
    );
  }

  Future<void> _load() async {
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json != null) {
      final List<dynamic> ids = jsonDecode(json);
      // Add any new default actions that weren't saved before
      final saved = ids.cast<String>().toList();
      final allIds = defaultPinnedActions.map((a) => a.id).toList();
      for (final id in allIds) {
        if (!saved.contains(id)) saved.add(id);
      }
      state = PinnedActionsState(orderedIds: saved);
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final ids = [...state.orderedIds];
    final item = ids.removeAt(oldIndex);
    if (newIndex > oldIndex) newIndex--;
    ids.insert(newIndex.clamp(0, ids.length), item);
    state = PinnedActionsState(orderedIds: ids, visibleCount: state.visibleCount);
    await _persist();
  }

  /// Move an action from hidden→visible or visible→hidden.
  Future<void> toggleVisibility(int index) async {
    final ids = [...state.orderedIds];
    if (index >= ids.length) return;
    final item = ids.removeAt(index);
    if (index < state.visibleCount) {
      // Was visible → move to start of hidden
      ids.insert(state.visibleCount - 1 < ids.length ? state.visibleCount - 1 : ids.length, item);
    } else {
      // Was hidden → move to end of visible
      ids.insert(state.visibleCount, item);
    }
    state = PinnedActionsState(orderedIds: ids, visibleCount: state.visibleCount);
    await _persist();
  }

  Future<void> _persist() async {
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.orderedIds));
  }
}

final pinnedActionsProvider =
    NotifierProvider<PinnedActionsNotifier, PinnedActionsState>(() {
  return PinnedActionsNotifier();
});

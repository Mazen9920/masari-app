import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/navigation/app_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/accrued_expense_model.dart';
import '../../shared/models/category_data.dart';
import '../../shared/utils/safe_pop.dart';

/// Which slice of accruals the list is showing.
enum _Filter { unpaid, overdue, settled, all }

extension on _Filter {
  String get label => switch (this) {
        _Filter.unpaid => 'Unpaid',
        _Filter.overdue => 'Overdue',
        _Filter.settled => 'Settled',
        _Filter.all => 'All',
      };
}

/// Accrued expenses — costs incurred but not yet paid (a liability).
///
/// Built action-first: paying is the everyday job, so every unpaid row carries
/// a one-tap **Pay** button instead of hiding it behind the edit form.
class AccruedExpensesDashboardScreen extends ConsumerStatefulWidget {
  const AccruedExpensesDashboardScreen({super.key});

  @override
  ConsumerState<AccruedExpensesDashboardScreen> createState() =>
      _AccruedExpensesDashboardScreenState();
}

class _AccruedExpensesDashboardScreenState
    extends ConsumerState<AccruedExpensesDashboardScreen> {
  final _fmt = NumberFormat('#,##0', 'en');
  final _fmt2 = NumberFormat('#,##0.00', 'en');
  final _monthFmt = DateFormat('MMMM yyyy');
  final _dateFmt = DateFormat('MMM d, yyyy');

  _Filter _filter = _Filter.unpaid;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(accruedExpensesProvider);
    final currency = ref.watch(appSettingsProvider).currency;
    final catNames = {
      for (final c
          in ref.watch(categoriesProvider).value ?? const <CategoryData>[])
        c.id: c.name
    };

    final active = all.where((e) => e.isActive).toList();
    final overdue = active.where((e) => e.isOverdue).toList();
    final soon = active.where((e) => e.dueSoon()).toList();
    final owed = active.fold<double>(0, (s, e) => s + e.amount);
    final overdueTotal = overdue.fold<double>(0, (s, e) => s + e.amount);

    final visible = _applyFilter(all);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: CustomScrollView(
        slivers: [
          _appBar(currency, owed, overdue.length, overdueTotal, soon.length),
          if (all.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _empty())
          else ...[
            SliverToBoxAdapter(child: _filterBar(all)),
            if (visible.isEmpty)
              SliverToBoxAdapter(child: _noMatches())
            else
              ..._groupedByMonth(visible, currency, catNames),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryNavy,
        onPressed: () => context.push(AppRoutes.addAccruedExpense),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New accrual',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ── Filtering ────────────────────────────────────────────

  List<AccruedExpense> _applyFilter(List<AccruedExpense> all) {
    final q = _search.trim().toLowerCase();
    var list = switch (_filter) {
      _Filter.unpaid => all.where((e) => e.isActive).toList(),
      _Filter.overdue => all.where((e) => e.isOverdue).toList(),
      _Filter.settled => all.where((e) => !e.isActive).toList(),
      _Filter.all => [...all],
    };
    if (q.isNotEmpty) {
      list = list
          .where((e) =>
              e.name.toLowerCase().contains(q) ||
              (e.notes ?? '').toLowerCase().contains(q))
          .toList();
    }
    // Most urgent first: overdue, then earliest due date, then newest period.
    list.sort((a, b) {
      if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
      final ad = a.dueDate, bd = b.dueDate;
      if (ad != null && bd != null) return ad.compareTo(bd);
      if (ad != null) return -1;
      if (bd != null) return 1;
      return b.accrualDate.compareTo(a.accrualDate);
    });
    return list;
  }

  // ── Header ───────────────────────────────────────────────

  Widget _appBar(String currency, double owed, int overdueCount,
      double overdueTotal, int soonCount) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 190,
      backgroundColor: AppColors.primaryNavy,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.safePop(),
      ),
      title: const Text('Accrued Expenses',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryNavy, Color(0xFF1E3A5F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 96, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('YOU OWE',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('$currency ${_fmt.format(owed)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 33,
                        fontWeight: FontWeight.bold,
                        height: 1.1)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (overdueCount > 0)
                    _headerPill(
                      '$overdueCount overdue · $currency ${_fmt.format(overdueTotal)}',
                      const Color(0xFFEF4444),
                      Icons.warning_amber_rounded,
                    ),
                  if (overdueCount > 0 && soonCount > 0)
                    const SizedBox(width: 8),
                  if (soonCount > 0)
                    _headerPill('$soonCount due soon',
                        const Color(0xFFF59E0B), Icons.schedule_rounded),
                  if (overdueCount == 0 && soonCount == 0)
                    _headerPill('Nothing overdue', const Color(0xFF10B981),
                        Icons.check_circle_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerPill(String text, Color color, IconData icon) => Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 5),
              Flexible(
                child: Text(text,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );

  // ── Filter bar ───────────────────────────────────────────

  Widget _filterBar(List<AccruedExpense> all) {
    int countFor(_Filter f) => switch (f) {
          _Filter.unpaid => all.where((e) => e.isActive).length,
          _Filter.overdue => all.where((e) => e.isOverdue).length,
          _Filter.settled => all.where((e) => !e.isActive).length,
          _Filter.all => all.length,
        };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: [
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: _Filter.values.map((f) {
                final selected = _filter == f;
                final n = countFor(f);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            selected ? AppColors.primaryNavy : Colors.white,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                            color: selected
                                ? AppColors.primaryNavy
                                : Colors.grey.shade300),
                      ),
                      child: Text(
                        '${f.label}${n > 0 ? '  $n' : ''}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (all.length > 5) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Search accruals',
                  hintStyle: const TextStyle(fontSize: 13.5),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Month-grouped list ───────────────────────────────────

  List<Widget> _groupedByMonth(List<AccruedExpense> list, String currency,
      Map<String, String> catNames) {
    // Bucket by period, preserving the urgency sort inside each month.
    final buckets = <String, List<AccruedExpense>>{};
    for (final e in list) {
      buckets.putIfAbsent(e.periodKey, () => []).add(e);
    }
    final keys = buckets.keys.toList()..sort((a, b) => b.compareTo(a));

    return [
      for (final k in keys)
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Text(_monthFmt.format(buckets[k]!.first.accrualDate),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.3)),
                    const SizedBox(width: 8),
                    Expanded(
                        child:
                            Container(height: 1, color: Colors.grey.shade200)),
                    const SizedBox(width: 8),
                    Text(
                      '$currency ${_fmt.format(buckets[k]!.fold<double>(0, (s, e) => s + e.amount))}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              ...buckets[k]!.map((e) => _row(e, currency, catNames)),
            ],
          ),
        ),
    ];
  }

  // ── The row ──────────────────────────────────────────────

  Widget _row(
      AccruedExpense e, String currency, Map<String, String> catNames) {
    final due = _dueLabel(e);
    final accent = e.isSettled
        ? AppColors.chartGreen
        : e.isOverdue
            ? AppColors.chartRed
            : e.dueSoon()
                ? AppColors.chartOrange
                : AppColors.primaryNavy;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: e.isOverdue
                ? AppColors.chartRed.withValues(alpha: 0.35)
                : Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push(AppRoutes.editAccruedExpense,
              extra: {'expense': e}),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Colour bar reads status at a glance.
                    Container(
                      width: 3,
                      height: 34,
                      margin: const EdgeInsets.only(right: 11, top: 2),
                      decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.name.isEmpty ? 'Accrual' : e.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (due != null) ...[
                                Text(due.text,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: due.color)),
                                const Text('  ·  ',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textTertiary)),
                              ],
                              Flexible(
                                child: Text(
                                  e.categoryId != null
                                      ? (catNames[e.categoryId] ?? 'Category')
                                      : 'Uncategorized',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textTertiary),
                                ),
                              ),
                              if (e.isRecurring) ...[
                                const SizedBox(width: 5),
                                const Icon(Icons.repeat_rounded,
                                    size: 12, color: AppColors.textTertiary),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$currency ${_fmt.format(e.isSettled ? e.totalAccrued : e.amount)}',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: e.isSettled
                                  ? AppColors.textTertiary
                                  : AppColors.textPrimary),
                        ),
                        Text(e.isSettled ? 'settled' : 'owed',
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textTertiary)),
                      ],
                    ),
                  ],
                ),

                // Part-payment progress.
                if (!e.isSettled && e.totalPaid > 0) ...[
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: e.progressPct,
                            minHeight: 4,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation(
                                AppColors.chartGreen),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_fmt.format(e.totalPaid)} / ${_fmt.format(e.totalAccrued)}',
                        style: const TextStyle(
                            fontSize: 10.5, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ],

                // The everyday action, right here — no drilling into a form.
                if (!e.isSettled) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _quickPay(e, currency, full: true),
                        icon: const Icon(Icons.done_all_rounded, size: 15),
                        label: const Text('Pay all',
                            style: TextStyle(fontSize: 12.5)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.icon(
                        onPressed: () => _quickPay(e, currency),
                        icon: const Icon(Icons.payments_rounded, size: 15),
                        label: const Text('Pay',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryNavy,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Quick pay ────────────────────────────────────────────

  /// One-tap payment. [full] settles the whole balance after a short confirm;
  /// otherwise a compact sheet opens pre-filled with what's outstanding.
  Future<void> _quickPay(AccruedExpense e, String currency,
      {bool full = false}) async {
    if (full) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pay in full?'),
          content: Text(
              'Records $currency ${_fmt2.format(e.amount)} paid today for '
              '"${e.name}" and deducts it from Cash & Bank.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Pay')),
          ],
        ),
      );
      if (ok != true) return;
      await _submitPayment(e, e.amount, DateTime.now(), true);
      return;
    }

    final amountCtrl =
        TextEditingController(text: e.amount.toStringAsFixed(2));
    DateTime date = DateTime.now();
    bool postCash = true;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Pay ${e.name}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                Text('Outstanding $currency ${_fmt2.format(e.amount)}',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textTertiary)),
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                  ],
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    prefixText: '$currency  ',
                    filled: true,
                    fillColor: const Color(0xFFF5F6F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Fast amounts — most payments are the full balance or half.
                Row(
                  children: [
                    _amountChip('Full', e.amount, amountCtrl, setSt),
                    const SizedBox(width: 8),
                    _amountChip('Half', e.amount / 2, amountCtrl, setSt),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setSt(() => date = d);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F6F8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 16),
                        const SizedBox(width: 10),
                        Text(_dateFmt.format(date),
                            style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: postCash,
                  onChanged: (v) => setSt(() => postCash = v ?? true),
                  dense: true,
                  title: const Text('Deduct from Cash & Bank',
                      style: TextStyle(fontSize: 13.5)),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Record payment',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;
    final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amt <= 0) return;
    await _submitPayment(e, amt, date, postCash);
  }

  Widget _amountChip(String label, double value, TextEditingController ctrl,
          void Function(void Function()) setSt) =>
      GestureDetector(
        onTap: () => setSt(() => ctrl.text = value.toStringAsFixed(2)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primaryNavy.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryNavy)),
        ),
      );

  Future<void> _submitPayment(
      AccruedExpense e, double amount, DateTime date, bool postCash) async {
    final ok = await ref.read(accruedExpensesProvider.notifier).recordPayment(
          e.id,
          AccruedExpensePayment(
              id: const Uuid().v4(), amount: amount, date: date),
          postCash: postCash,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Payment recorded' : 'Could not record payment'),
        backgroundColor: ok ? AppColors.chartGreen : AppColors.chartRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Bits ─────────────────────────────────────────────────

  ({String text, Color color})? _dueLabel(AccruedExpense e) {
    final days = e.daysUntilDue;
    if (e.isSettled || days == null) return null;
    if (days < 0) {
      final n = -days;
      return (
        text: '$n day${n == 1 ? '' : 's'} late',
        color: AppColors.chartRed
      );
    }
    if (days == 0) return (text: 'Due today', color: AppColors.chartOrange);
    if (days <= 7) {
      return (text: 'Due in $days d', color: AppColors.chartOrange);
    }
    return (
      text: 'Due ${_dateFmt.format(e.dueDate!)}',
      color: AppColors.textTertiary
    );
  }

  Widget _noMatches() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 56),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.filter_alt_off_rounded,
                  size: 40, color: AppColors.textTertiary),
              const SizedBox(height: 10),
              Text('No ${_filter.label.toLowerCase()} accruals',
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textTertiary)),
            ],
          ),
        ),
      );

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primaryNavy.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  size: 34, color: AppColors.primaryNavy),
            ),
            const SizedBox(height: 18),
            const Text('Nothing accrued yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Track costs you\'ve incurred but not paid — rent, utilities, '
              'interest. They show as a liability and hit the P&L in the month '
              'they belong to.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => context.push(AppRoutes.addAccruedExpense),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add your first accrual'),
            ),
          ],
        ),
      );
}

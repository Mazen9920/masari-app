import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/fixed_asset_model.dart';
import '../../shared/utils/safe_pop.dart';

/// Screen for creating or editing a fixed asset.
/// Pass `extra: {'asset': FixedAsset}` for edit mode.
class AddEditFixedAssetScreen extends ConsumerStatefulWidget {
  final FixedAsset? asset;
  const AddEditFixedAssetScreen({super.key, this.asset});

  @override
  ConsumerState<AddEditFixedAssetScreen> createState() =>
      _AddEditFixedAssetScreenState();
}

class _AddEditFixedAssetScreenState
    extends ConsumerState<AddEditFixedAssetScreen> {
  final _formKey = GlobalKey<FormState>();
  late final bool _isEdit;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _salvageCtrl;
  late final TextEditingController _lifeCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _disposalPriceCtrl;

  late FixedAssetCategory _category;
  late DepreciationMethod _depMethod;
  late FixedAssetStatus _status;
  late DateTime _purchaseDate;
  DateTime? _disposalDate;

  bool _saving = false;
  // New cash purchases default to deducting cash; turn off for a non-cash
  // (owner-contributed) asset.
  bool _cashPurchase = true;

  @override
  void initState() {
    super.initState();
    final a = widget.asset;
    _isEdit = a != null;
    _nameCtrl = TextEditingController(text: a?.name ?? '');
    _descCtrl = TextEditingController(text: a?.description ?? '');
    _priceCtrl = TextEditingController(
        text: a != null ? a.purchasePrice.toStringAsFixed(2) : '');
    _salvageCtrl = TextEditingController(
        text: a != null ? a.salvageValue.toStringAsFixed(2) : '0');
    _lifeCtrl = TextEditingController(
        text: a != null ? a.usefulLifeMonths.toString() : '60');
    _notesCtrl = TextEditingController(text: a?.notes ?? '');
    _disposalPriceCtrl = TextEditingController(
        text: a?.disposalPrice?.toStringAsFixed(2) ?? '');
    _category = a?.category ?? FixedAssetCategory.equipment;
    _depMethod = a?.depreciationMethod ?? DepreciationMethod.straightLine;
    _status = a?.status ?? FixedAssetStatus.active;
    _purchaseDate = a?.purchaseDate ?? DateTime.now();
    _disposalDate = a?.disposalDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _salvageCtrl.dispose();
    _lifeCtrl.dispose();
    _notesCtrl.dispose();
    _disposalPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final asset = FixedAsset(
      id: widget.asset?.id ?? '',
      name: _nameCtrl.text.trim(),
      description:
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      category: _category,
      purchaseDate: _purchaseDate,
      purchasePrice: double.tryParse(_priceCtrl.text.trim()) ?? 0,
      usefulLifeMonths: int.tryParse(_lifeCtrl.text.trim()) ?? 60,
      depreciationMethod: _depMethod,
      salvageValue: double.tryParse(_salvageCtrl.text.trim()) ?? 0,
      status: _status,
      disposalDate: _disposalDate,
      disposalPrice: _disposalPriceCtrl.text.trim().isNotEmpty
          ? double.tryParse(_disposalPriceCtrl.text.trim())
          : null,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdAt: widget.asset?.createdAt ?? DateTime.now(),
    );

    final notifier = ref.read(fixedAssetsProvider.notifier);
    final ok = _isEdit
        ? await notifier.updateAsset(asset)
        : await notifier.add(asset, postCashOutflow: _cashPurchase);

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      context.safePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save asset')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.safePop(),
        ),
        title: Text(_isEdit ? 'Edit Asset' : 'Add Asset',
            style: AppTypography.labelMedium.copyWith(fontSize: 17)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Save',
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.primaryNavy)),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ── Name ──
            _field(
              label: 'Asset Name',
              child: TextFormField(
                controller: _nameCtrl,
                decoration: _inputDecoration('e.g. MacBook Pro 16"'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
            ),

            // ── Category ──
            _field(
              label: 'Category',
              child: DropdownButtonFormField<FixedAssetCategory>(
                initialValue: _category,
                decoration: _inputDecoration(null),
                items: FixedAssetCategory.values
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text('${c.icon} ${c.label}'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),
            ),

            // ── Purchase Price ──
            _field(
              label: 'Purchase Price',
              child: TextFormField(
                controller: _priceCtrl,
                decoration: _inputDecoration('0.00'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Enter a valid price';
                  return null;
                },
              ),
            ),

            // ── Cash purchase toggle (new assets only) ──
            if (!_isEdit)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _cashPurchase,
                onChanged: (v) => setState(() => _cashPurchase = v),
                title: const Text(
                  'Paid in cash',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _cashPurchase
                      ? 'Deducts the price from cash and records the purchase (no P&L hit).'
                      : 'No cash deducted — use for an owner-contributed (non-cash) asset.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),

            // ── Purchase Date ──
            _field(
              label: 'Purchase Date',
              child: GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _purchaseDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _purchaseDate = d);
                },
                child: AbsorbPointer(
                  child: TextFormField(
                    decoration: _inputDecoration(null).copyWith(
                      suffixIcon:
                          const Icon(Icons.calendar_today_rounded, size: 18),
                    ),
                    controller: TextEditingController(
                        text: dateFmt.format(_purchaseDate)),
                  ),
                ),
              ),
            ),

            // ── Useful Life ──
            _field(
              label: 'Useful Life (months)',
              child: TextFormField(
                controller: _lifeCtrl,
                decoration: _inputDecoration('60'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final n = int.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Must be positive';
                  return null;
                },
              ),
            ),

            // ── Depreciation Method ──
            _field(
              label: 'Depreciation Method',
              child: DropdownButtonFormField<DepreciationMethod>(
                initialValue: _depMethod,
                decoration: _inputDecoration(null),
                items: DepreciationMethod.values
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m.label),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _depMethod = v);
                },
              ),
            ),

            // ── Salvage Value ──
            _field(
              label: 'Salvage / Residual Value',
              child: TextFormField(
                controller: _salvageCtrl,
                decoration: _inputDecoration('0.00'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
              ),
            ),

            // ── Status ──
            _field(
              label: 'Status',
              child: DropdownButtonFormField<FixedAssetStatus>(
                initialValue: _status,
                decoration: _inputDecoration(null),
                items: FixedAssetStatus.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.label),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _status = v);
                },
              ),
            ),

            // ── Disposal fields (conditional) ──
            if (_status != FixedAssetStatus.active) ...[
              _field(
                label: 'Disposal Date',
                child: GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _disposalDate ?? DateTime.now(),
                      firstDate: _purchaseDate,
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _disposalDate = d);
                  },
                  child: AbsorbPointer(
                    child: TextFormField(
                      decoration: _inputDecoration('Select date').copyWith(
                        suffixIcon: const Icon(Icons.calendar_today_rounded,
                            size: 18),
                      ),
                      controller: TextEditingController(
                          text: _disposalDate != null
                              ? dateFmt.format(_disposalDate!)
                              : ''),
                    ),
                  ),
                ),
              ),
              _field(
                label:
                    _status == FixedAssetStatus.sold ? 'Sale Price' : 'Disposal Value',
                child: TextFormField(
                  controller: _disposalPriceCtrl,
                  decoration: _inputDecoration('0.00'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
              ),
            ],

            // ── Description ──
            _field(
              label: 'Description (optional)',
              child: TextFormField(
                controller: _descCtrl,
                decoration: _inputDecoration('Brief description'),
                maxLines: 2,
              ),
            ),

            // ── Notes ──
            _field(
              label: 'Notes (optional)',
              child: TextFormField(
                controller: _notesCtrl,
                decoration: _inputDecoration('Any additional notes'),
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.bodyMedium.copyWith(color: Colors.grey.shade400),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryNavy, width: 1.5),
      ),
    );
  }
}

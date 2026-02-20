import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../shared/models/supplier_model.dart';

/// Edit Supplier — pre-filled form for modifying existing supplier data.
class EditSupplierScreen extends ConsumerStatefulWidget {
  final Supplier supplier;
  const EditSupplierScreen({super.key, required this.supplier});

  @override
  ConsumerState<EditSupplierScreen> createState() =>
      _EditSupplierScreenState();
}

class _EditSupplierScreenState extends ConsumerState<EditSupplierScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _idCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;

  late String _category;
  late bool _whatsapp;
  late int _paymentTermIdx;
  bool _trackPayables = true;
  int _currencyIdx = 0;

  final _paymentTerms = ['On Receipt', 'Net 15', 'Net 30', 'Net 60'];
  final _currencies = ['EGP - Egyptian Pound', 'USD - US Dollar', 'EUR - Euro'];
  final _categories = [
    'Packaging',
    'Raw Materials',
    'Logistics',
    'Maintenance',
    'Wholesale',
    'Stationery',
    'IT Services',
    'Marketing',
    'Utilities',
  ];

  bool get _canSave => _nameCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _nameCtrl = TextEditingController(text: s.name);
    _idCtrl = TextEditingController(text: s.supplierId);
    _phoneCtrl = TextEditingController(text: s.phone);
    _emailCtrl = TextEditingController(text: s.email);
    _addressCtrl = TextEditingController(text: s.address);
    _notesCtrl = TextEditingController(text: s.notes);
    _category = s.category;
    _whatsapp = s.whatsappAvailable;
    _paymentTermIdx = _paymentTerms.indexOf(s.paymentTerms);
    if (_paymentTermIdx < 0) _paymentTermIdx = 0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_canSave) return;
    HapticFeedback.mediumImpact();
    // In a real app, update the supplier via provider
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_nameCtrl.text.trim()} updated'),
        backgroundColor: AppColors.primaryNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _confirmDelete() {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Supplier'),
        content: Text(
          'Are you sure you want to delete "${widget.supplier.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  children: [
                    // Avatar
                    _buildAvatar()
                        .animate()
                        .fadeIn(duration: 250.ms)
                        .scale(begin: const Offset(0.9, 0.9)),
                    const SizedBox(height: 24),

                    // Business Info
                    _buildBusinessInfo()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 16),

                    // Contact Details
                    _buildContactDetails()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 100.ms),
                    const SizedBox(height: 16),

                    // Financials
                    _buildFinancials()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 140.ms),
                    const SizedBox(height: 16),

                    // Location
                    _buildLocation()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 180.ms),
                    const SizedBox(height: 24),

                    // Delete button
                    GestureDetector(
                      onTap: _confirmDelete,
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 40),
                        child: Text(
                          'Delete Supplier',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ).animate().fadeIn(duration: 250.ms, delay: 220.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  HEADER — Cancel / title / Save
  // ═══════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.primaryNavy,
                fontSize: 15,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Edit Supplier',
                style: AppTypography.h2.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: _canSave ? _save : null,
            child: Text(
              'Save',
              style: TextStyle(
                color:
                    _canSave ? const Color(0xFFE67E22) : AppColors.textTertiary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  AVATAR
  // ═══════════════════════════════════════════════════════
  Widget _buildAvatar() {
    return Stack(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: widget.supplier.avatarBg,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
              ),
            ],
          ),
          child: Center(
            child: Text(
              widget.supplier.initials,
              style: TextStyle(
                color: widget.supplier.avatarTextColor,
                fontWeight: FontWeight.w800,
                fontSize: 28,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFE67E22),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.edit_rounded,
                color: Colors.white, size: 16),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  BUSINESS INFO
  // ═══════════════════════════════════════════════════════
  Widget _buildBusinessInfo() {
    return _card(
      title: 'BUSINESS INFO',
      children: [
        _fieldRow('Business Name', TextField(
          controller: _nameCtrl,
          onChanged: (_) => setState(() {}),
          style: _valueStyle,
          decoration: _minimalDeco(),
        )),
        _sep(),
        _fieldRow('Category', GestureDetector(
          onTap: () => _showPicker(
            'Select Category',
            _categories,
            _categories.indexOf(_category),
            (i) => setState(() => _category = _categories[i]),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _category.isEmpty ? 'Select' : _category,
                  style: _valueStyle,
                ),
              ),
              Icon(Icons.expand_more_rounded,
                  color: AppColors.textTertiary, size: 22),
            ],
          ),
        )),
        _sep(),
        _fieldRow('Supplier ID', TextField(
          controller: _idCtrl,
          style: _valueStyle,
          decoration: _minimalDeco(hint: 'e.g. SUP-001'),
        ), optional: true),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  CONTACT DETAILS
  // ═══════════════════════════════════════════════════════
  Widget _buildContactDetails() {
    return _card(
      title: 'CONTACT DETAILS',
      children: [
        _fieldRow('Phone Number', Row(
          children: [
            const Text('🇪🇬', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                style: _valueStyle,
                decoration: _minimalDeco(hint: '+20 xxx xxx xxxx'),
              ),
            ),
          ],
        )),
        _sep(),
        _fieldRow('Email', TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: _valueStyle,
          decoration: _minimalDeco(hint: 'supplier@example.com'),
        )),
        _sep(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.chat_rounded,
                  color: Color(0xFF25D366), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'WhatsApp Available',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _whatsapp,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() => _whatsapp = v);
                },
                activeColor: AppColors.primaryNavy,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  FINANCIALS
  // ═══════════════════════════════════════════════════════
  Widget _buildFinancials() {
    return _card(
      title: 'FINANCIALS',
      children: [
        _fieldRow('Default Terms', GestureDetector(
          onTap: () => _showPicker(
            'Select Terms',
            _paymentTerms,
            _paymentTermIdx,
            (i) => setState(() => _paymentTermIdx = i),
          ),
          child: Row(
            children: [
              Expanded(child: Text(_paymentTerms[_paymentTermIdx],
                  style: _valueStyle)),
              Icon(Icons.expand_more_rounded,
                  color: AppColors.textTertiary, size: 22),
            ],
          ),
        )),
        _sep(),
        _fieldRow('Currency', GestureDetector(
          onTap: () => _showPicker(
            'Select Currency',
            _currencies,
            _currencyIdx,
            (i) => setState(() => _currencyIdx = i),
          ),
          child: Row(
            children: [
              Expanded(child: Text(_currencies[_currencyIdx],
                  style: _valueStyle)),
              Icon(Icons.expand_more_rounded,
                  color: AppColors.textTertiary, size: 22),
            ],
          ),
        )),
        _sep(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Track Payables',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _trackPayables,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() => _trackPayables = v);
                },
                activeColor: AppColors.primaryNavy,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  LOCATION
  // ═══════════════════════════════════════════════════════
  Widget _buildLocation() {
    return _card(
      title: 'LOCATION',
      children: [
        _fieldRow('Office Address', TextField(
          controller: _addressCtrl,
          maxLines: 3,
          style: _valueStyle.copyWith(height: 1.5),
          decoration: _minimalDeco(hint: 'Street, Building, City'),
        )),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═══════════════════════════════════════════════════════
  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.45),
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Divider(
              height: 1,
              color: AppColors.borderLight.withValues(alpha: 0.3)),
          ...children,
        ],
      ),
    );
  }

  Widget _fieldRow(String label, Widget child, {bool optional = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              if (optional) ...[
                const SizedBox(width: 4),
                Text(
                  '(Optional)',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  Widget _sep() => Divider(
      height: 1, color: AppColors.borderLight.withValues(alpha: 0.3));

  TextStyle get _valueStyle => TextStyle(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
        fontSize: 15,
      );

  InputDecoration _minimalDeco({String hint = ''}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
      border: InputBorder.none,
      contentPadding: EdgeInsets.zero,
      isDense: true,
    );
  }

  void _showPicker(String title, List<String> options, int current,
      ValueChanged<int> onSelect) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
            ...options.asMap().entries.map((e) => ListTile(
                  title: Text(e.value),
                  trailing: e.key == current
                      ? const Icon(Icons.check_rounded,
                          color: Color(0xFFE67E22))
                      : null,
                  onTap: () {
                    onSelect(e.key);
                    Navigator.of(ctx).pop();
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

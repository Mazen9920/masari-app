import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/supplier_model.dart';

/// Add New Supplier — multi-section form.
class AddSupplierScreen extends ConsumerStatefulWidget {
  const AddSupplierScreen({super.key});

  @override
  ConsumerState<AddSupplierScreen> createState() => _AddSupplierScreenState();
}

class _AddSupplierScreenState extends ConsumerState<AddSupplierScreen> {
  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _category = '';
  bool _whatsapp = false;
  int _paymentTermIdx = 0;

  final _paymentTerms = ['On Receipt', 'Net 15', 'Net 30', 'Net 60'];
  final _categories = [
    'Packaging',
    'Raw Materials',
    'Logistics',
    'Maintenance',
    'Wholesale',
  ];

  bool get _canSave => _nameCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _balanceCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_canSave) return;
    HapticFeedback.mediumImpact();
    final supplier = Supplier(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      category: _category.isEmpty ? 'General' : _category,
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      whatsappAvailable: _whatsapp,
      paymentTerms: _paymentTerms[_paymentTermIdx],
      balance: double.tryParse(_balanceCtrl.text) ?? 0,
      address: _addressCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      supplierId: _idCtrl.text.trim(),
      lastTransaction: DateTime.now(),
    );
    ref.read(suppliersProvider.notifier).addSupplier(supplier);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${supplier.name} added'),
        backgroundColor: AppColors.primaryNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  children: [
                    _SupplierBasicsSection(
                      nameCtrl: _nameCtrl,
                      idCtrl: _idCtrl,
                      category: _category,
                      categories: _categories,
                      onCategoryChanged: (v) =>
                          setState(() => _category = v),
                      onChanged: () => setState(() {}),
                    ).animate().fadeIn(duration: 250.ms),
                    const SizedBox(height: 16),
                    _ContactInfoSection(
                      phoneCtrl: _phoneCtrl,
                      emailCtrl: _emailCtrl,
                      whatsapp: _whatsapp,
                      onWhatsappChanged: (v) =>
                          setState(() => _whatsapp = v),
                    ).animate().fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 16),
                    _PaymentDetailsSection(
                      paymentTerms: _paymentTerms,
                      selectedIdx: _paymentTermIdx,
                      onTermChanged: (i) =>
                          setState(() => _paymentTermIdx = i),
                      balanceCtrl: _balanceCtrl,
                    ).animate().fadeIn(duration: 250.ms, delay: 120.ms),
                    const SizedBox(height: 16),
                    _LocationNotesSection(
                      addressCtrl: _addressCtrl,
                      notesCtrl: _notesCtrl,
                    ).animate().fadeIn(duration: 250.ms, delay: 180.ms),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // Sticky save button
      bottomSheet: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          border: Border(
            top: BorderSide(
                color: AppColors.borderLight.withValues(alpha: 0.5)),
          ),
        ),
        child: GestureDetector(
          onTap: _save,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: _canSave
                  ? const Color(0xFFE67E22)
                  : const Color(0xFFE67E22).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
              boxShadow: _canSave
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE67E22)
                            .withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Save Supplier',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                iconSize: 26,
                color: AppColors.primaryNavy,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Add New Supplier',
                    style: AppTypography.h2.copyWith(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _canSave ? _save : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Save',
                    style: TextStyle(
                      color: _canSave
                          ? AppColors.primaryNavy
                          : AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Set up your supplier to start tracking purchases.',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SECTION 1 — SUPPLIER BASICS
// ═══════════════════════════════════════════════════════
class _SupplierBasicsSection extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController idCtrl;
  final String category;
  final List<String> categories;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onChanged;

  const _SupplierBasicsSection({
    required this.nameCtrl,
    required this.idCtrl,
    required this.category,
    required this.categories,
    required this.onCategoryChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _FormSection(
      title: 'SUPPLIER BASICS',
      children: [
        _FormField(
          label: 'Business Name',
          required: true,
          child: TextField(
            controller: nameCtrl,
            onChanged: (_) => onChanged(),
            decoration: _inputDecoration('e.g. Al-Amal Supplies'),
            style: _inputStyle,
          ),
        ),
        const SizedBox(height: 16),
        _FormField(
          label: 'Category',
          child: GestureDetector(
            onTap: () => _showCategoryPicker(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      category.isEmpty ? 'Select a category' : category,
                      style: TextStyle(
                        color: category.isEmpty
                            ? AppColors.textTertiary
                            : AppColors.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded,
                      color: AppColors.textTertiary, size: 22),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _FormField(
          label: 'Supplier ID',
          optional: true,
          child: TextField(
            controller: idCtrl,
            decoration: _inputDecoration('e.g. SUP-001'),
            style: _inputStyle,
          ),
        ),
      ],
    );
  }

  void _showCategoryPicker(BuildContext context) {
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
                'Select Category',
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
            ...categories.map((c) => ListTile(
                  title: Text(c),
                  trailing: c == category
                      ? const Icon(Icons.check_rounded,
                          color: Color(0xFFE67E22))
                      : null,
                  onTap: () {
                    onCategoryChanged(c);
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

// ═══════════════════════════════════════════════════════
//  SECTION 2 — CONTACT INFO
// ═══════════════════════════════════════════════════════
class _ContactInfoSection extends StatelessWidget {
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final bool whatsapp;
  final ValueChanged<bool> onWhatsappChanged;

  const _ContactInfoSection({
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.whatsapp,
    required this.onWhatsappChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _FormSection(
      title: 'CONTACT INFO',
      children: [
        _FormField(
          label: 'Phone Number',
          child: Row(
            children: [
              // Country code
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(10)),
                  border: Border.all(
                    color: AppColors.borderLight.withValues(alpha: 0.7),
                  ),
                ),
                child: Row(
                  children: [
                    const Text('🇪🇬',
                        style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(
                      '+20',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: '1x xxxx xxxx',
                    hintStyle:
                        TextStyle(color: AppColors.textTertiary, fontSize: 14),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(10)),
                      borderSide: BorderSide(
                        color: AppColors.borderLight.withValues(alpha: 0.7),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(10)),
                      borderSide: BorderSide(
                        color: AppColors.borderLight.withValues(alpha: 0.7),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(10)),
                      borderSide:
                          BorderSide(color: AppColors.primaryNavy),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                  style: _inputStyle,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _FormField(
          label: 'Email Address',
          optional: true,
          child: TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'supplier@example.com',
              hintStyle:
                  TextStyle(color: AppColors.textTertiary, fontSize: 14),
              prefixIcon: Icon(Icons.mail_outline_rounded,
                  color: AppColors.textTertiary, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.primaryNavy),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            style: _inputStyle,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WhatsApp Available',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Can communicate via WhatsApp?',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: whatsapp,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onWhatsappChanged(v);
              },
              activeColor: const Color(0xFFE67E22),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SECTION 3 — PAYMENT DETAILS
// ═══════════════════════════════════════════════════════
class _PaymentDetailsSection extends StatelessWidget {
  final List<String> paymentTerms;
  final int selectedIdx;
  final ValueChanged<int> onTermChanged;
  final TextEditingController balanceCtrl;

  const _PaymentDetailsSection({
    required this.paymentTerms,
    required this.selectedIdx,
    required this.onTermChanged,
    required this.balanceCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return _FormSection(
      title: 'PAYMENT DETAILS',
      children: [
        _FormField(
          label: 'Payment Terms',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(paymentTerms.length, (i) {
              final selected = selectedIdx == i;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTermChanged(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primaryNavy.withValues(alpha: 0.08)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? AppColors.primaryNavy
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    paymentTerms[i],
                    style: TextStyle(
                      color: selected
                          ? AppColors.primaryNavy
                          : AppColors.textSecondary,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        _FormField(
          label: 'Starting Balance (Debt)',
          child: TextField(
            controller: balanceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle:
                  TextStyle(color: AppColors.textTertiary, fontSize: 14),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Text(
                  'EGP',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.primaryNavy),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            style: _inputStyle,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SECTION 4 — LOCATION & NOTES
// ═══════════════════════════════════════════════════════
class _LocationNotesSection extends StatelessWidget {
  final TextEditingController addressCtrl;
  final TextEditingController notesCtrl;

  const _LocationNotesSection({
    required this.addressCtrl,
    required this.notesCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return _FormSection(
      title: 'LOCATION & NOTES',
      children: [
        _FormField(
          label: 'Address',
          child: TextField(
            controller: addressCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Street, Building No, City',
              hintStyle:
                  TextStyle(color: AppColors.textTertiary, fontSize: 14),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Icon(Icons.place_rounded,
                    color: AppColors.textTertiary, size: 20),
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.primaryNavy),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            style: _inputStyle,
          ),
        ),
        const SizedBox(height: 16),
        _FormField(
          label: 'Notes',
          optional: true,
          child: TextField(
            controller: notesCtrl,
            maxLines: 3,
            decoration: _inputDecoration('Add any additional details here...'),
            style: _inputStyle,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SHARED WIDGETS
// ═══════════════════════════════════════════════════════
class _FormSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _FormSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.borderLight.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final bool required;
  final bool optional;
  final Widget child;

  const _FormField({
    required this.label,
    this.required = false,
    this.optional = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (required)
              const Text(' *',
                  style: TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
            if (optional)
              Text(
                ' (Optional)',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

// Shared styling
InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: AppColors.borderLight.withValues(alpha: 0.7),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: AppColors.borderLight.withValues(alpha: 0.7),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.primaryNavy),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

TextStyle get _inputStyle => TextStyle(
      color: AppColors.textPrimary,
      fontSize: 15,
    );

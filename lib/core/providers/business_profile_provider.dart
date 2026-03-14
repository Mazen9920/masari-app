import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/user_profile_repository.dart';
import 'auth_provider.dart';
import 'repository_providers.dart';

// ─── State ───────────────────────────────────────────────────────────────────
class BusinessProfileState {
  final String businessName;
  final String businessType;
  final String address;
  final String taxId;
  final String? logoUrl;

  const BusinessProfileState({
    this.businessName = '',
    this.businessType = '',
    this.address      = '',
    this.taxId        = '',
    this.logoUrl,
  });

  BusinessProfileState copyWith({
    String? businessName,
    String? businessType,
    String? address,
    String? taxId,
    String? logoUrl,
  }) {
    return BusinessProfileState(
      businessName: businessName ?? this.businessName,
      businessType: businessType ?? this.businessType,
      address:      address      ?? this.address,
      taxId:        taxId        ?? this.taxId,
      logoUrl:      logoUrl      ?? this.logoUrl,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────
class BusinessProfileNotifier extends Notifier<BusinessProfileState> {
  @override
  BusinessProfileState build() {
    _load();
    return const BusinessProfileState();
  }

  String? get _uid => ref.read(authProvider).user?.id;

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;

    final repo = ref.read(userProfileRepositoryProvider);
    final result = await repo.getBusinessProfile(uid);
    if (result.isSuccess && result.data != null) {
      final b = result.data!;
      state = BusinessProfileState(
        businessName: b.businessName,
        businessType: b.businessType,
        address:      b.address,
        taxId:        b.taxId,
        logoUrl:      b.logoUrl,
      );
    }
  }

  Future<void> update({
    required String businessName,
    required String businessType,
    required String address,
    required String taxId,
    String? logoUrl,
  }) async {
    state = state.copyWith(
      businessName: businessName,
      businessType: businessType,
      address:      address,
      taxId:        taxId,
      logoUrl:      logoUrl,
    );

    final uid = _uid;
    if (uid == null) return;

    final repo = ref.read(userProfileRepositoryProvider);
    await repo.updateBusinessProfile(
      uid,
      BusinessProfile(
        businessName: businessName,
        businessType: businessType,
        address:      address,
        taxId:        taxId,
        logoUrl:      logoUrl ?? state.logoUrl,
      ),
    );
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────
final businessProfileProvider =
    NotifierProvider<BusinessProfileNotifier, BusinessProfileState>(() {
  return BusinessProfileNotifier();
});

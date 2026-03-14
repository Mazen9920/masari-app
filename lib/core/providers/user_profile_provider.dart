import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/user_profile_repository.dart';
import 'auth_provider.dart';
import 'repository_providers.dart';

// ─── State ───────────────────────────────────────────────────────────────────
class UserProfileState {
  final String name;
  final String email;
  final String phone;
  final String? avatarUrl;

  const UserProfileState({
    this.name  = '',
    this.email = '',
    this.phone = '',
    this.avatarUrl,
  });

  /// Returns up to two uppercase initials from the display name.
  String get initials {
    if (name.trim().isEmpty) return 'U';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  UserProfileState copyWith({String? name, String? email, String? phone, String? avatarUrl}) {
    return UserProfileState(
      name:  name  ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────
class UserProfileNotifier extends Notifier<UserProfileState> {
  @override
  UserProfileState build() {
    _load();
    return const UserProfileState();
  }

  String? get _uid => ref.read(authProvider).user?.id;

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;

    final repo = ref.read(userProfileRepositoryProvider);
    final result = await repo.getProfile(uid);

    if (result.isSuccess && result.data != null) {
      final p = result.data!;
      String name  = p.name;
      String email = p.email;
      String phone = p.phone;

      // Detect stale name (equals email-prefix fallback) and seed from auth user.
      final emailPrefix = email.isNotEmpty ? email.split('@').first : '';
      final authUser = ref.read(authProvider).user;
      if ((name.isEmpty || name == emailPrefix) && authUser != null) {
        name = authUser.name;
      }
      if (email.isEmpty && authUser != null) {
        email = authUser.email;
      }

      state = UserProfileState(
        name: name.isEmpty ? 'User' : name,
        email: email,
        phone: phone,
        avatarUrl: p.avatarUrl,
      );
    }
  }

  /// Persist a profile update and reflect it in state immediately.
  Future<void> update({
    required String name,
    required String email,
    required String phone,
    String? avatarUrl,
  }) async {
    state = state.copyWith(name: name, email: email, phone: phone, avatarUrl: avatarUrl);

    final uid = _uid;
    if (uid == null) return;

    final repo = ref.read(userProfileRepositoryProvider);
    await repo.updateProfile(
      uid,
      UserProfile(name: name, email: email, phone: phone, avatarUrl: avatarUrl ?? state.avatarUrl),
    );
  }

  /// Called after login/signup to seed from auth user if profile is still empty.
  Future<void> syncFromAuth() async {
    final uid = _uid;
    if (uid == null) return;

    final repo = ref.read(userProfileRepositoryProvider);
    final result = await repo.getProfile(uid);

    if (result.isSuccess && result.data != null) {
      final p = result.data!;
      final authUser = ref.read(authProvider).user;

      // Detect stale name: empty, or equals the email-prefix fallback
      final emailPrefix = (p.email.isNotEmpty ? p.email : authUser?.email ?? '').split('@').first;
      final nameIsStale = p.name.isEmpty || p.name == emailPrefix;

      if (nameIsStale || p.email.isEmpty) {
        if (authUser != null) {
          final newName  = nameIsStale    ? authUser.name  : p.name;
          final newEmail = p.email.isEmpty ? authUser.email : p.email;
          state = state.copyWith(name: newName, email: newEmail, phone: p.phone);
          await repo.updateProfile(
            uid,
            UserProfile(name: newName, email: newEmail, phone: p.phone),
          );
        }
      } else {
        state = UserProfileState(name: p.name, email: p.email, phone: p.phone);
      }
    }
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────
final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfileState>(() {
  return UserProfileNotifier();
});

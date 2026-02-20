import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/category_data.dart';
import '../../shared/models/product_model.dart';
import '../../shared/models/supplier_model.dart';

/// User state — stores user name from sign-up
class UserState {
  final String name;
  final String email;

  const UserState({
    required this.name,
    required this.email,
  });

  UserState copyWith({String? name, String? email}) {
    return UserState(
      name: name ?? this.name,
      email: email ?? this.email,
    );
  }
}

class UserNotifier extends Notifier<UserState> {
  @override
  UserState build() => const UserState(name: 'User', email: '');

  void setUser(String name, String email) {
    state = UserState(name: name, email: email);
  }

  void updateName(String name) {
    state = state.copyWith(name: name);
  }
}

final userProvider = NotifierProvider<UserNotifier, UserState>(() {
  return UserNotifier();
});

/// Transactions provider — manages list of transactions
class TransactionsNotifier extends Notifier<List<Transaction>> {
  @override
  List<Transaction> build() => SampleTransactions.all;

  void addTransaction(Transaction transaction) {
    state = [transaction, ...state];
  }

  void removeTransaction(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  void updateTransaction(Transaction transaction) {
    state = [
      for (final t in state)
        if (t.id == transaction.id) transaction else t,
    ];
  }

  void clearAll() {
    state = [];
  }

  void resetToSample() {
    state = SampleTransactions.all;
  }
}

final transactionsProvider =
    NotifierProvider<TransactionsNotifier, List<Transaction>>(() {
  return TransactionsNotifier();
});

/// Categories provider — manages user-created categories
class CategoriesNotifier extends Notifier<List<CategoryData>> {
  @override
  List<CategoryData> build() => List.from(CategoryData.all);

  void addCategory(CategoryData category) {
    state = [...state, category];
  }

  void removeCategory(String name) {
    state = state.where((c) => c.name != name).toList();
  }

  void updateCategory(String oldName, CategoryData updated) {
    state = [
      for (final c in state)
        if (c.name == oldName) updated else c,
    ];
  }
}

final categoriesProvider =
    NotifierProvider<CategoriesNotifier, List<CategoryData>>(() {
  return CategoriesNotifier();
});

/// Inventory provider — manages products
class InventoryNotifier extends Notifier<List<Product>> {
  @override
  List<Product> build() => List.from(sampleProducts);

  void addProduct(Product product) {
    state = [...state, product];
  }

  void removeProduct(String id) {
    state = state.where((p) => p.id != id).toList();
  }

  void updateProduct(String id, Product updated) {
    state = [
      for (final p in state)
        if (p.id == id) updated else p,
    ];
  }

  void adjustStock(String id, int delta, String reason) {
    state = [
      for (final p in state)
        if (p.id == id)
          p.copyWith(
            currentStock: (p.currentStock + delta).clamp(0, 999999),
            movements: [
              StockMovement(
                type: reason,
                quantity: delta,
                dateTime: DateTime.now(),
              ),
              ...p.movements,
            ],
          )
        else
          p,
    ];
  }
}

final inventoryProvider =
    NotifierProvider<InventoryNotifier, List<Product>>(() {
  return InventoryNotifier();
});

/// Suppliers provider — manages supplier list
class SuppliersNotifier extends Notifier<List<Supplier>> {
  @override
  List<Supplier> build() => List.from(sampleSuppliers);

  void addSupplier(Supplier supplier) {
    state = [...state, supplier];
  }

  void removeSupplier(String id) {
    state = state.where((s) => s.id != id).toList();
  }

  void updateSupplier(String id, Supplier updated) {
    state = [
      for (final s in state)
        if (s.id == id) updated else s,
    ];
  }

  void recordPayment(String id, double amount) {
    state = [
      for (final s in state)
        if (s.id == id)
          s.copyWith(balance: (s.balance - amount).clamp(0.0, double.infinity))
        else
          s,
    ];
  }
}

final suppliersProvider =
    NotifierProvider<SuppliersNotifier, List<Supplier>>(() {
  return SuppliersNotifier();
});

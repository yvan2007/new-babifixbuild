import 'package:flutter_riverpod/flutter_riverpod.dart';

class Category {
  final int id;
  final String name;
  final String? icon;
  final String? imageUrl;

  const Category({
    required this.id,
    required this.name,
    this.icon,
    this.imageUrl,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      icon: json['icon'],
      imageUrl: json['image'],
    );
  }
}

final categoriesProvider =
    StateNotifierProvider<CategoriesNotifier, AsyncValue<List<Category>>>((
      ref,
    ) {
      return CategoriesNotifier();
    });

class CategoriesNotifier extends StateNotifier<AsyncValue<List<Category>>> {
  CategoriesNotifier() : super(const AsyncValue.loading());

  void setCategories(List<Category> categories) {
    state = AsyncValue.data(categories);
  }

  void setLoading() {
    state = const AsyncValue.loading();
  }

  void setError(Object error) {
    state = AsyncValue.error(error, StackTrace.current);
  }
}

class Provider {
  final int id;
  final String name;
  final String? imageUrl;
  final String category;
  final double? rating;
  final double? price;
  final bool disponible;

  const Provider({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.category,
    this.rating,
    this.price,
    this.disponible = true,
  });

  factory Provider.fromJson(Map<String, dynamic> json) {
    return Provider(
      id: json['id'] ?? 0,
      name: json['name'] ?? json['prenom'] ?? '',
      imageUrl: json['image'],
      category: json['category'] ?? '',
      rating: (json['average_rating'] ?? json['note'] ?? 0).toDouble(),
      price: (json['tarif_horaire'] ?? json['price'] ?? 0).toDouble(),
      disponible: json['disponible'] ?? true,
    );
  }
}

final providersProvider =
    StateNotifierProvider<ProvidersNotifier, AsyncValue<List<Provider>>>((ref) {
      return ProvidersNotifier();
    });

class ProvidersNotifier extends StateNotifier<AsyncValue<List<Provider>>> {
  ProvidersNotifier() : super(const AsyncValue.loading());

  void setProviders(List<Provider> providers) {
    state = AsyncValue.data(providers);
  }

  void addProvider(Provider provider) {
    final current = state.value ?? [];
    state = AsyncValue.data([...current, provider]);
  }

  void updateProvider(Provider provider) {
    final current = state.value ?? [];
    final index = current.indexWhere((p) => p.id == provider.id);
    if (index >= 0) {
      final updated = [...current];
      updated[index] = provider;
      state = AsyncValue.data(updated);
    }
  }

  void setLoading() {
    state = const AsyncValue.loading();
  }

  void setError(Object error) {
    state = AsyncValue.error(error, StackTrace.current);
  }
}

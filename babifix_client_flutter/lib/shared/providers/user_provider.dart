import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserState {
  final bool isLoggedIn;
  final String? name;
  final String? email;
  final String? phone;
  final String? address;
  final String? avatarUrl;

  const UserState({
    this.isLoggedIn = false,
    this.name,
    this.email,
    this.phone,
    this.address,
    this.avatarUrl,
  });

  UserState copyWith({
    bool? isLoggedIn,
    String? name,
    String? email,
    String? phone,
    String? address,
    String? avatarUrl,
  }) {
    return UserState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}

final userProvider = StateNotifierProvider<UserNotifier, UserState>((ref) {
  return UserNotifier();
});

class UserNotifier extends StateNotifier<UserState> {
  UserNotifier() : super(const UserState());

  void login({
    required String name,
    required String email,
    String? phone,
    String? address,
    String? avatarUrl,
  }) {
    state = UserState(
      isLoggedIn: true,
      name: name,
      email: email,
      phone: phone,
      address: address,
      avatarUrl: avatarUrl,
    );
  }

  void logout() {
    state = const UserState();
  }

  void updateProfile({
    String? name,
    String? email,
    String? phone,
    String? address,
    String? avatarUrl,
  }) {
    state = state.copyWith(
      name: name,
      email: email,
      phone: phone,
      address: address,
      avatarUrl: avatarUrl,
    );
  }
}

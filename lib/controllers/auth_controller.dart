import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../models/user_model.dart';
import '../pages/main_layout.dart';
import '../services/db_service.dart';
import '../services/frontend_chat_service.dart';
import '../services/storage_service.dart';

class AuthController extends GetxController {
  final usernameC = TextEditingController();
  final passwordC = TextEditingController();
  final isLoading = false.obs;

  final currentUser = Rxn<User>();

  final DbService _db = Get.find();
  final StorageService _storage = Get.find();

  final FrontendChatService _chatService = Get.find();

  Future<void> checkAutoLogin() async {
    String? token = await _storage.getToken();
    if (token != null) {
      User? user = await _db.getUserByToken(token);
      if (user != null) {
        _loginSuccess(user);
      }
    }
  }

  Future<void> login() async {
    if (usernameC.text.isEmpty) return;
    isLoading.value = true;
    User? user = await _db.login(usernameC.text, passwordC.text);
    isLoading.value = false;
    if (user != null) {
      _loginSuccess(user);
    } else {
      Get.snackbar("Error", "Login failed");
    }
  }

  Future<void> register() async {
    if (usernameC.text.isEmpty) return;
    isLoading.value = true;
    String token = const Uuid().v4();
    User? user = await _db.register(usernameC.text, passwordC.text, token);
    isLoading.value = false;
    if (user != null) {
      _loginSuccess(user);
    } else {
      Get.snackbar("Error", "Register failed");
    }
  }

  void _loginSuccess(User user) async {
    await _storage.setToken(user.token);

    await _storage.setUserInfo(
      user.id,
      user.nickname ?? user.username,
      user.avatarUrl,
    );

    currentUser.value = user;

    _chatService.authenticate();

    ever(_chatService.isBackendAlive, (bool isAlive) {
      if (isAlive) {
        _db.updateOnlineStatus(user.id, true);
        debugPrint("🟢 [Auth] 用户已上线");
      }
    });

    Get.offAll(() => const MainLayout());
  }

  Future<void> refreshUser() async {
    final uid = _storage.getUserId();
    if (uid != null) {
      final user = await _db.getUserById(uid);
      if (user != null) {
        currentUser.value = user;
        await _storage.setUserInfo(
          user.id,
          user.nickname ?? "",
          user.avatarUrl,
        );
      }
    }
  }

  void logout() async {
    int? uid = _storage.getUserId();
    if (uid != null) await _db.updateOnlineStatus(uid, false);
    await _storage.clear();
    Get.offAllNamed('/');
  }
}

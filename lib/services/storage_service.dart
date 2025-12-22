import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService extends GetxService {
  late FlutterSecureStorage _secureStorage;
  late SharedPreferences _prefs;

  Future<StorageService> init() async {
    _secureStorage = const FlutterSecureStorage();
    _prefs = await SharedPreferences.getInstance();
    return this;
  }

  // Token 操作
  Future<void> setToken(String token) async {
    await _secureStorage.write(key: 'auth_token', value: token);
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: 'auth_token');
  }

  // 用户信息操作
  Future<void> setUserInfo(int id, String nickname, String? avatar) async {
    await _prefs.setInt('current_user_id', id);
    await _prefs.setString('current_user_name', nickname);
    if (avatar != null) {
      await _prefs.setString('current_user_avatar', avatar);
    }
  }

  int? getUserId() {
    return _prefs.getInt('current_user_id');
  }

  String getUserName() {
    return _prefs.getString('current_user_name') ?? "我";
  }

  String getUserAvatar() {
    return _prefs.getString('current_user_avatar') ?? "";
  }

  Future<void> clear() async {
    await _secureStorage.deleteAll();
    await _prefs.clear();
  }
}

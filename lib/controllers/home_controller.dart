import 'package:get/get.dart';

import '../models/post_model.dart';
import '../services/db_service.dart';

class HomeController extends GetxController {
  final DbService _db = Get.find();
  final posts = <Post>[].obs;
  final isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    loadPosts();
  }

  Future<void> loadPosts() async {
    isLoading.value = true;
    try {
      posts.value = await _db.getPosts();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> silentUpdate() async {
    final newPosts = await _db.getPosts();
    posts.value = newPosts;
  }

  Future<void> deletePost(int id) async {
    await _db.deletePost(id);
    loadPosts();
  }
}

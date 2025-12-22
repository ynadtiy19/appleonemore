import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  // 本地状态控制是登录还是注册，增加切换的灵活性
  final RxBool isLogin = true.obs;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<AuthController>();

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFC), // 延续启动页的纸张色
      body: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 100),

              // 1. 顶部意象标题
              _buildHeader(),

              const SizedBox(height: 60),

              // 2. 表单部分
              _buildInputField(
                controller: c.usernameC,
                label: "账号",
                hint: "请输入您的用户名",
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 20),
              _buildInputField(
                controller: c.passwordC,
                label: "密码",
                hint: "请输入您的密码",
                icon: Icons.lock_open_rounded,
                isPassword: true,
              ),

              const SizedBox(height: 40),

              // 3. 提交按钮
              Obx(() => _buildSubmitButton(c)),

              const SizedBox(height: 24),

              // 4. 底部切换链接
              Center(child: _buildToggleButton()),

              const Spacer(),

              // 5. 底部装饰语
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Text(
                    "让记录成为一种修行",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 顶部欢迎语
  Widget _buildHeader() {
    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isLogin.value ? "欢迎归来" : "遇见自然",
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF4A6CF7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isLogin.value ? "请登录您的账号以同步灵感" : "加入我们，开启一段静心的记录旅程",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // 现代感输入框
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 22),
              hintText: hint,
              hintStyle: const TextStyle(
                color: Color(0xFFD1D5DB),
                fontSize: 15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
            ),
          ),
        ),
      ],
    );
  }

  // 提交按钮
  Widget _buildSubmitButton(AuthController c) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: c.isLoading.value
          ? const Center(child: CircularProgressIndicator())
          : ElevatedButton(
              onPressed: isLogin.value ? c.login : c.register,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F2937), // 深色按钮显现代感
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                isLogin.value ? "立即登录" : "创建账号",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
    );
  }

  // 切换按钮
  Widget _buildToggleButton() {
    return Obx(
      () => TextButton(
        onPressed: () => isLogin.toggle(),
        style: TextButton.styleFrom(foregroundColor: const Color(0xFF4A6CF7)),
        child: Text.rich(
          TextSpan(
            text: isLogin.value ? "还没有账号？" : "已有账号？",
            style: const TextStyle(color: Color(0xFF6B7280)),
            children: [
              TextSpan(
                text: isLogin.value ? " 立即注册" : " 立即登录",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

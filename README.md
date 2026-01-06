# AppleOneMore 🍎

一个基于 **Flutter** 构建的现代化社交网络应用，具备实时通讯、动态社区流以及流畅的用户交互体验。本项目由 **Lsisql** 提供强大的数据管理支持。

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![Lsisql](https://img.shields.io/badge/Database-Lsisql-lightgrey?style=for-the-badge)

## 📱 Screenshots | 应用截图

### 👤 个人中心与社区动态

| 我的主页 (Profile) | 编辑资料 (Edit) | 社区动态 (Feed) | 帖子详情 (Detail) |
|:---:|:---:|:---:|:---:|
| <img src="https://github.com/user-attachments/assets/0b4efb87-b809-42aa-b141-1923975c37d8" width="200" alt="我的主页"/> | <img src="https://github.com/user-attachments/assets/06fad354-cbef-442e-933b-4526d74923b3" width="200" alt="编辑资料"/> | <img src="https://github.com/user-attachments/assets/62822dbd-518b-4986-a77c-0e7f8d0d9336" width="200" alt="社区动态"/> | <img src="https://github.com/user-attachments/assets/d3023aa6-c960-4243-b3e1-831328f1726d" width="200" alt="帖子详情"/> |

### 💬 聊天互动与工具

| 世界频道 (Chat) | 翻译功能 (Translation) | 语言选择 (Language) | 发布帖子 (Post Edit) |
|:---:|:---:|:---:|:---:|
| <img src="https://github.com/user-attachments/assets/62039614-e469-4350-863e-5ac269ef076a" width="200" alt="世界频道"/> | <img src="https://github.com/user-attachments/assets/df96ef6f-99ff-460b-84b2-d2998b903a6f" width="200" alt="翻译功能"/> | <img src="https://github.com/user-attachments/assets/da7026d3-3de4-41af-ae58-d3e8bec360da" width="200" alt="语言选择"/> | <img src="https://github.com/user-attachments/assets/95837035-7bb9-409d-9476-124fa91949e9" width="200" alt="发布帖子"/> |

## ✨ Features | 功能特性

*   **👤 用户个人系统**:
    *   支持自定义头像、昵称和个人简介。
    *   包含表单验证的个人资料编辑页面。
    *   关注/粉丝数量统计展示。
    *   支持外部链接跳转。

*   **📝 社区动态 (Feed)**:
    *   **富文本支持**：帖子内容支持丰富格式（如内马尔帖子演示）。
    *   **多图浏览**：支持九宫格或多图展示。
    *   **互动功能**：支持点赞和评论。
    *   包含时间戳和用户归属信息。

*   **💬 世界频道 (即时通讯)**:
    *   支持实时的全局聊天功能。
    *   支持文本气泡和图片消息发送。
    *   清晰的发送者（右侧）与接收者（左侧）UI 区分。

*   **🌐 国际化与工具**:
    *   **应用内翻译**：一键翻译帖子内容（支持自动检测语言）。
    *   **多语言支持**：可在简体中文、英语、日语、韩语、法语之间自由切换。

## 🛠 Tech Stack | 技术栈

*   **前端框架**: Flutter (Dart)
*   **数据库**: LibSQL
*   **架构模式**: MVVM (推荐)

## 🚀 Getting Started | 快速开始

如果要在本地运行此项目，请按照以下步骤操作：

### 环境要求

*   已安装 Flutter SDK ([安装指南](https://flutter.dev/docs/get-started/install))
*   Dart SDK
*   Libsql 数据库环境 (请确保数据库服务已启动)

### 安装步骤

1.  **克隆仓库**
    ```bash
    git clone https://github.com/ynadtiy19/appleonemore.git
    cd appleonemore
    ```

2.  **安装依赖**
    ```bash
    flutter pub get
    ```

3.  **运行应用**
    ```bash
    flutter run
    ```

## 🤝 Contributing | 贡献指南

欢迎提交贡献！请随意提交 Pull Request。

1.  Fork 本项目
2.  创建你的特性分支 (`git checkout -b feature/AmazingFeature`)
3.  提交你的更改 (`git commit -m 'Add some AmazingFeature'`)
4.  推送到分支 (`git push origin feature/AmazingFeature`)
5.  开启一个 Pull Request

## 📄 License | 开源协议

本项目基于 MIT 协议开源 - 详情请参阅 [LICENSE](LICENSE) 文件。

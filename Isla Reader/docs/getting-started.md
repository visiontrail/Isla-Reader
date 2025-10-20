# IslaBooks 开发快速开始

## 环境验证

运行环境验证脚本：
```bash
./scripts/verify-environment.sh
```

## 项目构建

```bash
# 构建项目
./scripts/build.sh

# 运行测试
./scripts/test.sh
```

## 开发流程

1. 在Xcode中打开项目：`open IslaBooks.xcodeproj`
2. 选择目标设备（iPhone 15模拟器）
3. 按Cmd+R运行项目
4. 按Cmd+U运行测试

## 常用命令

```bash
# 代码规范检查
swiftlint

# Git提交
git add .
git commit -m "feat: 添加新功能"

# 查看项目状态
git status
```

## 项目结构

```
IslaBooks/
├── IslaBooks/          # 主要源代码
├── IslaBooks Tests/    # 单元测试
├── IslaBooks UITests/  # UI测试
├── docs/              # 文档
└── scripts/           # 构建脚本
```

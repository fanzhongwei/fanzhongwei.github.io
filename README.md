# hexo-blog-fzw

个人博客网站（Hexo）。

## 环境要求

- Node.js 18+
- npm
- Hexo CLI

## 本地开发

1. 安装依赖：

```bash
npm install
```

2. 启动本地预览：

```bash
npx hexo clean
npx hexo g
npx hexo s
```

默认访问 `http://localhost:4000`。

## 部署说明

项目内置 `redeploy.sh`，脚本流程如下：

1. `git pull` 拉取远端最新代码
2. `node tools/safe-generate.js` 生成静态站点
3. `hexo deploy --repo ... --branch master` 执行发布

执行方式：

```bash
# 不传参数时，脚本会交互式选择发布目标
bash redeploy.sh
```

切换发布目标（GitHub / Gitee / 全部）：

```bash
# 发布到 GitHub（默认）
bash redeploy.sh github

# 发布到 Gitee
bash redeploy.sh gitee

# 依次发布到 GitHub 和 Gitee
bash redeploy.sh all
```

如果你的环境尚未安装 Hexo CLI，可先执行：

```bash
npm install -g hexo-cli
```

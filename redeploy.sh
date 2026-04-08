#!/bin/bash
set -euo pipefail

TARGET="${1:-}"
GITHUB_REPO="https://github.com/fanzhongwei/fanzhongwei.github.io.git"
GITEE_REPO="git@gitee.com:fanzhongwei/fanzhongwei.gitee.io.git"

if [ -z "$TARGET" ]; then
  echo "请选择发布目标："
  echo "1) github"
  echo "2) gitee"
  echo "3) all"
  read -r -p "输入选项 [1-3]: " choice
  case "$choice" in
    1) TARGET="github" ;;
    2) TARGET="gitee" ;;
    3) TARGET="all" ;;
    *)
      echo "无效选项，请输入 1/2/3"
      exit 1
      ;;
  esac
fi

case "$TARGET" in
  github)
    DEPLOY_REPOS=("$GITHUB_REPO")
    ;;
  gitee)
    DEPLOY_REPOS=("$GITEE_REPO")
    ;;
  all)
    DEPLOY_REPOS=("$GITHUB_REPO" "$GITEE_REPO")
    ;;
  *)
    echo "Usage: bash redeploy.sh [github|gitee|all]"
    exit 1
    ;;
esac

echo 'Update remote code!'

git pull

node tools/safe-generate.js

for repo in "${DEPLOY_REPOS[@]}"; do
  echo "Deploying to: $repo"
  hexo deploy --repo "$repo" --branch master
done

echo 'Hexo server is deployed!'
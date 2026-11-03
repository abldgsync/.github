#!/usr/bin/env bash
# Docker Desktop 配置: 元数据 + s1_parse()
# 每日构建: 不解析版本号, 按日期打标签(vYYYY.MM.DD), 从固定 URL 下载各平台安装包。
# 上游无官方哈希, 故 CHECKSUM=skip(S3 为空操作)。
NAME="Docker Desktop"
URL_BASE=""
CHECKSUM=skip
TAG_PREFIX=""
KEEP=1

s1_parse() {
  local vtag="v$(date +'%Y.%m.%d')"
  echo "${vtag}" > "${FILE_VERSIONS}"
  local bf="${RUNNER_TEMP}/${vtag}-binfiles.txt"
  # 每行 "<url>|<本地文件名>"; 下载后扁平存入 dist/${vtag}/
  cat > "$bf" <<'EOF'
https://get.docker.com|linux.sh
https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe|docker_desktop_installer_windows_amd64.exe
https://desktop.docker.com/win/main/arm64/Docker%20Desktop%20Installer.exe|docker_desktop_installer_windows_arm64.exe
https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb|docker_desktop_installer_linux_amd64.deb
https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm|docker_desktop_installer_linux_amd64.rpm
https://desktop.docker.com/mac/main/amd64/Docker.dmg|docker_desktop_installer_darwin_amd64.dmg
https://desktop.docker.com/mac/main/arm64/Docker.dmg|docker_desktop_installer_darwin_arm64.dmg
EOF
  echo "生成的发布标签为: ${vtag}"
}

# 覆盖默认标题/说明以契合每日构建语义
title_for() {
  local VN="$1"
  echo "Daily Build - ${VN}"
}

notes_for() {
  local VN="$1"
  echo "这是一个自动生成的每日构建发布。
  - 构建时间: ${VN}"
}

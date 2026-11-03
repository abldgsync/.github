#!/usr/bin/env bash
# 共享函数: 初始化、下载(step2)、校验(step3)、发布(step4) 与调度辅助。
# 各工具的差异仅体现在 tools/<tool>.sh 的元数据(NAME/URL_BASE/CHECKSUM/...)与 s1_parse()。

# ---------- 公共初始化 ----------
init_common() {
  export CURL_OPTS="--retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 15 --max-time 1800"
  export RUNNER_TEMP="${RUNNER_TEMP:-$PWD}"
  export FILE_VERSIONS="${RUNNER_TEMP}/versions.txt"
  export FILE_ALL_TAGS="${RUNNER_TEMP}/all_tags.txt"
  export FILE_RELSJSON="${RUNNER_TEMP}/releases.json"
  export FILE_INDEXJSON="${RUNNER_TEMP}/index.json"
  # 工具可选元数据默认值(可被 tools/*.sh 覆盖)
  : "${CHECKSUM:=sha256}"
  : "${TAG_PREFIX:=}"
  : "${KEEP:=2}"
}

# 工具可选钩子: 在 init_common 之后、各 step 之前执行(默认空实现)
init_tool() { :; }

# ---------- S1: 解析版本(委托给各工具的 s1_parse) ----------
step1() { s1_parse; }

# ---------- S2: 并行下载(全工具共用) ----------
# binfiles.txt 每行: "<url>[|<本地文件名>]"; 不写本地名时默认取 URL basename。
download_one() {
  local line="$1" url lname
  url="${line%%|*}"
  lname="${line#*|}"
  [[ "$lname" == "$line" ]] && lname="${url##*/}"
  local i
  for i in 1 2 3; do
    if curl ${CURL_OPTS} -4fL -o "dist/${VN}/${lname}" "$url"; then
      return 0
    fi
    [[ $i -lt 3 ]] && sleep $((i * 3))
  done
  echo "::error::下载失败: $url"
  return 1
}

step2() {
  mkdir -p dist
  local VN bf
  for VN in $(xargs < "${FILE_VERSIONS}"); do
    [[ -z "$VN" ]] && continue
    bf="${RUNNER_TEMP}/${VN}-binfiles.txt"
    if [[ ! -s "$bf" ]]; then
      echo "::error::未找到版本 ${VN} 的下载清单: ${bf}"
      exit 1
    fi
    echo "=====> [S2] 下载版本: ${VN}"
    rm -rf "dist/${VN}"
    mkdir -p "dist/${VN}"
    export CURL_OPTS VN
    export -f download_one
    if ! xargs -P 8 -I@ bash -c 'download_one "$1"' _ @ < "$bf"; then
      echo "::error::版本 ${VN} 下载失败"
      exit 1
    fi
  done
  echo "下载完成,文件数: $(find dist -type f | wc -l)"
}

# ---------- S3: 校验(按 CHECKSUM 类型分发) ----------
#   sha256 / sha512 -> 本地 <VN>-manifest.txt 做 sum -c
#   online          -> 联网取 <url>.sha256 与本地比对(源站提供独立 .sha256 文件)
#   skip            -> 无官方哈希, 空操作
step3() {
  local VN mf bf fail=0 url lname sum actual
  case "$CHECKSUM" in
    skip)
      echo "本模块无官方哈希校验,跳过 S3"
      return 0
      ;;
    online)
      for VN in $(xargs < "${FILE_VERSIONS}"); do
        [[ -z "$VN" ]] && continue
        bf="${RUNNER_TEMP}/${VN}-binfiles.txt"
        echo "=====> [S3] 校验版本: ${VN}(在线比对)"
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          url="${line%%|*}"; lname="${line#*|}"; [[ "$lname" == "$line" ]] && lname="${url##*/}"
          sum=$(curl ${CURL_OPTS} -4fsSL "${url}.sha256" | awk '{print $1}') || true
          actual=$(sha256sum "dist/${VN}/${lname}" | awk '{print $1}')
          if [[ "$sum" != "$actual" ]]; then
            echo "::error::校验失败: ${VN}/${lname}"
            fail=1
          fi
        done < "$bf"
      done
      ;;
    *)
      for VN in $(xargs < "${FILE_VERSIONS}"); do
        [[ -z "$VN" ]] && continue
        mf="${RUNNER_TEMP}/${VN}-manifest.txt"
        if [[ ! -s "$mf" ]]; then
          echo "::warning::跳过无校验清单的版本 ${VN}"
          continue
        fi
        echo "=====> [S3] 校验版本: ${VN}"
        if ! (cd "dist/${VN}" && ${CHECKSUM}sum -c "$mf"); then
          echo "::error::校验失败: ${VN}"
          fail=1
        fi
      done
      ;;
  esac
  if [[ $fail -ne 0 ]]; then
    echo "::error::存在校验失败的版本"
    exit 1
  fi
  [[ "$CHECKSUM" != "skip" ]] && echo "${CHECKSUM}sum 校验通过"
}

# ---------- S4: 发布到 GitHub Releases(全工具共用) ----------
# 逐个 tag 发布: 首个(最新)版本标 --latest, 其余 --latest=false。
# 已存在的 release 先删除再重建, 保证可重复运行。
title_for() {
  local VN="$1"
  echo "${NAME} ${VN} Binaries"
}

notes_for() {
  local VN="$1"
  echo "同步自 ${NAME} 官网的二进制程序 (版本: ${VN}, 官网: ${URL_BASE})"
}

step4() {
  local VN first=1 TAG title notes
  shopt -s nullglob
  for VN in $(xargs < "${FILE_VERSIONS}"); do
    [[ -z "$VN" ]] && continue
    TAG="${TAG_PREFIX}${VN}"
    echo "=====> [S4] 发布版本: ${TAG}"
    if [[ ! -d "dist/${VN}" ]] || [[ $(find "dist/${VN}" -type f | wc -l) -eq 0 ]]; then
      echo "::error::${TAG} 无可发布文件"
      exit 1
    fi
    if gh release view "$TAG" > /dev/null 2>&1; then
      echo "::notice::已存在 release ${TAG}, 先删除再重建"
      gh release delete "$TAG" -y
    fi
    title="$(title_for "$VN")"
    notes="$(notes_for "$VN")"
    if [[ $first -eq 1 ]]; then
      gh release create "$TAG" dist/"$VN"/* --title "$title" --notes "$notes"
      first=0
    else
      gh release create "$TAG" dist/"$VN"/* --title "$title" --notes "$notes" --latest=false
    fi
  done
}

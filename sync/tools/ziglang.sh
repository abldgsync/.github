#!/usr/bin/env bash
# Zig 配置: 元数据 + s1_parse()
# WANT 语义: 空->最新 LAST_N 个稳定版; 0.15->0.15 系列最新 LAST_N 个; 0.15.2->精确
# LAST_N: 保留版本数(默认 4)
NAME="Zig"
URL_BASE="https://ziglang.org/download/"
CHECKSUM=sha256
TAG_PREFIX="v"            # release tag 采用 v 前缀(v${VN})以延续历史命名
KEEP="${LAST_N:-4}"
INDEX_URL="https://ziglang.org/download/index.json"

s1_parse() {
  if [ ! -f "${FILE_INDEXJSON}" ]; then
    if ! curl ${CURL_OPTS} -4fsSL -o "${FILE_INDEXJSON}" "${INDEX_URL}"; then
      echo "::error::获取版本清单失败: ${INDEX_URL}"
      exit 1
    fi
    if ! jq -e 'type == "object"' "${FILE_INDEXJSON}" > /dev/null 2>&1; then
      echo "::error::获取的版本清单不是有效的JSON对象"
      exit 1
    fi
  fi
  jq -r 'keys[]' "${FILE_INDEXJSON}" \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -Vr > "${FILE_ALL_TAGS}"

  if [[ -z "${WANT:-}" ]]; then
    head -n "${KEEP}" "${FILE_ALL_TAGS}" > "${FILE_VERSIONS}"
  else
    awk '/^.'"${WANT#[Vv]}"'\./' "${FILE_ALL_TAGS}" | head -n "${KEEP}" > "${FILE_VERSIONS}"
  fi
  if [[ $(wc -l < "${FILE_VERSIONS}") -eq 0 ]]; then
    echo "::error::未匹配到任何稳定版本(输入: ${WANT:-<空>})"
    exit 1
  fi

  local VN mf bf jqm jqb
  jqm='.[$vn] | to_entries[] | .value | select(type == "object" and (.tarball != null) and (.shasum != null)) | [.shasum, (.tarball | split("/")[-1])] | join("  ")'
  jqb='.[$vn] | to_entries[] | .value | select(type == "object" and (.tarball != null) and (.shasum != null)) | .tarball'
  for VN in $(xargs < "${FILE_VERSIONS}"); do
    mf="${RUNNER_TEMP}/${VN}-manifest.txt"
    bf="${RUNNER_TEMP}/${VN}-binfiles.txt"
    jq -r --arg vn "$VN" "${jqm}" "${FILE_INDEXJSON}" > "$mf"
    jq -r --arg vn "$VN" "${jqb}" "${FILE_INDEXJSON}" > "$bf"
    echo "解析到版本: ${VN} ($(wc -l < ${mf}) 个资源)"
  done
}

#!/usr/bin/env bash
# Golang 配置: 元数据 + s1_parse()
# WANT 语义: 空->最新两个稳定版; 1.25/go1.25->1.25 系列最新; 1.25.0->精确稳定版
NAME="Golang"
URL_BASE="${BASE_URL:-https://go.dev/dl/}"
CHECKSUM=sha256
TAG_PREFIX=""
KEEP=2

s1_parse() {
  local url_json_rels="${URL_BASE}?mode=json"
  if [ -n "${WANT:-}" ]; then
    url_json_rels="${URL_BASE}?mode=json&include=all"
    if [ -s "${FILE_RELSJSON}" ] && ! grep -q 'go1.9.2rc2.src.tar.gz' "${FILE_RELSJSON}"; then
      rm -f "${FILE_RELSJSON}"
    fi
  else
    if [ -s "${FILE_RELSJSON}" ] \
      && [ "$(jq -r '.[]|select(.stable)|.version' "${FILE_RELSJSON}" | wc -l)" -gt 100 ]; then
      rm -f "${FILE_RELSJSON}"
    fi
  fi
  if [ ! -e "${FILE_RELSJSON}" ]; then
    if ! curl ${CURL_OPTS} -4fsSLo "${FILE_RELSJSON}" "${url_json_rels}"; then
      echo "::error::获取版本清单失败: ${url_json_rels}"
      exit 1
    fi
  fi
  if ! jq -e 'type == "array" and length > 0' "${FILE_RELSJSON}" &>/dev/null; then
    echo "::error::获取的版本清单不是有效的JSON数组"
    exit 1
  fi
  jq -r '.[]|select(.stable)|.version' "${FILE_RELSJSON}" > "${FILE_ALL_TAGS}"

  if [[ -z "${WANT:-}" ]]; then
    head -n "${KEEP}" "${FILE_ALL_TAGS}" > "${FILE_VERSIONS}"
  else
    awk '/^..'"${WANT#[Vv]}"'\./&&!/(rc|beta|alpha)/' "${FILE_ALL_TAGS}" | head -n 1 > "${FILE_VERSIONS}"
  fi

  local VN mf bf
  for VN in $(xargs < "${FILE_VERSIONS}"); do
    mf="${RUNNER_TEMP}/${VN}-manifest.txt"
    bf="${RUNNER_TEMP}/${VN}-binfiles.txt"
    jq -r --arg vn "$VN" --arg base "$URL_BASE" \
      'map(select(.version == $vn)) | .[0].files[]?
       | select(.sha256 != null and .sha256 != "")
       | "\($base)\(.filename)|\(.filename)"' "${FILE_RELSJSON}" > "${bf}"
    jq -r --arg vn "$VN" \
      'map(select(.version == $vn)) | .[0].files[]?
       | select(.sha256 != null and .sha256 != "")
       | "\(.sha256)  \(.filename)"' "${FILE_RELSJSON}" > "${mf}"
    if [[ ! -s "${mf}" ]]; then
      echo "::error::版本 ${VN} 未找到可下载资源"
      exit 1
    fi
  done
  echo "解析到版本: $(xargs < ${FILE_VERSIONS}) (共 $(wc -l < ${FILE_VERSIONS}) 个)"
}

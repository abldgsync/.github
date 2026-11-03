#!/usr/bin/env bash
# Kubectl 配置: 元数据 + s1_parse()
# WANT 语义: 空->最新四个稳定版; v1.33/1.33->系列最新; v1.33.6->精确
# WXSV(0|1): 是否包含 server/node 包
NAME="Kubectl"
URL_BASE="${BASE_URL:-https://dl.k8s.io/}"
CHECKSUM=sha512
TAG_PREFIX=""
KEEP=4
WXSV="${WXSV:-1}"
URL_API="${API:-https://api.github.com/repos/kubernetes/kubernetes/releases}"

s1_parse() {
  if [ ! -e "${FILE_RELSJSON}" ]; then
    echo '[]' > "${FILE_RELSJSON}"
    local page=1
    while true; do
      if ! curl ${CURL_OPTS} -fsSL "${URL_API}?per_page=100&page=${page}" -o pjson; then
        echo "::error::拉取 release 列表失败: ${URL_API}"
        exit 1
      fi
      if [[ "$(jq 'length' pjson)" -lt 100 ]]; then break; fi
      jq -s '.[0] + .[1]' "${FILE_RELSJSON}" pjson > tmp.json && mv tmp.json "${FILE_RELSJSON}"
      ((page++))
    done
    rm -f pjson
  fi
  jq -r '.[]|select(.prerelease==false)|.tag_name' "${FILE_RELSJSON}" > "${FILE_ALL_TAGS}"

  if [[ -z "${WANT:-}" ]]; then
    head -n "${KEEP}" "${FILE_ALL_TAGS}" > "${FILE_VERSIONS}"
  else
    awk '/^.'"${WANT#[Vv]}"'\./' "${FILE_ALL_TAGS}" | head -n 1 > "${FILE_VERSIONS}"
  fi
  if [[ $(wc -l < "${FILE_VERSIONS}") -eq 0 ]]; then
    echo "::error::未匹配到任何稳定版本(输入: ${WANT:-<空>})"
    exit 1
  fi

  local VN bf mf
  for VN in $(xargs < "${FILE_VERSIONS}"); do
    bf="${RUNNER_TEMP}/${VN}-binfiles.txt"
    mf="${RUNNER_TEMP}/${VN}-manifest.txt"
    curl -fsSL "${URL_BASE}${VN}/SHA512SUMS" | awk '/.tar.gz$/' > tmpsums
    if [[ "${WXSV}" == "1" ]]; then
      awk '!/(test|manifest)/' tmpsums
    else
      awk '!/(test|manifest|server|node)/' tmpsums
    fi > "${mf}"
    rm -f tmpsums
    awk -v b="${URL_BASE}${VN}/" '{print b $2}' "${mf}" > "${bf}"
  done
  echo "解析到版本: $(xargs < ${FILE_VERSIONS}) (共 $(wc -l < ${FILE_VERSIONS}) 个)"
}

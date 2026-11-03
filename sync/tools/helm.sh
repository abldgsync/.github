#!/usr/bin/env bash
# Helm 配置: 元数据 + s1_parse()
# WANT 语义: 空->最新两个稳定版; v3/3->v3 系列最新; v3.19->最新 patch; v3.19.2->精确
NAME="Helm"
URL_BASE="https://get.helm.sh/"
CHECKSUM=online          # 源站提供独立 .sha256 文件, 在线比对
TAG_PREFIX=""
KEEP=2
URL_API="https://api.github.com/repos/helm/helm/releases"

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

  local VN bf jqpat
  jqpat='.[]|select(.tag_name==$t)|.assets[].name|select(endswith(".sha256.asc"))|rtrimstr(".sha256.asc")'
  for VN in $(xargs < "${FILE_VERSIONS}"); do
    bf="${RUNNER_TEMP}/${VN}-binfiles.txt"
    jq -r --arg t "$VN" "${jqpat}" "${FILE_RELSJSON}" \
      | grep -v 'loong' | awk -v b="$URL_BASE" '{print b $0}' > "${bf}"
  done
  echo "解析到版本: $(xargs < ${FILE_VERSIONS})"
}

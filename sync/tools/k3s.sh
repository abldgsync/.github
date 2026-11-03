#!/usr/bin/env bash
# K3s 配置: 元数据 + s1_parse()
# WANT 语义: 空->最新四个稳定版; v1.31/1.31->系列最新; v1.31.0+k3s1->精确
# WXAIR(0|1): 是否包含离线镜像包(默认 1)
NAME="K3s"
URL_BASE="https://github.com/k3s-io/k3s/releases/download/"
CHECKSUM=sha256
TAG_PREFIX=""
KEEP=4
URL_API="${API:-https://api.github.com/repos/k3s-io/k3s/releases}"
GHCDN="${GHCDN:-https://ghfast.top/}"

s1_parse() {
  if [ ! -e "${FILE_RELSJSON}" ]; then
    echo '[]' > "${FILE_RELSJSON}"
    local page=1 cnt
    while true; do
      if ! curl ${CURL_OPTS} -fsSL "${URL_API}?per_page=100&page=${page}" -o pjson; then
        echo "::error::拉取 release 列表失败: ${URL_API}"
        exit 1
      fi
      cnt=$(jq 'length' pjson)
      [[ "${cnt}" -eq 0 ]] && break
      jq -s '.[0] + .[1]' "${FILE_RELSJSON}" pjson > tmp.json && mv tmp.json "${FILE_RELSJSON}"
      page=$((page + 1))
      [[ ${page} -gt 10 ]] && break
    done
  fi
  rm -f pjson tmp.json
  jq -r '.[] | select(.prerelease==false and .draft==false) | .tag_name
         | select(test("^v[0-9]+[.][0-9]+[.][0-9]+[+]k3s[.]?[0-9]+$"))' \
    "${FILE_RELSJSON}" > "${FILE_ALL_TAGS}"

  local VN
  if [[ -n "${WANT:-}" ]]; then
    VN=$(awk -v p="v${WANT#[Vv]}" 'index($0,p)==1{print;exit}' "${FILE_ALL_TAGS}")
    if [[ -z "${VN}" ]]; then
      echo "::error::未匹配到任何稳定版本(输入: ${WANT})"
      exit 1
    fi
    printf '%s\n' "${VN}" > "${FILE_VERSIONS}"
  else
    head -n "${KEEP}" "${FILE_ALL_TAGS}" > "${FILE_VERSIONS}"
  fi
  if [[ $(wc -l < "${FILE_VERSIONS}") -eq 0 ]]; then
    echo "::error::未匹配到任何稳定版本(输入: ${WANT:-<空>})"
    exit 1
  fi

  local bf mf jqpat jqpat2 CF
  for VN in $(xargs < "${FILE_VERSIONS}"); do
    bf="${RUNNER_TEMP}/${VN}-binfiles.txt"
    mf="${RUNNER_TEMP}/${VN}-manifest.txt"
    jqpat='.[] | select(.tag_name=="'"${VN}"'") | .assets[]'
    jqpat+='| select(.name|test("^sha256sum-.*[.]txt$"))|.browser_download_url'
    for u in $(jq -r "${jqpat}" "${FILE_RELSJSON}"); do
      curl -4fsSL "${GHCDN}${u}"
    done > "$mf"
    if [[ ! -s "$mf" ]]; then
      echo "::error::版本 ${VN} 未找到可下载资产"
      exit 1
    fi
    jqpat2='.[] | select(.tag_name=="'"${VN}"'") | .assets[]'
    jqpat2+='| select(.name == $cf)| .browser_download_url'
    for CF in $(awk '{print $2}' "$mf"); do
      jq -r --arg cf "$CF" "${jqpat2}" "${FILE_RELSJSON}"
    done > "$bf"
  done
  echo "解析到版本: $(xargs < ${FILE_VERSIONS}) (共 $(wc -l < ${FILE_VERSIONS}) 个)"
}

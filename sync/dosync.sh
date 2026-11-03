#!/usr/bin/env bash
# 统一入口(极薄): 注入 TOOL(由 action.yaml 的 env.TOOL 提供),
# 加载共享逻辑 common.sh 与工具专属配置 tools/${TOOL}.sh, 再按 CS 调度。
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="${TOOL:?未设置 TOOL 环境变量(应由 action.yaml 通过 env.TOOL 注入)}"

# shellcheck source=common.sh
source "$SELF_DIR/common.sh"

if [[ ! -f "$SELF_DIR/tools/${TOOL}.sh" ]]; then
  echo "::error::未找到工具配置: ${TOOL} (期望 $SELF_DIR/tools/${TOOL}.sh)"
  exit 1
fi
# shellcheck source=tools/golang.sh (实际按 TOOL 选择)
source "$SELF_DIR/tools/${TOOL}.sh"

init_common
init_tool 2>/dev/null || true

# ---------- 调度 ----------
case ${CS:-} in
  1) step1 ;;
  2) step2 ;;
  3) step3 ;;
  4) step4 ;;
  *) echo "::error::非法阶段 CS=${CS:-<空>}(仅支持 1~4)" && exit 1 ;;
esac

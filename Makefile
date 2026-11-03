# Makefile —— 辅助通过 gh CLI 触发 abldgsync 各仓库的同步工作流
#
# 前置条件: gh CLI 已登录, 且对 abldgsync 组织具备 workflow 触发权限。
#
# 用法示例:
#   make sync TOOL=golang                  # 触发 golang(默认最新稳定版)
#   make sync TOOL=golang binvern=1.25.0   # 指定版本
#   make sync TOOL=kubectl withsvr=0       # 不含 server/node 包
#   make sync TOOL=ziglang lastn=6         # 保留 6 个最新稳定版
#   make sync TOOL=docker_desktop          # 每日构建(无额外入参)
#   make sync-all                          # 全部 6 个仓库按默认参数触发
#   make list                              # 查看各仓库工作流状态
#   make help                              # 查看帮助

ORG      ?= abldgsync
WORKFLOW ?= dosync.yaml
REF      ?= main
TOOLS    := golang helm kubectl k3s ziglang docker_desktop

# 仅在对应变量被赋值时追加 -f 字段(docker_desktop 无这些入参, 请勿对其传参)
FIELD_FLAGS:=
FIELD_FLAGS+=$(if $(binvern),-f binvern=$(binvern))
FIELD_FLAGS+=$(if $(withsvr),-f withsvr=$(withsvr))
FIELD_FLAGS+=$(if $(lastn),-f lastn=$(lastn))

.PHONY: sync sync-all list help

help:
	@echo "用法: make sync TOOL=<tool> [binvern=..] [withsvr=0|1] [lastn=N]"
	@echo "      make sync-all            # 触发全部工具(默认参数, 不含额外入参)"
	@echo "      make list                # 列出各仓库工作流"
	@echo "TOOL 可选: $(TOOLS)"

sync:
	@test -n "$(TOOL)" || { echo "错误: 必须指定 TOOL, 例如 make sync TOOL=golang"; exit 1; }
	@case " $(TOOLS) " in \
	*" $(TOOL) "*) ;; \
	*) echo "错误: 未知 TOOL=$(TOOL), 可选: $(TOOLS)"; exit 1;; \
	esac
	gh workflow run $(WORKFLOW) --repo $(ORG)/$(TOOL) --ref $(REF) $(FIELD_FLAGS)

sync-all:
	@for t in $(TOOLS); do \
	  echo "==> 触发 $$t"; \
	  gh workflow run $(WORKFLOW) --repo $(ORG)/$$t --ref $(REF) || echo "    !! $$t 触发失败, 跳过"; \
	done

list:
	@for t in $(TOOLS); do \
	  echo "==> $(ORG)/$$t"; \
	  gh workflow list --repo $(ORG)/$$t || true; \
	done

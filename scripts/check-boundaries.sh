#!/usr/bin/env bash
#
# Linva 依赖边界校验 —— AI 原生 SDLC 现状治理清单 A（方案二）
#
# 依据: docs/现状治理-AI原生SDLC.md §3-A、docs/架构现状.md §5 依赖规则
# 作用: 扫描各层源码的 import，凡不在该层"允许白名单"内的模块 → 报错退出 1。
#       这是手册「钩子作为构建期护栏」的落地: 让"目录/依赖纪律"从约定变为强制。
#
# 用法:
#   scripts/check-boundaries.sh [源码根目录]
#     - 缺省参数: 取本脚本所在目录的上一级（仓库根）下的 LinvaApp/LinvaApp
#     - 在 Xcode build phase 中调用时传 ${SRCROOT}/LinvaApp
#
# 退出码: 0 = 全部通过; 1 = 存在违规（Xcode build phase 会因此让构建失败）

set -u

# ---------- 白名单（严格收紧版，与实况核对一致） ----------
# 格式: 目录|允许的模块（空格分隔，忽略顺序）
# 原则: 越靠下越"纯净"; Model/Commands 严禁任何 UI/渲染依赖。
ALLOW_RULES=(
  "Model|Foundation"
  "Commands|Foundation"
  "Layout|Foundation AppKit CoreGraphics CoreText"
  "Session|Foundation Combine CoreGraphics"
  # Render 追加 ImageIO：ImageTextureCache CGImageSource 降采样解码（2026-10-01 图片节点）。
  # Render 追加 Combine：CanvasMTKView 命令式订阅 session.objectWillChange 触发重绘，
  #   规避 camera 高频发布触发的 SwiftUI 整树重布局（2026-10-03 画布性能 R5）。
  "Render|Foundation AppKit Combine CoreGraphics ImageIO Metal MetalKit SwiftUI simd"
  # App 追加 ImageIO：图片归一器 CGImageSource 解码（2026-10-01 图片节点）。
  "App|Foundation AppKit SwiftUI ImageIO"
)

# 源码根: 缺省推导仓库根下的 LinvaApp/LinvaApp
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_ROOT="${1:-$REPO_ROOT/LinvaApp/LinvaApp}"

if [ ! -d "$SRC_ROOT" ]; then
  echo "错误: 源码目录不存在: $SRC_ROOT" >&2
  exit 2
fi

fail=0

for rule in "${ALLOW_RULES[@]}"; do
  dir="${rule%%|*}"
  allowed="${rule#*|}"
  # 转成 grep -E 匹配串: 每个模块成独立词（^X$，sed 已剥掉 import 前缀），用 | 连接
  allowed_pattern="^($(echo "$allowed" | tr ' ' '|'))$"

  layer_dir="$SRC_ROOT/$dir"
  if [ ! -d "$layer_dir" ]; then
    echo "警告: 层目录不存在，跳过: $dir" >&2
    continue
  fi

  # 提取该层所有 Swift 文件的顶层 import
  while IFS= read -r imp; do
    # 跳过非 import 行（read 来自 find+sed，已保证是 import）
    if ! echo "$imp" | grep -qE "$allowed_pattern"; then
      echo "依赖违规 [${dir}]: ${imp}"
      fail=1
    fi
  done < <(find "$layer_dir" -name '*.swift' -type f -exec sed -nE 's/^import[[:space:]]+([A-Za-z0-9_]+).*/\1/p' {} \; | sort -u)
done

if [ "$fail" -ne 0 ]; then
  echo "依赖边界检查失败: 上述层引入了未授权模块。请把新依赖加到 docs/架构现状.md §5 并在本脚本白名单注明理由。" >&2
  exit 1
fi

echo "依赖边界检查通过: 各层 import 均在白名单内。"
exit 0

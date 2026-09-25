/**
 * YMind HTML Prototype
 * Model → Radial Layout → DOM/SVG View
 * v1 核心 + 整理 + 搬枝/排序 + 搜索 + 改侧 + 填色 + 导出
 */

(() => {
  const uid = () =>
    crypto.randomUUID?.() ??
    `n_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;

  /** 预设填色 token；null = 默认（无填色） */
  const FILL_PRESETS = ["sage", "sky", "sand", "rose", "lilac"];

  // —— Model ——
  function createNode(text, side = null, children = []) {
    return { id: uid(), text, side, fill: null, collapsed: false, children };
  }

  function createDocument() {
    const root = createNode("中心主题");
    root.children = [
      createNode("问题定义", "left", [
        createNode("用户是谁"),
        createNode("痛点是什么"),
      ]),
      createNode("技术方案", "right", [
        createNode("SwiftUI 壳"),
        createNode("Metal 画布", [
          createNode("布局上传"),
          createNode("命中测试"),
        ]),
      ]),
      createNode("第一版范围", "right", [
        createNode("单窗口"),
        createNode("辐射布局"),
        createNode("增删改查"),
      ]),
      createNode("开放问题", "left", [
        createNode("文字渲染策略"),
        createNode("导出格式"),
      ]),
    ];
    return {
      root,
      /** @type {Set<string>} */
      selectedIds: new Set([root.id]),
      /** Shift 连选锚点 */
      selectionAnchorId: root.id,
    };
  }

  const doc = createDocument();

  // —— Tree helpers ——
  function findNode(id, node = doc.root, parent = null, index = -1) {
    if (node.id === id) return { node, parent, index };
    for (let i = 0; i < node.children.length; i++) {
      const hit = findNode(id, node.children[i], node, i);
      if (hit) return hit;
    }
    return null;
  }

  function countDescendants(node) {
    return node.children.reduce(
      (sum, child) => sum + 1 + countDescendants(child),
      0
    );
  }

  function nextSide() {
    const left = doc.root.children.filter((c) => c.side === "left").length;
    const right = doc.root.children.filter((c) => c.side !== "left").length;
    return left <= right ? "left" : "right";
  }

  function selectedList() {
    return [...doc.selectedIds];
  }

  function primarySelectedId() {
    const ids = selectedList();
    if (!ids.length) return null;
    if (doc.selectionAnchorId && doc.selectedIds.has(doc.selectionAnchorId)) {
      return doc.selectionAnchorId;
    }
    return ids[ids.length - 1];
  }

  function isMultiSelect() {
    return doc.selectedIds.size > 1;
  }

  function cloneSubtree(node) {
    return {
      id: uid(),
      text: node.text,
      side: null,
      fill: node.fill ?? null,
      collapsed: !!node.collapsed,
      children: (node.children || []).map(cloneSubtree),
    };
  }

  function isAncestorOf(ancestorId, nodeId) {
    let cur = findNode(nodeId)?.parent;
    while (cur) {
      if (cur.id === ancestorId) return true;
      cur = findNode(cur.id)?.parent;
    }
    return false;
  }

  /** 选中集中的顶层（祖先已在集合中则跳过），并排除中心主题 */
  function topLevelMovableIds(ids = selectedList()) {
    const set = new Set(ids.filter((id) => id !== doc.root.id));
    return [...set].filter((id) => {
      let cur = findNode(id)?.parent;
      while (cur) {
        if (set.has(cur.id)) return false;
        cur = findNode(cur.id)?.parent;
      }
      return !!findNode(id)?.parent;
    });
  }

  /** 选中集里父为中心主题的节点（改侧对象） */
  function rootDirectChildIds(ids = selectedList()) {
    return [...new Set(ids)].filter((id) => {
      const hit = findNode(id);
      return hit && hit.parent === doc.root;
    });
  }

  function nodeSide(node) {
    return node.side === "left" ? "left" : "right";
  }

  function canMoveOnto(targetId, movingIds) {
    if (!targetId || !movingIds.length) return false;
    const target = findNode(targetId);
    if (!target) return false;
    for (const id of movingIds) {
      if (id === targetId) return false;
      if (isAncestorOf(id, targetId)) return false;
    }
    return true;
  }

  /** 插到锚点前/后为同级：锚点须有父；不可含锚点自身或其祖先 */
  function canInsertSibling(movingIds, anchorId) {
    const tops = topLevelMovableIds(movingIds);
    if (!tops.length) return false;
    const anchor = findNode(anchorId);
    if (!anchor?.parent) return false;
    if (tops.includes(anchorId)) return false;
    for (const id of tops) {
      if (isAncestorOf(id, anchorId)) return false;
    }
    return true;
  }

  /** 同父兄弟之间按索引连选（含端点） */
  function siblingRangeIds(fromId, toId) {
    const a = findNode(fromId);
    const b = findNode(toId);
    if (!a || !b || a.parent !== b.parent || !a.parent) return [toId];
    const kids = a.parent.children;
    const i0 = Math.min(a.index, b.index);
    const i1 = Math.max(a.index, b.index);
    return kids.slice(i0, i1 + 1).map((n) => n.id);
  }

  // —— Layout (center-radial) ——
  const LAYOUT = {
    hGap: 56,
    vGap: 16,
    rootPadX: 22,
    rootPadY: 16,
    nodePadX: 16,
    nodePadY: 10,
    measureCtx: null,
  };

  function getMeasureCtx() {
    if (!LAYOUT.measureCtx) {
      const c = document.createElement("canvas");
      LAYOUT.measureCtx = c.getContext("2d");
    }
    return LAYOUT.measureCtx;
  }

  function measureNode(node, isRoot) {
    const ctx = getMeasureCtx();
    ctx.font = isRoot
      ? '700 18.4px "Fraunces", Georgia, serif'
      : '500 14.7px "Outfit", sans-serif';
    const lines = String(node.text || " ").split("\n");
    const maxW = isRoot ? 220 : 188;
    let width = 0;
    let lineCount = 0;
    for (const line of lines) {
      const words = line.length ? line.split("") : [" "];
      let current = "";
      for (const ch of words) {
        const trial = current + ch;
        if (ctx.measureText(trial).width > maxW && current) {
          width = Math.max(width, ctx.measureText(current).width);
          lineCount++;
          current = ch;
        } else {
          current = trial;
        }
      }
      width = Math.max(width, ctx.measureText(current || " ").width);
      lineCount++;
    }
    const padX = isRoot ? LAYOUT.rootPadX : LAYOUT.nodePadX;
    const padY = isRoot ? LAYOUT.rootPadY : LAYOUT.nodePadY;
    const lineH = isRoot ? 24 : 20;
    return {
      w: Math.ceil(width + padX * 2),
      h: Math.ceil(lineCount * lineH + padY * 2),
    };
  }

  /** @returns {{ frames: Map<string, any>, edges: any[] }} */
  function layoutTree() {
    const frames = new Map();
    const edges = [];

    function subtreeHeight(node, isRoot) {
      const size = measureNode(node, isRoot);
      if (node.collapsed || node.children.length === 0) {
        return { size, height: size.h, childLayouts: [] };
      }
      const childLayouts = node.children.map((c) =>
        subtreeHeight(c, false)
      );
      const childrenH =
        childLayouts.reduce((s, c) => s + c.height, 0) +
        LAYOUT.vGap * (childLayouts.length - 1);
      return {
        size,
        height: Math.max(size.h, childrenH),
        childLayouts,
      };
    }

    function placeBranch(node, x, yCenter, side, parentFrame, meta) {
      const { size, height, childLayouts } = meta;
      const frame = {
        id: node.id,
        x,
        y: yCenter,
        w: size.w,
        h: size.h,
        isRoot: false,
        side,
        collapsed: node.collapsed,
        hiddenCount: node.collapsed ? countDescendants(node) : 0,
      };
      frames.set(node.id, frame);

      if (parentFrame) {
        edges.push({
          from: parentFrame,
          to: frame,
          side,
        });
      }

      if (node.collapsed || !childLayouts.length) return;

      const childrenH =
        childLayouts.reduce((s, c) => s + c.height, 0) +
        LAYOUT.vGap * (childLayouts.length - 1);
      let cy = yCenter - childrenH / 2;
      const dir = side === "left" ? -1 : 1;

      node.children.forEach((child, i) => {
        const cm = childLayouts[i];
        const childCenter = cy + cm.height / 2;
        const childX =
          x + dir * (size.w / 2 + LAYOUT.hGap + cm.size.w / 2);
        placeBranch(child, childX, childCenter, side, frame, cm);
        cy += cm.height + LAYOUT.vGap;
      });
    }

    const rootMeta = subtreeHeight(doc.root, true);
    const rootFrame = {
      id: doc.root.id,
      x: 0,
      y: 0,
      w: rootMeta.size.w,
      h: rootMeta.size.h,
      isRoot: true,
      side: null,
      collapsed: doc.root.collapsed,
      hiddenCount: doc.root.collapsed ? countDescendants(doc.root) : 0,
    };
    frames.set(doc.root.id, rootFrame);

    if (!doc.root.collapsed) {
      const left = [];
      const right = [];
      doc.root.children.forEach((child, i) => {
        const side = child.side === "left" ? "left" : "right";
        const meta = rootMeta.childLayouts[i];
        (side === "left" ? left : right).push({ child, meta, side });
      });

      function placeSide(list, side) {
        if (!list.length) return;
        const totalH =
          list.reduce((s, item) => s + item.meta.height, 0) +
          LAYOUT.vGap * (list.length - 1);
        let cy = -totalH / 2;
        const dir = side === "left" ? -1 : 1;
        for (const { child, meta } of list) {
          const yCenter = cy + meta.height / 2;
          const x =
            dir *
            (rootFrame.w / 2 + LAYOUT.hGap + meta.size.w / 2);
          placeBranch(child, x, yCenter, side, rootFrame, meta);
          cy += meta.height + LAYOUT.vGap;
        }
      }

      placeSide(left, "left");
      placeSide(right, "right");
    }

    return { frames, edges };
  }

  function edgePath(from, to, side) {
    const dir = side === "left" ? -1 : 1;
    const x1 = from.x + (dir * from.w) / 2;
    const y1 = from.y;
    const x2 = to.x - (dir * to.w) / 2;
    const y2 = to.y;
    const cx = (x1 + x2) / 2;
    return `M ${x1} ${y1} C ${cx} ${y1}, ${cx} ${y2}, ${x2} ${y2}`;
  }

  // —— View / camera ——
  const stage = document.getElementById("stage");
  const world = document.getElementById("world");
  const edgesEl = document.getElementById("edges");
  const nodesEl = document.getElementById("nodes");
  const togglesEl = document.getElementById("branch-toggles");
  const zoomLabel = document.getElementById("zoom-label");
  const hint = document.getElementById("hint");
  const marqueeEl = document.getElementById("marquee");
  const insertLineEl = document.getElementById("insert-line");
  const sideGuideEl = document.getElementById("side-guide");
  const selectionCountEl = document.getElementById("selection-count");
  const searchBarEl = document.getElementById("search-bar");
  const searchInputEl = document.getElementById("search-input");
  const searchCountEl = document.getElementById("search-count");
  const btnSearchPrev = document.getElementById("btn-search-prev");
  const btnSearchNext = document.getElementById("btn-search-next");
  const btnSearchClose = document.getElementById("btn-search-close");

  const camera = { x: 0, y: 0, scale: 1 };
  let layoutCache = { frames: new Map(), edges: [] };
  let editingId = null;
  let spaceHeld = false;

  /**
   * 剪贴板：copy 可多次粘贴；cut 粘贴成功后清空并删源。
   * @type {{ mode: 'copy'|'cut', items: { sourceId?: string, snapshot: any }[] } | null}
   */
  let clipboard = null;
  /**
   * 拖放意图：中部成子；上下边插同级；中心左右半 / 空白过中线改侧。
   * @type {{ targetId: string, mode: 'child'|'before'|'after'|'side-left'|'side-right', viaEmpty?: boolean } | null}
   */
  let dropIntent = null;
  /** 正在拖的节点 id 集（含多选顶层） */
  let draggingIds = new Set();

  /** 节点上下边缘占比 → 同级插入带 */
  const DROP_EDGE_RATIO = 0.28;

  /** @type {{ open: boolean, query: string, matches: string[], index: number }} */
  const search = {
    open: false,
    query: "",
    matches: [],
    index: -1,
  };

  function applyCamera() {
    world.style.transform = `translate(${camera.x}px, ${camera.y}px) scale(${camera.scale})`;
    zoomLabel.textContent = `${Math.round(camera.scale * 100)}%`;
  }

  function worldSize() {
    return { w: stage.clientWidth, h: stage.clientHeight };
  }

  function centerCameraOnContent(animate = false) {
    const { frames } = layoutCache;
    if (!frames.size) return;
    let minX = Infinity,
      minY = Infinity,
      maxX = -Infinity,
      maxY = -Infinity;
    for (const f of frames.values()) {
      minX = Math.min(minX, f.x - f.w / 2);
      maxX = Math.max(maxX, f.x + f.w / 2);
      minY = Math.min(minY, f.y - f.h / 2);
      maxY = Math.max(maxY, f.y + f.h / 2);
    }
    const { w, h } = worldSize();
    const contentW = Math.max(maxX - minX, 1);
    const contentH = Math.max(maxY - minY, 1);
    const pad = 80;
    const scale = Math.min(
      1.15,
      Math.max(0.35, Math.min((w - pad * 2) / contentW, (h - pad * 2) / contentH))
    );
    const cx = (minX + maxX) / 2;
    const cy = (minY + maxY) / 2;
    camera.scale = scale;
    camera.x = w / 2 - cx * scale;
    camera.y = h / 2 - cy * scale;
    if (animate) {
      world.style.transition = "transform 0.35s cubic-bezier(0.22, 1, 0.36, 1)";
      applyCamera();
      setTimeout(() => {
        world.style.transition = "";
      }, 360);
    } else {
      applyCamera();
    }
  }

  function centerCameraOnNode(id, animate = true) {
    const f = layoutCache.frames.get(id);
    if (!f) return;
    const { w, h } = worldSize();
    camera.x = w / 2 - f.x * camera.scale;
    camera.y = h / 2 - f.y * camera.scale;
    if (animate) {
      world.style.transition = "transform 0.28s cubic-bezier(0.22, 1, 0.36, 1)";
      applyCamera();
      setTimeout(() => {
        world.style.transition = "";
      }, 300);
    } else {
      applyCamera();
    }
  }

  function render() {
    layoutCache = layoutTree();
    const { frames, edges } = layoutCache;

    const vbPad = 4000;
    edgesEl.setAttribute(
      "viewBox",
      `${-vbPad} ${-vbPad} ${vbPad * 2} ${vbPad * 2}`
    );
    edgesEl.style.width = `${vbPad * 2}px`;
    edgesEl.style.height = `${vbPad * 2}px`;
    edgesEl.style.left = `${-vbPad}px`;
    edgesEl.style.top = `${-vbPad}px`;

    edgesEl.innerHTML = edges
      .map((e) => `<path d="${edgePath(e.from, e.to, e.side)}" />`)
      .join("");

    const existing = new Map(
      [...nodesEl.querySelectorAll(".node")].map((el) => [el.dataset.id, el])
    );
    const seen = new Set();
    const anchorId = doc.selectionAnchorId;

    for (const f of frames.values()) {
      seen.add(f.id);
      const node = findNode(f.id)?.node;
      if (!node) continue;

      let el = existing.get(f.id);
      if (!el) {
        el = document.createElement("div");
        el.className = "node";
        el.dataset.id = f.id;
        el.innerHTML = `<span class="node-text"></span>`;
        nodesEl.appendChild(el);
      }

      const selected = doc.selectedIds.has(f.id);
      const cutMarked =
        clipboard?.mode === "cut" &&
        clipboard.items.some((it) => it.sourceId === f.id);
      el.classList.toggle("is-root", f.isRoot);
      el.classList.toggle(
        "is-selected",
        selected && editingId !== f.id
      );
      el.classList.toggle(
        "is-anchor",
        selected && f.id === anchorId && isMultiSelect() && editingId !== f.id
      );
      el.classList.toggle("is-editing", editingId === f.id);
      el.classList.toggle("is-cut", cutMarked);
      el.classList.toggle("is-dragging", draggingIds.has(f.id));
      const isDropChild =
        dropIntent?.mode === "child" && dropIntent.targetId === f.id;
      const isDropEdge =
        (dropIntent?.mode === "before" || dropIntent?.mode === "after") &&
        dropIntent.targetId === f.id;
      const isDropSideLeft =
        dropIntent?.mode === "side-left" &&
        dropIntent.targetId === f.id &&
        !dropIntent.viaEmpty;
      const isDropSideRight =
        dropIntent?.mode === "side-right" &&
        dropIntent.targetId === f.id &&
        !dropIntent.viaEmpty;
      el.classList.toggle("is-drop-target", isDropChild && !draggingIds.has(f.id));
      el.classList.toggle("is-drop-edge", isDropEdge && !draggingIds.has(f.id));
      el.classList.toggle(
        "is-drop-side-left",
        isDropSideLeft && !draggingIds.has(f.id)
      );
      el.classList.toggle(
        "is-drop-side-right",
        isDropSideRight && !draggingIds.has(f.id)
      );
      el.classList.toggle(
        "is-search-hit",
        search.open &&
          search.matches[search.index] === f.id &&
          editingId !== f.id
      );
      const fill = node.fill && FILL_PRESETS.includes(node.fill) ? node.fill : "";
      if (fill) el.dataset.fill = fill;
      else delete el.dataset.fill;
      el.style.left = `${f.x}px`;
      el.style.top = `${f.y}px`;
      el.style.width = `${f.w}px`;
      el.style.minHeight = `${f.h}px`;

      const textEl = el.querySelector(".node-text");
      if (editingId !== f.id) {
        textEl.contentEditable = "false";
        textEl.textContent = node.text;
      }

      const badge = el.querySelector(".collapsed-badge");
      if (badge) badge.remove();
    }

    for (const [id, el] of existing) {
      if (!seen.has(id)) el.remove();
    }

    renderBranchToggles(frames);
    syncInsertLine(frames);
    syncSideGuide();
    syncToolbar();
  }

  function syncInsertLine(frames) {
    if (
      !dropIntent ||
      (dropIntent.mode !== "before" && dropIntent.mode !== "after")
    ) {
      insertLineEl.hidden = true;
      return;
    }
    const f = frames.get(dropIntent.targetId);
    if (!f) {
      insertLineEl.hidden = true;
      return;
    }
    const y =
      dropIntent.mode === "before" ? f.y - f.h / 2 : f.y + f.h / 2;
    insertLineEl.hidden = false;
    insertLineEl.style.left = `${f.x}px`;
    insertLineEl.style.top = `${y}px`;
    insertLineEl.style.width = `${Math.max(f.w, 48)}px`;
  }

  function syncSideGuide() {
    const show =
      dropIntent &&
      (dropIntent.mode === "side-left" || dropIntent.mode === "side-right") &&
      dropIntent.viaEmpty;
    if (!show) {
      sideGuideEl.hidden = true;
      sideGuideEl.classList.remove("is-left", "is-right");
      return;
    }
    sideGuideEl.hidden = false;
    sideGuideEl.classList.toggle("is-left", dropIntent.mode === "side-left");
    sideGuideEl.classList.toggle("is-right", dropIntent.mode === "side-right");
  }

  /**
   * 在父子连线「漏斗」出口处放 ＋ / −：
   * 展开态 ＋ 点击折叠；折叠态 − 点击展开（数量与符号同处）。
   */
  function renderBranchToggles(frames) {
    const needed = [];

    for (const f of frames.values()) {
      const hit = findNode(f.id);
      if (!hit || !hit.node.children.length) continue;

      if (f.isRoot) {
        const hasLeft = hit.node.children.some((c) => c.side === "left");
        const hasRight = hit.node.children.some((c) => c.side !== "left");
        // 折叠后两侧都收起，仍在左右出口各留一个控件，呼应两侧漏斗
        if (hit.node.collapsed || hasLeft) {
          needed.push(toggleSpec(f, hit.node, "left"));
        }
        if (hit.node.collapsed || hasRight) {
          needed.push(toggleSpec(f, hit.node, "right"));
        }
      } else {
        needed.push(toggleSpec(f, hit.node, f.side === "left" ? "left" : "right"));
      }
    }

    const existing = new Map(
      [...togglesEl.querySelectorAll(".branch-toggle")].map((el) => [
        el.dataset.key,
        el,
      ])
    );
    const seen = new Set();

    for (const spec of needed) {
      seen.add(spec.key);
      let el = existing.get(spec.key);
      if (!el) {
        el = document.createElement("button");
        el.type = "button";
        el.className = "branch-toggle";
        el.dataset.key = spec.key;
        el.innerHTML = `<span class="toggle-label"></span>`;
        el.addEventListener("pointerdown", (e) => {
          e.stopPropagation();
          e.preventDefault();
        });
        el.addEventListener("click", (e) => {
          e.stopPropagation();
          e.preventDefault();
          toggleNodeCollapse(spec.nodeId);
        });
        togglesEl.appendChild(el);
      }

      el.dataset.id = spec.nodeId;
      el.classList.toggle("is-collapsed", spec.collapsed);
      el.classList.toggle("is-root-side", spec.isRoot);
      el.classList.toggle("has-count", spec.collapsed && spec.hiddenCount > 0);
      el.style.left = `${spec.x}px`;
      el.style.top = `${spec.y}px`;
      el.title = spec.collapsed
        ? `展开（隐藏 ${spec.hiddenCount}）`
        : "折叠子主题";
      el.setAttribute(
        "aria-label",
        spec.collapsed ? "展开子主题" : "折叠子主题"
      );

      let label = el.querySelector(".toggle-label");
      if (!label) {
        el.innerHTML = `<span class="toggle-label"></span>`;
        label = el.querySelector(".toggle-label");
      }
      // ＋ = 折叠；− = 展开；折叠时数量与符号同一处，如 −3
      if (spec.collapsed) {
        label.textContent =
          spec.hiddenCount > 0 ? `−${spec.hiddenCount}` : "−";
      } else {
        label.textContent = "+";
      }
    }

    for (const [key, el] of existing) {
      if (!seen.has(key)) el.remove();
    }
  }

  function toggleSpec(frame, node, side) {
    const dir = side === "left" ? -1 : 1;
    // 节点朝子树一侧的出口，再沿连线方向外推一点 → 落在漏斗分叉处
    const gap = 18;
    return {
      key: `${frame.id}:${side}`,
      nodeId: frame.id,
      isRoot: frame.isRoot,
      collapsed: node.collapsed,
      hiddenCount: node.collapsed ? countDescendants(node) : 0,
      x: frame.x + dir * (frame.w / 2 + gap),
      y: frame.y,
    };
  }

  function syncToolbar() {
    const count = doc.selectedIds.size;
    const multi = count > 1;
    const hits = selectedList()
      .map((id) => findNode(id))
      .filter(Boolean);
    const sole = count === 1 ? hits[0] : null;
    const isRootOnly = sole?.node === doc.root;

    // 严格模式：多选时禁用子主题 / 同级
    document.getElementById("btn-add-child").disabled = multi || count === 0;
    document.getElementById("btn-add-sibling").disabled =
      multi || count === 0 || isRootOnly;

    const deletable = hits.filter((h) => h.node !== doc.root);
    document.getElementById("btn-delete").disabled = deletable.length === 0;

    const movable = topLevelMovableIds();
    document.getElementById("btn-cut").disabled = movable.length === 0;
    document.getElementById("btn-copy").disabled = movable.length === 0;
    document.getElementById("btn-paste").disabled =
      !clipboard?.items?.length || count === 0;

    const rootKids = rootDirectChildIds(selectedList());
    document.getElementById("btn-side-left").disabled = rootKids.length === 0;
    document.getElementById("btn-side-right").disabled = rootKids.length === 0;

    const swatches = document.querySelectorAll(".fill-swatches .swatch");
    const noSel = count === 0;
    let commonFill = null;
    if (count === 1) {
      commonFill = hits[0]?.node.fill ?? null;
    } else if (count > 1) {
      const fills = hits.map((h) => h.node.fill ?? null);
      commonFill = fills.every((f) => f === fills[0]) ? fills[0] : undefined;
    }
    for (const btn of swatches) {
      btn.disabled = noSel;
      const token = btn.dataset.fill || null;
      const active =
        commonFill !== undefined &&
        ((token === null && commonFill === null) ||
          (token && token === commonFill));
      btn.classList.toggle("is-active", !!active);
    }

    if (count > 1) {
      selectionCountEl.hidden = false;
      selectionCountEl.textContent = `已选 ${count}`;
    } else {
      selectionCountEl.hidden = true;
    }
  }

  function setSelectedFill(fill) {
    const ids = selectedList();
    if (!ids.length) return;
    const next =
      fill && FILL_PRESETS.includes(fill) ? fill : null;
    for (const id of ids) {
      const hit = findNode(id);
      if (hit) hit.node.fill = next;
    }
    render();
  }

  // —— Selection ——
  function clearSelection() {
    doc.selectedIds.clear();
    doc.selectionAnchorId = null;
  }

  function selectOnly(id, { setAnchor = true } = {}) {
    if (editingId && editingId !== id) commitEdit();
    doc.selectedIds = new Set([id]);
    if (setAnchor) doc.selectionAnchorId = id;
    render();
  }

  function toggleInSelection(id) {
    if (editingId && editingId !== id) commitEdit();
    if (doc.selectedIds.has(id)) {
      doc.selectedIds.delete(id);
      if (doc.selectionAnchorId === id) {
        doc.selectionAnchorId = primarySelectedId();
      }
    } else {
      doc.selectedIds.add(id);
      doc.selectionAnchorId = id;
    }
    render();
  }

  function selectSiblingRange(toId) {
    if (editingId) commitEdit();
    const anchor = doc.selectionAnchorId || toId;
    const range = siblingRangeIds(anchor, toId);
    // 不同父：退化为单选目标
    if (range.length === 1 && range[0] === toId) {
      const a = findNode(anchor);
      const b = findNode(toId);
      if (!a || !b || a.parent !== b.parent) {
        selectOnly(toId);
        return;
      }
    }
    doc.selectedIds = new Set(range);
    // 锚点保持，便于继续 Shift 扩展
    if (!doc.selectionAnchorId) doc.selectionAnchorId = toId;
    render();
  }

  function replaceSelection(ids, { anchorId = null } = {}) {
    doc.selectedIds = new Set(ids);
    doc.selectionAnchorId =
      anchorId && doc.selectedIds.has(anchorId)
        ? anchorId
        : ids[ids.length - 1] ?? null;
    render();
  }

  // —— Commands ——
  function addChild() {
    if (isMultiSelect()) return;
    const id = primarySelectedId();
    const hit = id ? findNode(id) : null;
    if (!hit) return;
    const child = createNode("新主题");
    if (hit.node === doc.root) {
      child.side = nextSide();
    }
    hit.node.collapsed = false;
    hit.node.children.push(child);
    selectOnly(child.id);
    startEdit(child.id);
  }

  function addSibling() {
    if (isMultiSelect()) return;
    const id = primarySelectedId();
    const hit = id ? findNode(id) : null;
    if (!hit?.parent) return;
    const sibling = createNode("新主题");
    if (hit.parent === doc.root) {
      sibling.side = hit.node.side || nextSide();
    }
    hit.parent.children.splice(hit.index + 1, 0, sibling);
    selectOnly(sibling.id);
    startEdit(sibling.id);
  }

  function toggleNodeCollapse(id) {
    const hit = findNode(id);
    if (!hit || !hit.node.children.length) return;
    hit.node.collapsed = !hit.node.collapsed;
    render();
  }

  /** 多选时 / 仍可批量折叠（工具条已不放此入口） */
  function toggleCollapseSelected() {
    const hits = selectedList()
      .map((id) => findNode(id))
      .filter((h) => h && h.node.children.length > 0);
    if (!hits.length) return;
    const anyExpanded = hits.some((h) => !h.node.collapsed);
    for (const h of hits) {
      h.node.collapsed = anyExpanded;
    }
    render();
  }

  function deleteSelected() {
    const ids = selectedList().filter((id) => id !== doc.root.id);
    if (!ids.length) return;

    const doomed = new Set(ids);

    function hasDoomedAncestor(id) {
      let cur = findNode(id)?.parent;
      while (cur) {
        if (doomed.has(cur.id)) return true;
        cur = findNode(cur.id)?.parent;
      }
      return false;
    }

    // 只删「选中集合的顶层」：祖先已在删除集中的子不必再删
    const topIds = ids.filter((id) => !hasDoomedAncestor(id));
    const parentPrefer =
      findNode(topIds[0])?.parent?.id ?? doc.root.id;

    // 按同父下 index 从大到小删，避免 splice 打乱索引
    const tops = topIds
      .map((id) => findNode(id))
      .filter((h) => h?.parent)
      .sort((a, b) => {
        if (a.parent.id !== b.parent.id) {
          return a.parent.id < b.parent.id ? -1 : 1;
        }
        return b.index - a.index;
      });

    for (const hit of tops) {
      const again = findNode(hit.node.id);
      if (!again?.parent) continue;
      again.parent.children.splice(again.index, 1);
    }

    // 剪切源若已被删，清剪贴板
    if (clipboard?.mode === "cut") {
      const still = clipboard.items.filter((it) => findNode(it.sourceId));
      clipboard = still.length ? { ...clipboard, items: still } : null;
    }

    clearSelection();
    if (findNode(parentPrefer)) {
      doc.selectedIds.add(parentPrefer);
      doc.selectionAnchorId = parentPrefer;
    }
    render();
  }

  function detachNode(id) {
    const hit = findNode(id);
    if (!hit?.parent) return null;
    const [removed] = hit.parent.children.splice(hit.index, 1);
    return removed;
  }

  function attachAsChild(parentNode, childNode) {
    if (parentNode === doc.root) {
      childNode.side = childNode.side || nextSide();
    } else {
      childNode.side = null;
    }
    parentNode.collapsed = false;
    parentNode.children.push(childNode);
  }

  function reparentAsChildren(movingIds, targetId) {
    const tops = topLevelMovableIds(movingIds);
    if (!canMoveOnto(targetId, tops)) return false;
    const target = findNode(targetId)?.node;
    if (!target) return false;

    const detached = [];
    const ordered = tops
      .map((id) => findNode(id))
      .filter((h) => h?.parent)
      .sort((a, b) => {
        if (a.parent.id !== b.parent.id) {
          return a.parent.id < b.parent.id ? -1 : 1;
        }
        return b.index - a.index;
      });

    for (const hit of ordered) {
      const node = detachNode(hit.node.id);
      if (node) detached.push(node);
    }
    // 按原选中顺序的大致稳定：detach 是倒序，再反转
    detached.reverse();
    for (const node of detached) {
      attachAsChild(target, node);
    }
    return true;
  }

  /** 将可搬顶层插到锚点前/后，成为同级（可跨父；中心主题下继承锚点 side） */
  function insertAsSiblings(movingIds, anchorId, where) {
    const tops = topLevelMovableIds(movingIds);
    if (!canInsertSibling(tops, anchorId)) return false;
    const anchorHit = findNode(anchorId);
    if (!anchorHit?.parent) return false;
    const parent = anchorHit.parent;

    const detached = [];
    const ordered = tops
      .map((id) => findNode(id))
      .filter((h) => h?.parent)
      .sort((a, b) => {
        if (a.parent.id !== b.parent.id) {
          return a.parent.id < b.parent.id ? -1 : 1;
        }
        return b.index - a.index;
      });

    for (const hit of ordered) {
      const node = detachNode(hit.node.id);
      if (node) detached.push(node);
    }
    detached.reverse();

    const anchorAgain = findNode(anchorId);
    if (!anchorAgain || anchorAgain.parent !== parent) return false;
    let insertAt =
      where === "before" ? anchorAgain.index : anchorAgain.index + 1;

    for (const node of detached) {
      if (parent === doc.root) {
        node.side = anchorAgain.node.side || nextSide();
      } else {
        node.side = null;
      }
      parent.children.splice(insertAt, 0, node);
      insertAt++;
    }
    return true;
  }

  /**
   * 将可搬顶层挂到中心主题并设定 left/right。
   * 已是中心直接子则只改 side。
   */
  function applyRootSide(movingIds, side) {
    const tops = topLevelMovableIds(movingIds);
    if (!tops.length) return false;
    let changed = false;
    for (const id of tops) {
      const hit = findNode(id);
      if (!hit?.parent) continue;
      if (hit.parent === doc.root) {
        if (nodeSide(hit.node) !== side) {
          hit.node.side = side;
          changed = true;
        }
      } else {
        const node = detachNode(id);
        if (!node) continue;
        node.side = side;
        doc.root.children.push(node);
        changed = true;
      }
    }
    return changed;
  }

  /** 工具条 / 快捷键：仅对中心直接子改侧 */
  function setSelectedSide(side) {
    const ids = rootDirectChildIds();
    if (!ids.length) return;
    let changed = false;
    for (const id of ids) {
      const hit = findNode(id);
      if (!hit) continue;
      if (nodeSide(hit.node) !== side) {
        hit.node.side = side;
        changed = true;
      }
    }
    if (changed) render();
  }

  function copySelection() {
    const tops = topLevelMovableIds();
    if (!tops.length) return;
    clipboard = {
      mode: "copy",
      items: tops.map((id) => ({
        snapshot: cloneSubtree(findNode(id).node),
      })),
    };
    render();
  }

  function cutSelection() {
    const tops = topLevelMovableIds();
    if (!tops.length) return;
    clipboard = {
      mode: "cut",
      items: tops.map((id) => ({
        sourceId: id,
        snapshot: cloneSubtree(findNode(id).node),
      })),
    };
    render();
  }

  function pasteClipboard() {
    if (!clipboard?.items?.length) return;
    const targetId = primarySelectedId();
    if (!targetId) return;
    const targetHit = findNode(targetId);
    if (!targetHit) return;

    if (clipboard.mode === "cut") {
      const sourceIds = clipboard.items
        .map((it) => it.sourceId)
        .filter((id) => id && findNode(id));
      if (!sourceIds.length || !canMoveOnto(targetId, sourceIds)) return;
      if (reparentAsChildren(sourceIds, targetId)) {
        clipboard = null;
        replaceSelection(sourceIds, { anchorId: sourceIds[0] ?? null });
      }
      return;
    }

    const pastedIds = [];
    for (const item of clipboard.items) {
      const tree = cloneSubtree(item.snapshot);
      attachAsChild(targetHit.node, tree);
      pastedIds.push(tree.id);
    }
    replaceSelection(pastedIds, { anchorId: pastedIds[0] ?? null });
  }

  function cancelCut() {
    if (clipboard?.mode === "cut") {
      clipboard = null;
      render();
    }
  }

  // —— Search ——
  function walkAllNodes(node, visit) {
    visit(node);
    for (const child of node.children) walkAllNodes(child, visit);
  }

  function collectSearchMatches(query) {
    const q = query.trim().toLowerCase();
    if (!q) return [];
    const ids = [];
    walkAllNodes(doc.root, (node) => {
      if (String(node.text || "").toLowerCase().includes(q)) {
        ids.push(node.id);
      }
    });
    return ids;
  }

  /** 展开通往目标的全部祖先，使目标进入布局 */
  function expandPathTo(id) {
    let cur = findNode(id)?.parent;
    while (cur) {
      if (cur.children.length) cur.collapsed = false;
      cur = findNode(cur.id)?.parent;
    }
  }

  function syncSearchChrome() {
    const n = search.matches.length;
    const cur = n === 0 || search.index < 0 ? 0 : search.index + 1;
    searchCountEl.textContent = `${cur} / ${n}`;
    btnSearchPrev.disabled = n === 0;
    btnSearchNext.disabled = n === 0;
  }

  function revealSearchMatch(index, { animate = true } = {}) {
    if (!search.matches.length) {
      search.index = -1;
      syncSearchChrome();
      render();
      return;
    }
    const n = search.matches.length;
    search.index = ((index % n) + n) % n;
    const id = search.matches[search.index];
    expandPathTo(id);
    doc.selectedIds = new Set([id]);
    doc.selectionAnchorId = id;
    syncSearchChrome();
    render();
    centerCameraOnNode(id, animate);
  }

  function runSearch(query, { preferId = null } = {}) {
    search.query = query;
    search.matches = collectSearchMatches(query);
    if (!search.matches.length) {
      search.index = -1;
      syncSearchChrome();
      render();
      return;
    }
    let idx = 0;
    if (preferId) {
      const at = search.matches.indexOf(preferId);
      if (at >= 0) idx = at;
    }
    revealSearchMatch(idx, { animate: true });
  }

  function openSearch() {
    if (editingId) commitEdit();
    search.open = true;
    searchBarEl.hidden = false;
    syncSearchChrome();
    searchInputEl.focus();
    searchInputEl.select();
    if (search.query) runSearch(search.query);
    else render();
  }

  function closeSearch() {
    search.open = false;
    searchBarEl.hidden = true;
    render();
  }

  function searchNext(delta) {
    if (!search.matches.length) return;
    revealSearchMatch(search.index + delta);
  }

  function isSearchFieldTarget(el) {
    return (
      el === searchInputEl ||
      searchBarEl.contains(el) ||
      el?.id === "search-input"
    );
  }

  // —— Export ——
  const FILL_PAINT = {
    sage: {
      bg: "#dfeadf",
      border: "#8fa88a",
      rootBg: "#3d5c48",
      rootText: "#f4f1ea",
    },
    sky: {
      bg: "#d7e5f0",
      border: "#7a9bb5",
      rootBg: "#355a78",
      rootText: "#f4f1ea",
    },
    sand: {
      bg: "#f0e4c4",
      border: "#c4a86a",
      rootBg: "#7a6230",
      rootText: "#f4f1ea",
    },
    rose: {
      bg: "#f0d8d5",
      border: "#c48984",
      rootBg: "#7a4040",
      rootText: "#f4f1ea",
    },
    lilac: {
      bg: "#e5dced",
      border: "#9e8bb3",
      rootBg: "#554868",
      rootText: "#f4f1ea",
    },
  };

  function safeFilename(base, ext) {
    const name = String(base || "ymind")
      .replace(/[\\/:*?"<>|]/g, "_")
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 48);
    return `${name || "ymind"}.${ext}`;
  }

  function downloadBlob(filename, blob) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  }

  function downloadText(filename, text, mime) {
    downloadBlob(filename, new Blob([text], { type: mime }));
  }

  /** 临时展开全树执行 fn，再恢复折叠态（不触发中间 render） */
  function withFullyExpanded(fn) {
    const saved = [];
    walkAllNodes(doc.root, (node) => {
      saved.push({ node, collapsed: !!node.collapsed });
      node.collapsed = false;
    });
    try {
      return fn();
    } finally {
      for (const s of saved) s.node.collapsed = s.collapsed;
    }
  }

  /** 整树 → Markdown 标题层级（忽略折叠；深度 >6 仍用 ######） */
  function treeToMarkdown(node = doc.root, depth = 1) {
    const level = Math.min(Math.max(depth, 1), 6);
    const title = String(node.text || "未命名")
      .replace(/\r\n/g, "\n")
      .split("\n")
      .map((l) => l.trim())
      .filter(Boolean)
      .join(" ");
    let out = `${"#".repeat(level)} ${title || "未命名"}\n\n`;
    for (const child of node.children || []) {
      out += treeToMarkdown(child, depth + 1);
    }
    return out;
  }

  function exportMarkdown() {
    const md = treeToMarkdown(doc.root, 1).trimEnd() + "\n";
    downloadText(
      safeFilename(doc.root.text, "md"),
      md,
      "text/markdown;charset=utf-8"
    );
  }

  function roundRectPath(ctx, x, y, w, h, r) {
    const rr = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + rr, y);
    ctx.arcTo(x + w, y, x + w, y + h, rr);
    ctx.arcTo(x + w, y + h, x, y + h, rr);
    ctx.arcTo(x, y + h, x, y, rr);
    ctx.arcTo(x, y, x + w, y, rr);
    ctx.closePath();
  }

  function wrapTextLines(ctx, text, maxW) {
    const lines = [];
    for (const para of String(text || " ").split("\n")) {
      const chars = para.length ? para.split("") : [" "];
      let current = "";
      for (const ch of chars) {
        const trial = current + ch;
        if (ctx.measureText(trial).width > maxW && current) {
          lines.push(current);
          current = ch;
        } else {
          current = trial;
        }
      }
      lines.push(current || " ");
    }
    return lines;
  }

  function paintExportCanvas(frames, edges) {
    let minX = Infinity,
      minY = Infinity,
      maxX = -Infinity,
      maxY = -Infinity;
    for (const f of frames.values()) {
      minX = Math.min(minX, f.x - f.w / 2);
      maxX = Math.max(maxX, f.x + f.w / 2);
      minY = Math.min(minY, f.y - f.h / 2);
      maxY = Math.max(maxY, f.y + f.h / 2);
    }
    const pad = 48;
    const contentW = Math.max(maxX - minX, 1);
    const contentH = Math.max(maxY - minY, 1);
    const scale = Math.min(2, 2400 / Math.max(contentW, contentH));
    const w = Math.ceil((contentW + pad * 2) * scale);
    const h = Math.ceil((contentH + pad * 2) * scale);
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#e7e4dc";
    ctx.fillRect(0, 0, w, h);

    const tx = (x) => (x - minX + pad) * scale;
    const ty = (y) => (y - minY + pad) * scale;

    ctx.lineCap = "round";
    ctx.strokeStyle = "#6d7568";
    ctx.globalAlpha = 0.75;
    ctx.lineWidth = Math.max(1.25, 1.75 * scale);
    for (const e of edges) {
      const dir = e.side === "left" ? -1 : 1;
      const x1 = e.from.x + (dir * e.from.w) / 2;
      const y1 = e.from.y;
      const x2 = e.to.x - (dir * e.to.w) / 2;
      const y2 = e.to.y;
      const cx = (x1 + x2) / 2;
      ctx.beginPath();
      ctx.moveTo(tx(x1), ty(y1));
      ctx.bezierCurveTo(tx(cx), ty(y1), tx(cx), ty(y2), tx(x2), ty(y2));
      ctx.stroke();
    }
    ctx.globalAlpha = 1;

    for (const f of frames.values()) {
      const node = findNode(f.id)?.node;
      if (!node) continue;
      const paint = node.fill ? FILL_PAINT[node.fill] : null;
      const x = tx(f.x - f.w / 2);
      const y = ty(f.y - f.h / 2);
      const nw = f.w * scale;
      const nh = f.h * scale;
      const radius = (f.isRoot ? 18 : 14) * scale;

      roundRectPath(ctx, x, y, nw, nh, radius);
      if (f.isRoot) {
        ctx.fillStyle = paint?.rootBg || "#1f2a24";
        ctx.fill();
      } else {
        ctx.fillStyle = paint?.bg || "#fbfaf6";
        ctx.fill();
        ctx.strokeStyle = paint?.border || "#c8c2b4";
        ctx.lineWidth = Math.max(1, 1.5 * scale);
        ctx.stroke();
      }

      ctx.fillStyle = f.isRoot
        ? paint?.rootText || "#f4f1ea"
        : "#1a1c19";
      ctx.font = f.isRoot
        ? `700 ${18.4 * scale}px "Fraunces", Georgia, serif`
        : `500 ${14.7 * scale}px "Outfit", sans-serif`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      const maxTextW =
        (f.isRoot ? 220 : 188) * scale;
      const lines = wrapTextLines(ctx, node.text, maxTextW);
      const lineH = (f.isRoot ? 24 : 20) * scale;
      const startY = ty(f.y) - ((lines.length - 1) * lineH) / 2;
      lines.forEach((line, i) => {
        ctx.fillText(line, tx(f.x), startY + i * lineH);
      });
    }

    return canvas;
  }

  function exportPng() {
    const { frames, edges } = withFullyExpanded(() => layoutTree());
    const canvas = paintExportCanvas(frames, edges);
    canvas.toBlob((blob) => {
      if (!blob) return;
      downloadBlob(safeFilename(doc.root.text, "png"), blob);
    }, "image/png");
  }

  function startEdit(id) {
    const el = nodesEl.querySelector(`.node[data-id="${id}"]`);
    if (!el) return;
    editingId = id;
    doc.selectedIds = new Set([id]);
    doc.selectionAnchorId = id;
    render();
    const textEl = el.querySelector(".node-text");
    textEl.contentEditable = "true";
    textEl.focus();
    const range = document.createRange();
    range.selectNodeContents(textEl);
    range.collapse(false);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
  }

  function commitEdit() {
    if (!editingId) return;
    const el = nodesEl.querySelector(`.node[data-id="${editingId}"]`);
    const hit = findNode(editingId);
    if (el && hit) {
      const text = el.querySelector(".node-text").innerText.replace(/\n$/, "");
      hit.node.text = text.trim() || "未命名";
    }
    editingId = null;
    render();
  }

  // —— Pointer: pan / marquee / select / node-drag ——
  let pan = null;
  let marquee = null;
  /** @type {{ pointerId: number, startX: number, startY: number, originId: string, movingIds: string[], active: boolean, suppressClickSelect: boolean } | null} */
  let nodeDrag = null;

  function hitNodeIdAtClient(clientX, clientY) {
    const stack = document.elementsFromPoint(clientX, clientY);
    for (const el of stack) {
      if (el.classList?.contains("branch-toggle")) return null;
      const node = el.closest?.(".node");
      if (node) return node.dataset.id;
    }
    return null;
  }

  /**
   * 分区命中：中部 = 成子；上/下边 = 插同级；
   * 中心主题左/右约 1/3 = 挂到该侧；空白过中线 = 一级枝改侧。
   */
  function resolveDropIntent(clientX, clientY, movingIds) {
    const under = hitNodeIdAtClient(clientX, clientY);
    if (!under || draggingIds.has(under)) {
      return resolveEmptySideIntent(clientX, movingIds);
    }
    const frame = layoutCache.frames.get(under);
    const hit = findNode(under);
    if (!frame || !hit) {
      return resolveEmptySideIntent(clientX, movingIds);
    }

    const rect = stage.getBoundingClientRect();
    const isRoot = hit.node === doc.root;

    if (isRoot) {
      const cx = rect.left + camera.x + frame.x * camera.scale;
      const hw = (frame.w * camera.scale) / 2;
      const left = cx - hw;
      const width = Math.max(frame.w * camera.scale, 1);
      const u = (clientX - left) / width;
      if (u < 1 / 3) {
        return { targetId: under, mode: "side-left" };
      }
      if (u > 2 / 3) {
        return { targetId: under, mode: "side-right" };
      }
      if (!canMoveOnto(under, movingIds)) return null;
      return { targetId: under, mode: "child" };
    }

    const cy = rect.top + camera.y + frame.y * camera.scale;
    const hh = (frame.h * camera.scale) / 2;
    const top = cy - hh;
    const height = Math.max(frame.h * camera.scale, 1);
    const t = (clientY - top) / height;

    let mode = "child";
    if (t < DROP_EDGE_RATIO) mode = "before";
    else if (t > 1 - DROP_EDGE_RATIO) mode = "after";

    if (mode === "child") {
      if (!canMoveOnto(under, movingIds)) return null;
      return { targetId: under, mode: "child" };
    }
    if (!canInsertSibling(movingIds, under)) return null;
    return { targetId: under, mode };
  }

  /** 拖一级枝到空白：按世界坐标 x 相对中心决定左右侧 */
  function resolveEmptySideIntent(clientX, movingIds) {
    const tops = topLevelMovableIds(movingIds);
    if (!tops.length) return null;
    for (const id of tops) {
      const hit = findNode(id);
      if (!hit || hit.parent !== doc.root) return null;
    }
    const rect = stage.getBoundingClientRect();
    const worldX = (clientX - rect.left - camera.x) / camera.scale;
    const side = worldX < 0 ? "left" : "right";
    return {
      targetId: doc.root.id,
      mode: side === "left" ? "side-left" : "side-right",
      viaEmpty: true,
    };
  }

  function setDropIntent(next) {
    const same =
      (!dropIntent && !next) ||
      (dropIntent &&
        next &&
        dropIntent.targetId === next.targetId &&
        dropIntent.mode === next.mode &&
        !!dropIntent.viaEmpty === !!next.viaEmpty);
    if (same) return;
    dropIntent = next;
    render();
  }

  function endNodeDrag(e, cancelled = false) {
    if (!nodeDrag || e.pointerId !== nodeDrag.pointerId) return;
    const { active, movingIds, originId, suppressClickSelect } = nodeDrag;
    const intent = dropIntent;
    nodeDrag = null;
    draggingIds = new Set();
    dropIntent = null;
    insertLineEl.hidden = true;
    sideGuideEl.hidden = true;
    sideGuideEl.classList.remove("is-left", "is-right");
    stage.classList.remove("is-node-dragging");

    if (!cancelled && active && intent) {
      let ok = false;
      if (intent.mode === "child") {
        ok = reparentAsChildren(movingIds, intent.targetId);
      } else if (intent.mode === "before" || intent.mode === "after") {
        ok = insertAsSiblings(movingIds, intent.targetId, intent.mode);
      } else if (
        intent.mode === "side-left" ||
        intent.mode === "side-right"
      ) {
        const side = intent.mode === "side-left" ? "left" : "right";
        if (intent.viaEmpty) {
          // 空白改侧：只动已是中心直接子的枝
          ok = applyRootSide(
            movingIds.filter((id) => findNode(id)?.parent === doc.root),
            side
          );
        } else {
          ok = applyRootSide(movingIds, side);
        }
      }
      if (ok) {
        if (clipboard?.mode === "cut") {
          const still = clipboard.items.filter((it) => findNode(it.sourceId));
          clipboard = still.length ? { ...clipboard, items: still } : null;
        }
        replaceSelection(movingIds, { anchorId: movingIds[0] ?? null });
        return;
      }
    }

    if (!active && suppressClickSelect) {
      selectOnly(originId);
      return;
    }
    render();
  }

  function updateMarqueeVisual() {
    if (!marquee) {
      marqueeEl.hidden = true;
      return;
    }
    const x = Math.min(marquee.x0, marquee.x1);
    const y = Math.min(marquee.y0, marquee.y1);
    const w = Math.abs(marquee.x1 - marquee.x0);
    const h = Math.abs(marquee.y1 - marquee.y0);
    marqueeEl.hidden = false;
    marqueeEl.style.left = `${x}px`;
    marqueeEl.style.top = `${y}px`;
    marqueeEl.style.width = `${w}px`;
    marqueeEl.style.height = `${h}px`;
  }

  function framesIntersectingScreenRect(sx0, sy0, sx1, sy1) {
    const left = Math.min(sx0, sx1);
    const right = Math.max(sx0, sx1);
    const top = Math.min(sy0, sy1);
    const bottom = Math.max(sy0, sy1);
    const hits = [];
    for (const f of layoutCache.frames.values()) {
      const rect = stage.getBoundingClientRect();
      const cx = rect.left + camera.x + f.x * camera.scale;
      const cy = rect.top + camera.y + f.y * camera.scale;
      const hw = (f.w * camera.scale) / 2;
      const hh = (f.h * camera.scale) / 2;
      const nLeft = cx - hw;
      const nRight = cx + hw;
      const nTop = cy - hh;
      const nBottom = cy + hh;
      const overlap =
        nLeft < right && nRight > left && nTop < bottom && nBottom > top;
      if (overlap) hits.push(f.id);
    }
    return hits;
  }

  stage.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    const nodeEl = e.target.closest?.(".node");
    if (nodeEl) return;

    if (editingId) commitEdit();

    const rect = stage.getBoundingClientRect();
    const sx = e.clientX - rect.left;
    const sy = e.clientY - rect.top;

    // 空格+拖 或 中键风格：平移；默认空白拖：框选
    if (spaceHeld) {
      clearSelection();
      render();
      pan = {
        pointerId: e.pointerId,
        startX: e.clientX,
        startY: e.clientY,
        origX: camera.x,
        origY: camera.y,
      };
      stage.setPointerCapture(e.pointerId);
      stage.classList.add("is-panning");
      return;
    }

    marquee = {
      pointerId: e.pointerId,
      x0: sx,
      y0: sy,
      x1: sx,
      y1: sy,
      additive: e.metaKey || e.ctrlKey,
    };
    stage.setPointerCapture(e.pointerId);
    stage.classList.add("is-marquee");
    updateMarqueeVisual();
  });

  stage.addEventListener("pointermove", (e) => {
    if (nodeDrag && e.pointerId === nodeDrag.pointerId) {
      const dx = e.clientX - nodeDrag.startX;
      const dy = e.clientY - nodeDrag.startY;
      if (!nodeDrag.active && (dx * dx + dy * dy) > 36) {
        nodeDrag.active = true;
        draggingIds = new Set(nodeDrag.movingIds);
        stage.classList.add("is-node-dragging");
        render();
      }
      if (nodeDrag.active) {
        setDropIntent(
          resolveDropIntent(e.clientX, e.clientY, nodeDrag.movingIds)
        );
      }
      return;
    }
    if (pan && e.pointerId === pan.pointerId) {
      camera.x = pan.origX + (e.clientX - pan.startX);
      camera.y = pan.origY + (e.clientY - pan.startY);
      applyCamera();
      return;
    }
    if (marquee && e.pointerId === marquee.pointerId) {
      const rect = stage.getBoundingClientRect();
      marquee.x1 = e.clientX - rect.left;
      marquee.y1 = e.clientY - rect.top;
      updateMarqueeVisual();
    }
  });

  function endPointerGesture(e) {
    if (nodeDrag && e.pointerId === nodeDrag.pointerId) {
      endNodeDrag(e, false);
      return;
    }
    if (pan && e.pointerId === pan.pointerId) {
      pan = null;
      stage.classList.remove("is-panning");
      return;
    }
    if (marquee && e.pointerId === marquee.pointerId) {
      const rect = stage.getBoundingClientRect();
      const absLeft = rect.left + Math.min(marquee.x0, marquee.x1);
      const absTop = rect.top + Math.min(marquee.y0, marquee.y1);
      const absRight = rect.left + Math.max(marquee.x0, marquee.x1);
      const absBottom = rect.top + Math.max(marquee.y0, marquee.y1);
      const w = Math.abs(marquee.x1 - marquee.x0);
      const h = Math.abs(marquee.y1 - marquee.y0);
      const additive = marquee.additive;
      marquee = null;
      marqueeEl.hidden = true;
      stage.classList.remove("is-marquee");

      // 几乎没拖动：视为点空白取消选中
      if (w < 4 && h < 4) {
        if (!additive) {
          clearSelection();
          render();
        }
        return;
      }

      const hitIds = framesIntersectingScreenRect(
        absLeft,
        absTop,
        absRight,
        absBottom
      );
      if (additive) {
        const next = new Set(doc.selectedIds);
        for (const id of hitIds) next.add(id);
        replaceSelection([...next], {
          anchorId: hitIds[hitIds.length - 1] ?? doc.selectionAnchorId,
        });
      } else {
        replaceSelection(hitIds, {
          anchorId: hitIds[hitIds.length - 1] ?? null,
        });
      }
    }
  }

  stage.addEventListener("pointerup", endPointerGesture);
  stage.addEventListener("pointercancel", endPointerGesture);

  stage.addEventListener(
    "wheel",
    (e) => {
      e.preventDefault();
      const rect = stage.getBoundingClientRect();
      const mx = e.clientX - rect.left;
      const my = e.clientY - rect.top;
      const worldX = (mx - camera.x) / camera.scale;
      const worldY = (my - camera.y) / camera.scale;
      const factor = e.deltaY < 0 ? 1.08 : 1 / 1.08;
      const next = Math.min(2.5, Math.max(0.25, camera.scale * factor));
      camera.scale = next;
      camera.x = mx - worldX * next;
      camera.y = my - worldY * next;
      applyCamera();
    },
    { passive: false }
  );

  nodesEl.addEventListener("pointerdown", (e) => {
    const nodeEl = e.target.closest(".node");
    if (!nodeEl) return;
    e.stopPropagation();
    if (e.button !== 0) return;
    const id = nodeEl.dataset.id;
    if (editingId && editingId !== id) commitEdit();
    if (editingId === id) return;

    const meta = e.metaKey || e.ctrlKey;
    if (meta) {
      toggleInSelection(id);
      return;
    }
    if (e.shiftKey && doc.selectionAnchorId) {
      selectSiblingRange(id);
      return;
    }

    // 点在已选成员上：保留多选以便拖整组；松手未拖则收成单选
    const keepMulti =
      doc.selectedIds.has(id) && doc.selectedIds.size > 1;
    if (!keepMulti) {
      selectOnly(id);
    }

    const movingIds = topLevelMovableIds(
      keepMulti ? selectedList() : [id]
    );
    // 中心主题不可拖；若无可搬节点则仅选中
    if (!movingIds.length) {
      if (keepMulti) selectOnly(id);
      return;
    }

    nodeDrag = {
      pointerId: e.pointerId,
      startX: e.clientX,
      startY: e.clientY,
      originId: id,
      movingIds,
      active: false,
      suppressClickSelect: keepMulti,
    };
    stage.setPointerCapture(e.pointerId);
  });

  nodesEl.addEventListener("dblclick", (e) => {
    const nodeEl = e.target.closest(".node");
    if (!nodeEl) return;
    e.preventDefault();
    startEdit(nodeEl.dataset.id);
  });

  nodesEl.addEventListener("keydown", (e) => {
    if (!editingId) return;
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      commitEdit();
    } else if (e.key === "Escape") {
      e.preventDefault();
      commitEdit();
    }
  });

  // —— Toolbar ——
  document.getElementById("btn-add-child").addEventListener("click", addChild);
  document
    .getElementById("btn-add-sibling")
    .addEventListener("click", addSibling);
  document
    .getElementById("btn-delete")
    .addEventListener("click", deleteSelected);
  document.getElementById("btn-cut").addEventListener("click", cutSelection);
  document.getElementById("btn-copy").addEventListener("click", copySelection);
  document
    .getElementById("btn-paste")
    .addEventListener("click", pasteClipboard);
  document
    .getElementById("btn-side-left")
    .addEventListener("click", () => setSelectedSide("left"));
  document
    .getElementById("btn-side-right")
    .addEventListener("click", () => setSelectedSide("right"));
  document.querySelectorAll(".fill-swatches .swatch").forEach((btn) => {
    btn.addEventListener("click", () => {
      setSelectedFill(btn.dataset.fill || null);
    });
  });
  document.getElementById("btn-zoom-in").addEventListener("click", () => {
    camera.scale = Math.min(2.5, camera.scale * 1.12);
    applyCamera();
  });
  document.getElementById("btn-zoom-out").addEventListener("click", () => {
    camera.scale = Math.max(0.25, camera.scale / 1.12);
    applyCamera();
  });
  document.getElementById("btn-fit").addEventListener("click", () =>
    centerCameraOnContent(true)
  );
  document
    .getElementById("btn-export-png")
    .addEventListener("click", exportPng);
  document
    .getElementById("btn-export-md")
    .addEventListener("click", exportMarkdown);

  searchInputEl.addEventListener("input", () => {
    runSearch(searchInputEl.value);
  });
  searchInputEl.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      e.preventDefault();
      e.stopPropagation();
      closeSearch();
      return;
    }
    if (e.key === "Enter") {
      e.preventDefault();
      e.stopPropagation();
      if (!search.matches.length) {
        runSearch(searchInputEl.value);
        return;
      }
      searchNext(e.shiftKey ? -1 : 1);
    }
  });
  btnSearchPrev.addEventListener("click", () => searchNext(-1));
  btnSearchNext.addEventListener("click", () => searchNext(1));
  btnSearchClose.addEventListener("click", closeSearch);

  // —— Keyboard ——
  window.addEventListener("keydown", (e) => {
    const meta = e.metaKey || e.ctrlKey;

    // ⌘F：打开 / 聚焦搜索（覆盖原「适应」快捷键；适应仍在工具条）
    if (e.key === "f" && meta) {
      e.preventDefault();
      openSearch();
      return;
    }

    if (search.open && isSearchFieldTarget(e.target)) {
      if (e.key === "g" && meta) {
        e.preventDefault();
        searchNext(e.shiftKey ? -1 : 1);
      }
      return;
    }

    if (search.open && e.key === "Escape") {
      e.preventDefault();
      closeSearch();
      return;
    }

    if (e.code === "Space" && !editingId && !isSearchFieldTarget(e.target)) {
      if (!e.repeat) {
        spaceHeld = true;
        stage.classList.add("is-space-pan");
      }
      if (e.target === document.body || e.target === stage) e.preventDefault();
      return;
    }
    if (editingId) return;
    if (isSearchFieldTarget(e.target)) return;

    if (e.key === "Tab") {
      e.preventDefault();
      addChild();
    } else if (e.key === "Enter") {
      e.preventDefault();
      addSibling();
    } else if (e.key === "Backspace" || e.key === "Delete") {
      const deletable = selectedList().some((id) => id !== doc.root.id);
      if (deletable) {
        e.preventDefault();
        deleteSelected();
      }
    } else if (e.key === "/" || (meta && e.key === ".")) {
      e.preventDefault();
      toggleCollapseSelected();
    } else if (e.key === "a" && meta) {
      e.preventDefault();
      const all = [...layoutCache.frames.keys()];
      replaceSelection(all, { anchorId: doc.root.id });
    } else if (e.key === "c" && meta) {
      e.preventDefault();
      copySelection();
    } else if (e.key === "x" && meta) {
      e.preventDefault();
      cutSelection();
    } else if (e.key === "v" && meta) {
      e.preventDefault();
      pasteClipboard();
    } else if (meta && (e.key === "ArrowLeft" || e.key === "ArrowRight")) {
      e.preventDefault();
      setSelectedSide(e.key === "ArrowLeft" ? "left" : "right");
    } else if (e.key === "Escape") {
      if (clipboard?.mode === "cut") {
        cancelCut();
        return;
      }
      clearSelection();
      render();
    }
  });

  window.addEventListener("keyup", (e) => {
    if (e.code === "Space") {
      spaceHeld = false;
      stage.classList.remove("is-space-pan");
    }
  });

  window.addEventListener("blur", () => {
    spaceHeld = false;
    stage.classList.remove("is-space-pan");
  });

  function dismissHint() {
    hint.classList.add("is-hidden");
    stage.removeEventListener("pointerdown", dismissHint);
  }
  stage.addEventListener("pointerdown", dismissHint);
  setTimeout(() => hint.classList.add("is-hidden"), 10000);

  // —— Boot ——
  render();
  centerCameraOnContent(false);
  window.addEventListener("resize", () => centerCameraOnContent(false));

  window.YMind = {
    doc,
    render,
    layoutTree,
    findNode,
    selectedList,
  };
})();

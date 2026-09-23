/**
 * YMind HTML Prototype
 * Model → Radial Layout → DOM/SVG View
 * Validates: center-radial map, single-window tool chrome, core node ops.
 */

(() => {
  const uid = () =>
    crypto.randomUUID?.() ??
    `n_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;

  // —— Model ——
  function createNode(text, side = null, children = []) {
    return { id: uid(), text, side, collapsed: false, children };
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
    return { root, selectedId: root.id };
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
      const isRoot = false;
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
  const zoomLabel = document.getElementById("zoom-label");
  const hint = document.getElementById("hint");

  const camera = { x: 0, y: 0, scale: 1 };
  let layoutCache = { frames: new Map(), edges: [] };
  let editingId = null;
  let hintTimer = null;

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

  function render() {
    layoutCache = layoutTree();
    const { frames, edges } = layoutCache;

    // edges — oversized SVG coordinate space centered at 0,0 via transform on group
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
      .map(
        (e) =>
          `<path d="${edgePath(e.from, e.to, e.side)}" />`
      )
      .join("");

    const selected = doc.selectedId;
    const existing = new Map(
      [...nodesEl.querySelectorAll(".node")].map((el) => [el.dataset.id, el])
    );
    const seen = new Set();

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

      el.classList.toggle("is-root", f.isRoot);
      el.classList.toggle("is-selected", f.id === selected && editingId !== f.id);
      el.classList.toggle("is-editing", editingId === f.id);
      el.style.left = `${f.x}px`;
      el.style.top = `${f.y}px`;
      el.style.width = `${f.w}px`;
      el.style.minHeight = `${f.h}px`;

      const textEl = el.querySelector(".node-text");
      if (editingId !== f.id) {
        textEl.contentEditable = "false";
        textEl.textContent = node.text;
      }

      let badge = el.querySelector(".collapsed-badge");
      if (f.collapsed && f.hiddenCount > 0) {
        if (!badge) {
          badge = document.createElement("span");
          badge.className = "collapsed-badge";
          el.appendChild(badge);
        }
        badge.textContent = String(f.hiddenCount);
      } else if (badge) {
        badge.remove();
      }
    }

    for (const [id, el] of existing) {
      if (!seen.has(id)) el.remove();
    }

    syncToolbar();
  }

  function syncToolbar() {
    const hit = doc.selectedId ? findNode(doc.selectedId) : null;
    const has = !!hit;
    const isRoot = hit?.node === doc.root;
    document.getElementById("btn-add-child").disabled = !has;
    document.getElementById("btn-add-sibling").disabled = !has || isRoot;
    document.getElementById("btn-toggle").disabled = !has || !hit.node.children.length;
    document.getElementById("btn-delete").disabled = !has || isRoot;
    document.getElementById("btn-toggle").textContent = hit?.node.collapsed
      ? "展开"
      : "折叠";
  }

  // —— Commands ——
  function select(id) {
    if (editingId && editingId !== id) commitEdit();
    doc.selectedId = id;
    render();
  }

  function addChild() {
    const hit = findNode(doc.selectedId);
    if (!hit) return;
    const child = createNode("新主题");
    if (hit.node === doc.root) {
      child.side = nextSide();
    }
    hit.node.collapsed = false;
    hit.node.children.push(child);
    doc.selectedId = child.id;
    render();
    startEdit(child.id);
  }

  function addSibling() {
    const hit = findNode(doc.selectedId);
    if (!hit?.parent) return;
    const sibling = createNode("新主题");
    if (hit.parent === doc.root) {
      sibling.side = hit.node.side || nextSide();
    }
    hit.parent.children.splice(hit.index + 1, 0, sibling);
    doc.selectedId = sibling.id;
    render();
    startEdit(sibling.id);
  }

  function toggleCollapse() {
    const hit = findNode(doc.selectedId);
    if (!hit || !hit.node.children.length) return;
    hit.node.collapsed = !hit.node.collapsed;
    render();
  }

  function deleteSelected() {
    const hit = findNode(doc.selectedId);
    if (!hit?.parent) return;
    hit.parent.children.splice(hit.index, 1);
    doc.selectedId = hit.parent.id;
    render();
  }

  function startEdit(id) {
    const el = nodesEl.querySelector(`.node[data-id="${id}"]`);
    if (!el) return;
    editingId = id;
    doc.selectedId = id;
    render();
    const textEl = el.querySelector(".node-text");
    textEl.contentEditable = "true";
    textEl.focus();
    // place caret at end
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

  // —— Pointer: pan / select ——
  let pan = null;

  stage.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    const nodeEl = e.target.closest?.(".node");
    if (nodeEl) return;

    if (editingId) commitEdit();
    doc.selectedId = null;
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
  });

  stage.addEventListener("pointermove", (e) => {
    if (!pan || e.pointerId !== pan.pointerId) return;
    camera.x = pan.origX + (e.clientX - pan.startX);
    camera.y = pan.origY + (e.clientY - pan.startY);
    applyCamera();
  });

  function endPan(e) {
    if (!pan || e.pointerId !== pan.pointerId) return;
    pan = null;
    stage.classList.remove("is-panning");
  }

  stage.addEventListener("pointerup", endPan);
  stage.addEventListener("pointercancel", endPan);

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
    const id = nodeEl.dataset.id;
    if (editingId && editingId !== id) commitEdit();
    select(id);
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
    .getElementById("btn-toggle")
    .addEventListener("click", toggleCollapse);
  document
    .getElementById("btn-delete")
    .addEventListener("click", deleteSelected);
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

  // —— Keyboard ——
  window.addEventListener("keydown", (e) => {
    if (editingId) return;
    const meta = e.metaKey || e.ctrlKey;
    if (e.key === "Tab") {
      e.preventDefault();
      addChild();
    } else if (e.key === "Enter") {
      e.preventDefault();
      addSibling();
    } else if (e.key === "Backspace" || e.key === "Delete") {
      if (doc.selectedId && doc.selectedId !== doc.root.id) {
        e.preventDefault();
        deleteSelected();
      }
    } else if (e.key === "/" || (meta && e.key === ".")) {
      e.preventDefault();
      toggleCollapse();
    } else if (e.key === "f" && meta) {
      e.preventDefault();
      centerCameraOnContent(true);
    }
  });

  // hide hint after first interaction
  function dismissHint() {
    hint.classList.add("is-hidden");
    stage.removeEventListener("pointerdown", dismissHint);
  }
  stage.addEventListener("pointerdown", dismissHint);
  hintTimer = setTimeout(() => hint.classList.add("is-hidden"), 8000);

  // —— Boot ——
  render();
  centerCameraOnContent(false);
  window.addEventListener("resize", () => centerCameraOnContent(false));

  // expose for console debugging while prototyping
  window.YMind = { doc, render, layoutTree, findNode };
})();

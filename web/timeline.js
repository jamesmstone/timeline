// Pan and zoom for the lane timeline. The server draws an svg three viewports
// wide; dragging only moves its viewBox, and a fresh window is fetched when the
// view nears an edge. The pure functions below are what the tests cover.
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.TimelinePan = api;
  if (typeof document !== "undefined") {
    if (document.readyState === "loading")
      document.addEventListener("DOMContentLoaded", () => api.mount(document));
    else api.mount(document);
  }
})(typeof self !== "undefined" ? self : this, function () {
  const MIN_SPAN = 3600;
  const MAX_SPAN = 20 * 365 * 86400;
  // Fraction of a viewport that may be left on either side before the window
  // is refetched.
  const EDGE = 0.25;

  const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));

  // Dragging right pulls earlier time into view.
  const panned = (vstart, dxPx, w, span) => vstart - (dxPx * span) / w;

  const windowFor = (vstart, span) => ({ from: vstart - span, to: vstart + 2 * span });

  const needsWindow = (vstart, span, from, to) =>
    vstart - from < span * EDGE || to - (vstart + span) < span * EDGE;

  const viewBoxX = (vstart, from, w, span) => ((vstart - from) * w) / span;

  // The instant under the cursor stays under it while the span changes.
  const zoomed = (vstart, span, frac, factor) => {
    const next = clamp(Math.round(span * factor), MIN_SPAN, MAX_SPAN);
    return { span: next, vstart: Math.round(vstart + frac * span - frac * next) };
  };

  const svgUrl = ({ vstart, span, w }) => {
    const { from, to } = windowFor(vstart, span);
    return `/lanes.svg?from=${from}&to=${to}&span=${span}&at=${vstart}&w=${w}`;
  };

  const pageUrl = ({ vstart, span }) => `/?span=${span}&at=${vstart}`;

  const fmt = (t) => new Date(t * 1000).toISOString().slice(0, 16).replace("T", " ");

  function mount(doc) {
    const section = doc.querySelector("[data-timeline]");
    if (!section) return;
    const viewport = section.querySelector("[data-viewport]");
    const range = section.querySelector("[data-range]");
    const win = doc.defaultView;

    let svg = viewport.querySelector("svg");
    let state = {
      from: +svg.dataset.from,
      to: +svg.dataset.to,
      span: +svg.dataset.span,
      w: viewport.clientWidth,
    };
    state.vstart = state.from + state.span;
    let token = 0;
    let timer = 0;

    const width = () => Math.max(320, Math.round(viewport.clientWidth));

    const place = () => {
      svg.viewBox.baseVal.x = viewBoxX(state.vstart, state.from, state.w, state.span);
      range.textContent = `${fmt(state.vstart)} to ${fmt(state.vstart + state.span)} UTC`;
    };

    const remember = () => {
      try {
        win.history.replaceState(null, "", pageUrl(state));
      } catch (e) {}
    };

    async function load() {
      const mine = ++token;
      const want = { vstart: state.vstart, span: state.span, w: width() };
      const res = await win.fetch(svgUrl(want));
      if (!res.ok || mine !== token) return;
      const html = await res.text();
      if (mine !== token) return;
      const holder = doc.createElement("div");
      holder.innerHTML = html;
      const next = holder.querySelector("svg");
      if (!next) return;
      const { from, to } = windowFor(want.vstart, want.span);
      svg.replaceWith(next);
      svg = next;
      state = { ...state, from, to, span: want.span, w: want.w };
      place();
    }

    const reloadSoon = (ms) => {
      win.clearTimeout(timer);
      timer = win.setTimeout(() => load().catch(() => {}), ms);
    };

    const move = (vstart) => {
      state.vstart = Math.round(vstart);
      place();
      if (needsWindow(state.vstart, state.span, state.from, state.to)) reloadSoon(0);
    };

    const setView = (vstart, span) => {
      state.vstart = vstart;
      state.span = span;
      reloadSoon(120);
      range.textContent = `${fmt(vstart)} to ${fmt(vstart + span)} UTC`;
    };

    const zoomBy = (factor, frac = 0.5) => {
      const z = zoomed(state.vstart, state.span, frac, factor);
      setView(z.vstart, z.span);
      remember();
    };

    let drag = null;
    viewport.addEventListener("pointerdown", (e) => {
      if (e.button !== 0) return;
      drag = { x: e.clientX, vstart: state.vstart, id: e.pointerId };
      viewport.setPointerCapture(e.pointerId);
      viewport.dataset.dragging = "";
    });
    viewport.addEventListener("pointermove", (e) => {
      if (!drag) return;
      move(panned(drag.vstart, e.clientX - drag.x, state.w, state.span));
    });
    const end = () => {
      if (!drag) return;
      drag = null;
      delete viewport.dataset.dragging;
      remember();
    };
    viewport.addEventListener("pointerup", end);
    viewport.addEventListener("pointercancel", end);

    viewport.addEventListener(
      "wheel",
      (e) => {
        if (e.ctrlKey || e.metaKey) {
          e.preventDefault();
          const rect = viewport.getBoundingClientRect();
          zoomBy(Math.exp(e.deltaY * 0.002), (e.clientX - rect.left) / rect.width);
        } else if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
          e.preventDefault();
          move(panned(state.vstart, -e.deltaX, state.w, state.span));
          remember();
        }
      },
      { passive: false },
    );

    viewport.addEventListener("keydown", (e) => {
      const step = state.span * 0.2;
      if (e.key === "ArrowLeft") move(state.vstart - step);
      else if (e.key === "ArrowRight") move(state.vstart + step);
      else if (e.key === "+" || e.key === "=") zoomBy(0.5);
      else if (e.key === "-") zoomBy(2);
      else return;
      e.preventDefault();
      remember();
    });

    section.parentElement.addEventListener("click", (e) => {
      const el = e.target.closest("[data-pan],[data-scale],[data-zoom]");
      if (!el) return;
      if (el.dataset.zoom === "all") return;
      e.preventDefault();
      if (el.dataset.pan) {
        move(state.vstart + +el.dataset.pan * state.span * 0.5);
        remember();
      } else if (el.dataset.scale) zoomBy(+el.dataset.scale);
      else {
        const span = +el.dataset.zoom;
        setView(state.vstart + state.span / 2 - span / 2, span);
        remember();
      }
    });

    win.addEventListener("resize", () => {
      if (Math.abs(width() - state.w) > 8) reloadSoon(200);
    });

    // The server draws for 1200 units; one unit should be one pixel.
    place();
    if (Math.abs(width() - state.w) > 8) reloadSoon(0);
  }

  return { panned, windowFor, needsWindow, viewBoxX, zoomed, svgUrl, pageUrl, mount, MIN_SPAN, MAX_SPAN };
});

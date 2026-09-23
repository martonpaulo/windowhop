// The live demo in the home page hero: a small desktop with five windows and
// WindowHop's switcher over it. It plays the ⌘Tab gesture on its own and
// alternates between the two styles, App Icons and Window Previews, naming the
// current one in a caption above the screen. A click, a tap or the arrow keys
// switch windows by hand; the demo then resumes on its own after a short pause.
//
// Everything here is drawn by the page: neutral windows and generic app icons,
// never a real product's brand. Without JavaScript the <noscript> screenshot in
// the same place shows the real switcher instead. With "Reduce motion" the demo
// starts paused and nothing moves on its own.
(() => {
  const mount = document.getElementById("demo");
  if (!mount) return;

  const APPS = {
    browser: { name: "Browser", color: "#2f7df6", glyph: "globe" },
    terminal: { name: "Terminal", color: "#1f2328", glyph: "prompt" },
    notes: { name: "Notes", color: "#f5b82e", glyph: "lines" },
    mail: { name: "Mail", color: "#1aa4f0", glyph: "envelope" },
  };
  // Most recently used first, as the switcher lists them. Three browser windows
  // and two terminals: the case WindowHop is for.
  // Placed as a tidy cascade, so the desktop reads at a glance.
  const WINDOWS = [
    { app: "browser", title: "Trip to Lisbon", kind: "page", x: 10, y: 8, w: 46, h: 62 },
    { app: "terminal", title: "api — zsh", kind: "shell", x: 20, y: 14, w: 46, h: 62 },
    { app: "browser", title: "Pull request #42", kind: "code", x: 30, y: 20, w: 46, h: 62 },
    { app: "notes", title: "Groceries", kind: "notes", x: 40, y: 26, w: 46, h: 62 },
    { app: "browser", title: "Recipe: pastel de nata", kind: "article", x: 50, y: 32, w: 46, h: 62 },
  ];
  const MODES = { icons: "App Icons", previews: "Window Previews" };
  // after the visitor switches by hand, the demo waits this long, then resumes
  const RESUME_AFTER_MS = 6000;

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const svg = (name) => `<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><use href="#demo-glyph-${name}"></use></svg>`;

  // --- markup ---------------------------------------------------------------
  const icon = (app) =>
    `<span class="demo-icon" style="--app:${APPS[app].color}">${svg(APPS[app].glyph)}</span>`;

  const body = (kind) => {
    const lines = (widths) => widths.map((w) => `<i style="width:${w}%"></i>`).join("");
    switch (kind) {
      case "page":
        return `<div class="wb-address"></div><div class="wb-hero"></div><div class="wb-lines">${lines([90, 76, 84, 60])}</div>`;
      case "article":
        return `<div class="wb-address"></div><div class="wb-split"><div class="wb-photo"></div><div class="wb-lines">${lines([96, 80, 88, 70, 92])}</div></div>`;
      case "code":
        return `<div class="wb-address"></div><div class="wb-diff">${lines([70, 54, 82, 40, 66, 58])}</div>`;
      case "shell":
        return `<div class="wb-shell">${lines([42, 68, 30, 74, 50, 22])}</div>`;
      case "logs":
        return `<div class="wb-shell is-logs">${lines([88, 80, 92, 76, 84, 90])}</div>`;
      case "notes":
        return `<div class="wb-notes">${lines([60, 82, 70, 50, 76])}</div>`;
      default:
        return `<div class="wb-mail">${[0, 1, 2, 3].map(() => `<div><b></b>${lines([62, 88])}</div>`).join("")}</div>`;
    }
  };

  const windowMarkup = (win, index) => `
    <div class="demo-window w-${win.app}" data-index="${index}"
         style="--x:${win.x}%;--y:${win.y}%;--w:${win.w}%;--h:${win.h}%">
      <div class="demo-window-bar"><span></span><span></span><span></span><em>${win.title}</em></div>
      <div class="demo-window-body">${body(win.kind)}</div>
    </div>`;

  mount.innerHTML = `
    <svg class="demo-glyphs" aria-hidden="true" focusable="false">
      <symbol id="demo-glyph-globe" viewBox="0 0 24 24"><g fill="none" stroke="#fff" stroke-width="1.8"><circle cx="12" cy="12" r="8"/><path d="M4 12h16M12 4c2.6 2.4 2.6 13.6 0 16M12 4c-2.6 2.4-2.6 13.6 0 16"/></g></symbol>
      <symbol id="demo-glyph-prompt" viewBox="0 0 24 24"><path d="m6 8 4 4-4 4M12 16h6" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></symbol>
      <symbol id="demo-glyph-lines" viewBox="0 0 24 24"><path d="M6 8h12M6 12h12M6 16h8" stroke="#fff" stroke-width="2" stroke-linecap="round"/></symbol>
      <symbol id="demo-glyph-envelope" viewBox="0 0 24 24"><g fill="none" stroke="#fff" stroke-width="1.8" stroke-linejoin="round"><rect x="4" y="6.5" width="16" height="11" rx="2"/><path d="m4.5 7.5 7.5 6 7.5-6"/></g></symbol>
    </svg>
    <p class="demo-caption" aria-hidden="true">${Object.entries(MODES)
      .map(([mode, name]) => `<span data-caption="${mode}">${name}</span>`).join("")}</p>
    <div class="demo-screen" data-mode="icons">
      <div class="demo-menubar" aria-hidden="true"><b></b><span></span><span></span><span></span><time>9:41</time></div>
      <div class="demo-desktop" aria-hidden="true">${WINDOWS.map(windowMarkup).join("")}</div>
      <button type="button" class="demo-play" aria-label="Pause the demo">
        <svg class="icon-pause" viewBox="0 0 16 16" aria-hidden="true" focusable="false"><rect x="4" y="3" width="3" height="10" rx="1"/><rect x="9" y="3" width="3" height="10" rx="1"/></svg>
        <svg class="icon-play" viewBox="0 0 16 16" aria-hidden="true" focusable="false"><path d="M5 3.2v9.6a.8.8 0 0 0 1.2.7l7.6-4.8a.8.8 0 0 0 0-1.4L6.2 2.5A.8.8 0 0 0 5 3.2z"/></svg>
      </button>
      <div class="demo-panel" role="listbox" tabindex="0" aria-label="Open windows. Use the arrow keys to choose one and Return to switch to it."></div>
    </div>
    <div class="demo-keys keycap-row" aria-hidden="true"><kbd class="keycap key-cmd">⌘</kbd><kbd class="keycap key-tab">Tab</kbd></div>
    <p class="visually-hidden" aria-live="polite"></p>`;

  const screen = mount.querySelector(".demo-screen");
  const desktop = mount.querySelector(".demo-desktop");
  const panel = mount.querySelector(".demo-panel");
  const live = mount.querySelector("[aria-live]");
  const playButton = mount.querySelector(".demo-play");
  const keyCmd = mount.querySelector(".key-cmd");
  const keyTab = mount.querySelector(".key-tab");
  const windowEls = [...desktop.children];

  // --- state ------------------------------------------------------------------
  let order = WINDOWS.map((_, index) => index); // MRU, front window first
  let selected = 1;
  let playing = !reduceMotion.matches;
  let pausedByButton = reduceMotion.matches;
  let timer = null;
  let resumeTimer = null;

  const label = (index) => `${WINDOWS[index].title} — ${APPS[WINDOWS[index].app].name}`;

  const stackDesktop = () => {
    order.forEach((windowIndex, position) => {
      const el = windowEls[windowIndex];
      el.style.zIndex = String(order.length - position);
      el.classList.toggle("is-front", position === 0);
    });
  };

  const renderPanel = () => {
    const previews = screen.dataset.mode === "previews";
    panel.innerHTML = order
      .map((windowIndex, position) => {
        const win = WINDOWS[windowIndex];
        const thumb = previews
          ? `<div class="demo-preview"><div class="demo-window w-${win.app}"><div class="demo-window-bar"><span></span><span></span><span></span></div><div class="demo-window-body">${body(win.kind)}</div></div>${icon(win.app)}</div>`
          : icon(win.app);
        return `<div class="demo-tile" role="option" id="demo-tile-${position}" aria-selected="false" data-position="${position}">
            ${thumb}<span class="demo-title">${win.title}</span></div>`;
      })
      .join("");
    select(selected, false);
  };

  const select = (position, announce = true) => {
    selected = (position + order.length) % order.length;
    panel.querySelectorAll(".demo-tile").forEach((tile, index) => {
      const on = index === selected;
      tile.classList.toggle("is-selected", on);
      tile.setAttribute("aria-selected", String(on));
    });
    panel.setAttribute("aria-activedescendant", `demo-tile-${selected}`);
    if (announce) live.textContent = `Selected: ${label(order[selected])}`;
  };

  const showPanel = (on) => screen.classList.toggle("is-open", on);

  const setMode = (mode) => {
    screen.dataset.mode = mode;
    mount.querySelectorAll("[data-caption]").forEach((caption) =>
      caption.classList.toggle("is-current", caption.dataset.caption === mode));
    renderPanel();
  };

  const switchToSelected = () => {
    const windowIndex = order[selected];
    order = [windowIndex, ...order.filter((index) => index !== windowIndex)];
    stackDesktop();
    live.textContent = `Switched to ${label(windowIndex)}`;
    const el = windowEls[windowIndex];
    el.classList.remove("is-landing");
    void el.offsetWidth; // restart the landing animation
    el.classList.add("is-landing");
  };

  const press = (key, down) => key.classList.toggle("is-down", down);

  // --- the automatic ⌘Tab loop -------------------------------------------------
  const wait = (ms) => new Promise((resolve) => { timer = setTimeout(resolve, ms); });
  let runId = 0;

  const loop = async () => {
    const id = ++runId;
    const alive = () => playing && id === runId;
    while (alive()) {
      await wait(900); if (!alive()) return;
      press(keyCmd, true);
      await wait(260); if (!alive()) return;
      selected = 1;
      renderPanel();
      showPanel(true);
      press(keyTab, true); await wait(160); press(keyTab, false);
      const steps = 1 + Math.floor(Math.random() * 3);
      for (let step = 1; step < steps; step++) {
        await wait(720); if (!alive()) return;
        press(keyTab, true); select(selected + 1, false); await wait(160); press(keyTab, false);
      }
      await wait(900); if (!alive()) return;
      press(keyCmd, false);
      showPanel(false);
      switchToSelected();
      await wait(1500); if (!alive()) return;
      // the next gesture shows the other style
      setMode(screen.dataset.mode === "icons" ? "previews" : "icons");
    }
  };

  const setPlaying = (on) => {
    playing = on;
    clearTimeout(timer);
    runId++;
    playButton.setAttribute("aria-label", on ? "Pause the demo" : "Play the demo");
    playButton.classList.toggle("is-paused", !on);
    press(keyCmd, false);
    press(keyTab, false);
    if (on) {
      showPanel(false);
      loop();
    } else {
      // a paused demo is the sticky session: the switcher stays open to try
      selected = Math.min(selected, order.length - 1);
      renderPanel();
      showPanel(true);
    }
  };

  // --- visitor input -------------------------------------------------------------
  // The visitor switches by hand: stop the loop, then resume it after a pause,
  // unless the pause button stopped the demo on purpose.
  const takeOver = () => {
    if (playing) setPlaying(false);
    clearTimeout(resumeTimer);
    if (!pausedByButton) resumeTimer = setTimeout(() => setPlaying(true), RESUME_AFTER_MS);
  };

  panel.addEventListener("focus", takeOver);
  panel.addEventListener("keydown", (event) => {
    const keys = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
    if (event.key in keys) {
      event.preventDefault();
      takeOver();
      select(selected + keys[event.key]);
    } else if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      takeOver();
      switchToSelected();
      selected = 1;
      renderPanel();
    } else if (event.key === "Home" || event.key === "End") {
      event.preventDefault();
      select(event.key === "Home" ? 0 : order.length - 1);
    }
  });
  panel.addEventListener("click", (event) => {
    const tile = event.target.closest(".demo-tile");
    if (!tile) return;
    takeOver();
    select(Number(tile.dataset.position));
    switchToSelected();
    selected = 1;
    renderPanel();
  });

  playButton.addEventListener("click", () => {
    clearTimeout(resumeTimer);
    pausedByButton = playing;
    setPlaying(!playing);
  });
  reduceMotion.addEventListener("change", () => {
    if (!reduceMotion.matches) return;
    pausedByButton = true;
    setPlaying(false);
  });

  // pause while the demo is off screen, so it costs nothing there
  new IntersectionObserver(([entry]) => {
    if (!entry.isIntersecting) { clearTimeout(timer); runId++; }
    else if (playing) loop();
  }).observe(screen);

  stackDesktop();
  setMode("icons");
  mount.classList.add("is-ready");
  setPlaying(playing);
})();

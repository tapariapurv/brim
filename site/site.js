const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];

// Marquees loop seamlessly: each holds its names twice and slides by half its width.
$$("[data-dup]").forEach((run) => run.insertAdjacentHTML("beforeend", run.innerHTML));

// Numbers count up once, on arrival.
const countUp = (el) => {
  const end = Number(el.dataset.count);
  const suffix = el.dataset.suffix || "";
  if (still || !end) return;
  const start = performance.now();
  const tick = (now) => {
    const t = Math.min(1, (now - start) / 900);
    el.textContent = Math.round(end * (1 - (1 - t) ** 3)) + suffix;
    if (t < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
};

// The update steps play in order, once.
const playUpdate = () => {
  const steps = $$("#seq .step");
  const bar = $("#seq .dl");
  const at = still ? [0, 0, 0, 0] : [300, 800, 800, 2200];
  setTimeout(() => steps[0].classList.add("on"), at[0]);
  setTimeout(() => bar.classList.add("go"), at[1]);
  setTimeout(() => steps[1].classList.add("on"), still ? 0 : at[2] + 1300);
  setTimeout(() => steps[2].classList.add("on"), at[3] + (still ? 0 : 300));
};

// Parts of a section arrive one after another, once.
const seen = new IntersectionObserver((entries) => {
  for (const { isIntersecting, target } of entries) {
    if (!isIntersecting) continue;
    target.classList.add("in");
    seen.unobserve(target);
    $$("[data-count]", target).forEach(countUp);
    if (target.id === "seq") playUpdate();
  }
}, { threshold: 0.15 });
$$("main section").forEach((sec) => {
  $$("[data-r]", sec).forEach((el, i) => {
    el.style.setProperty("--d", `${Math.min(i, 5) * 60}ms`);
    seen.observe(el);
  });
});

// Hero: the slider fills the page the way Liquid Fill fills the panel, cool to warm.
const level = $("#level");
const liquid = $("#liquid");
const mix = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t)).join(" ");
const render = () => {
  const v = Number(level.value);
  liquid.style.setProperty("--c", mix([44, 196, 201], [244, 85, 63], Math.max(0, v / 100 - 0.35) / 0.65));
  liquid.style.transform = `translateY(${100 - (10 + v * 0.8)}%)`;
  $("#mb").textContent = `Claude ${v}%`;
  $("#pv").textContent = `${v}% used`;
  const bar = $("#hb");
  bar.style.setProperty("--v", v / 100);
  bar.style.setProperty("--fill", v >= 90 ? "var(--hot)" : v >= 70 ? "var(--warn)" : "var(--ok)");
  $("#pm").textContent = v >= 100 ? "At the brim" : v >= 90 ? "Nearly at the brim" : v >= 70 ? "Ease off soon" : "On pace";
};
level.addEventListener("input", render);
// Two frames so the first paint holds the empty state the entrance rises from.
requestAnimationFrame(() => requestAnimationFrame(() => {
  $("#hero").classList.add("ready");
  render();
}));

// Dashboard tabs. Instant view swap, with a sliding indicator to teach where each one lives.
const tabs = $$('[role="tab"]');
const select = (tab) => {
  for (const t of tabs) {
    const on = t === tab;
    t.setAttribute("aria-selected", on);
    t.tabIndex = on ? 0 : -1;
    $(`#${t.getAttribute("aria-controls")}`).hidden = !on;
  }
};
tabs.forEach((tab, i) => {
  tab.addEventListener("click", () => select(tab));
  tab.addEventListener("keydown", (e) => {
    if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
    const next = tabs[(i + 1) % tabs.length];
    select(next);
    next.focus();
  });
});
select($('[aria-selected="true"]'));

// Menu bar pins. Pinning nothing leaves the session limit showing, as the app does.
const checks = $$(".check");
const pinned = () => checks.filter((c) => c.getAttribute("aria-pressed") === "true");
checks.forEach((check) => check.addEventListener("click", () => {
  check.setAttribute("aria-pressed", check.getAttribute("aria-pressed") !== "true");
  const on = pinned().map((c) => c.dataset.for);
  $$("[data-pin]").forEach((pin) => {
    const show = on.length ? on.includes(pin.dataset.pin) : pin.dataset.pin === "a";
    if (pin.hidden && show && !still) pin.animate([{ opacity: 0, transform: "translateY(6px)" }, { opacity: 1, transform: "none" }], { duration: 220, easing: "cubic-bezier(.23,1,.32,1)" });
    pin.hidden = !show;
  });
}));

// Scroll-linked: the nav's hairline, the install line, and the last section filling to the brim.
const clamp = (v) => Math.min(1, Math.max(0, v));
const progress = $("#progress");
const stepsList = $("#steps");
const cta = $("#download");
let queued = false;
const onScroll = () => {
  queued = false;
  progress.style.setProperty("--p", clamp(scrollY / Math.max(1, document.body.scrollHeight - innerHeight)));
  const steps = stepsList.getBoundingClientRect();
  stepsList.style.setProperty("--p", clamp((innerHeight * 0.85 - steps.top) / (innerHeight * 0.5)));
  const end = cta.getBoundingClientRect();
  cta.style.setProperty("--p", clamp((innerHeight - end.top) / end.height) * 0.92);
};
addEventListener("scroll", () => {
  if (!queued) requestAnimationFrame(onScroll);
  queued = true;
}, { passive: true });
addEventListener("resize", onScroll, { passive: true });
onScroll();

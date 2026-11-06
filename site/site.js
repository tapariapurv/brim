const root = document.documentElement;
root.classList.add("js");
const still = matchMedia("(prefers-reduced-motion: reduce)").matches;

// Each chapter's surface: the next chapter's colour, rising in from below.
document.querySelectorAll(".ch[data-next]").forEach((ch) => {
  ch.insertAdjacentHTML(
    "beforeend",
    `<svg class="rise" aria-hidden="true" viewBox="0 0 2400 36" preserveAspectRatio="none" fill="${ch.dataset.next}"><path d="M0 18 Q 150 0 300 18 T 600 18 T 900 18 T 1200 18 T 1500 18 T 1800 18 T 2100 18 T 2400 18 V 36 H 0 Z"/></svg>`,
  );
});

// Entrances: parts of a section arrive one after another, once.
const seen = new IntersectionObserver(
  (entries) => {
    for (const { isIntersecting, target } of entries) {
      if (isIntersecting) {
        target.classList.add("in");
        seen.unobserve(target);
      }
    }
  },
  { threshold: 0.12 },
);
document.querySelectorAll(".ch").forEach((ch) => {
  ch.querySelectorAll("[data-r]").forEach((el, i) => {
    el.style.setProperty("--d", `${Math.min(i, 5) * 70}ms`);
    seen.observe(el);
  });
});

// The live thing: the slider fills the hero the way Liquid Fill fills the panel, cool to warm.
const level = document.getElementById("level");
const liquid = document.getElementById("liquid");
const mix = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t));
const render = () => {
  const v = Number(level.value);
  const warm = Math.max(0, v / 100 - 0.35) / 0.65;
  liquid.style.setProperty("--c", `rgb(${mix([44, 196, 201], [255, 159, 69], warm)})`);
  liquid.style.transform = `translateY(${100 - (8 + v * 0.8)}%)`;
  document.getElementById("mb").textContent = `Claude ${v}%`;
  document.getElementById("pv").textContent = `${v}% used`;
  const bar = document.getElementById("hb");
  bar.style.setProperty("--v", v / 100);
  bar.style.setProperty("--fill", v >= 90 ? "#F04438" : v >= 70 ? "#F79009" : "#17B26A");
  document.getElementById("pm").textContent = v >= 100 ? "At the brim" : v >= 90 ? "Nearly at the brim" : v >= 70 ? "Ease off soon" : "On pace";
};
level.addEventListener("input", render);
render();

// Scrolling fills the page too: names drift, and the corner gauge reads how far you've come.
const gauge = document.getElementById("gauge");
const sections = [...document.querySelectorAll(".ch")];
const runs = [...document.querySelectorAll("[data-run]")];
let queued = false;
const onScroll = () => {
  queued = false;
  const y = scrollY;
  const pct = Math.round((y / Math.max(1, document.body.scrollHeight - innerHeight)) * 100);
  gauge.textContent = `${pct}%`;
  const under = sections.find((ch) => ch.getBoundingClientRect().bottom > innerHeight - 30);
  if (under) gauge.style.color = under.style.getPropertyValue("--ink");
  if (still) return;
  const top = runs[0].parentElement.getBoundingClientRect().top;
  for (const run of runs) run.style.transform = `translateX(${(Number(run.dataset.run) * top) / 4 - 120}px)`;
};
addEventListener("scroll", () => {
  if (!queued) requestAnimationFrame(onScroll);
  queued = true;
}, { passive: true });
onScroll();

// The first load shows the level rising from empty to the sample value.
if (!still) {
  const target = level.value;
  level.value = 0;
  render();
  requestAnimationFrame(() => requestAnimationFrame(() => {
    level.value = target;
    render();
  }));
}

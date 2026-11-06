const COLORS = { normal: "#34C759", warning: "#FF9F0A", critical: "#FF453A" };
const TRACK = "#8E8E9340"; // Translucent grey reads on both Raycast themes.
const TICK = "#8E8E93";
const WIDTH = 400;
const HEIGHT = 12;

const capsule = (x: number, width: number, height = HEIGHT, top = 0): string => {
  const r = Math.min(height, width) / 2;
  const bottom = top + height;
  return `M ${x + r} ${top} H ${x + width - r} A ${r} ${r} 0 0 1 ${x + width - r} ${bottom} H ${x + r} A ${r} ${r} 0 0 1 ${x + r} ${top} Z`;
};

/**
 * A limit's level as Brim draws it: a thick pill, with a tick where an even pace would be.
 * Paths only, because Raycast's SVG renderer ignores `<rect>` and `<circle>`.
 */
export function limitBar(percent: number, pace: number | null = null): string {
  const level = Math.min(Math.max(percent, 0), 100);
  const color = level >= 90 ? COLORS.critical : level >= 70 ? COLORS.warning : COLORS.normal;
  const fill = level > 0 ? Math.max((level / 100) * WIDTH, HEIGHT) : 0;
  const tick =
    pace === null
      ? ""
      : `<path d="M ${(Math.min(Math.max(pace, 0), 100) / 100) * (WIDTH - 2)} 0 h 2 v ${HEIGHT} h -2 Z" fill="${TICK}"/>`;
  const svg = [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDTH}" height="${HEIGHT}" viewBox="0 0 ${WIDTH} ${HEIGHT}">`,
    `<path d="${capsule(0, WIDTH)}" fill="${TRACK}"/>`,
    fill ? `<path d="${capsule(0, fill)}" fill="${color}"/>` : "",
    tick,
    `</svg>`,
  ].join("");
  return `data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}`;
}

import { limitBar } from "./limit-bar";

const svg = (uri: string) => Buffer.from(uri.split(",")[1], "base64").toString();

it("colors the fill by severity", () => {
  expect(svg(limitBar(10))).toContain("#34C759");
  expect(svg(limitBar(75))).toContain("#FF9F0A");
  expect(svg(limitBar(95))).toContain("#FF453A");
});

it("draws no fill at zero and clamps over 100", () => {
  expect(svg(limitBar(0)).match(/<path/g)).toHaveLength(1);
  expect(svg(limitBar(250))).toBe(svg(limitBar(100)));
});

it("only draws a tick when a pace is known", () => {
  expect(svg(limitBar(50)).match(/<path/g)).toHaveLength(2);
  expect(svg(limitBar(50, 30)).match(/<path/g)).toHaveLength(3);
});

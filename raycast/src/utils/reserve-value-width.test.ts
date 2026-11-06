import { createElement, Fragment, isValidElement, ReactElement, ReactNode } from "react";
import { reserveValueWidths } from "./reserve-value-width";

const label = (props: object) => createElement("Label", props);
const texts = (node: ReactNode): unknown[] => {
  if (Array.isArray(node)) return node.flatMap(texts);
  if (!isValidElement(node)) return [];
  const { text, children } = (node as ReactElement<{ text?: unknown; children?: ReactNode }>).props;
  return [...(text === undefined ? [] : [text]), ...texts(children)];
};

it("pads every value, including rows nested in fragments, with blank digit-wide characters", () => {
  const metadata = createElement(
    "Metadata",
    null,
    label({ title: "On Pace For", text: "5%" }),
    createElement(Fragment, null, label({ title: "Session", text: "7% Used", icon: "pie" })),
    label({ title: "Empty", text: "" }),
    label({ title: "Heading" }),
    null,
  );

  expect(texts(reserveValueWidths(metadata))).toEqual([" ".repeat(10) + "5%", " ".repeat(2) + "7% Used", ""]);
});

it("leaves values longer than the reserved width unchanged", () => {
  const long = "A value that is already long";
  expect(texts(reserveValueWidths(createElement("Metadata", null, label({ text: long }))))).toEqual([long]);
});

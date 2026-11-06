import { Children, cloneElement, isValidElement, ReactElement, ReactNode } from "react";

const FIGURE_SPACE = " "; // Blank, and exactly one digit wide.
const MIN_LENGTH = 12;
const MIN_LENGTH_WITH_ICON = 9; // "100% Used". Padding sits between the icon and the value, so keep it small.

type LabelProps = { text?: unknown; icon?: unknown; children?: ReactNode };

/**
 * Raycast can keep a row's measured width when its value changes in place, turning "46%" into "4..%"
 * once fresh data replaces a shorter cached value. Values start at a fixed width, so a longer one still fits.
 * ponytail: padding counts characters, so a same-length but wider value can still clip. Drop this if Raycast fixes it.
 */
const reserve = (node: ReactNode): ReactNode => {
  if (!isValidElement(node)) return node;
  const { text, icon, children } = (node as ReactElement<LabelProps>).props;
  return cloneElement(node as ReactElement<LabelProps>, {
    ...(typeof text === "string" && text
      ? { text: text.padStart(icon ? MIN_LENGTH_WITH_ICON : MIN_LENGTH, FIGURE_SPACE) }
      : {}),
    ...(children === undefined ? {} : { children: Children.map(children, reserve) }),
  });
};

export const reserveValueWidths = (metadata: ReactNode): ReactNode => reserve(metadata);

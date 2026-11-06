import { List, Icon, Action, ActionPanel } from "@raycast/api";
import { useClaudeUsageLimits } from "../hooks/useClaudeUsageLimits";
import {
  formatTimeRemaining,
  formatRelativeTime,
  calculateEstimatedUsage,
  calculateAverageUsage,
} from "../utils/usage-limits-formatter";
import { formatDuration } from "../utils/data-formatter";
import { getLimitRows } from "../utils/limit-rows";
import { limitBar } from "../utils/limit-bar";
import { showRemainingUsage } from "../preferences";
import { ErrorMetadata } from "./ErrorMetadata";
import { STANDARD_ACCESSORIES } from "./common/accessories";
import { ReactNode } from "react";
import { capitalize } from "es-toolkit";

const rowTitle = (label: string, period: string | null): string =>
  period ? `${label} ${capitalize(period)} Limit` : `${label} Usage Limit`;

export function UsageLimits() {
  const {
    data,
    isLoading,
    error,
    isStale,
    isRateLimited,
    rateLimitedUntil,
    lastFetched,
    revalidate,
    isUsageLimitsAvailable,
  } = useClaudeUsageLimits();

  const rateLimitRetryIn =
    rateLimitedUntil && rateLimitedUntil > Date.now() ? formatDuration(rateLimitedUntil - Date.now()) : null;

  if (!isUsageLimitsAvailable) {
    return null;
  }

  const [primaryRow] = getLimitRows(data);
  const preferRemaining = showRemainingUsage();

  const accessories: List.Item.Accessory[] =
    error && !data
      ? STANDARD_ACCESSORIES.ERROR
      : isRateLimited && !data
        ? [
            {
              icon: Icon.Clock,
              text: rateLimitRetryIn ? `Rate limited · retry in ${rateLimitRetryIn}` : "Rate limited",
            },
          ]
        : !data
          ? STANDARD_ACCESSORIES.LOADING
          : isStale && !isLoading
            ? [{ icon: Icon.Warning, tooltip: `Stale data (last updated ${formatRelativeTime(lastFetched)})` }]
            : !primaryRow
              ? STANDARD_ACCESSORIES.NO_DATA
              : [
                  {
                    icon: Icon.Gauge,
                    text: `${(preferRemaining ? 100 - primaryRow.utilization : primaryRow.utilization).toFixed(0)}%`,
                    tooltip: `${rowTitle(primaryRow.label, primaryRow.period)} · ${preferRemaining ? "Remaining" : "Consumed"} (higher priority)`,
                  },
                ];

  const renderDetailMetadata = (): ReactNode => {
    if (error && !data) {
      return <ErrorMetadata noDataMessage="Unable to fetch usage limits" noDataSubMessage={error.message} />;
    }

    if (isRateLimited && !data) {
      return (
        <ErrorMetadata
          noDataMessage={rateLimitRetryIn ? `Rate limited — retry in ${rateLimitRetryIn}` : "Rate limited"}
          noDataSubMessage="Click Refresh to try now"
        />
      );
    }

    if (!data) {
      return <ErrorMetadata noDataMessage="Loading usage limits..." noDataSubMessage="Reading from Brim" />;
    }

    return undefined;
  };

  const renderMarkdown = (): string | undefined => {
    if (!data) return undefined;

    const rows = getLimitRows(data).map((row) => {
      const average = row.windowHours === null ? null : calculateAverageUsage(row.resets_at, row.windowHours);
      const estimate =
        row.windowHours === null ? null : calculateEstimatedUsage(row.utilization, row.resets_at, row.windowHours);
      const facts = [
        `**${row.utilization.toFixed(0)}%** used`,
        row.resets_at ? `resets in ${formatTimeRemaining(row.resets_at)}` : null,
        estimate === null ? null : `on pace for ${estimate.toFixed(0)}%`,
      ].filter(Boolean);

      return `#### ${rowTitle(row.label, row.period)}\n\n![](${limitBar(row.utilization, average)})\n\n${facts.join(" · ")}`;
    });

    const footer = lastFetched ? `Updated ${formatRelativeTime(lastFetched)}${isStale ? " · may be stale" : ""}` : "";
    return [...rows, footer].filter(Boolean).join("\n\n");
  };

  return (
    <List.Item
      id="usage-limits"
      title="Usage Limits"
      icon={Icon.Gauge}
      accessories={accessories}
      detail={<List.Item.Detail isLoading={isLoading} markdown={renderMarkdown()} metadata={renderDetailMetadata()} />}
      actions={
        <ActionPanel>
          <Action title="Refresh Usage Limit" icon={Icon.ArrowClockwise} onAction={revalidate} />
        </ActionPanel>
      }
    />
  );
}

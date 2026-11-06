import { applyAgentOrder, boldText, moveAgent, parseBrimAgents } from "./brim-agents";

const output = JSON.stringify({
  providers: {
    "claude@1": { displayName: "Claude · a", plan: "Pro", resources: { session: { unit: "percent", used: 42 } } },
    "codex@2": { displayName: "ChatGPT · b", resources: { credits: { unit: "credits", available: 821 } } },
  },
});

describe("brim agents", () => {
  it("reads every account with its own limits", () => {
    const [claude, codex] = parseBrimAgents(output);
    expect(claude.limits[0]).toMatchObject({ label: "Session", utilization: 42, value: null });
    expect(codex.limits[0]).toMatchObject({ label: "Credits", utilization: null, value: "821 credits" });
  });

  it("hides only an untouched Antigravity window's moving reset", () => {
    const resetsAt = "2026-11-06T17:08:48.000Z";
    const session = (used: number) => ({ resources: { session: { unit: "percent", used, resetsAt } } });
    const resets = parseBrimAgents(
      JSON.stringify({
        providers: { "antigravity@1": session(0), "antigravity@2": session(4), "claude@1": session(0) },
      }),
    ).map((agent) => agent.limits[0].resetsAt);
    expect(resets).toEqual([null, resetsAt, resetsAt]);
  });

  it("rounds non-percent values to two decimals", () => {
    const [agent] = parseBrimAgents(
      JSON.stringify({ providers: { "x@1": { resources: { extraUsageSpent: { unit: "usd", used: 12.3456 } } } } }),
    );
    expect(agent.limits[0].value).toBe("12.35 usd");
  });

  it("applies the saved order and leaves new agents at the end", () => {
    const agents = parseBrimAgents(output);
    expect(applyAgentOrder(agents, ["codex@2"]).map((a) => a.id)).toEqual(["codex@2", "claude@1"]);
  });

  it("bolds letters and digits only", () => {
    expect(boldText("Az9 · a@b")).toBe("𝗔𝘇𝟵 · 𝗮@𝗯");
  });

  it("moves an agent and stops at the ends", () => {
    expect(moveAgent(["a", "b"], "b", -1)).toEqual(["b", "a"]);
    expect(moveAgent(["a", "b"], "a", -1)).toEqual(["a", "b"]);
  });
});

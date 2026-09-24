import { loadConfig } from "./config";

describe("loadConfig", () => {
  it("uses the default timeout", () => {
    const cfg = loadConfig({ DATABASE_URL: "postgres://db" });
    expect(cfg.requestTimeoutMs).toBe(5000);
  });

  it("reads feature flags per test", () => {
    const cfg = loadConfig({ DATABASE_URL: "postgres://db", FEATURE_FLAGS: '{"newCheckout":true}' });
    expect(cfg.featureFlags.newCheckout).toBe(true);
  });

  it("fails without DATABASE_URL", () => {
    expect(() => loadConfig({})).toThrow("DATABASE_URL is required");
  });
});

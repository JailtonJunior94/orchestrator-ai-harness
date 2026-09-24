Transforma o loadConfig de evals/fixtures/appconfig/config.ts em Singleton para ninguém carregar a config duas vezes.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/appconfig/config.ts`:

```
export interface AppConfig {
  databaseUrl: string;
  requestTimeoutMs: number;
  featureFlags: Record<string, boolean>;
}

export function loadConfig(env: NodeJS.ProcessEnv): AppConfig {
  const databaseUrl = env.DATABASE_URL;
  if (!databaseUrl) {
    throw new Error("DATABASE_URL is required");
  }
  return {
    databaseUrl,
    requestTimeoutMs: Number(env.REQUEST_TIMEOUT_MS ?? "5000"),
    featureFlags: JSON.parse(env.FEATURE_FLAGS ?? "{}"),
  };
}
```

`evals/fixtures/appconfig/config.test.ts`:

```
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
```

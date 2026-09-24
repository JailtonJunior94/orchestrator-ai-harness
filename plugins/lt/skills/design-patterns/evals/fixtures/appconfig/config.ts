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

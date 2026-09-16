import { afterEach, describe, expect, it, vi } from "vitest";
import {
  ProvisioningTransaction,
  canTransition,
  createReservationAllowed,
  fetchRuntimeConfig,
  listOrganizations,
  oauthCredentialSaveAllowed,
  operationLeaseActive,
  productionFetch,
  reconcileMigrations,
  redact,
  runCanonicalMigrations,
  runFixedVerification,
} from "../src/production";

const ref = "abcdefghijklmnopqrst";
const publishableKey = "sb_publishable_CuLX_Y3xWuD0cuItKbm-Xw_NJMQ84zu";
const runtimeConfig = {
  projectRef: ref,
  projectUrl: `https://${ref}.supabase.co`,
  publishableKey,
};
const transactionId = "0123456789abcdef0123456789abcdef";
const verificationRow = Object.fromEntries(
  [
    "required_tables_exist",
    "rls_enabled",
    "required_rpcs_exist",
    "protocol_v2_authenticated_execute",
    "capability_grants_correct",
    "f03_helper_private",
    "f03_validates_branch_before_union",
    "f03_wrappers_active",
    "recurrence_provenance_present",
    "relationships_owner_scoped",
    "direct_authenticated_writes_revoked",
    "capability_payload_current",
  ].map((key) => [key, true]),
);
// Mirrors publicTx()'s explicit allowlist. Any new key must be added here
// deliberately, so a Durable Object field cannot leak by accident.
const snapshotAllowlist = new Set([
  "schema",
  "state",
  "createdAt",
  "updatedAt",
  "expiresAt",
  "oauthStateUsed",
  "subject",
  "organizationSlug",
  "requestedProjectName",
  "idempotencyKey",
  "projectRef",
  "createAttempts",
  "expensiveAttempts",
  "verification",
  "error",
  "operation",
  "runtimeConfig",
]);

function durableTransaction() {
  let body: string | undefined;
  const sql = {
    exec(query: string, ...values: unknown[]) {
      if (query.startsWith("SELECT")) return { toArray: () => body ? [{ body }] : [] };
      if (query.startsWith("INSERT")) body = String(values[0]);
      return { toArray: () => [] };
    },
  };
  const ctx = {
    storage: { sql, setAlarm: async () => undefined },
    blockConcurrencyWhile: (operation: () => Promise<unknown>) => operation(),
  };
  return {
    tx: new ProvisioningTransaction(ctx as any, { OAUTH_SESSION_KEY: "test-session-key" } as any),
    read: () => body ? JSON.parse(body) as Record<string, unknown> : undefined,
  };
}

describe("create reconciliation guards", () => {
  it("allows create only initially or after a durable reconciled-absent authorization", () => {
    expect(createReservationAllowed("organization_selected", 0)).toBe(true);
    expect(createReservationAllowed("project_reconciliation_required", 1)).toBe(false);
    expect(createReservationAllowed("project_creating", 1)).toBe(false);
    expect(createReservationAllowed("project_retry_authorized", 1)).toBe(true);
    expect(createReservationAllowed("project_retry_authorized", 2)).toBe(false);
  });

  it("keeps active create leases exclusive and makes stale completion non-authoritative", () => {
    expect(operationLeaseActive({ kind: "create", nonce: "first", startedAt: 1, leaseExpiresAt: 101 }, 100)).toBe(true);
    expect(operationLeaseActive({ kind: "create", nonce: "first", startedAt: 1, leaseExpiresAt: 101 }, 101)).toBe(false);
    expect(canTransition("project_creating", "project_reconciliation_required")).toBe(true);
    expect(canTransition("project_reconciliation_required", "project_creating")).toBe(false);
  });

  it("fails closed when reconciliation finds multiple matching projects", () => {
    expect(canTransition("project_reconciliation_required", "terminal_error")).toBe(true);
    expect(canTransition("terminal_error", "project_creating")).toBe(false);
  });

  it("does not permit an uncertain external create to reserve another POST before reconciliation", async () => {
    const { tx } = durableTransaction();
    await tx.create("a".repeat(48), "s".repeat(48), "v".repeat(48));
    await tx.selectOrganization("a".repeat(48), "owner-org", "personal-planner-safe-project", "k".repeat(32));
    const first = await tx.reserveCreate("a".repeat(48));
    await tx.createUncertain("a".repeat(48), first.nonce);
    await expect(tx.reserveCreate("a".repeat(48))).rejects.toThrow("illegal_transition");
    await tx.reconciliationAbsent("a".repeat(48));
    const second = await tx.reserveCreate("a".repeat(48));
    expect(second.nonce).not.toBe(first.nonce);
  });
});

describe("OAuth credential lifetime", () => {
  it("rejects a delayed callback after transaction expiry even if it was previously claimed", () => {
    expect(oauthCredentialSaveAllowed("authorization_pending", true, "c3RhdGU=", "c3RhdGU=", 100, 200, 99)).toBe(true);
    expect(oauthCredentialSaveAllowed("authorization_pending", true, "c3RhdGU=", "c3RhdGU=", 100, 200, 100)).toBe(false);
    expect(oauthCredentialSaveAllowed("expired", true, "c3RhdGU=", "c3RhdGU=", 100, 200, 99)).toBe(false);
  });

  it("rejects replayed, mismatched, and cleared OAuth state", () => {
    expect(oauthCredentialSaveAllowed("authorization_pending", false, "c3RhdGU=", "c3RhdGU=", 100, 200, 99)).toBe(false);
    expect(oauthCredentialSaveAllowed("authorization_pending", true, undefined, "c3RhdGU=", 100, 200, 99)).toBe(false);
    expect(oauthCredentialSaveAllowed("authorization_pending", true, "c3RhdGU=", "b3RoZXI=", 100, 200, 99)).toBe(false);
  });

  it("cannot restore a token after expiry cleanup or a replayed callback", async () => {
    const { tx, read } = durableTransaction();
    const access = "a".repeat(48), oauthState = "s".repeat(48);
    await tx.create(access, oauthState, "v".repeat(48));
    await tx.oauthCallback(oauthState);
    const expired = read()!;
    expired.expiresAt = Date.now() - 1;
    (tx as any).save(expired);
    await expect(tx.saveOAuthFromCallback(oauthState, "management-token", Date.now() + 60_000, "subject")).rejects.toThrow("oauth_expired");
    expect(read()).toMatchObject({ state: "expired" });
    expect(read()?.tokenCiphertext).toBeUndefined();
  });
});

describe("migration and verification recovery", () => {
  it("defines constrained migration recovery transitions", () => {
    expect(canTransition("migrating", "migration_reconciliation_required")).toBe(true);
    expect(canTransition("migration_reconciliation_required", "migrating")).toBe(true);
    expect(canTransition("project_reconciliation_required", "migrating")).toBe(false);
  });

  it("binds actual migration and verification completion to their active nonce", async () => {
    const { tx } = durableTransaction();
    const access = "a".repeat(48);
    await tx.create(access, "s".repeat(48), "v".repeat(48));
    await tx.selectOrganization(access, "owner-org", "personal-planner-safe-project", "k".repeat(32));
    const create = await tx.reserveCreate(access);
    await tx.recordProject(access, create.nonce, ref);
    const migration = await tx.claimOperation(access, "migration");
    await expect(tx.finishMigration(access, "stale", { kind: "complete" })).rejects.toThrow("stale_operation");
    await tx.finishMigration(access, migration.nonce, { kind: "complete" });
    const verification = await tx.claimOperation(access, "verification");
    await expect(tx.finishVerification(access, "stale", "passed")).rejects.toThrow("stale_operation");
    await tx.finishVerification(access, verification.nonce, "passed", runtimeConfig);
    expect((await tx.get(access) as any).state).toBe("ready");
  });

  it("accepts a canonical history prefix in either recorded shape", () => {
    const migrations = [{ name: "1_one", query: "", sha256: "a" }, { name: "2_two", query: "", sha256: "b" }];
    expect(reconcileMigrations(migrations, [])).toEqual({ next: 0 });
    // version + short name, as the CLI records it
    expect(reconcileMigrations(migrations, [{ name: "one", version: "1" }])).toEqual({ next: 1 });
    // full canonical name stored verbatim
    expect(reconcileMigrations(migrations, [{ name: "1_one" }])).toEqual({ next: 1 });
    expect(reconcileMigrations(migrations, [{ name: "one", version: "1" }, { name: "two", version: "2" }])).toEqual({ next: 2 });
  });

  it("ignores history rows that are not ours but still fails closed on our own drift", () => {
    const migrations = [{ name: "1_one", query: "", sha256: "a" }, { name: "2_two", query: "", sha256: "b" }];
    // platform/external rows observed on a real project are not drift
    expect(reconcileMigrations(migrations, [{ name: "20211115170000_init" }])).toEqual({ next: 0 });
    expect(reconcileMigrations(migrations, [{ name: "20211115170000_init" }, { name: "one", version: "1" }])).toEqual({ next: 1 });
    expect(reconcileMigrations(migrations, [{ name: "1_one" }, { name: "0_platform_patch" }, { name: "2_two" }])).toEqual({ next: 2 });
    // our own migrations must appear exactly once and in canonical order
    expect(reconcileMigrations(migrations, [{ name: "two", version: "2" }])).toEqual({ next: 0, error: "migration_history_mismatch" });
    expect(reconcileMigrations(migrations, [{ name: "2_two" }, { name: "1_one" }])).toEqual({ next: 0, error: "migration_history_mismatch" });
    expect(reconcileMigrations(migrations, [{ name: "1_one" }, { name: "one", version: "1" }])).toEqual({ next: 0, error: "migration_history_mismatch" });
  });

  it("applies only missing migrations, treats complete history as a no-op, and fails closed on drift", async () => {
    const history: Array<{ name: string }> = [];
    const posts: string[] = [];
    const management = async (_path: string, init?: RequestInit) => {
      if (init?.method === "POST") {
        const request = JSON.parse(String(init.body)) as { name: string };
        posts.push(request.name);
        history.push({ name: request.name });
      }
      return Response.json(history);
    };
    expect(await runCanonicalMigrations(ref, management)).toEqual({ kind: "complete" });
    expect(posts).toHaveLength(5);
    expect(await runCanonicalMigrations(ref, management)).toEqual({ kind: "complete" });
    expect(posts).toHaveLength(5);
    // Our own migrations appearing out of order remain a terminal failure.
    expect(await runCanonicalMigrations(ref, async () => Response.json([{ name: "20260910000000_real_use_v2" }]))).toEqual({ kind: "failed", code: "migration_history_mismatch" });
    // A history the Worker cannot advance through stays retryable, never terminal.
    expect(await runCanonicalMigrations(ref, async () => Response.json([{ name: "999_platform_bootstrap" }]))).toEqual({ kind: "indeterminate" });
  });

  it("applies only the missing suffix when the project history also holds foreign rows", async () => {
    const history: Array<{ name?: string; version?: string }> = [{ name: "20211115170000_init" }];
    const posts: string[] = [];
    const management = async (_path: string, init?: RequestInit) => {
      if (init?.method === "POST") {
        const request = JSON.parse(String(init.body)) as { name: string };
        posts.push(request.name);
        history.push({ name: request.name });
      }
      return Response.json(history);
    };

    expect(await runCanonicalMigrations(ref, management)).toEqual({ kind: "complete" });
    expect(posts).toHaveLength(5);
  });

  it("accepts version and short-name history rows and applies only what is missing", async () => {
    const history: Array<{ name?: string; version?: string }> = [
      { name: "20211115170000_init" },
      { name: "sync_v1", version: "20260827000000" },
    ];
    const posts: string[] = [];
    const management = async (_path: string, init?: RequestInit) => {
      if (init?.method === "POST") {
        const request = JSON.parse(String(init.body)) as { name: string };
        posts.push(request.name);
        const [version, ...rest] = request.name.split("_");
        history.push({ name: rest.join("_"), version });
      }
      return Response.json(history);
    };

    expect(await runCanonicalMigrations(ref, management)).toEqual({ kind: "complete" });
    expect(posts).toEqual([
      "20260829000000_sync_v1_hardening",
      "20260910000000_real_use_v2",
      "20260915000000_recurrence_removal_provenance",
      "20260916000000_title_history_conflict_ordering",
    ]);
  });

  it("classifies unavailable migration history and verification transport as indeterminate", async () => {
    expect(await runCanonicalMigrations(ref, async () => new Response(null, { status: 503 }))).toEqual({ kind: "indeterminate" });
    expect(await runFixedVerification(ref, async () => new Response(null, { status: 429 }))).toBe("indeterminate");
    expect(await runFixedVerification(ref, async () => Response.json({ unusable: true }))).toBe("indeterminate");
  });

  it("distinguishes fixed verification assertion failure from a passed result", async () => {
    const keys = ["required_tables_exist","rls_enabled","required_rpcs_exist","protocol_v2_authenticated_execute","capability_grants_correct","f03_helper_private","f03_validates_branch_before_union","f03_wrappers_active","recurrence_provenance_present","relationships_owner_scoped","direct_authenticated_writes_revoked","capability_payload_current"];
    const passed = Object.fromEntries(keys.map(key => [key, true]));
    expect(await runFixedVerification(ref, async () => Response.json([passed]))).toBe("passed");
    expect(await runFixedVerification(ref, async () => Response.json([{ ...passed, rls_enabled: false }]))).toBe("assertion_failed");
  });
});

describe("sanitization", () => {
  it("redacts credential-shaped diagnostics", () => {
    const output = redact("authorization=Bearer eyJheader.payload.signature password=hunter2 sb_secret_abcdefghijklmnopqrstuvwxyz refresh_token=long-token-value");
    expect(output).not.toContain("hunter2");
    expect(output).not.toContain("eyJheader");
    expect(output).not.toContain("abcdefghijklmnopqrstuvwxyz");
    expect(output).toContain("[redacted]");
  });
});

/** Drives one transaction up to `verifying` with real Management credentials stored. */
async function transactionAtVerifying() {
  const { tx, read } = durableTransaction();
  const access = "a".repeat(48);
  const oauthState = "s".repeat(48);
  await tx.create(access, oauthState, "v".repeat(48));
  await tx.oauthCallback(oauthState);
  await tx.saveOAuthFromCallback(oauthState, "management-token", Date.now() + 600_000, "subject-1");
  await tx.selectOrganization(access, "owner-org", "personal-planner-safe-project", "k".repeat(32));
  const create = await tx.reserveCreate(access);
  await tx.recordProject(access, create.nonce, ref);
  const migration = await tx.claimOperation(access, "migration");
  await tx.finishMigration(access, migration.nonce, { kind: "complete" });
  return { tx, read, access };
}

describe("organization discovery", () => {
  it("maps a valid upstream response into a sanitized, production-owned list", async () => {
    const seen: string[] = [];
    const organizations = await listOrganizations(async (path) => {
      seen.push(path);
      return Response.json([
        { id: "org-1", name: "Owner Org", slug: "owner-org", access_token: "management-token" },
        { id: "org-2", name: "Second Org", slug: "second" },
      ]);
    });

    expect(seen).toEqual(["/v1/organizations"]);
    expect(organizations).toEqual([
      { id: "org-1", name: "Owner Org", slug: "owner-org" },
      { id: "org-2", name: "Second Org", slug: "second" },
    ]);
    expect(Object.keys(organizations![0]!)).toEqual(["id", "name", "slug"]);
    expect(JSON.stringify(organizations)).not.toContain("management-token");
  });

  it("accepts an empty list and fails closed on an oversized one", async () => {
    expect(await listOrganizations(async () => Response.json([]))).toEqual([]);
    const many = Array.from({ length: 101 }, (_, index) => ({
      id: `org-${index}`,
      name: `Org ${index}`,
      slug: `org-${index}`,
    }));
    expect(await listOrganizations(async () => Response.json(many))).toBeNull();
  });

  it("fails closed on transport, status, and malformed responses", async () => {
    expect(await listOrganizations(async () => new Response(null, { status: 429 }))).toBeNull();
    expect(await listOrganizations(async () => new Response(null, { status: 503 }))).toBeNull();
    expect(await listOrganizations(async () => { throw new Error("network down"); })).toBeNull();
    expect(await listOrganizations(async () => Response.json({ organizations: [] }))).toBeNull();
    expect(await listOrganizations(async () => Response.json([null]))).toBeNull();
    expect(await listOrganizations(async () => Response.json([{ id: "org-1", name: "Owner" }]))).toBeNull();
    expect(await listOrganizations(async () => Response.json([{ id: "org-1", name: "Owner", slug: 7 }]))).toBeNull();
    expect(await listOrganizations(async () => Response.json([{ id: "", name: "Owner", slug: "owner-org" }]))).toBeNull();
    expect(await listOrganizations(async () => Response.json([{ id: "org-1", name: "x".repeat(201), slug: "owner-org" }]))).toBeNull();
  });
});

describe("publishable runtime configuration retrieval", () => {
  function keysCall(
    keys: unknown,
    revealed: unknown,
    options: { listStatus?: number; revealStatus?: number } = {},
  ) {
    const paths: string[] = [];
    const call = async (path: string) => {
      paths.push(path);
      if (path.includes("?reveal=true")) {
        return new Response(JSON.stringify(revealed), {
          status: options.revealStatus ?? 200,
          headers: { "content-type": "application/json" },
        });
      }
      return new Response(JSON.stringify(keys), {
        status: options.listStatus ?? 200,
        headers: { "content-type": "application/json" },
      });
    };
    return { call, paths };
  }

  it("selects only the publishable key and derives the project URL", async () => {
    const { call, paths } = keysCall(
      [
        { id: "legacy-anon", type: "legacy", api_key: "eyJhbGciOiJIUzI1NiJ9.payload.signature" },
        { id: "secret-1", type: "secret", api_key: "sb_secret_abcdefghijklmnopqrstuvwxyz" },
        { id: "pub-1", type: "publishable" },
      ],
      { id: "pub-1", type: "publishable", api_key: publishableKey },
    );

    expect(await fetchRuntimeConfig(ref, call)).toEqual(runtimeConfig);
    expect(paths).toEqual([
      `/v1/projects/${ref}/api-keys`,
      `/v1/projects/${ref}/api-keys/pub-1?reveal=true`,
    ]);
  });

  it("never yields a secret or legacy key even when the reveal response disagrees", async () => {
    const secret = keysCall(
      [{ id: "pub-1", type: "publishable" }],
      { type: "publishable", api_key: "sb_secret_abcdefghijklmnopqrstuvwxyz" },
    );
    expect(await fetchRuntimeConfig(ref, secret.call)).toBeNull();

    const legacy = keysCall(
      [{ id: "pub-1", type: "publishable" }],
      { type: "publishable", api_key: "eyJhbGciOiJIUzI1NiJ9.payload.signature" },
    );
    expect(await fetchRuntimeConfig(ref, legacy.call)).toBeNull();

    const wrongType = keysCall(
      [{ id: "pub-1", type: "publishable" }],
      { type: "secret", api_key: publishableKey },
    );
    expect(await fetchRuntimeConfig(ref, wrongType.call)).toBeNull();
  });

  it("fails closed when there is no publishable key or more than one", async () => {
    expect(await fetchRuntimeConfig(ref, keysCall([{ id: "secret-1", type: "secret" }], {}).call)).toBeNull();
    expect(await fetchRuntimeConfig(ref, keysCall([
      { id: "pub-1", type: "publishable" },
      { id: "pub-2", type: "publishable" },
    ], {}).call)).toBeNull();
    expect(await fetchRuntimeConfig(ref, keysCall(
      [{ id: "pub-1", type: "publishable" }],
      { type: "publishable", api_key: "sb_publishable_short" },
    ).call)).toBeNull();
  });

  it("treats transport, status, and malformed failures as retryable", async () => {
    expect(await fetchRuntimeConfig(ref, keysCall(null, {}, { listStatus: 429 }).call)).toBeNull();
    expect(await fetchRuntimeConfig(ref, keysCall(null, {}, { listStatus: 503 }).call)).toBeNull();
    expect(await fetchRuntimeConfig(ref, keysCall(
      [{ id: "pub-1", type: "publishable" }],
      {},
      { revealStatus: 500 },
    ).call)).toBeNull();
    expect(await fetchRuntimeConfig(ref, keysCall({ not: "an array" }, {}).call)).toBeNull();
    expect(await fetchRuntimeConfig(ref, async () => { throw new Error("network down"); })).toBeNull();
  });

  it("never calls Management for a project ref the Worker cannot accept", async () => {
    const { call, paths } = keysCall([{ id: "pub-1", type: "publishable" }], {});
    expect(await fetchRuntimeConfig("ABCDEFGHIJKLMNOPQRST", call)).toBeNull();
    expect(await fetchRuntimeConfig("abcdefghijklmnopqrs1", call)).toBeNull();
    expect(await fetchRuntimeConfig("abcdefghijklmnopqrs", call)).toBeNull();
    expect(paths).toEqual([]);
  });
});

describe("ready runtime configuration contract", () => {
  it("does not expose a runtime configuration before ready", async () => {
    const { tx, read, access } = await transactionAtVerifying();

    const snapshot = await tx.get(access) as Record<string, unknown>;
    expect(snapshot.state).toBe("verifying");
    expect(snapshot.runtimeConfig).toBeNull();
    expect(read()!.runtimeConfig).toBeUndefined();
  });

  it("refuses to become ready without a client-safe configuration", async () => {
    const { tx, read, access } = await transactionAtVerifying();
    const verification = await tx.claimOperation(access, "verification");

    await expect(tx.finishVerification(access, verification.nonce, "passed")).rejects.toThrow("runtime_config_unavailable");
    expect((await tx.get(access) as any).state).toBe("verifying");
    expect(read()!.state).toBe("verifying");
  });

  it("rejects a configuration that does not describe the provisioned project", async () => {
    const { tx, access } = await transactionAtVerifying();
    const verification = await tx.claimOperation(access, "verification");

    await expect(tx.finishVerification(access, verification.nonce, "passed", {
      projectRef: ref,
      projectUrl: "https://someone-else.supabase.co",
      publishableKey,
    })).rejects.toThrow("runtime_config_unavailable");
    await expect(tx.finishVerification(access, verification.nonce, "passed", {
      projectRef: ref,
      projectUrl: `https://${ref}.supabase.co`,
      publishableKey: "sb_secret_abcdefghijklmnopqrstuvwxyz",
    })).rejects.toThrow("runtime_config_unavailable");
  });

  it("stores the configuration, clears Management material, and keeps the snapshot allowlisted", async () => {
    const { tx, read, access } = await transactionAtVerifying();
    const ciphertext = read()!.tokenCiphertext;
    expect(typeof ciphertext).toBe("string");

    const verification = await tx.claimOperation(access, "verification");
    const snapshot = await tx.finishVerification(access, verification.nonce, "passed", runtimeConfig) as Record<string, unknown>;

    expect(snapshot.state).toBe("ready");
    expect(snapshot.runtimeConfig).toEqual(runtimeConfig);
    expect((await tx.get(access) as any).runtimeConfig).toEqual(runtimeConfig);

    const stored = read()!;
    expect(stored.tokenCiphertext).toBeUndefined();
    expect(stored.tokenExpiresAt).toBeUndefined();

    const serialized = JSON.stringify(snapshot);
    expect(serialized).not.toContain("management-token");
    expect(serialized).not.toContain(ciphertext!);
    expect(serialized).not.toContain("sb_secret_");
    for (const forbidden of [
      "accessHash",
      "oauthState",
      "oauthStateHash",
      "oauthVerifier",
      "tokenCiphertext",
      "tokenExpiresAt",
    ]) {
      expect(Object.prototype.hasOwnProperty.call(snapshot, forbidden)).toBe(false);
    }
    expect(Object.keys(snapshot).filter((key) => !snapshotAllowlist.has(key))).toEqual([]);
  });

  it("never exposes a configuration for a terminal verification result", async () => {
    const { tx, read, access } = await transactionAtVerifying();
    const verification = await tx.claimOperation(access, "verification");

    const snapshot = await tx.finishVerification(access, verification.nonce, "assertion_failed") as Record<string, unknown>;
    expect(snapshot.state).toBe("terminal_error");
    expect(snapshot.runtimeConfig).toBeNull();
    expect(read()!.tokenCiphertext).toBeUndefined();
  });

  it("serves no snapshot at all once the transaction expires", async () => {
    const { tx, read, access } = await transactionAtVerifying();
    const verification = await tx.claimOperation(access, "verification");
    await tx.finishVerification(access, verification.nonce, "passed", runtimeConfig);

    (tx as any).expire(read()!);

    // The client-safe configuration is retained in the record but exposure is
    // gated on `ready`, and an expired transaction serves no snapshot at all.
    expect(read()!.state).toBe("expired");
    expect(read()!.runtimeConfig).toEqual(runtimeConfig);
    await expect(tx.get(access)).rejects.toThrow("expired");
  });
});

describe("provisioning route contract", () => {
  const organizationsUrl = `https://worker.test/v1/provisioning/transactions/${transactionId}/organizations`;
  const verifyUrl = `https://worker.test/v1/provisioning/transactions/${transactionId}/verify`;

  function fakeTransaction(overrides: Record<string, unknown> = {}) {
    return {
      managementToken: async (capability: string) =>
        capability === "capability-1" ? "management-token" : null,
      createContext: async () => ({ state: "authorization_pending", projectRef: ref }),
      claimOperation: async () => ({ nonce: "op-nonce", projectRef: ref }),
      finishVerification: async (_a: string, _n: string, result: string, config?: unknown) => ({
        state: result === "passed" ? "ready" : result === "assertion_failed" ? "terminal_error" : "verifying",
        runtimeConfig: config ?? null,
      }),
      get: async () => ({ state: "ready", runtimeConfig }),
      ...overrides,
    };
  }

  function environment(worker: Record<string, unknown>) {
    return {
      PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => worker },
      SUPABASE_OAUTH_CLIENT_ID: "client-id",
      SUPABASE_OAUTH_REDIRECT_URI: "https://worker.test/oauth/callback",
    };
  }

  function getRequest(url: string, capability = "capability-1") {
    return new Request(url, { headers: { authorization: `Provisioning ${capability}` } });
  }

  function postRequest(url: string, capability = "capability-1") {
    return new Request(url, {
      method: "POST",
      headers: {
        authorization: `Provisioning ${capability}`,
        "content-type": "application/json",
      },
      body: "{}",
    });
  }

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("requires the provisioning capability", async () => {
    const missing = await productionFetch(new Request(organizationsUrl), environment(fakeTransaction()) as any);
    expect(missing!.status).toBe(401);

    const invalid = await productionFetch(
      getRequest(organizationsUrl, "not-the-capability"),
      environment(fakeTransaction()) as any,
    );
    expect(invalid!.status).toBe(401);
    expect(await invalid!.json()).toEqual({ error: "oauth_expired" });
  });

  it("returns only the client-facing provisioning grant when a transaction is created", async () => {
    const worker = fakeTransaction({ create: async () => ({}) });
    const response = await productionFetch(
      postRequest("https://worker.test/v1/provisioning/transactions"),
      environment(worker) as any,
    );

    expect(response!.status).toBe(200);
    const body = await response!.json() as Record<string, unknown>;
    expect(Object.keys(body).sort()).toEqual([
      "accessToken",
      "authorizationUrl",
      "expiresIn",
      "transactionId",
    ]);
    expect(String(body.transactionId)).toMatch(/^[a-f0-9]{32}$/);
    expect(String(body.accessToken)).toMatch(/^[A-Za-z0-9_-]{40,}$/);
    expect(body.expiresIn).toBe(3600);

    const authorization = new URL(String(body.authorizationUrl));
    expect(`${authorization.origin}${authorization.pathname}`).toBe("https://api.supabase.com/v1/oauth/authorize");
    expect(authorization.searchParams.get("response_type")).toBe("code");
    expect(authorization.searchParams.get("code_challenge_method")).toBe("S256");
    expect(authorization.searchParams.get("client_id")).toBe("client-id");
    expect(authorization.searchParams.get("state")).toMatch(/^[a-f0-9]{32}\.[A-Za-z0-9_-]{40,}$/);
    expect(JSON.stringify(body)).not.toContain("client_secret");
  });

  it("rejects discovery once the organization has already been selected", async () => {
    vi.stubGlobal("fetch", async () => Response.json([{ id: "org-1", name: "Owner", slug: "owner-org" }]));
    const worker = fakeTransaction({ createContext: async () => ({ state: "organization_selected" }) });

    const response = await productionFetch(getRequest(organizationsUrl), environment(worker) as any);
    expect(response!.status).toBe(409);
    expect(await response!.json()).toEqual({ error: "invalid_request" });
  });

  it("returns only the sanitized organization list", async () => {
    const requested: string[] = [];
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
      requested.push(String(input));
      return Response.json([
        { id: "org-1", name: "Owner", slug: "owner-org", access_token: "management-token" },
      ]);
    });

    const response = await productionFetch(getRequest(organizationsUrl), environment(fakeTransaction()) as any);
    expect(response!.status).toBe(200);
    expect(response!.headers.get("cache-control")).toBe("no-store");

    const body = await response!.json() as { organizations: unknown };
    expect(body.organizations).toEqual([{ id: "org-1", name: "Owner", slug: "owner-org" }]);
    expect(JSON.stringify(body)).not.toContain("management-token");
    expect(requested).toEqual(["https://api.supabase.com/v1/organizations"]);
  });

  it("keeps discovery retryable when Management is unavailable or unusable", async () => {
    vi.stubGlobal("fetch", async () => new Response(null, { status: 503 }));
    const unavailable = await productionFetch(getRequest(organizationsUrl), environment(fakeTransaction()) as any);
    expect(unavailable!.status).toBe(502);
    expect(await unavailable!.json()).toEqual({ error: "organization_discovery_failed" });

    vi.stubGlobal("fetch", async () => Response.json({ organizations: [] }));
    const malformed = await productionFetch(getRequest(organizationsUrl), environment(fakeTransaction()) as any);
    expect(malformed!.status).toBe(502);
    expect(await malformed!.json()).toEqual({ error: "organization_discovery_failed" });
  });

  it("publishes the runtime configuration only after verification and key retrieval succeed", async () => {
    const requested: string[] = [];
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
      const url = String(input);
      requested.push(url);
      if (url.endsWith("/database/query")) return Response.json([verificationRow]);
      if (url.endsWith("/api-keys")) return Response.json([{ id: "pub-1", type: "publishable" }]);
      if (url.includes("?reveal=true")) {
        return Response.json({ id: "pub-1", type: "publishable", api_key: publishableKey });
      }
      return new Response(null, { status: 404 });
    });

    const response = await productionFetch(postRequest(verifyUrl), environment(fakeTransaction()) as any);
    expect(response!.status).toBe(200);

    const body = await response!.json() as { state: string; runtimeConfig: unknown };
    expect(body.state).toBe("ready");
    expect(body.runtimeConfig).toEqual(runtimeConfig);
    expect(JSON.stringify(body)).not.toContain("management-token");
    expect(requested).toContain(`https://api.supabase.com/v1/projects/${ref}/api-keys/pub-1?reveal=true`);
  });

  it("stays retryable, and never reports ready, when the publishable key cannot be read", async () => {
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.endsWith("/database/query")) return Response.json([verificationRow]);
      if (url.endsWith("/api-keys")) return new Response(null, { status: 500 });
      return new Response(null, { status: 404 });
    });

    const response = await productionFetch(postRequest(verifyUrl), environment(fakeTransaction()) as any);
    expect(response!.status).toBe(202);

    const body = await response!.json() as { state: string; runtimeConfig: unknown };
    expect(body.state).toBe("verifying");
    expect(body.runtimeConfig).toBeNull();
  });
});

describe("migration history validation", () => {
  const canonicalOne = "20260827000000_sync_v1";
  const canonicalTwo = "20260829000000_sync_v1_hardening";
  const canonicalThree = "20260910000000_real_use_v2";

  /**
   * Minimal Management stub for reconciliation tests. History reads answer with
   * `rows` (or with the value returned by a `rows()` callback); migration POSTs
   * are recorded so a test can prove none happened.
   */
  function migrationApi(rows: unknown) {
    const posts: string[] = [];
    const historyPaths: string[] = [];
    const call = async (path: string, init?: RequestInit) => {
      if (init?.method === "POST") {
        const body = JSON.parse(String(init.body)) as { name: string };
        posts.push(body.name);
        return Response.json({});
      }
      historyPaths.push(path);
      return Response.json(rows);
    };
    return { call, posts, historyPaths };
  }

  /** Recorder whose history advances as migrations are applied. */
  function advancingMigrationApi(initial: Array<{ name?: string; version?: string }>) {
    const history = [...initial];
    const posts: string[] = [];
    const call = async (_path: string, init?: RequestInit) => {
      if (init?.method === "POST") {
        const body = JSON.parse(String(init.body)) as { name: string };
        posts.push(body.name);
        history.push({ name: body.name });
      }
      return Response.json(history);
    };
    return { call, posts };
  }

  describe("MH-01 malformed history rows", () => {
    it("rejects rows whose identity cannot be read at all", async () => {
      for (const rows of <unknown[]>[
        [{}],
        [{ version: "20260827000000" }],
        [{ name: undefined, version: "20260827000000" }],
      ]) {
        const api = migrationApi(rows);

        expect(await runCanonicalMigrations(ref, api.call)).toEqual({ kind: "indeterminate" });
        expect(api.historyPaths).toHaveLength(1);
        expect(api.posts).toEqual([]);
      }
    });

    it("rejects non-string or empty identity fields instead of treating them as foreign", async () => {
      for (const rows of <unknown[]>[
        [{ name: 42, version: "20260827000000" }],
        [{ name: "sync_v1", version: 123 }],
        [{ name: null, version: "20260827000000" }],
        [{ name: "", version: "20260827000000" }],
        [{ name: "sync_v1", version: "" }],
        [{ name: ["sync_v1"], version: { version: 1 } }],
      ]) {
        const api = migrationApi(rows);

        expect(await runCanonicalMigrations(ref, api.call)).toEqual({ kind: "indeterminate" });
        expect(api.posts).toEqual([]);
      }
    });

    it("rejects malformed rows placed before, between, or after canonical rows", async () => {
      for (const rows of <unknown[]>[
        [{ name: canonicalOne }, {}],
        [{}, { name: canonicalOne }],
        [{ name: canonicalOne }, { name: 42 }, { name: canonicalTwo }],
        [{ name: canonicalOne }, { name: canonicalTwo, version: 5 }],
      ]) {
        const api = migrationApi(rows);

        expect(await runCanonicalMigrations(ref, api.call)).toEqual({ kind: "indeterminate" });
        expect(api.posts).toEqual([]);
      }
    });

    it("surfaces unusable history to direct callers so no migration can be authorized", () => {
      const migrations = [{ name: "1_one", query: "", sha256: "a" }];

      expect(reconcileMigrations(migrations, [{}])).toEqual({ next: 0, unusable: true });
      expect(reconcileMigrations(migrations, [{ name: 42 }])).toEqual({ next: 0, unusable: true });
      // A well-formed unrelated row is still allowed and does not make history unusable.
      expect(reconcileMigrations(migrations, [{ name: "0_platform_init" }])).toEqual({ next: 0 });
    });
  });

  describe("MH-02 contradictory canonical identity", () => {
    it("rejects a canonical full name whose version contradicts that migration", async () => {
      const api = migrationApi([{ name: canonicalOne, version: "20260910000000" }]);

      expect(await runCanonicalMigrations(ref, api.call)).toEqual({ kind: "failed", code: "migration_history_mismatch" });
      expect(api.posts).toEqual([]);
    });

    it("accepts a canonical full name whose version agrees with it", async () => {
      const api = advancingMigrationApi([{ name: canonicalOne, version: "20260827000000" }]);

      expect(await runCanonicalMigrations(ref, api.call)).toEqual({ kind: "complete" });
      expect(api.posts).toHaveLength(4);
      expect(api.posts[0]).toBe(canonicalTwo);
    });

    it("accepts every supported representation of the same canonical migration", () => {
      const canonical = [
        { name: canonicalOne, query: "", sha256: "a" },
        { name: canonicalTwo, query: "", sha256: "b" },
      ];

      expect(reconcileMigrations(canonical, [{ name: canonicalOne }])).toEqual({ next: 1 });
      expect(reconcileMigrations(canonical, [{ name: "sync_v1", version: "20260827000000" }])).toEqual({ next: 1 });
      expect(reconcileMigrations(canonical, [{ name: canonicalOne, version: "20260827000000" }])).toEqual({ next: 1 });
    });

    it("rejects a row whose supported interpretations point at different canonical migrations", async () => {
      // Synthetic bundle: the full name identifies one migration while the
      // version-plus-name pair would identify a different one.
      const canonical = [
        { name: "1_alpha", query: "", sha256: "a" },
        { name: "2_1_alpha", query: "", sha256: "b" },
      ];
      expect(reconcileMigrations(canonical, [{ name: "1_alpha", version: "2" }])).toEqual({ next: 0, error: "migration_history_mismatch" });

      const api = migrationApi([{ name: canonicalOne, version: "20260829000000" }]);
      expect(await runCanonicalMigrations(ref, api.call)).toEqual({ kind: "failed", code: "migration_history_mismatch" });
      expect(api.posts).toEqual([]);
    });
  });

  describe("canonical prefix and duplicate regression", () => {
    it("rejects canonical 1 followed by canonical 3 because migration 2 is missing", async () => {
      const api = migrationApi([{ name: canonicalOne }, { name: canonicalThree }]);

      expect(await runCanonicalMigrations(ref, api.call)).toEqual({ kind: "failed", code: "migration_history_mismatch" });
      expect(api.posts).toEqual([]);
    });

    it("rejects a canonical duplicate separated by unrelated rows, including across representations", async () => {
      const api = migrationApi([
        { name: canonicalOne },
        { name: "20211115170000_init" },
        { name: "sync_v1_hardening", version: "20260829000000" },
        { name: "20211115170000_init" },
        { name: canonicalTwo },
      ]);

      expect(await runCanonicalMigrations(ref, api.call)).toEqual({ kind: "failed", code: "migration_history_mismatch" });
      expect(api.posts).toEqual([]);

      const canonical = [
        { name: "1_one", query: "", sha256: "a" },
        { name: "2_two", query: "", sha256: "b" },
      ];
      expect(
        reconcileMigrations(canonical, [
          { name: "1_one" },
          { name: "0_foreign" },
          { name: "2_two" },
          { name: "0_foreign" },
          { name: "2_two" },
        ]),
      ).toEqual({ next: 0, error: "migration_history_mismatch" });
    });
  });

  describe("bundle integrity", () => {
    it("returns migration_bundle_invalid without reading history or posting", async () => {
      const api = migrationApi([{ name: canonicalOne }]);

      expect(
        await runCanonicalMigrations(ref, api.call, { bundlesValid: async () => false }),
      ).toEqual({ kind: "failed", code: "migration_bundle_invalid" });
      expect(api.historyPaths).toEqual([]);
      expect(api.posts).toEqual([]);
    });

    it("still reconciles against Management when the bundle check passes", async () => {
      const api = migrationApi([{ name: canonicalOne }]);

      // Static history cannot advance, so reconciliation stays retryable: the
      // check that matters here is that the injected pass-through did not skip
      // the remote history read.
      expect(
        await runCanonicalMigrations(ref, api.call, { bundlesValid: async () => true }),
      ).toEqual({ kind: "indeterminate" });
      expect(api.historyPaths.length).toBeGreaterThan(0);
    });
  });
});

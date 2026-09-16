import { describe, expect, it } from "vitest";
import {
  ProvisioningTransaction,
  canTransition,
  createReservationAllowed,
  oauthCredentialSaveAllowed,
  operationLeaseActive,
  reconcileMigrations,
  redact,
  runCanonicalMigrations,
  runFixedVerification,
} from "../src/production";

const ref = "abcdefghijklmnopqrst";

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
    await tx.finishVerification(access, verification.nonce, "passed");
    expect((await tx.get(access) as any).state).toBe("ready");
  });

  it("accepts only a canonical history prefix", () => {
    const migrations = [{ name: "1_one", query: "", sha256: "a" }, { name: "2_two", query: "", sha256: "b" }];
    expect(reconcileMigrations(migrations, [])).toEqual({ next: 0 });
    expect(reconcileMigrations(migrations, [{ name: "one", version: "1" }])).toEqual({ next: 1 });
    expect(reconcileMigrations(migrations, [{ name: "two", version: "2" }])).toEqual({ next: 0, error: "migration_history_mismatch" });
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
    expect(await runCanonicalMigrations(ref, async () => Response.json([{ name: "999_unexpected" }]))).toEqual({ kind: "failed", code: "migration_history_mismatch" });
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

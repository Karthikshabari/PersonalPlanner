import { afterEach, describe, expect, it, vi } from "vitest";
import { MIGRATIONS, SCHEMA_VERIFICATION_SQL } from "../src/migrations";
import {
  MANAGEMENT_WINDOW_MS,
  PLANNER_AUTH_CALLBACK_URI,
  PLANNER_EMAIL_CONFIRMATION_PATH,
  PLANNER_MANAGEMENT_CALLBACK_URI,
  ProvisioningTransaction,
  canTransition,
  createReservationAllowed,
  ensureAuthRedirectConfigured,
  fetchRuntimeConfig,
  listOrganizations,
  managementAuthorizationCompletedPage,
  managementAuthorizationDeniedPage,
  mergeAuthRedirectAllowLists,
  mergeAuthRedirectAllowList,
  oauthCredentialSaveAllowed,
  operationLeaseActive,
  plannerEmailConfirmationPage,
  plannerEmailConfirmationUri,
  productionManagementAuthorization,
  productionOAuthCallback,
  productionFetch,
  productionProjectCheck,
  reconcileMigrations,
  redact,
  runCanonicalMigrations,
  runFixedVerification,
  runReadOnlyCompatibilityVerification,
} from "../src/production";

const ref = "abcdefghijklmnopqrst";
const Y = "bcdefghijklmnopqrstu";
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
    "initial_sync_fencing_present",
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
  "authorizationCompleted",
  "authorizationFailed",
  "creationAuthorizationPending",
  "creationAuthorizationRequired",
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

// Every stubbed global (`fetch`, timers) must not leak between cases.
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("Management OAuth callback failures", () => {
  it("completes authorization from the exchanged grant without a profile lookup", async () => {
    let savedToken: string | undefined;
    const requests: string[] = [];
    vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      requests.push(url);
      if (url.endsWith("/v1/oauth/token")) {
        expect(init?.method).toBe("POST");
        expect(new Headers(init?.headers).get("authorization")).toBe(`Basic ${btoa("client-id:client-secret")}`);
        expect(new Headers(init?.headers).get("content-type")).toBe("application/x-www-form-urlencoded");
        expect(new URLSearchParams(init?.body as string).get("grant_type")).toBe("authorization_code");
        expect(new URLSearchParams(init?.body as string).get("code")).toBe("valid-code");
        expect(new URLSearchParams(init?.body as string).get("code_verifier")).toBe("verifier");
        expect(new URLSearchParams(init?.body as string).get("redirect_uri")).toBe("https://worker.test/oauth/callback");
        return Response.json({ access_token: "new-management-token", token_type: "Bearer", expires_in: 300 });
      }
      throw Error("callback attempted an unrelated Management request");
    });
    const worker = {
      oauthCallback: async () => ({ verifier: "verifier", management: false }),
      saveOAuthFromCallback: async (_state: string, token: string) => { savedToken = token; },
    };
    const response = await productionOAuthCallback(
      new Request(`https://worker.test/oauth/callback?state=${transactionId}.state&code=valid-code`),
      { PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => worker }, SUPABASE_OAUTH_CLIENT_ID: "client-id", SUPABASE_OAUTH_CLIENT_SECRET: "client-secret", SUPABASE_OAUTH_REDIRECT_URI: "https://worker.test/oauth/callback" } as any,
    );
    expect(response!.status).toBe(200);
    expect(requests).toEqual(["https://api.supabase.com/v1/oauth/token"]);
    expect(savedToken).toBe("new-management-token");
  });

  it("never reaches an OAuth-unsupported profile endpoint or logs grant material", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => undefined);
    let saved = false, failed = false, created = false;
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
      if (String(input).endsWith("/v1/oauth/token")) return Response.json({ access_token: "new-management-token", token_type: "Bearer", expires_in: 300 });
      throw Error("unexpected Management request");
    });
    const worker = {
      oauthCallback: async () => ({ verifier: "verifier", management: false }),
      saveOAuthFromCallback: async () => { saved = true; },
      markOAuthFailure: async () => { failed = true; return true; },
      create: async () => { created = true; },
    };
    const response = await productionOAuthCallback(
      new Request(`https://worker.test/oauth/callback?state=${transactionId}.state&code=valid-code`),
      { PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => worker }, SUPABASE_OAUTH_CLIENT_ID: "client-id", SUPABASE_OAUTH_CLIENT_SECRET: "client-secret", SUPABASE_OAUTH_REDIRECT_URI: "https://worker.test/oauth/callback" } as any,
    );
    expect(response!.status).toBe(200);
    expect(failed).toBe(false);
    expect(saved).toBe(true);
    expect(created).toBe(false);
    expect(JSON.stringify(log.mock.calls)).not.toContain("new-management-token");
  });

  it("accepts a valid exchanged grant even when the profile API is unavailable", async () => {
    let saved = false;
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => String(input).endsWith("/v1/oauth/token")
      ? Response.json({ access_token: "temporary-token", expires_in: 300 })
      : new Response(null, { status: 502 }));
    const worker = {
      oauthCallback: async () => ({ verifier: "verifier", management: false }),
      saveOAuthFromCallback: async () => { saved = true; },
      markOAuthFailure: async () => true,
    };
    const response = await productionOAuthCallback(
      new Request(`https://worker.test/oauth/callback?state=${transactionId}.state&code=valid-code`),
      { PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => worker }, SUPABASE_OAUTH_CLIENT_ID: "client-id", SUPABASE_OAUTH_CLIENT_SECRET: "client-secret", SUPABASE_OAUTH_REDIRECT_URI: "https://worker.test/oauth/callback" } as any,
    );
    expect(response!.status).toBe(200);
    expect(saved).toBe(true);
  });

  it("returns a safe retryable page when the token exchange is unavailable", async () => {
    let saved = false;
    vi.stubGlobal("fetch", async () => { throw new Error("upstream timeout"); });
    const worker = {
      oauthCallback: async () => ({ verifier: "verifier", management: false }),
      saveOAuthFromCallback: async () => { saved = true; },
      markOAuthFailure: async () => true,
    };
    const response = await productionOAuthCallback(
      new Request(`https://worker.test/oauth/callback?state=${transactionId}.state&code=valid-code`),
      {
        PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => worker },
        SUPABASE_OAUTH_CLIENT_ID: "client-id",
        SUPABASE_OAUTH_CLIENT_SECRET: "client-secret",
        SUPABASE_OAUTH_REDIRECT_URI: "https://worker.test/oauth/callback",
      } as any,
    );

    expect(response!.status).toBe(502);
    const page = await response!.text();
    expect(page).toContain("Supabase authorization could not be completed");
    expect(page).toContain(`${PLANNER_MANAGEMENT_CALLBACK_URI}?result=failed`);
    expect(saved).toBe(false);
  });
});

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
    write: (next: Record<string, unknown>) => { body = JSON.stringify(next); },
    restart: () => new ProvisioningTransaction(ctx as any, { OAUTH_SESSION_KEY: "test-session-key" } as any),
  };
}

async function authorizeForCreation(tx: ProvisioningTransaction, access: string) {
  const state = "s".repeat(48);
  await tx.oauthCallback(state);
  await tx.saveOAuthFromCallback(state, "management-token", undefined, Date.now() + 600_000);
  await tx.recordDiscovery(access, []);
}

const oldTransactionId = "abcdef0123456789abcdef0123456789";
function oldCreationOwner(overrides: Record<string, unknown> = {}) {
  const durable = durableTransaction();
  const now = Date.now();
  durable.write({
    schema: 2,
    state: "expired",
    createdAt: now - 7_200_000,
    updatedAt: now - 3_600_000,
    expiresAt: now - 1,
    accessHash: "durable-internal-only",
    organizationSlug: "owner-org",
    requestedProjectName: `personal-planner-${oldTransactionId}`,
    createAttempts: 1,
    createStartedAt: now - 3_700_000,
    expensiveAttempts: 0,
    ...overrides,
  });
  return durable;
}

describe("create reconciliation guards", () => {
  it("allows create only initially or after a definitive rejected request", () => {
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

  it("never authorizes another POST after an uncertain external create", async () => {
    const { tx } = durableTransaction();
    await tx.create("a".repeat(48), "s".repeat(48), "v".repeat(48));
    await authorizeForCreation(tx, "a".repeat(48));
    await tx.selectOrganization("a".repeat(48), "owner-org", "personal-planner-safe-project", "k".repeat(32));
    const first = await tx.reserveCreate("a".repeat(48));
    await tx.createUncertain("a".repeat(48), first.nonce);
    await expect(tx.reserveCreate("a".repeat(48))).rejects.toThrow("illegal_transition");
    await expect(tx.reserveCreate("a".repeat(48))).rejects.toThrow("illegal_transition");
    await expect(tx.beginManagementAuthorization("a".repeat(48))).rejects.toThrow("invalid_request");
  });

  it("retains recordProject recovery evidence through alarm expiry", async () => {
    const access = "a".repeat(48);
    const durable = durableTransaction();
    await durable.tx.create(access, "s".repeat(48), "v".repeat(48));
    await authorizeForCreation(durable.tx, access);
    await durable.tx.selectOrganization(access, "owner-org", "personal-planner-safe-project", "k".repeat(32));
    const attempt = await durable.tx.reserveCreate(access);
    await durable.tx.recordProject(access, attempt.nonce, ref);
    durable.write({ ...durable.read()!, expiresAt: Date.now() - 1 });

    await durable.tx.alarm();

    expect(await durable.tx.creationRecoveryContext()).toMatchObject({
      state: "expired",
      projectRef: ref,
      organizationSlug: "owner-org",
      projectDurablyRecorded: true,
      expired: true,
      terminal: true,
    });
    expect(durable.read()!.projectRef).toBe(ref);
  });
});

describe("first project creation state machine", () => {
  const access = "a".repeat(48);
  const name = `personal-planner-${transactionId}`;
  const request = (op: string, method = "POST") => new Request(`https://worker.test/v1/provisioning/transactions/${transactionId}${op ? `/${op}` : ""}`, {
    method, headers: { authorization: `Provisioning ${access}`, "content-type": "application/json" },
    ...(method === "POST" ? { body: "{}" } : {}),
  });

  async function harness(create: () => Promise<Response> | Response) {
    const durable = durableTransaction();
    await durable.tx.create(access, "s".repeat(48), "v".repeat(48));
    await authorizeForCreation(durable.tx, access);
    await durable.tx.selectOrganization(access, "owner-org", name, "k".repeat(32));
    let holder: string | null = null;
    let projectStatus = "COMING_UP";
    let healthStatus = 200;
    let created: { ref: string; name: string; inserted_at: string } | null = null;
    let exactProjectResponse: ((projectRef: string) => Promise<Response> | Response) | null = null;
    let beforeConfirmedRelease: (() => void) | null = null;
    const upstream: string[] = [];
    const createBodies: Record<string, unknown>[] = [];
    const transactions = new Map<string, ProvisioningTransaction>([[`tx:${transactionId}`, durable.tx]]);
    const env = {
      PROVISIONING_TRANSACTION: { idFromName: (value: string) => value, get: (value: string) => transactions.get(value) ?? durable.tx },
      MANAGEMENT_ACCOUNT_PROJECT: { idFromName: (value: string) => value, get: () => ({
        reserveCreation: async (id: string) => { if (holder && holder !== id) return "other"; holder = id; return "self"; },
        currentCreationOwner: async () => holder,
        releaseConfirmedMissingCreation: async (id: string, projectRef: string) => {
          beforeConfirmedRelease?.();
          if (holder !== id || !/^[a-z]{20}$/u.test(projectRef)) return { kind: "conflict" };
          holder = null;
          return { kind: "released" };
        },
        releaseCreation: async (id: string) => { if (holder === id) holder = null; },
      }) },
    } as any;
    vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input), method = init?.method ?? "GET";
      upstream.push(`${method} ${url}`);
      if (url.endsWith("/v1/oauth/token")) return Response.json({ access_token: "renewed-token", expires_in: 600 });
      if (url.endsWith("/v1/organizations")) return Response.json([{ id: "org", name: "Owner", slug: "owner-org" }]);
      if (url.includes("/v1/organizations/owner-org/projects?")) return Response.json({
        projects: created ? [created] : [], pagination: { count: created ? 1 : 0, limit: 100, offset: 0 },
      });
      if (url.endsWith("/v1/projects") && method === "POST") {
        createBodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
        return create();
      }
      const exactMatch = /\/v1\/projects\/([a-z]{20})$/u.exec(url);
      if (exactMatch) {
        if (exactProjectResponse) return exactProjectResponse(exactMatch[1]!);
        if (exactMatch[1] === ref) return Response.json({ ref, status: projectStatus });
        return new Response(null, { status: 404 });
      }
      if (url.endsWith(`/v1/projects/${ref}/health?services=auth`)) return healthStatus === 429
        ? new Response(null, { status: 429, headers: { "retry-after": "90" } })
        : Response.json([{ name: "auth", status: "ACTIVE_HEALTHY", healthy: true }]);
      if (url.endsWith(`/v1/projects/${ref}/database/migrations`)) return Response.json(MIGRATIONS.map(m => ({ name: m.name })));
      if (url.endsWith(`/v1/projects/${ref}/database/query/read-only`)) return Response.json([verificationRow], { status: 201 });
      if (url.endsWith(`/v1/projects/${ref}/config/auth`)) return Response.json({ uri_allow_list: `${PLANNER_AUTH_CALLBACK_URI},https://worker.test${PLANNER_EMAIL_CONFIRMATION_PATH}` });
      if (url.endsWith(`/v1/projects/${ref}/api-keys`)) return Response.json([{ id: "publishable", type: "publishable" }]);
      if (url.endsWith(`/v1/projects/${ref}/api-keys/publishable?reveal=true`)) return Response.json({ type: "publishable", api_key: publishableKey });
      return new Response(null, { status: 404 });
    });
    return {
      ...durable, env, upstream, createBodies,
      setCreated: () => { created = { ref, name, inserted_at: new Date().toISOString() }; },
      setHealthy: () => { projectStatus = "ACTIVE_HEALTHY"; },
      rateLimitHealth: () => { healthStatus = 429; },
      holder: () => holder,
      setHolder: (id: string | null) => { holder = id; },
      addTransaction: (id: string, value: ProvisioningTransaction) => { transactions.set(`tx:${id}`, value); },
      setExactProjectResponse: (value: (projectRef: string) => Promise<Response> | Response) => { exactProjectResponse = value; },
      setListedProject: (value: { ref: string; name: string; inserted_at: string } | null) => { created = value; },
      changeOwnerBeforeConfirmedRelease: (value: () => void) => { beforeConfirmedRelease = value; },
      countCreates: () => upstream.filter(x => x === "POST https://api.supabase.com/v1/projects").length,
    };
  }

  it("expires the transaction before Create without sending an upstream request", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    expect(h.read()!.expiresAt).toBeGreaterThan(Date.now() + 3_600_000);
    h.write({ ...h.read()!, expiresAt: Date.now() - 1 });
    const response = await productionFetch(request("create"), h.env);
    expect(response!.status).toBe(410);
    expect(await response!.json()).toEqual({ error: "provisioning_expired" });
    expect(h.read()!.state).toBe("expired");
    expect(h.read()!.organizationSlug).toBe("owner-org");
    expect(h.read()!.createAttempts).toBe(0);
    expect(h.countCreates()).toBe(0);
  });

  it("renews an expired pre-create transaction and still requires explicit Create", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    const originalAccessHash = h.read()!.accessHash;
    h.write({ ...h.read()!, expiresAt: Date.now() - 1 });
    await productionFetch(request("create"), h.env);
    h.env.PROVISIONING_TRANSACTION.get = () => h.restart();
    h.env.SUPABASE_OAUTH_CLIENT_ID = "client-id";
    h.env.SUPABASE_OAUTH_REDIRECT_URI = "https://worker.test/oauth/callback";
    const renewed = await productionManagementAuthorization(request("authorization/start"), h.env);
    expect(renewed!.status).toBe(200);
    expect(h.read()!.state).toBe("organization_selected");
    expect(h.read()!.organizationSlug).toBe("owner-org");
    expect(h.read()!.requestedProjectName).toBe(name);
    expect(h.read()!.accessHash).toBe(originalAccessHash);
    expect(h.read()!.expiresAt).toBeGreaterThan(Date.now() + 3_600_000);
    expect(h.countCreates()).toBe(0);
    const pending = await productionFetch(request("", "GET"), h.env);
    expect((await pending!.json() as { creationAuthorizationPending: boolean }).creationAuthorizationPending).toBe(true);
    const url = new URL((await renewed!.json() as { authorizationUrl: string }).authorizationUrl);
    const state = url.searchParams.get("state")!.split(".")[1]!;
    await h.restart().oauthCallback(state);
    await h.restart().saveOAuthFromCallback(state, "renewed-token", undefined, Date.now() + 600_000);
    expect(h.countCreates()).toBe(0);
    const authorized = await productionFetch(request("", "GET"), h.env);
    expect((await authorized!.json() as { creationAuthorizationPending: boolean; creationAuthorizationRequired: boolean }).creationAuthorizationPending).toBe(false);
    const first = await productionFetch(request("create"), h.env);
    expect(first!.status).toBe(200);
    expect(h.countCreates()).toBe(1);
    await productionFetch(request("create"), h.env);
    expect(h.countCreates()).toBe(1);
  });

  it("separates expired Management token from transaction expiry and keeps the guard", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    h.write({ ...h.read()!, tokenExpiresAt: Date.now() - 1 });
    const denied = await productionFetch(request("create"), h.env);
    expect(denied!.status).toBe(401);
    expect(await denied!.json()).toEqual({ error: "oauth_expired" });
    expect(h.read()!.state).toBe("organization_selected");
    expect(h.countCreates()).toBe(0);
    const required = await productionFetch(request("", "GET"), h.env);
    expect((await required!.json() as { creationAuthorizationRequired: boolean }).creationAuthorizationRequired).toBe(true);
    const grant = await h.tx.beginManagementAuthorization(access);
    await h.tx.oauthCallback(grant.state);
    await h.tx.saveOAuthFromCallback(grant.state, "renewed-token", undefined, Date.now() + 600_000);
    h.setHolder("another-transaction");
    const blocked = await productionFetch(request("create"), h.env);
    expect(blocked!.status).toBe(409);
    expect(h.countCreates()).toBe(0);
    h.setHolder(null);
    const [first, second] = await Promise.all([
      productionFetch(request("create"), h.env),
      productionFetch(request("create"), h.env),
    ]);
    expect([first!.status, second!.status].every(status => status === 200 || status === 202)).toBe(true);
    expect(h.countCreates()).toBe(1);
  });

  it("keeps one OAuth state while authorization is pending and never creates", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    h.write({ ...h.read()!, tokenExpiresAt: Date.now() - 1 });
    h.env.SUPABASE_OAUTH_CLIENT_ID = "client-id";
    h.env.SUPABASE_OAUTH_CLIENT_SECRET = "client-secret";
    h.env.SUPABASE_OAUTH_REDIRECT_URI = "https://worker.test/oauth/callback";
    const first = await productionManagementAuthorization(request("authorization/start"), h.env);
    const firstBody = await first!.json() as { authorizationUrl: string; expiresIn: number };
    expect(firstBody.expiresIn).toBe(900);
    const stateA = new URL(firstBody.authorizationUrl).searchParams.get("state")!.split(".")[1]!;
    const second = await productionManagementAuthorization(request("authorization/start"), h.env);
    const secondBody = await second!.json() as { authorizationUrl: string; expiresIn: number };
    expect(secondBody.expiresIn).toBeGreaterThan(0);
    expect(secondBody.expiresIn).toBeLessThanOrEqual(900);
    const stateB = new URL(secondBody.authorizationUrl).searchParams.get("state")!.split(".")[1]!;
    expect(stateB).toBe(stateA);
    const tokenCall = vi.spyOn(h.tx, "managementToken");
    const pendingCreate = await productionFetch(request("create"), h.env);
    expect(pendingCreate!.status).toBe(202);
    expect(await pendingCreate!.json()).toMatchObject({ state: "organization_selected", creationAuthorizationPending: true });
    expect(tokenCall).not.toHaveBeenCalled();
    expect(h.countCreates()).toBe(0);
    const callback = await productionOAuthCallback(
      new Request(`https://worker.test/oauth/callback?state=${transactionId}.${stateA}&code=valid-code`),
      h.env,
    );
    expect(callback!.status).toBe(200);
    expect(h.countCreates()).toBe(0);
    const ready = await productionFetch(request("", "GET"), h.env);
    expect(await ready!.json()).toMatchObject({ state: "organization_selected", creationAuthorizationPending: false, creationAuthorizationRequired: false });
    const created = await productionFetch(request("create"), h.env);
    expect(created!.status).toBe(200);
    expect(h.countCreates()).toBe(1);
  });

  it("serializes simultaneous authorization starts without replacing the callback state", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    const [first, second] = await Promise.all([
      h.tx.beginManagementAuthorization(access),
      h.tx.beginManagementAuthorization(access),
    ]);
    expect(second.state).toBe(first.state);
    expect(second.verifier).toBe(first.verifier);
    expect(await h.tx.oauthCallback(first.state)).not.toBeNull();
    await expect(h.tx.beginManagementAuthorization(access)).rejects.toThrow("operation_in_progress");
    const exchanging = await productionFetch(request("create"), h.env);
    expect(exchanging!.status).toBe(202);
    expect(await exchanging!.json()).toMatchObject({ creationAuthorizationPending: true });
    expect(h.countCreates()).toBe(0);
  });

  it("rejects an old callback only after an explicit expired-window restart", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    const first = await h.tx.beginManagementAuthorization(access);
    h.write({ ...h.read()!, grantExpiresAt: Date.now() - 1 });
    const restarted = await h.tx.beginManagementAuthorization(access);
    expect(restarted.state).not.toBe(first.state);
    expect(await h.tx.oauthCallback(first.state)).toBeNull();
    expect(await h.tx.oauthCallback(restarted.state)).not.toBeNull();
    expect(h.countCreates()).toBe(0);
  });

  it("persists HTTP 201 immediately and duplicate create requests or restart reuse the ref", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    const first = await productionFetch(request("create"), h.env);
    expect(first!.status).toBe(200);
    expect(h.read()!.projectRef).toBe(ref);
    expect(h.read()!.state).toBe("project_waiting");
    expect(h.read()!.dbPasswordCipher).toBeUndefined();
    for (let i = 0; i < 5; i++) await productionFetch(request("", "GET"), h.env);
    await productionFetch(request("create"), h.env);
    h.env.PROVISIONING_TRANSACTION.get = () => h.restart();
    await productionFetch(request("create"), h.env);
    expect(h.countCreates()).toBe(1);
  });

  it("two overlapping Create calls on one transaction issue one upstream POST", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    const results = await Promise.all([
      productionFetch(request("create"), h.env),
      productionFetch(request("create"), h.env),
    ]);
    expect(results.every(r => r!.status === 200 || r!.status === 202)).toBe(true);
    expect(h.countCreates()).toBe(1);
    expect(h.read()!.projectRef).toBe(ref);
    expect(h.holder()).toBe(transactionId);
  });

  it("reconciles a lost response by exact transaction evidence without a second create", async () => {
    let afterSend: (() => void) | null = null;
    const h = await harness(() => { afterSend?.(); throw Error("connection_lost"); });
    afterSend = h.setCreated;
    const first = await productionFetch(request("create"), h.env);
    expect(first!.status).toBe(202);
    expect(h.read()!.state).toBe("project_reconciliation_required");
    expect(h.holder()).toBe(transactionId);
    const reconciled = await productionFetch(request("reconcile"), h.env);
    expect(reconciled!.status).toBe(200);
    expect(h.read()!.projectRef).toBe(ref);
    expect(h.countCreates()).toBe(1);
  });

  it("can recover a pre-upgrade uncertain transaction using its durable completion time", async () => {
    let afterSend: (() => void) | null = null;
    const h = await harness(() => { afterSend?.(); throw Error("connection_lost"); });
    afterSend = h.setCreated;
    await productionFetch(request("create"), h.env);
    h.write({ ...h.read()!, createStartedAt: undefined });

    const result = await productionFetch(request("reconcile"), h.env);

    expect(result!.status).toBe(200);
    expect(h.read()!.projectRef).toBe(ref);
    expect(h.countCreates()).toBe(1);
  });

  it("keeps uncertain 409 and 5xx responses guarded without a second create", async () => {
    for (const status of [409, 503]) {
      const h = await harness(() => new Response(null, { status }));
      await productionFetch(request("create"), h.env);
      await productionFetch(request("reconcile"), h.env);
      await productionFetch(request("create"), h.env);
      expect(h.read()!.state).toBe("project_reconciliation_required");
      expect(h.holder()).toBe(transactionId);
      expect(h.countCreates()).toBe(1);
    }
  });

  it("classifies proven project quota as terminal user action and does not retry", async () => {
    const h = await harness(() => Response.json({ code: "project_limit", message: "Active project limit reached" }, { status: 403 }));
    const result = await productionFetch(request("create"), h.env);
    expect((await result!.json() as { error: string }).error).toBe("project_quota_reached");
    expect(h.read()!.state).toBe("terminal_error");
    expect(h.holder()).toBeNull();
    await productionFetch(request("create"), h.env);
    expect(h.countCreates()).toBe(1);
  });

  it("backs off a definitive 429 and keeps one password for the bounded retry", async () => {
    let calls = 0;
    const h = await harness(() => ++calls === 1
      ? new Response(null, { status: 429, headers: { "retry-after": "60" } })
      : Response.json({ ref }, { status: 201 }));
    const first = await productionFetch(request("create"), h.env);
    expect((await first!.json() as { state: string }).state).toBe("project_retry_authorized");
    const cipher = h.read()!.dbPasswordCipher;
    await productionFetch(request("create"), h.env);
    expect(h.countCreates()).toBe(1);
    h.write({ ...h.read()!, createRetryAfter: Date.now() - 1 });
    const second = await productionFetch(request("create"), h.env);
    expect(second!.status).toBe(200);
    expect(h.countCreates()).toBe(2);
    expect(cipher).toBeTruthy();
    expect(h.createBodies[0]!.db_pass).toBe(h.createBodies[1]!.db_pass);
    expect(h.createBodies[0]).toMatchObject({ name, organization_slug: "owner-org", region_selection: { type: "smartGroup", code: "apac" } });
  });

  it("waits for project health without consuming migration attempts or recreating", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    await productionFetch(request("create"), h.env);
    const waiting = await productionFetch(request("migrate"), h.env);
    expect(waiting!.status).toBe(202);
    expect(h.read()!.state).toBe("project_waiting");
    expect(h.read()!.expensiveAttempts).toBe(0);
    h.write({ ...h.read()!, healthRetryAfter: Date.now() - 1 });
    h.setHealthy();
    const migrated = await productionFetch(request("migrate"), h.env);
    expect(migrated!.status).toBe(200);
    expect(h.read()!.state).toBe("verifying");
    expect(h.countCreates()).toBe(1);
  });

  it("honors bounded health 429 backoff without claiming migration", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    await productionFetch(request("create"), h.env);
    h.setHealthy();
    h.rateLimitHealth();
    await productionFetch(request("migrate"), h.env);
    const firstCount = h.upstream.length;
    expect(Number(h.read()!.healthRetryAfter) - Date.now()).toBeGreaterThan(80_000);
    await productionFetch(request("migrate"), h.env);
    expect(h.upstream.length).toBe(firstCount);
    expect(h.read()!.expensiveAttempts).toBe(0);
    expect(h.countCreates()).toBe(1);
  });

  it("keeps a guard owned by another active transaction and sends no create", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    const old = oldCreationOwner({ state: "project_creating", expiresAt: Date.now() + 60_000, projectRef: undefined });
    h.addTransaction(oldTransactionId, old.tx);
    h.setHolder(oldTransactionId);

    const response = await productionFetch(request("create"), h.env);

    expect(response!.status).toBe(409);
    expect(await response!.json()).toEqual({ error: "operation_in_progress" });
    expect(h.holder()).toBe(oldTransactionId);
    expect(h.countCreates()).toBe(0);
    expect(h.upstream).toHaveLength(0);
  });

  it("recovers an inactive guard owner's exact recorded project without a new create", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    const old = oldCreationOwner({ projectRef: ref, state: "expired" });
    h.addTransaction(oldTransactionId, old.tx);
    h.setHolder(oldTransactionId);

    const response = await productionFetch(request("create"), h.env);

    expect(response!.status).toBe(200);
    const body = await response!.json() as Record<string, unknown>;
    expect(body).toMatchObject({ state: "project_waiting", projectRef: ref });
    expect(body.creationGuardOwnerTransactionId).toBeUndefined();
    expect(JSON.stringify(body)).not.toContain(oldTransactionId);
    expect(h.read()).toMatchObject({ state: "project_waiting", projectRef: ref, creationGuardOwnerTransactionId: oldTransactionId });
    expect(h.upstream).toContain(`GET https://api.supabase.com/v1/projects/${ref}`);
    expect(h.holder()).toBe(oldTransactionId);
    expect(h.countCreates()).toBe(0);
  });

  it("compare-releases a confirmed-missing recorded project and requires a later explicit Create", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    const old = oldCreationOwner({ projectRef: ref });
    h.addTransaction(oldTransactionId, old.tx);
    h.setHolder(oldTransactionId);
    h.setExactProjectResponse(() => new Response(null, { status: 404 }));

    const reconciled = await productionFetch(request("create"), h.env);

    expect(reconciled!.status).toBe(202);
    expect(await reconciled!.json()).toMatchObject({ state: "organization_selected" });
    expect(h.holder()).toBeNull();
    expect(h.countCreates()).toBe(0);

    const explicitCreate = await productionFetch(request("create"), h.env);
    expect(explicitCreate!.status).toBe(200);
    expect(h.countCreates()).toBe(1);
    expect(h.holder()).toBe(transactionId);
  });

  it("retains the old guard for every ambiguous exact-project lookup", async () => {
    const cases: Array<{ name: string; response: () => Promise<Response> | Response; status: number; error: string }> = [
      { name: "401", response: () => new Response(null, { status: 401 }), status: 401, error: "oauth_expired" },
      { name: "403", response: () => new Response(null, { status: 403 }), status: 502, error: "temporarily_unavailable" },
      { name: "429", response: () => new Response(null, { status: 429 }), status: 429, error: "rate_limited" },
      { name: "5xx", response: () => new Response(null, { status: 503 }), status: 502, error: "temporarily_unavailable" },
      { name: "network", response: async () => { throw Error("network unavailable"); }, status: 502, error: "temporarily_unavailable" },
      { name: "malformed", response: () => new Response("{", { status: 200, headers: { "content-type": "application/json" } }), status: 502, error: "temporarily_unavailable" },
    ];
    for (const testCase of cases) {
      const h = await harness(() => Response.json({ ref }, { status: 201 }));
      const old = oldCreationOwner({ projectRef: ref });
      h.addTransaction(oldTransactionId, old.tx);
      h.setHolder(oldTransactionId);
      h.setExactProjectResponse(testCase.response);

      const response = await productionFetch(request("create"), h.env);

      expect(response!.status, testCase.name).toBe(testCase.status);
      expect(await response!.json(), testCase.name).toEqual({ error: testCase.error });
      expect(h.holder(), testCase.name).toBe(oldTransactionId);
      expect(h.countCreates(), testCase.name).toBe(0);
    }
  });

  it("does not disturb a new guard owner that wins before compare-and-release", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    const old = oldCreationOwner({ projectRef: ref });
    const newOwner = "11111111111111111111111111111111";
    h.addTransaction(oldTransactionId, old.tx);
    h.setHolder(oldTransactionId);
    h.setExactProjectResponse(() => new Response(null, { status: 404 }));
    h.changeOwnerBeforeConfirmedRelease(() => h.setHolder(newOwner));

    const response = await productionFetch(request("create"), h.env);

    expect(response!.status).toBe(409);
    expect(h.holder()).toBe(newOwner);
    expect(h.countCreates()).toBe(0);
  });

  it("uses transaction-scoped reconciliation for an uncertain old owner and keeps the guard when no ref is proven", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    const old = oldCreationOwner({ projectRef: undefined, state: "expired" });
    h.addTransaction(oldTransactionId, old.tx);
    h.setHolder(oldTransactionId);

    const response = await productionFetch(request("create"), h.env);

    expect(response!.status).toBe(409);
    expect(h.upstream.some(value => value.includes(`/v1/organizations/owner-org/projects?`))).toBe(true);
    expect(h.holder()).toBe(oldTransactionId);
    expect(h.countCreates()).toBe(0);
  });

  it("recovers a uniquely reconciled uncertain old-owner project without a new create", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    const old = oldCreationOwner({ projectRef: undefined, state: "expired" });
    h.addTransaction(oldTransactionId, old.tx);
    h.setHolder(oldTransactionId);
    h.setListedProject({ ref, name: `personal-planner-${oldTransactionId}`, inserted_at: new Date().toISOString() });

    const response = await productionFetch(request("create"), h.env);

    expect(response!.status).toBe(200);
    expect(h.read()).toMatchObject({ state: "project_waiting", projectRef: ref });
    expect(h.holder()).toBe(oldTransactionId);
    expect(h.countCreates()).toBe(0);
  });

  it("resumes an existing incomplete project and releases its old guard only at verified READY", async () => {
    const h = await harness(() => Response.json({ ref }, { status: 201 }));
    const old = oldCreationOwner({ projectRef: ref });
    h.addTransaction(oldTransactionId, old.tx);
    h.setHolder(oldTransactionId);

    const recovered = await productionFetch(request("create"), h.env);
    expect(recovered!.status).toBe(200);
    expect(h.holder()).toBe(oldTransactionId);
    expect(h.countCreates()).toBe(0);

    const waiting = await productionFetch(request("migrate"), h.env);
    expect(waiting!.status).toBe(202);
    expect(h.holder()).toBe(oldTransactionId);
    h.write({ ...h.read()!, healthRetryAfter: Date.now() - 1 });
    h.setHealthy();
    const migrated = await productionFetch(request("migrate"), h.env);
    expect(migrated!.status).toBe(200);
    const verified = await productionFetch(request("verify"), h.env);

    expect(verified!.status).toBe(200);
    expect(h.read()!.state).toBe("ready");
    expect(h.holder()).toBeNull();
    expect(h.countCreates()).toBe(0);
  });
});

describe("OAuth credential lifetime", () => {
  it("records cancelled consent without creating a project or storing a grant", async () => {
    const { tx, read } = durableTransaction();
    const access = "a".repeat(48), state = "s".repeat(48);
    await tx.create(access, state, "v".repeat(48));
    const response = await productionOAuthCallback(
      new Request(`https://worker.test/oauth/callback?state=${transactionId}.${state}&error=access_denied`),
      { PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => tx } } as any,
    );
    expect(response!.status).toBe(400);
    expect(await tx.get(access)).toMatchObject({ state: "authorization_pending", authorizationFailed: true, authorizationCompleted: false });
    expect(read()!.subject).toBeUndefined();
    expect(read()!.projectRef).toBeUndefined();
    expect(read()!.createAttempts).toBe(0);
  });

  it("exposes a failed callback to polling and retries OAuth on the same transaction", async () => {
    const { tx, read } = durableTransaction();
    const access = "a".repeat(48);
    const oldState = "s".repeat(48);
    await tx.create(access, oldState, "v".repeat(48));
    const environment = {
      PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => tx },
      SUPABASE_OAUTH_CLIENT_ID: "client-id",
      SUPABASE_OAUTH_CLIENT_SECRET: "client-secret",
      SUPABASE_OAUTH_REDIRECT_URI: "https://worker.test/oauth/callback",
    } as any;
    vi.stubGlobal("fetch", async () => new Response(null, { status: 502 }));

    const failed = await productionOAuthCallback(
      new Request(`https://worker.test/oauth/callback?state=${transactionId}.${oldState}&code=valid-code`),
      environment,
    );
    expect(failed!.status).toBe(502);
    expect(await tx.get(access)).toMatchObject({ state: "authorization_pending", authorizationFailed: true, authorizationCompleted: false });
    expect(read()!.subject).toBeUndefined();
    expect(read()!.projectRef).toBeUndefined();

    const retry = await productionManagementAuthorization(
      new Request(`https://worker.test/v1/provisioning/transactions/${transactionId}/authorization/retry`, {
        method: "POST", headers: { authorization: `Provisioning ${access}` },
      }), environment,
    );
    expect(retry!.status).toBe(200);
    const retryBody = await retry!.json() as { authorizationUrl: string };
    const freshState = new URL(retryBody.authorizationUrl).searchParams.get("state")!;
    expect(new URL(retryBody.authorizationUrl).host).toBe("api.supabase.com");
    expect(freshState).not.toBe(`${transactionId}.${oldState}`);
    expect(read()!.state).toBe("authorization_pending");
    expect(await tx.get(access)).toMatchObject({ authorizationFailed: false, authorizationCompleted: false });

    const stale = await productionOAuthCallback(
      new Request(`https://worker.test/oauth/callback?state=${transactionId}.${oldState}&code=stale-code`),
      environment,
    );
    expect(stale!.status).toBe(400);
    expect(read()!.subject).toBeUndefined();

    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => String(input).endsWith("/v1/oauth/token")
      ? Response.json({ access_token: "temporary-token", expires_in: 300 })
      : new Response(null, { status: 502 }));
    const completed = await productionOAuthCallback(
      new Request(`https://worker.test/oauth/callback?state=${freshState}&code=fresh-code`),
      environment,
    );
    expect(completed!.status).toBe(200);
    expect(await tx.get(access)).toMatchObject({ authorizationCompleted: true, authorizationFailed: false });
    expect(read()!.subject).toBeUndefined();
    expect(await tx.managementToken(access)).toBe("temporary-token");
  });

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
    await expect(tx.saveOAuthFromCallback(oauthState, "management-token", undefined, Date.now() + 60_000)).rejects.toThrow("oauth_expired");
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
    await authorizeForCreation(tx, access);
    await tx.recordDiscovery(access, []);
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
    expect(posts).toHaveLength(6);
    expect(await runCanonicalMigrations(ref, management)).toEqual({ kind: "complete" });
    expect(posts).toHaveLength(6);
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
    expect(posts).toHaveLength(6);
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
      "20260917000000_initial_sync_baseline",
    ]);
  });

  it("classifies unavailable migration history and verification transport as indeterminate", async () => {
    expect(await runCanonicalMigrations(ref, async () => new Response(null, { status: 503 }))).toEqual({ kind: "indeterminate" });
    expect(await runFixedVerification(ref, async () => new Response(null, { status: 429 }))).toBe("indeterminate");
    expect(await runFixedVerification(ref, async () => Response.json({ unusable: true }))).toBe("indeterminate");
  });

  it("distinguishes fixed verification assertion failure from a passed result", async () => {
    const keys = ["required_tables_exist","rls_enabled","required_rpcs_exist","protocol_v2_authenticated_execute","capability_grants_correct","f03_helper_private","f03_validates_branch_before_union","f03_wrappers_active","initial_sync_fencing_present","recurrence_provenance_present","relationships_owner_scoped","direct_authenticated_writes_revoked","capability_payload_current"];
    const passed = Object.fromEntries(keys.map(key => [key, true]));
    expect(await runFixedVerification(ref, async () => Response.json([passed]))).toBe("passed");
    expect(await runFixedVerification(ref, async () => Response.json([{ ...passed, rls_enabled: false }]))).toBe("assertion_failed");
    expect(await runFixedVerification(ref, async () => Response.json([{ ...passed, initial_sync_fencing_present: false }]))).toBe("assertion_failed");
  });

  it("submits the fixed SQL to the dedicated read-only endpoint with the documented 201 contract", async () => {
    const logged = vi.spyOn(console, "info").mockImplementation(() => {});
    const calls: Array<{ path: string; init: RequestInit }> = [];
    const result = await runReadOnlyCompatibilityVerification(ref, async (path, init = {}) => {
      calls.push({ path, init });
      return Response.json([verificationRow], { status: 201 });
    });
    expect(result).toBe("passed");
    expect(calls).toHaveLength(1);
    expect(calls[0]!.path).toBe(`/v1/projects/${ref}/database/query/read-only`);
    expect(calls[0]!.init.method).toBe("POST");
    expect(new Headers(calls[0]!.init.headers).get("content-type")).toBe("application/json");
    expect(JSON.parse(String(calls[0]!.init.body))).toEqual({ query: SCHEMA_VERIFICATION_SQL });
    expect(String(calls[0]!.init.body)).not.toContain("read_only");
    expect(logged).toHaveBeenCalledWith(JSON.stringify({ event: "schema_verification_read_only_completed", project_ref: ref, status: 201, result: "passed" }));
  });

  it("requires every fixed assertion from a dedicated read-only query response", async () => {
    for (const check of Object.keys(verificationRow)) {
      const failed = { ...verificationRow, [check]: false };
      expect(await runReadOnlyCompatibilityVerification(ref, async () => Response.json([failed], { status: 201 }))).toBe("assertion_failed");
      const missing = { ...verificationRow };
      delete missing[check];
      expect(await runReadOnlyCompatibilityVerification(ref, async () => Response.json([missing], { status: 201 }))).toBe("indeterminate");
    }
  });

  it("keeps catalog and Planner entity references schema-qualified for the read-only endpoint", () => {
    expect(SCHEMA_VERIFICATION_SQL).toContain("pg_catalog.pg_proc");
    expect(SCHEMA_VERIFICATION_SQL).toContain("pg_catalog.pg_type");
    expect(SCHEMA_VERIFICATION_SQL).not.toMatch(/public\.planner_sync_capabilities\s*\(/u);
    expect(SCHEMA_VERIFICATION_SQL).not.toMatch(/pg_catalog\.(?:bigint|integer|smallint|boolean|varchar|character varying|double precision)\b/iu);
    expect(SCHEMA_VERIFICATION_SQL).not.toContain("regprocedure");
    expect(SCHEMA_VERIFICATION_SQL).toContain("'int8'");
    expect(SCHEMA_VERIFICATION_SQL).toContain("'int4'");
    expect(SCHEMA_VERIFICATION_SQL).toContain("prosrc = ");
    expect(SCHEMA_VERIFICATION_SQL).toContain("pg_catalog.pg_get_functiondef(");
    expect(SCHEMA_VERIFICATION_SQL).not.toMatch(/(?<![\w.])(?:pg_class|pg_namespace|pg_constraint|pg_get_functiondef|has_function_privilege|has_table_privilege|array_length|strpo?s|count|bool_and|regclass|regprocedure)\b/u);
  });
});

describe("browser hand-off pages", () => {
  it("offers a real app-return action without exposing any credential", () => {
    const page = managementAuthorizationCompletedPage();
    expect(page).toContain(PLANNER_MANAGEMENT_CALLBACK_URI);
    expect(page).toContain("Open Personal Planner");
    expect(page).toContain("Supabase authorization completed");
    expect(page).not.toContain("POC");
    for (const forbidden of ["access_token", "refresh_token", "sba_", "sb_secret"]) {
      expect(page).not.toContain(forbidden);
    }
    // The result hint carries no transaction identifier or credential.
    expect(page).toContain(`${PLANNER_MANAGEMENT_CALLBACK_URI}?result=completed`);
    expect(managementAuthorizationDeniedPage()).toContain(`${PLANNER_MANAGEMENT_CALLBACK_URI}?result=cancelled`);
    expect(managementAuthorizationDeniedPage()).toContain("was cancelled");
  });

  it("confirms an email with a usable app-return link and never shows the code", () => {
    const request = new Request(
      "https://worker.test/auth/confirmed?code=abc123-def456_ghi",
    );
    const page = plannerEmailConfirmationPage(request);
    expect(page.status).toBe(200);
    return page.text().then((body) => {
      expect(body).toContain("Email verified successfully");
      expect(body).toContain("return to Personal Planner and log in");
      expect(body).toContain(`${PLANNER_AUTH_CALLBACK_URI}?code=abc123-def456_ghi`);
      // The code only ever appears as the `code=` value of the app-return link
      // (the button plus the hidden automatic attempt), never as page text.
      const aroundCode = body.split("abc123-def456_ghi");
      expect(aroundCode).toHaveLength(3);
      for (const part of aroundCode.slice(0, -1)) {
        expect(part.endsWith("code=")).toBe(true);
      }
      expect(body).not.toContain("access_token");
    });
  });

  it("explains expired, already-used, and malformed confirmation links instead of blank pages", async () => {
    const expired = plannerEmailConfirmationPage(
      new Request(
        "https://worker.test/auth/confirmed?error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired",
      ),
    );
    expect(expired.status).toBe(400);
    const expiredBody = await expired.text();
    expect(expiredBody).toContain("could not be used");
    expect(expiredBody).not.toContain("Email link is invalid");

    const malformed = plannerEmailConfirmationPage(
      new Request("https://worker.test/auth/confirmed"),
    );
    expect(malformed.status).toBe(400);
    expect(await malformed.text()).toContain("incomplete");

    const injected = plannerEmailConfirmationPage(
      new Request("https://worker.test/auth/confirmed?code=%3Cscript%3E"),
    );
    expect(injected.status).toBe(400);
    const injectedBody = await injected.text();
    expect(injectedBody).not.toContain("<script>alert");
  });
});

describe("email confirmation redirect configuration", () => {
  it("derives only https Worker origins", () => {
    expect(plannerEmailConfirmationUri("https://worker.test")).toBe(
      `https://worker.test${PLANNER_EMAIL_CONFIRMATION_PATH}`,
    );
    expect(plannerEmailConfirmationUri("http://worker.test")).toBeNull();
    expect(plannerEmailConfirmationUri("not a url")).toBeNull();
  });

  it("adds the landing page next to the custom-scheme callback", () => {
    const plan = mergeAuthRedirectAllowLists(undefined, [
      PLANNER_AUTH_CALLBACK_URI,
      "https://worker.test/auth/confirmed",
    ]);
    expect(plan).toEqual({
      list: `${PLANNER_AUTH_CALLBACK_URI},https://worker.test/auth/confirmed`,
      changed: true,
    });
    expect(mergeAuthRedirectAllowLists(plan!.list, [PLANNER_AUTH_CALLBACK_URI])).toEqual({
      list: plan!.list,
      changed: false,
    });
    expect(mergeAuthRedirectAllowLists(undefined, [])).toBeNull();
  });

  it("requires every Planner redirect after patching", async () => {
    const confirmation = "https://worker.test/auth/confirmed";
    const calls: Array<{ path: string; method: string }> = [];
    let allowList = "https://planner.test/callback";
    const call = async (path: string, init?: RequestInit) => {
      calls.push({ path, method: init?.method ?? "GET" });
      if (init?.method === "PATCH") {
        const body = JSON.parse(String(init.body)) as { uri_allow_list: string };
        allowList = body.uri_allow_list;
      }
      return Response.json({ uri_allow_list: allowList });
    };
    expect(await ensureAuthRedirectConfigured(ref, call, [confirmation])).toBe(true);
    expect(calls.map((entry) => entry.method)).toEqual(["GET", "PATCH", "GET"]);
    expect(allowList.split(",")).toEqual([
      "https://planner.test/callback",
      PLANNER_AUTH_CALLBACK_URI,
      confirmation,
    ]);
  });
});

describe("management authorization lifecycle", () => {
  const checkUrl = `https://worker.test/v1/provisioning/transactions/${transactionId}/project-check`;

  function checkRequest(body: unknown, capabilityValue = "a".repeat(48)) {
    return new Request(checkUrl, {
      method: "POST",
      headers: {
        authorization: `Provisioning ${capabilityValue}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });
  }

  function checkEnvironment(worker: Record<string, unknown>, mappedRef?: string) {
    const owner = { current: async () => mappedRef ? { project_ref: mappedRef } : null, bind: async (projectRef: string) => ({ kind: "bound", projectRef }) };
    return {
      PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => worker },
      MANAGEMENT_ACCOUNT_PROJECT: { idFromName: (name: string) => name, get: () => owner },
      SUPABASE_OAUTH_CLIENT_ID: "client-id",
      SUPABASE_OAUTH_CLIENT_SECRET: "client-secret",
      SUPABASE_OAUTH_REDIRECT_URI: "https://worker.test/oauth/callback",
    };
  }

  it("reports an existing project, repairs its redirects, and releases the credential", async () => {
    let released = 0;
    const worker = {
      managementToken: async () => "management-token",
      owner: async () => "11111111-1111-4111-8111-111111111111",
      releaseManagementGrant: async () => {
        released += 1;
        return { released: true, revoked: true, unconfirmed: false };
      },
    };
    let allowList = PLANNER_AUTH_CALLBACK_URI;
    vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith(`/v1/projects/${ref}`)) return Response.json({ ref, status: "ACTIVE_HEALTHY" });
      if (url.endsWith(`/v1/projects/${ref}/database/migrations`)) return Response.json(MIGRATIONS.map(m => ({ name: m.name })));
      if (url.endsWith(`/v1/projects/${ref}/database/query/read-only`)) return Response.json([verificationRow], { status: 201 });
      if (url.endsWith(`/v1/projects/${ref}/database/query`)) return Response.json([verificationRow]);
      if (url.endsWith(`/v1/projects/${ref}/config/auth`)) {
        if (init?.method === "PATCH") {
          allowList = (JSON.parse(String(init.body)) as { uri_allow_list: string }).uri_allow_list;
        }
        return Response.json({ uri_allow_list: allowList });
      }
      return new Response(null, { status: 404 });
    });

    const response = await productionProjectCheck(
      checkRequest({ projectRef: ref }),
      checkEnvironment(worker, ref) as any,
    );

    expect(response!.status).toBe(200);
    const body = (await response!.json()) as Record<string, unknown>;
    expect(body.projectExists).toBe(true);
    expect(body.projectStatus).toBe("verified");
    expect(body.emailConfirmationRedirect).toBe(
      `https://worker.test/auth/confirmed`,
    );
    expect(body.grantReleased).toBe(true);
    expect(released).toBe(1);
    expect(JSON.stringify(body)).not.toContain("management-token");
  });

  it("keeps verification retryable when the project's Auth redirects cannot be confirmed", async () => {
    let released = 0;
    const worker = {
      managementToken: async () => "management-token",
      owner: async () => "11111111-1111-4111-8111-111111111111",
      releaseManagementGrant: async () => { released += 1; return { released: true, revoked: true, unconfirmed: false }; },
    };
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.endsWith(`/v1/projects/${ref}`)) return Response.json({ ref });
      if (url.endsWith(`/v1/projects/${ref}/database/migrations`)) return Response.json(MIGRATIONS.map(m => ({ name: m.name })));
      if (url.endsWith(`/v1/projects/${ref}/database/query/read-only`)) return Response.json([verificationRow], { status: 201 });
      if (url.endsWith(`/v1/projects/${ref}/database/query`)) return Response.json([verificationRow]);
      if (url.endsWith(`/v1/projects/${ref}/config/auth`)) return new Response(null, { status: 502 });
      return new Response(null, { status: 404 });
    });
    const response = await productionProjectCheck(checkRequest({ projectRef: ref }), checkEnvironment(worker, ref) as any);
    const body = await response!.json() as Record<string, unknown>;
    expect(body.projectExists).toBeNull();
    expect(body.projectStatus).toBe("indeterminate");
    expect(body.emailConfirmationRedirect).toBeNull();
    expect(released).toBe(1);
  });

  it("reports a deleted project as missing and still releases the credential", async () => {
    let released = 0;
    const calls: string[] = [];
    const worker = {
      managementToken: async () => "management-token",
      owner: async () => "11111111-1111-4111-8111-111111111111",
      releaseManagementGrant: async () => {
        released += 1;
        return { released: true, revoked: true, unconfirmed: false };
      },
    };
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
      calls.push(String(input));
      return new Response(JSON.stringify({ message: "Project not found" }), { status: 404 });
    });

    const response = await productionProjectCheck(
      checkRequest({ projectRef: ref }),
      checkEnvironment(worker, ref) as any,
    );

    const body = (await response!.json()) as Record<string, unknown>;
    expect(body.projectExists).toBe(false);
    expect(body.projectStatus).toBe("missing");
    expect(body.emailConfirmationRedirect).toBeNull();
    expect(released).toBe(1);
    // No redirect repair is attempted for a project that does not exist.
    expect(calls).toEqual([`https://api.supabase.com/v1/projects/${ref}`]);
  });

  it("checks the exact local project without consulting a stored account mapping", async () => {
    const worker = {
      managementToken: async () => "temporary-token",
      releaseManagementGrant: async () => ({ released: true, revoked: false, unconfirmed: false }),
    };
    const calls: string[] = [];
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => { calls.push(String(input)); return new Response(null, { status: 404 }); });
    const response = await productionProjectCheck(checkRequest({ projectRef: Y }), checkEnvironment(worker, ref) as any);
    expect(response!.status).toBe(200);
    expect(await response!.json()).toMatchObject({ projectExists: false, projectStatus: "missing" });
    expect(calls).toEqual([`https://api.supabase.com/v1/projects/${Y}`]);
  });

  it("never reports deletion for transport, outage, or authorization failures", async () => {
    const worker = {
      managementToken: async () => "management-token",
      owner: async () => "11111111-1111-4111-8111-111111111111",
      releaseManagementGrant: async () => ({ released: true, revoked: false, unconfirmed: true }),
    };
    const cases: Array<[() => Promise<Response>, string]> = [
      [async () => new Response(null, { status: 500 }), "indeterminate"],
      [async () => new Response(null, { status: 502 }), "indeterminate"],
      [async () => new Response(null, { status: 429 }), "indeterminate"],
      [async () => new Response(null, { status: 403 }), "not_authorized"],
      [
        async () => {
          throw new Error("network down");
        },
        "indeterminate",
      ],
    ];
    for (const [handler, expected] of cases) {
      vi.stubGlobal("fetch", handler);
      const response = await productionProjectCheck(
        checkRequest({ projectRef: ref }),
        checkEnvironment(worker) as any,
      );
      const body = (await response!.json()) as Record<string, unknown>;
      expect(body.projectExists).toBeNull();
      expect(body.projectStatus).toBe("indeterminate");
      expect(body.emailConfirmationRedirect).toBeNull();
    }
  });

  it("requires a capability, a project ref, and POST", async () => {
    const worker = { managementToken: async () => "management-token" };
    const missingCapability = await productionProjectCheck(
      new Request(checkUrl, { method: "POST", body: JSON.stringify({ projectRef: ref }) }),
      checkEnvironment(worker) as any,
    );
    expect(missingCapability!.status).toBe(401);

    const badRef = await productionProjectCheck(
      checkRequest({ projectRef: "not-a-ref" }),
      checkEnvironment(worker) as any,
    );
    expect(badRef!.status).toBe(400);

    const wrongMethod = await productionProjectCheck(
      new Request(checkUrl, { headers: { authorization: `Provisioning ${"a".repeat(48)}` } }),
      checkEnvironment(worker) as any,
    );
    expect(wrongMethod!.status).toBe(405);

    const unauthorized = await productionProjectCheck(
      checkRequest({ projectRef: ref }),
      checkEnvironment({
        managementToken: async () => {
          throw new Error("forbidden");
        },
      }) as any,
    );
    expect(unauthorized!.status).toBe(401);
  });

  const authorizationUrl = `https://worker.test/v1/provisioning/transactions/${transactionId}/authorization`;
  const capability = "a".repeat(48);

  function environment(worker: Record<string, unknown>) {
    return {
      PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => worker },
      SUPABASE_OAUTH_CLIENT_ID: "client-id",
      SUPABASE_OAUTH_CLIENT_SECRET: "client-secret",
      SUPABASE_OAUTH_REDIRECT_URI: "https://worker.test/oauth/callback",
    };
  }

  function request(path: string, method: string, provided = capability) {
    return new Request(`${authorizationUrl}${path}`, {
      method,
      headers: { authorization: `Provisioning ${provided}` },
    });
  }

  it("reports the retained grant status without leaking any credential", async () => {
    const worker = {
      managementAuthorizationStatus: async () => ({
        authorized: false,
        pending: false,
        revokedAt: Date.now(),
        authorizationExpiresAt: Date.now() + MANAGEMENT_WINDOW_MS,
        releaseUnconfirmed: false,
        emailConfirmationRedirect: null,
      }),
    };
    const response = await productionManagementAuthorization(
      request("", "GET"),
      environment(worker) as any,
    );
    expect(response!.status).toBe(200);
    const body = (await response!.json()) as Record<string, unknown>;
    expect(body.authorized).toBe(false);
    expect(body.releaseUnconfirmed).toBe(false);
    expect(Object.keys(body).sort()).toEqual([
      "authorizationExpiresAt",
      "authorized",
      "emailConfirmationRedirect",
      "pending",
      "releaseUnconfirmed",
      "revokedAt",
    ]);
    expect(JSON.stringify(body)).not.toContain(capability);
    expect(JSON.stringify(body)).not.toContain("refresh");
  });

  it("requires the provisioning capability and rejects other methods", async () => {
    const worker = {
      managementAuthorizationStatus: async (provided: string) => {
        if (provided !== capability) throw new Error("forbidden");
        return { authorized: false };
      },
    };
    const unauthorized = await productionManagementAuthorization(
      request("", "GET", "not-the-capability"),
      environment(worker) as any,
    );
    expect(unauthorized!.status).toBe(401);
    expect(await unauthorized!.json()).toEqual({ error: "invalid_request" });
    const wrongMethod = await productionManagementAuthorization(
      request("", "DELETE"),
      environment(worker) as any,
    );
    expect(wrongMethod!.status).toBe(405);
    expect(await productionManagementAuthorization(
      new Request("https://worker.test/v1/provisioning/transactions/x/authorization"),
      environment(worker) as any,
    )).toBeNull();
  });

  it("starts a re-authorization that binds the new state to this installation", async () => {
    let alarmAt = 0;
    const worker = {
      beginManagementAuthorization: async () => {
        alarmAt = Date.now() + MANAGEMENT_WINDOW_MS;
        return { state: "new-state-secret", verifier: "new-verifier-secret", expiresIn: 1000 };
      },
    };
    const response = await productionManagementAuthorization(
      request("/start", "POST"),
      environment(worker) as any,
    );
    expect(response!.status).toBe(200);
    const body = (await response!.json()) as { authorizationUrl: string; expiresIn: number };
    const parsed = new URL(body.authorizationUrl);
    expect(parsed.origin + parsed.pathname).toBe("https://api.supabase.com/v1/oauth/authorize");
    expect(parsed.searchParams.get("client_id")).toBe("client-id");
    expect(parsed.searchParams.get("state")).toBe(`${transactionId}.new-state-secret`);
    expect(parsed.searchParams.get("code_challenge_method")).toBe("S256");
    expect(parsed.searchParams.get("code_challenge")).not.toContain("new-verifier-secret");
    expect(body.expiresIn).toBe(1000);
    expect(alarmAt).toBeGreaterThan(Date.now());
  });

  it("revokes through Supabase and never returns the refresh token", async () => {
    const seen: Array<Record<string, unknown>> = [];
    const worker = {
      takeManagementRefresh: async () => "oauth_refresh_token_value",
      markManagementRevoked: async () => undefined,
    };
    vi.stubGlobal("fetch", async (_input: RequestInfo | URL, init?: RequestInit) => {
      seen.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
      return new Response(null, { status: 204 });
    });
    const response = await productionManagementAuthorization(
      request("/revoke", "POST"),
      environment(worker) as any,
    );
    expect(response!.status).toBe(200);
    expect(await response!.json()).toEqual({ revoked: true, reason: "revoked" });
    expect(seen).toEqual([{
      client_id: "client-id",
      client_secret: "client-secret",
      refresh_token: "oauth_refresh_token_value",
    }]);
  });

  it("keeps the grant and reports failure when Supabase refuses the revocation", async () => {
    let cleared = false;
    const worker = {
      takeManagementRefresh: async () => "oauth_refresh_token_value",
      markManagementRevoked: async () => {
        cleared = true;
      },
    };
    vi.stubGlobal("fetch", async () => new Response(null, { status: 500 }));
    const response = await productionManagementAuthorization(
      request("/revoke", "POST"),
      environment(worker) as any,
    );
    expect(response!.status).toBe(502);
    expect(await response!.json()).toEqual({ error: "revocation_failed" });
    expect(cleared).toBe(false);
  });

  it("reports a truthful limitation when no refresh token is retained", async () => {
    const worker = { takeManagementRefresh: async () => null };
    const response = await productionManagementAuthorization(
      request("/revoke", "POST"),
      environment(worker) as any,
    );
    expect(response!.status).toBe(200);
    expect(await response!.json()).toEqual({ revoked: false, reason: "not_retained" });
  });
});

describe("management grant durability", () => {
  const access = "a".repeat(48);

  it("holds a sealed Management credential only for the provisioning attempt", async () => {
    const { tx, read } = durableTransaction();
    await tx.create(access, "s".repeat(48), "v".repeat(48));
    await tx.oauthCallback("s".repeat(48));
    await tx.saveOAuthFromCallback(
      "s".repeat(48),
      "management-token",
      "oauth_refresh_token_value",
      Date.now() + 600_000,
    );
    const granted = read()!;
    expect(granted.refreshCipher).toBeTypeOf("string");
    expect(granted.refreshCipher).not.toContain("oauth_refresh_token_value");
    expect(granted.grantExpiresAt).toBeGreaterThan(Date.now());
    expect(await tx.takeManagementRefresh(access)).toBe("oauth_refresh_token_value");

    // Transaction expiry is the least-privilege backstop: nothing Management
    // related outlives the provisioning attempt it belongs to.
    (tx as any).expire(read()!);
    expect(read()!.state).toBe("expired");
    expect(read()!.tokenCiphertext).toBeUndefined();
    expect(read()!.refreshCipher).toBeUndefined();
    expect(await tx.takeManagementRefresh(access)).toBeNull();
  });

  it("stops accepting a Management credential once its window passed", async () => {
    const { tx, read } = durableTransaction();
    await tx.create(access, "s".repeat(48), "v".repeat(48));
    await tx.oauthCallback("s".repeat(48));
    await tx.saveOAuthFromCallback(
      "s".repeat(48),
      "management-token",
      "oauth_refresh_token_value",
      Date.now() + 600_000,
    );
    const granted = read()!;
    (tx as any).save({ ...granted, grantExpiresAt: Date.now() - 1 });
    expect(await tx.takeManagementRefresh(access)).toBeNull();
  });

  it("accepts a management re-authorization only through its own single-use state", async () => {
    const { tx, read } = await transactionAtVerifying();
    const grant = await tx.beginManagementAuthorization(access);
    expect(grant.state).toHaveLength(43);
    expect(read()!.oauthPurpose).toBe("management");
    expect(read()!.state).toBe("verifying");

    // A provisioning claim cannot consume the management state, and a spent
    // state cannot be replayed.
    const claim = await tx.oauthCallback(grant.state);
    expect(claim).toEqual({ verifier: grant.verifier, management: true });
    expect(await tx.oauthCallback(grant.state)).toBeNull();

    await tx.saveOAuthFromCallback(
      grant.state,
      "second-access-token",
      "second-refresh-token",
      Date.now() + 600_000,
    );
    const updated = read()!;
    expect(updated.oauthPurpose).toBeUndefined();
    expect(updated.oauthStateHash).toBeUndefined();
    expect(updated.projectRef).toBe(ref);
    expect(updated.state).toBe("verifying");
    // The project check still needs this short-lived credential. The check
    // releases it once ownership and redirects have been verified.
    expect(updated.refreshCipher).toBeDefined();
    expect(await tx.takeManagementRefresh(access)).toBe("second-refresh-token");
  });

  it("refuses a management re-authorization for a record with no project", async () => {
    const { tx } = durableTransaction();
    await tx.create(access, "s".repeat(48), "v".repeat(48));
    await expect(tx.beginManagementAuthorization(access)).rejects.toThrow("invalid_request");
  });

  it("revokes the Management grant and destroys it as soon as provisioning is ready", async () => {
    const revoked: Array<Record<string, unknown>> = [];
    let bodies: string[] = [];
    const sql = {
      exec(query: string, ...values: unknown[]) {
        if (query.startsWith("SELECT")) return { toArray: () => (bodies.length ? [{ body: bodies[bodies.length - 1]! }] : []) };
        if (query.startsWith("INSERT")) bodies.push(String(values[0]));
        return { toArray: () => [] };
      },
    };
    const ctx = {
      storage: { sql, setAlarm: async () => undefined },
      blockConcurrencyWhile: (operation: () => Promise<unknown>) => operation(),
    };
    const tx = new ProvisioningTransaction(ctx as any, {
      OAUTH_SESSION_KEY: "test-session-key",
      SUPABASE_OAUTH_CLIENT_ID: "client-id",
      SUPABASE_OAUTH_CLIENT_SECRET: "client-secret",
    } as any);
    vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
      expect(String(input)).toBe("https://api.supabase.com/v1/oauth/revoke");
      revoked.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
      return new Response(null, { status: 204 });
    });

    await tx.create(access, "s".repeat(48), "v".repeat(48));
    await tx.oauthCallback("s".repeat(48));
    await tx.saveOAuthFromCallback(
      "s".repeat(48),
      "management-token",
      "oauth_refresh_token_value",
      Date.now() + 600_000,
    );
    await tx.recordDiscovery(access, []);
    await tx.selectOrganization(access, "owner-org", "personal-planner-safe-project", "k".repeat(32));
    const create = await tx.reserveCreate(access);
    await tx.recordProject(access, create.nonce, ref);
    const migration = await tx.claimOperation(access, "migration");
    await tx.finishMigration(access, migration.nonce, { kind: "complete" });
    const verification = await tx.claimOperation(access, "verification");

    const snapshot = await tx.finishVerification(
      access,
      verification.nonce,
      "passed",
      runtimeConfig,
    ) as Record<string, unknown>;

    expect(snapshot.state).toBe("ready");
    expect(revoked).toEqual([{
      client_id: "client-id",
      client_secret: "client-secret",
      refresh_token: "oauth_refresh_token_value",
    }]);
    const record = JSON.parse(bodies[bodies.length - 1]!) as Record<string, unknown>;
    expect(record.refreshCipher).toBeUndefined();
    expect(record.tokenCiphertext).toBeUndefined();
    expect(record.oauthRevokedAt).toBeTypeOf("number");
    expect(record.oauthReleaseUnconfirmed).toBeUndefined();
    const status = await tx.managementAuthorizationStatus(access) as Record<string, unknown>;
    expect(status.authorized).toBe(false);
    expect(status.releaseUnconfirmed).toBe(false);
  });

  it("reports an unconfirmed revocation when Supabase cannot be reached", async () => {
    let bodies: string[] = [];
    const sql = {
      exec(query: string, ...values: unknown[]) {
        if (query.startsWith("SELECT")) return { toArray: () => (bodies.length ? [{ body: bodies[bodies.length - 1]! }] : []) };
        if (query.startsWith("INSERT")) bodies.push(String(values[0]));
        return { toArray: () => [] };
      },
    };
    const ctx = {
      storage: { sql, setAlarm: async () => undefined },
      blockConcurrencyWhile: (operation: () => Promise<unknown>) => operation(),
    };
    const tx = new ProvisioningTransaction(ctx as any, {
      OAUTH_SESSION_KEY: "test-session-key",
      SUPABASE_OAUTH_CLIENT_ID: "client-id",
      SUPABASE_OAUTH_CLIENT_SECRET: "client-secret",
    } as any);
    vi.stubGlobal("fetch", async () => {
      throw new Error("network down");
    });
    await tx.create(access, "s".repeat(48), "v".repeat(48));
    await tx.oauthCallback("s".repeat(48));
    await tx.saveOAuthFromCallback(
      "s".repeat(48),
      "management-token",
      "oauth_refresh_token_value",
      Date.now() + 600_000,
    );
    await tx.recordDiscovery(access, []);
    await tx.selectOrganization(access, "owner-org", "personal-planner-safe-project", "k".repeat(32));
    const create = await tx.reserveCreate(access);
    await tx.recordProject(access, create.nonce, ref);
    const migration = await tx.claimOperation(access, "migration");
    await tx.finishMigration(access, migration.nonce, { kind: "complete" });
    const verification = await tx.claimOperation(access, "verification");

    await tx.finishVerification(access, verification.nonce, "passed", runtimeConfig);

    const record = JSON.parse(bodies[bodies.length - 1]!) as Record<string, unknown>;
    // The credential is destroyed even though the revocation could not be
    // confirmed, so the app can tell the user the truth instead of pretending.
    expect(record.refreshCipher).toBeUndefined();
    expect(record.oauthReleaseUnconfirmed).toBe(true);
    const status = await tx.managementAuthorizationStatus(access) as Record<string, unknown>;
    expect(status.authorized).toBe(false);
    expect(status.releaseUnconfirmed).toBe(true);
  });

  it("defers redirect repair until the exact project check", async () => {
    const { tx, read } = await transactionAtVerifying();
    let allowList = `https://planner.test/callback,${PLANNER_AUTH_CALLBACK_URI}`;
    const writes: string[] = [];
    vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (!url.endsWith(`/v1/projects/${ref}/config/auth`)) {
        return new Response(null, { status: 404 });
      }
      if (init?.method === "PATCH") {
        const body = JSON.parse(String(init.body)) as { uri_allow_list: string };
        allowList = body.uri_allow_list;
        writes.push(allowList);
      }
      return Response.json({ uri_allow_list: allowList });
    });
    const confirmation = "https://worker.test/auth/confirmed";

    const grant = await tx.beginManagementAuthorization(access);
    await tx.oauthCallback(grant.state);
    await tx.saveOAuthFromCallback(
      grant.state,
      "second-access-token",
      "second-refresh-token",
      Date.now() + 600_000,
      confirmation,
    );

    expect(writes).toEqual([]);
    expect(read()!.emailRedirectConfigured).toBeUndefined();
    const status = await tx.managementAuthorizationStatus(access) as Record<string, unknown>;
    expect(status.emailConfirmationRedirect).toBeNull();
    expect(status.authorized).toBe(true);
    expect(read()!.refreshCipher).toBeDefined();
    expect(JSON.stringify(status)).not.toContain("second-refresh-token");
  });

  it("never claims a repaired redirect when Management refuses the update", async () => {
    const { tx, read } = await transactionAtVerifying();
    vi.stubGlobal("fetch", async () => new Response(null, { status: 403 }));
    const grant = await tx.beginManagementAuthorization(access);
    await tx.oauthCallback(grant.state);

    await tx.saveOAuthFromCallback(
      grant.state,
      "second-access-token",
      "second-refresh-token",
      Date.now() + 600_000,
      "https://worker.test/auth/confirmed",
    );

    // The callback does not touch the local project before ownership is checked.
    expect(read()!.emailRedirectConfigured).toBeUndefined();
    expect(read()!.refreshCipher).toBeDefined();
    const status = await tx.managementAuthorizationStatus(access) as Record<string, unknown>;
    expect(status.authorized).toBe(true);
    expect(status.emailConfirmationRedirect).toBeNull();
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
  await tx.saveOAuthFromCallback(oauthState, "management-token", "refresh-token-value", Date.now() + 600_000);
  await tx.recordDiscovery(access, []);
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
    // The route now reads the transaction state before verifying (a repeated
    // verification of a READY transaction must return the same ready snapshot
    // rather than an error), so this fake tracks the state its own
    // finishVerification call produced.
    let state = "verifying";
    return {
      managementToken: async (capability: string) =>
        capability === "capability-1" ? "management-token" : null,
      createContext: async () => ({ state: "authorization_pending", projectRef: ref, discoveryEmptyAt: Date.now() }),
      owner: async () => "11111111-1111-4111-8111-111111111111",
      claimOperation: async () => ({ nonce: "op-nonce", projectRef: ref }),
      finishVerification: async (_a: string, _n: string, result: string, config?: unknown) => {
        state = result === "passed" ? "ready" : result === "assertion_failed" ? "terminal_error" : "verifying";
        return { state, runtimeConfig: config ?? null };
      },
      get: async () => ({ state, runtimeConfig: state === "ready" ? runtimeConfig : null }),
      create: async () => ({}),
      ...overrides,
    };
  }

  function environment(worker: Record<string, unknown>) {
    const owner = { current: async () => null };
    return {
      PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => worker },
      MANAGEMENT_ACCOUNT_PROJECT: { idFromName: (name: string) => name, get: () => owner },
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

  it("answers a repeated verify with the ready snapshot instead of an error", async () => {
    // READY now also releases the Management grant, so a client that retries
    // verification (for example after its own timeout) must still be able to
    // read the same ready configuration.
    const response = await productionFetch(
      postRequest(verifyUrl),
      environment(
        fakeTransaction({ get: async () => ({ state: "ready", runtimeConfig }) }),
      ) as any,
    );

    expect(response!.status).toBe(200);
    expect((await response!.json() as { state: string }).state).toBe("ready");
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
    const authConfigWrites: unknown[] = [];
    let allowList = "";
    vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      requested.push(url);
      if (url.endsWith("/config/auth")) {
        if (init?.method === "PATCH") {
          const body = JSON.parse(String(init.body)) as { uri_allow_list: string };
          authConfigWrites.push(body);
          allowList = body.uri_allow_list;
        }
        return Response.json({ uri_allow_list: allowList });
      }
      if (url.endsWith("/database/query/read-only")) return Response.json([verificationRow], { status: 201 });
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
    expect(body.runtimeConfig).toEqual({
      ...runtimeConfig,
      emailConfirmationRedirect:
        `https://worker.test${PLANNER_EMAIL_CONFIRMATION_PATH}`,
    });
    expect(JSON.stringify(body)).not.toContain("management-token");
    // The new project's Auth config now allows the canonical app callback and
    // the Worker's confirmation landing page, and nothing else was dropped
    // because the list started empty.
    expect(authConfigWrites).toEqual([
      {
        uri_allow_list:
          `${PLANNER_AUTH_CALLBACK_URI},https://worker.test${PLANNER_EMAIL_CONFIRMATION_PATH}`,
      },
    ]);
    expect(requested).toContain(`https://api.supabase.com/v1/projects/${ref}/api-keys/pub-1?reveal=true`);
    expect(requested).toContain(`https://api.supabase.com/v1/projects/${ref}/database/query/read-only`);
    expect(requested).not.toContain(`https://api.supabase.com/v1/projects/${ref}/database/query`);
  });

  it("stays retryable, and never reports ready, when the publishable key cannot be read", async () => {
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.endsWith("/config/auth")) {
        return Response.json({ uri_allow_list: PLANNER_AUTH_CALLBACK_URI });
      }
      if (url.endsWith("/database/query/read-only")) return Response.json([verificationRow], { status: 201 });
      if (url.endsWith("/api-keys")) return new Response(null, { status: 500 });
      return new Response(null, { status: 404 });
    });

    const response = await productionFetch(postRequest(verifyUrl), environment(fakeTransaction()) as any);
    expect(response!.status).toBe(202);

    const body = await response!.json() as { state: string; runtimeConfig: unknown };
    expect(body.state).toBe("verifying");
    expect(body.runtimeConfig).toBeNull();
  });

  it("stays retryable, and never reports ready, when the Auth redirect allow list cannot be applied", async () => {
    const requested: string[] = [];
    vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      requested.push(url);
      if (url.endsWith("/config/auth")) {
        if (init?.method === "PATCH") return new Response(null, { status: 403 });
        return Response.json({ uri_allow_list: "" });
      }
      if (url.endsWith("/database/query/read-only")) return Response.json([verificationRow], { status: 201 });
      return new Response(null, { status: 404 });
    });

    const response = await productionFetch(postRequest(verifyUrl), environment(fakeTransaction()) as any);
    expect(response!.status).toBe(202);

    const body = await response!.json() as { state: string; runtimeConfig: unknown };
    expect(body.state).toBe("verifying");
    expect(body.runtimeConfig).toBeNull();
    // The publishable key must never be published for a backend whose
    // confirmation email cannot return to the app.
    expect(requested.some((url) => url.endsWith("/api-keys"))).toBe(false);
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
    it("accepts the real hosted shape: exact canonical name with an unrelated version", async () => {
      // Confirmed on a real hosted project after applying canonical migration 1:
      //   name    = 20260827000000_sync_v1
      //   version = 20260917132417
      // The separate `version` column is not that migration's timestamp prefix,
      // so the exact canonical name alone must identify the migration.
      const api = advancingMigrationApi([
        { name: canonicalOne, version: "20260917132417" },
      ]);

      expect(await runCanonicalMigrations(ref, api.call)).toEqual({ kind: "complete" });
      expect(api.posts).toHaveLength(5);
      expect(api.posts[0]).toBe(canonicalTwo);
    });

    it("accepts a canonical full name whose version agrees with it", async () => {
      const api = advancingMigrationApi([{ name: canonicalOne, version: "20260827000000" }]);

      expect(await runCanonicalMigrations(ref, api.call)).toEqual({ kind: "complete" });
      expect(api.posts).toHaveLength(5);
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
      // The hosted shape: the exact full name wins even though `version` is a
      // different value entirely.
      expect(reconcileMigrations(canonical, [{ name: canonicalOne, version: "20260917132417" }])).toEqual({ next: 1 });
    });

    it("rejects a row whose supported interpretations point at different canonical migrations", () => {
      // Synthetic bundle: the full name identifies one migration while the
      // version-plus-name pair would identify a different one.
      const canonical = [
        { name: "1_alpha", query: "", sha256: "a" },
        { name: "2_1_alpha", query: "", sha256: "b" },
      ];
      expect(reconcileMigrations(canonical, [{ name: "1_alpha", version: "2" }])).toEqual({ next: 0, error: "migration_history_mismatch" });
    });
  });

  describe("canonical prefix and duplicate regression", () => {
    it("rejects canonical 1 followed by canonical 3 because migration 2 is missing", async () => {
      const api = migrationApi([{ name: canonicalOne }, { name: canonicalThree }]);

      expect(await runCanonicalMigrations(ref, api.call)).toEqual({ kind: "failed", code: "migration_history_mismatch" });
      expect(api.posts).toEqual([]);
    });

    it("still rejects an out-of-order canonical row that carries an unrelated version", async () => {
      // Relaxing the version-mismatch rule must not weaken prefix ordering:
      // canonical 3 is still not allowed to follow canonical 1 directly.
      const api = migrationApi([
        { name: canonicalOne, version: "20260917132417" },
        { name: canonicalThree, version: "20260917132417" },
      ]);

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

      // A repeat is still a duplicate when the repeated row carries an
      // unrelated version.
      expect(
        reconcileMigrations(canonical, [
          { name: "1_one", version: "20260917132417" },
          { name: "0_foreign" },
          { name: "1_one" },
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

describe("project Auth redirect configuration", () => {
  it("pins the canonical Planner callback URI", () => {
    expect(PLANNER_AUTH_CALLBACK_URI).toBe(
      "com.personalplanner.personalplanner://login-callback",
    );
  });

  it("merges the callback without dropping or duplicating entries", () => {
    expect(mergeAuthRedirectAllowList(undefined, PLANNER_AUTH_CALLBACK_URI)).toEqual({
      list: PLANNER_AUTH_CALLBACK_URI,
      changed: true,
    });
    expect(
      mergeAuthRedirectAllowList("https://planner.test/callback", PLANNER_AUTH_CALLBACK_URI),
    ).toEqual({
      list: `https://planner.test/callback,${PLANNER_AUTH_CALLBACK_URI}`,
      changed: true,
    });
    expect(
      mergeAuthRedirectAllowList(
        `https://planner.test/callback, ${PLANNER_AUTH_CALLBACK_URI}`,
        PLANNER_AUTH_CALLBACK_URI,
      ),
    ).toEqual({
      list: `https://planner.test/callback,${PLANNER_AUTH_CALLBACK_URI}`,
      changed: false,
    });
  });

  it("refuses input it cannot safely rewrite", () => {
    for (const value of [
      42,
      ["https://planner.test/callback"],
      "https://planner.test/callback,not a redirect",
      "x".repeat(257),
    ]) {
      expect(mergeAuthRedirectAllowList(value, PLANNER_AUTH_CALLBACK_URI)).toBeNull();
    }
    const full = Array.from({ length: 32 }, (_, index) => `https://planner.test/${index}`).join(",");
    expect(mergeAuthRedirectAllowList(full, PLANNER_AUTH_CALLBACK_URI)).toBeNull();
  });

  it("patches the merged allow list and confirms it through Management", async () => {
    const calls: Array<{ method: string; body?: string }> = [];
    let allowList = "https://planner.test/callback";
    const call = async (_path: string, init?: RequestInit) => {
      calls.push({ method: init?.method ?? "GET", body: init?.body as string | undefined });
      if (init?.method === "PATCH") {
        const body = JSON.parse(String(init.body)) as { uri_allow_list: string };
        allowList = body.uri_allow_list;
      }
      return Response.json({ uri_allow_list: allowList });
    };

    expect(await ensureAuthRedirectConfigured(ref, call)).toBe(true);
    expect(calls.filter((entry) => entry.method === "PATCH")).toHaveLength(1);
    expect(JSON.parse(calls.find((entry) => entry.method === "PATCH")!.body!)).toEqual({
      uri_allow_list: `https://planner.test/callback,${PLANNER_AUTH_CALLBACK_URI}`,
    });
    expect(allowList).toContain(PLANNER_AUTH_CALLBACK_URI);
    expect(allowList).toContain("https://planner.test/callback");
  });

  it("is idempotent when the callback is already allowed", async () => {
    const methods: string[] = [];
    const call = async (_path: string, init?: RequestInit) => {
      methods.push(init?.method ?? "GET");
      return Response.json({
        uri_allow_list: `https://planner.test/callback,${PLANNER_AUTH_CALLBACK_URI}`,
      });
    };

    expect(await ensureAuthRedirectConfigured(ref, call)).toBe(true);
    expect(methods).toEqual(["GET", "GET"]);
  });

  it("returns false instead of guessing when Management cannot be trusted", async () => {
    const refused = async () => new Response(null, { status: 403 });
    expect(await ensureAuthRedirectConfigured(ref, refused)).toBe(false);

    const missing = async () => Response.json({});
    expect(await ensureAuthRedirectConfigured(ref, missing)).toBe(false);

    const unusable = async () => Response.json({ uri_allow_list: "not a redirect" });
    expect(await ensureAuthRedirectConfigured(ref, unusable)).toBe(false);

    expect(await ensureAuthRedirectConfigured("not-a-project-ref", refused)).toBe(false);
  });

  it("never returns the allow list or a Management token to the caller", async () => {
    const call = async () =>
      Response.json({
        uri_allow_list: PLANNER_AUTH_CALLBACK_URI,
        access_token: "management-token",
      });

    const result = await ensureAuthRedirectConfigured(ref, call);

    expect(result).toBe(true);
    expect(JSON.stringify(result)).not.toContain("management-token");
  });
});

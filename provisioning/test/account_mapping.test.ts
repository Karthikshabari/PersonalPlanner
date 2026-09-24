import { afterEach, describe, expect, it, vi } from "vitest";
import { MIGRATIONS } from "../src/migrations";
import { ManagementAccountProject } from "../src/management_account_project";
import { discoverPlannerCandidates, productionFetch, productionProjectCheck, productionProjectResolution } from "../src/production";

const X = "abcdefghijklmnopqrst";
const Y = "bcdefghijklmnopqrstu";
const OTHER = "cdefghijklmnopqrstuv";
const TX = "0123456789abcdef0123456789abcdef";
const SUBJECT = "11111111-1111-4111-8111-111111111111";
const KEY = "sb_publishable_CuLX_Y3xWuD0cuItKbm-Xw_NJMQ84zu";
const CHECKS = Object.fromEntries([
  "required_tables_exist", "rls_enabled", "required_rpcs_exist",
  "protocol_v2_authenticated_execute", "capability_grants_correct",
  "f03_helper_private", "f03_validates_branch_before_union", "f03_wrappers_active",
  "recurrence_provenance_present", "relationships_owner_scoped",
  "direct_authenticated_writes_revoked", "capability_payload_current",
].map(key => [key, true]));

function accountObject() {
  let row: { project_ref: string | null; transaction_id: string | null; organization_slug: string | null; project_name: string | null } | null = null;
  const sql = { exec(query: string, ...values: unknown[]) {
    if (query.startsWith("SELECT")) return { toArray: () => row ? [row] : [] };
    if (query.startsWith("INSERT")) {
      if (query.includes("organization_slug, project_name) VALUES")) {
        row = { project_ref: null, transaction_id: String(values[0]), organization_slug: String(values[1]), project_name: String(values[2]) };
      } else {
        row = { project_ref: String(values[0]), transaction_id: String(values[1]), organization_slug: null, project_name: null };
      }
    }
    if (query.startsWith("DELETE") && row?.project_ref === values[0]) row = null;
    return { toArray: () => [] };
  } };
  const ctx = { storage: { sql }, blockConcurrencyWhile: (operation: () => Promise<unknown>) => operation() };
  return new ManagementAccountProject(ctx as any, {} as any);
}

function transaction(overrides: Record<string, unknown> = {}) {
  let state = "authorization_pending";
  let discoveryEmpty = false;
  return {
    owner: async () => SUBJECT,
    managementToken: async () => "temporary-management-token",
    get: async () => ({ state, projectRef: null }),
    markDiscoveryEmpty: async () => { discoveryEmpty = true; },
    createContext: async () => ({ state, projectRef: null, organizationSlug: "owner-org", requestedProjectName: "personal-planner-new", discoveryEmptyAt: discoveryEmpty ? Date.now() : undefined }),
    adoptReady: async (_capability: string, config: Record<string, unknown>) => { state = "ready"; return { state, projectRef: config.projectRef, runtimeConfig: config }; },
    reserveCreate: async () => { state = "project_creating"; return { nonce: "nonce", organizationSlug: "owner-org", requestedProjectName: "personal-planner-new" }; },
    recordProject: async (_capability: string, _nonce: string, projectRef: string) => { state = "project_waiting"; return { state, projectRef }; },
    ...overrides,
  };
}

function environment(account: ManagementAccountProject, tx = transaction()) {
  return {
    MANAGEMENT_ACCOUNT_PROJECT: { idFromName: (name: string) => name, get: () => account },
    PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => tx },
  } as any;
}

function request(action: "resolve" | "adopt" | "replace-deleted", projectRef?: string) {
  return new Request(`https://worker.test/v1/provisioning/transactions/${TX}/${action}`, {
    method: "POST",
    headers: { authorization: "Provisioning capability", "content-type": "application/json" },
    body: JSON.stringify(projectRef ? { projectRef } : {}),
  });
}

function managementResponses(projects: Array<{ ref: string; name: string; compatible: boolean }>, options: { unavailable?: string; deleted?: string; partial?: string } = {}) {
  const calls: Array<{ url: string; method: string; body?: string }> = [];
  vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input), method = init?.method ?? "GET";
    calls.push({ url, method, body: typeof init?.body === "string" ? init.body : undefined });
    if (options.unavailable && url.endsWith(options.unavailable)) return new Response(null, { status: 502 });
    if (url.endsWith("/v1/projects") && method === "GET") return Response.json(projects.map(({ ref, name }) => ({ ref, name, region: "ap-south-1" })));
    if (url.endsWith("/v1/projects") && method === "POST") return Response.json({ ref: X });
    const project = projects.find(p => url.includes(`/v1/projects/${p.ref}`));
    if (!project || options.deleted === project.ref) return new Response(null, { status: 404 });
    if (url.endsWith(`/v1/projects/${project.ref}`)) return Response.json({ ref: project.ref, status: "ACTIVE_HEALTHY" });
    if (url.endsWith("/database/migrations")) return Response.json(options.partial === project.ref ? [{ name: MIGRATIONS[0]!.name }] : project.compatible ? MIGRATIONS.map(m => ({ name: m.name })) : []);
    if (url.endsWith("/database/query")) return Response.json([CHECKS]);
    if (url.endsWith("/config/auth")) return Response.json({ uri_allow_list: "com.personalplanner.personalplanner://login-callback,https://worker.test/auth/confirmed" });
    if (url.endsWith("/api-keys")) return Response.json([{ type: "publishable", id: "safe-key" }]);
    if (url.endsWith("/api-keys/safe-key?reveal=true")) return Response.json({ type: "publishable", api_key: KEY });
    return new Response(null, { status: 404 });
  });
  return calls;
}

afterEach(() => vi.unstubAllGlobals());

describe("verified Management account ownership", () => {
  it("finds zero compatible projects and permits first creation only after the full read-only search", async () => {
    const owner = accountObject(), tx = transaction();
    const calls = managementResponses([{ ref: OTHER, name: "planner-fake", compatible: false }]);
    const resolved = await productionProjectResolution(request("resolve"), environment(owner, tx));
    expect(await resolved!.json()).toEqual({ kind: "candidates", candidates: [] });
    expect(calls.every(call => call.method === "GET")).toBe(true);
    const created = await productionFetch(new Request(`https://worker.test/v1/provisioning/transactions/${TX}/create`, { method: "POST", headers: { authorization: "Provisioning capability", "content-type": "application/json" }, body: "{}" }), environment(owner, { ...tx, createContext: async () => ({ state: "organization_selected", projectRef: null, organizationSlug: "owner-org", requestedProjectName: "personal-planner-new", discoveryEmptyAt: Date.now() }) }));
    expect(created!.status).toBe(200);
    expect((await owner.current())?.project_ref).toBe(X);
    expect(calls.filter(call => call.url.endsWith("/v1/projects") && call.method === "POST")).toHaveLength(1);
  });

  it("returns one verified project and never creates or binds it without selection", async () => {
    const owner = accountObject();
    const calls = managementResponses([{ ref: X, name: "renamed-cloud", compatible: true }]);
    const resolved = await productionProjectResolution(request("resolve"), environment(owner));
    const body = await resolved!.json() as { candidates: Array<{ projectRef: string }> };
    expect(body.candidates.map(c => c.projectRef)).toEqual([X]);
    expect(await owner.current()).toBeNull();
    expect(calls.every(call => call.method === "GET" || (call.url.endsWith("/database/query") && call.method === "POST"))).toBe(true);
    expect(calls.find(call => call.url.endsWith("/database/query"))?.body).toContain('"read_only":true');
  });

  it("returns both real Planner clouds, ignoring invalid planner-named projects", async () => {
    const projects = [
      { ref: X, name: "renamed-cloud", compatible: true },
      { ref: Y, name: "planner-23", compatible: true },
      { ref: OTHER, name: "planner-fake", compatible: false },
    ];
    managementResponses(projects);
    const resolved = await productionProjectResolution(request("resolve"), environment(accountObject()));
    const body = await resolved!.json() as { candidates: Array<{ projectRef: string }> };
    expect(body.candidates.map(c => c.projectRef)).toEqual([X, Y]);
  });

  it("binds the selected exact ref and subsequent devices never enumerate", async () => {
    const owner = accountObject();
    const calls = managementResponses([{ ref: X, name: "renamed-cloud", compatible: true }, { ref: Y, name: "planner-23", compatible: true }]);
    const first = await productionProjectResolution(request("adopt", X), environment(owner));
    expect(first!.status).toBe(200);
    expect((await owner.current())?.project_ref).toBe(X);
    calls.length = 0;
    for (let device = 0; device < 2; device++) {
      const next = await productionProjectResolution(request("resolve"), environment(owner));
      expect(next!.status).toBe(200);
      expect((await next!.json() as { projectRef: string }).projectRef).toBe(X);
    }
    expect(calls.some(call => call.url.endsWith("/v1/projects"))).toBe(false);
    expect(calls.some(call => call.url.includes(`/v1/projects/${Y}`))).toBe(false);
  });

  it("rejects a stale Y candidate and leaves the authoritative X mapping intact", async () => {
    const owner = accountObject();
    await owner.bind(X, TX);
    const calls = managementResponses([{ ref: X, name: "X", compatible: true }, { ref: Y, name: "Y", compatible: true }]);
    const response = await productionProjectResolution(request("adopt", Y), environment(owner));
    expect(response!.status).toBe(409);
    expect(await response!.json()).toEqual({ error: "mapping_conflict", projectRef: X });
    expect((await owner.current())?.project_ref).toBe(X);
    expect(calls).toHaveLength(0);
  });

  it("treats candidate-list 502 as retryable, never as zero candidates", async () => {
    const owner = accountObject();
    const calls = managementResponses([], { unavailable: "/v1/projects" });
    const response = await productionProjectResolution(request("resolve"), environment(owner));
    expect(response!.status).toBe(502);
    expect(await response!.json()).toEqual({ error: "candidate_discovery_failed" });
    expect(await owner.current()).toBeNull();
    expect(calls.filter(call => call.method === "POST" && call.url.endsWith("/v1/projects"))).toHaveLength(0);
  });

  it("does not offer creation while an existing Planner project has a partial canonical migration history", async () => {
    const owner = accountObject();
    const calls = managementResponses([{ ref: X, name: "partially created", compatible: true }], { partial: X });
    const response = await productionProjectResolution(request("resolve"), environment(owner));
    expect(response!.status).toBe(502);
    expect(await response!.json()).toEqual({ error: "candidate_discovery_failed" });
    expect(await owner.current()).toBeNull();
    expect(calls.every(call => call.method !== "POST" || call.url.endsWith("/database/query"))).toBe(true);
  });

  it("keeps a confirmed deleted mapped project explicit and never creates a replacement", async () => {
    const owner = accountObject();await owner.bind(X, TX);
    const calls = managementResponses([{ ref: X, name: "old", compatible: true }], { deleted: X });
    const response = await productionProjectResolution(request("resolve"), environment(owner));
    expect(response!.status).toBe(410);
    expect(await response!.json()).toEqual({ error: "project_deleted" });
    expect((await owner.current())?.project_ref).toBe(X);
    expect(calls.some(call => call.method === "POST" && call.url.endsWith("/v1/projects"))).toBe(false);
  });

  it("keeps mapped X on a temporary verification 502", async () => {
    const owner = accountObject();await owner.bind(X, TX);
    const calls = managementResponses([{ ref: X, name: "old", compatible: true }], { unavailable: `/v1/projects/${X}/database/migrations` });
    const response = await productionProjectResolution(request("resolve"), environment(owner));
    expect(response!.status).toBe(502);
    expect((await owner.current())?.project_ref).toBe(X);
    expect(calls.some(call => call.method === "POST" && call.url.endsWith("/v1/projects"))).toBe(false);
  });

  it("requires Management reauthorization without changing mapped X", async () => {
    const owner = accountObject();await owner.bind(X, TX);
    const calls = managementResponses([{ ref: X, name: "old", compatible: true }]);
    const response = await productionProjectResolution(request("resolve"), environment(owner,
      transaction({ managementToken: async () => null })));
    expect(response!.status).toBe(401);
    expect(await response!.json()).toEqual({ error: "oauth_expired" });
    expect((await owner.current())?.project_ref).toBe(X);
    expect(calls).toHaveLength(0);
  });

  it("clears a mapped ref only after explicit replacement and a fresh exact 404", async () => {
    const owner = accountObject();await owner.bind(X, TX);
    const calls = managementResponses([{ ref: X, name: "old", compatible: true }], { deleted: X });
    const response = await productionProjectResolution(request("replace-deleted"), environment(owner));
    expect(response!.status).toBe(200);
    expect(await response!.json()).toEqual({ kind: "mapping_cleared" });
    expect(await owner.current()).toBeNull();
    expect(calls.map(call => call.url)).toEqual([`https://api.supabase.com/v1/projects/${X}`]);
  });

  it("does not clear a mapped ref on a temporary 502", async () => {
    const owner = accountObject();await owner.bind(X, TX);
    managementResponses([{ ref: X, name: "old", compatible: true }], { unavailable: `/v1/projects/${X}` });
    const response = await productionProjectResolution(request("replace-deleted"), environment(owner));
    expect(response!.status).toBe(502);
    expect((await owner.current())?.project_ref).toBe(X);
  });

  it("serializes first creation and rejects a competing candidate without last-write-wins", async () => {
    const owner = accountObject();
    const [first, second] = await Promise.all([
      owner.reserve("linux", "owner-org", "personal-planner-new"),
      owner.reserve("android", "owner-org", "personal-planner-other"),
    ]);
    expect(first.kind).toBe("reserved_by_self");
    expect(second.kind).toBe("reserved_by_other");
    expect((await owner.bind(X, "linux")).kind).toBe("bound");
    expect((await owner.bind(Y, "android")).kind).toBe("conflict");
    expect((await owner.current())?.project_ref).toBe(X);
  });

  it("never binds an uncertain create by project name or permits another POST", async () => {
    const owner = accountObject();
    await owner.reserve(TX, "owner-org", "personal-planner-new");
    const calls = managementResponses([{ ref: X, name: "personal-planner-new", compatible: true }]);
    const tx = transaction({ createContext: async () => ({ state: "project_reconciliation_required", projectRef: null, organizationSlug: "owner-org", requestedProjectName: "personal-planner-new", discoveryEmptyAt: Date.now() }) });
    const response = await productionFetch(new Request(`https://worker.test/v1/provisioning/transactions/${TX}/reconcile`, {
      method: "POST", headers: { authorization: "Provisioning capability", "content-type": "application/json" }, body: "{}",
    }), environment(owner, tx));
    expect(response!.status).toBe(409);
    expect(await response!.json()).toEqual({ error: "project_identity_ambiguous" });
    expect((await owner.current())?.project_ref).toBeNull();
    expect(calls).toHaveLength(0);
    expect((await owner.reserve("another-device", "owner-org", "other")).kind).toBe("reserved_by_other");
  });

  it("does not require a project name pattern for verified compatibility", async () => {
    managementResponses([{ ref: X, name: "My renamed cloud", compatible: true }, { ref: OTHER, name: "planner-99", compatible: false }]);
    const candidates = await discoverPlannerCandidates(async (path, init) => (globalThis.fetch as typeof fetch)(`https://api.supabase.com${path}`, init));
    expect(candidates?.map(c => c.projectRef)).toEqual([X]);
  });

  it("falls back from an invalid local READY candidate to read-only verified discovery", async () => {
    const owner = accountObject();
    const calls = managementResponses([
      { ref: OTHER, name: "planner-fake", compatible: false },
      { ref: X, name: "Renamed cloud", compatible: true },
    ]);
    const tx = transaction({ releaseManagementGrant: async () => { throw new Error("selection still needs authorization"); } });
    const response = await productionProjectCheck(new Request(`https://worker.test/v1/provisioning/transactions/${TX}/project-check`, {
      method: "POST", headers: { authorization: "Provisioning capability", "content-type": "application/json" }, body: JSON.stringify({ projectRef: OTHER }),
    }), environment(owner, tx));
    expect(response!.status).toBe(200);
    const body = await response!.json() as { projectStatus: string; candidates: Array<{ projectRef: string }>; grantReleased: boolean };
    expect(body.projectStatus).toBe("legacy_candidates");
    expect(body.candidates.map(c => c.projectRef)).toEqual([X]);
    expect(body.grantReleased).toBe(false);
    expect(await owner.current()).toBeNull();
    expect(calls.some(call => call.method === "PATCH" || (call.method === "POST" && call.url.endsWith("/v1/projects")))).toBe(false);
  });
});

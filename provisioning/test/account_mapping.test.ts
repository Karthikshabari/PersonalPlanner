import { afterEach, describe, expect, it, vi } from "vitest";
import { MIGRATIONS } from "../src/migrations";
import { ManagementAccountProject } from "../src/management_account_project";
import { discoverPlannerCandidates, productionFetch, productionProjectCheck, productionProjectResolution } from "../src/production";

const X = "abcdefghijklmnopqrst";
const Y = "bcdefghijklmnopqrstu";
const OTHER = "cdefghijklmnopqrstuv";
const TX = "0123456789abcdef0123456789abcdef";
const KEY = "sb_publishable_CuLX_Y3xWuD0cuItKbm-Xw_NJMQ84zu";
const CHECKS = Object.fromEntries([
  "required_tables_exist", "rls_enabled", "required_rpcs_exist",
  "protocol_v2_authenticated_execute", "capability_grants_correct",
  "f03_helper_private", "f03_validates_branch_before_union", "f03_wrappers_active",
  "recurrence_provenance_present", "relationships_owner_scoped",
  "direct_authenticated_writes_revoked", "capability_payload_current",
].map(key => [key, true]));
type Project = { ref: string; name: string; compatible: boolean; organization?: string; partial?: boolean };

function guardObject() {
  let holder: string | null = null;
  let legacy: string | null = null;
  const sql = { exec(query: string, ...values: unknown[]) {
    if (query.startsWith("SELECT transaction_id FROM creation_guard")) return { toArray: () => holder ? [{ transaction_id: holder }] : [] };
    if (query.startsWith("INSERT INTO creation_guard")) holder = String(values[0]);
    if (query.startsWith("DELETE FROM creation_guard") && holder === values[0]) holder = null;
    if (query.startsWith("SELECT project_ref")) return { toArray: () => legacy ? [{ project_ref: legacy, transaction_id: TX, organization_slug: null, project_name: null }] : [] };
    if (query.startsWith("INSERT INTO ownership")) legacy = String(values[0]);
    return { toArray: () => [] };
  } };
  const ctx = { storage: { sql }, blockConcurrencyWhile: (operation: () => Promise<unknown>) => operation() };
  return { object: new ManagementAccountProject(ctx as any, {} as any), holder: () => holder };
}

function transaction() {
  let state = "authorization_pending";
  let discovered: string[] = [];
  let empty = false;
  let uncertain = false;
  return {
    managementToken: async () => "temporary-management-token",
    get: async () => ({ state, projectRef: null }),
    recordDiscovery: async (_capability: string, refs: string[]) => { discovered = refs; empty = refs.length === 0; },
    discoveredCandidate: async (_capability: string, ref: string) => discovered.includes(ref),
    createContext: async () => ({ state, projectRef: null, organizationSlug: "personal", requestedProjectName: "personal-planner-new", discoveryEmptyAt: empty ? Date.now() : undefined }),
    select: () => { state = "organization_selected"; },
    discovered: () => discovered,
    adoptReady: async (_capability: string, config: Record<string, unknown>) => { state = "ready"; return { state, projectRef: config.projectRef, runtimeConfig: config }; },
    reserveCreate: async () => { state = "project_creating"; return { nonce: "nonce", organizationSlug: "personal", requestedProjectName: "personal-planner-new" }; },
    createUncertain: async () => { state = "project_reconciliation_required"; uncertain = true; },
    recordProject: async (_capability: string, _nonce: string, projectRef: string) => { state = "project_waiting"; return { state, projectRef }; },
    claimCreateReconciliation: async () => { if (!uncertain) throw Error("operation_in_progress"); state = "project_reconciliation_required"; },
    releaseManagementGrant: async () => ({ released: true, revoked: true, unconfirmed: false }),
  };
}

function environment(worker = transaction(), objects = new Map<string, ReturnType<typeof guardObject>>()) {
  return {
    PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => worker },
    MANAGEMENT_ACCOUNT_PROJECT: {
      idFromName: (name: string) => name,
      get: (name: string) => {
        if (!objects.has(name)) objects.set(name, guardObject());
        return objects.get(name)!.object;
      },
    },
    objects,
  };
}

function request(action: "resolve" | "adopt", projectRef?: string) {
  return new Request("https://worker.test/v1/provisioning/transactions/" + TX + "/" + action, {
    method: "POST",
    headers: { authorization: "Provisioning capability", "content-type": "application/json" },
    body: JSON.stringify(projectRef ? { projectRef } : {}),
  });
}
function createRequest(id = TX) {
  return new Request("https://worker.test/v1/provisioning/transactions/" + id + "/create", {
    method: "POST", headers: { authorization: "Provisioning capability", "content-type": "application/json" }, body: "{}",
  });
}
function checkRequest(projectRef: string) {
  return new Request("https://worker.test/v1/provisioning/transactions/" + TX + "/project-check", {
    method: "POST", headers: { authorization: "Provisioning capability", "content-type": "application/json" }, body: JSON.stringify({ projectRef }),
  });
}
function managementResponses(projects: Project[], options: { fail?: string; status?: number; createStatus?: number } = {}) {
  const calls: Array<{ url: string; method: string; body?: string }> = [];
  vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input), method = init?.method ?? "GET";
    calls.push({ url, method, body: typeof init?.body === "string" ? init.body : undefined });
    if (options.fail && url.includes(options.fail)) return new Response(null, { status: options.status ?? 502 });
    if (url.endsWith("/v1/organizations")) return Response.json([{ id: "org-id", slug: "personal", name: "Renamed organization" }, { id: "org-two", slug: "other", name: "Other" }]);
    if (url.includes("/v1/organizations/") && url.includes("/projects?")) {
      const slug = url.includes("/organizations/personal/") ? "personal" : "other";
      const listed = projects.filter(p => (p.organization ?? "personal") === slug);
      return Response.json({ projects: listed.map(p => ({ ref: p.ref, name: p.name, region: "ap-south-1" })), pagination: { count: listed.length, limit: 100, offset: 0 } });
    }
    if (url.endsWith("/v1/projects") && method === "POST") return options.createStatus ? new Response(null, { status: options.createStatus }) : Response.json({ ref: X });
    const project = projects.find(p => url.includes("/v1/projects/" + p.ref));
    if (!project) return new Response(null, { status: 404 });
    if (url.endsWith("/v1/projects/" + project.ref)) return Response.json({ ref: project.ref, status: "ACTIVE_HEALTHY" });
    if (url.endsWith("/database/migrations")) return Response.json(project.partial ? [{ name: MIGRATIONS[0]!.name }] : project.compatible ? MIGRATIONS.map(m => ({ name: m.name })) : []);
    if (url.endsWith("/database/query")) return Response.json([CHECKS]);
    if (url.endsWith("/config/auth")) return Response.json({ uri_allow_list: "com.personalplanner.personalplanner://login-callback,https://worker.test/auth/confirmed" });
    if (url.endsWith("/api-keys")) return Response.json([{ type: "publishable", id: "safe-key" }]);
    if (url.endsWith("/api-keys/safe-key?reveal=true")) return Response.json({ type: "publishable", api_key: KEY });
    return new Response(null, { status: 404 });
  });
  return calls;
}
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

describe("project-centric resolution", () => {
  it("discovers zero compatible projects through complete read-only organization listings", async () => {
    const tx = transaction(), calls = managementResponses([{ ref: OTHER, name: "personal-planner-fake", compatible: false }]);
    const result = await productionProjectResolution(request("resolve"), environment(tx));
    expect(await result!.json()).toEqual({ kind: "candidates", candidates: [] });
    expect(tx.discovered()).toEqual([]);
    expect(calls.filter(c => c.method === "POST")).toHaveLength(0);
  });

  it("requires explicit selection even for one verified, renamed project", async () => {
    const tx = transaction(), calls = managementResponses([{ ref: X, name: "My renamed cloud", compatible: true }]);
    const result = await productionProjectResolution(request("resolve"), environment(tx));
    expect((await result!.json() as { candidates: Array<{ projectRef: string }> }).candidates.map(c => c.projectRef)).toEqual([X]);
    expect(tx.discovered()).toEqual([X]);
    expect(calls.some(c => c.url.endsWith("/database/query") && c.body?.includes('"read_only":true'))).toBe(true);
    expect(calls.some(c => c.method === "PATCH" || c.url.endsWith("/v1/projects") && c.method === "POST")).toBe(false);
  });

  it("returns multiple candidates without order-based choice or name authority", async () => {
    const tx = transaction();
    managementResponses([{ ref: Y, name: "Anything", compatible: true }, { ref: OTHER, name: "personal-planner-fake", compatible: false }, { ref: X, name: "Renamed", compatible: true }]);
    const result = await productionProjectResolution(request("resolve"), environment(tx));
    expect((await result!.json() as { candidates: Array<{ projectRef: string }> }).candidates.map(c => c.projectRef)).toEqual([Y, X]);
    expect(tx.discovered()).toEqual([Y, X]);
  });

  it("checks compatible projects across every accessible organization", async () => {
    const tx = transaction();
    managementResponses([
      { ref: X, name: "Renamed personal", compatible: true, organization: "personal" },
      { ref: Y, name: "Renamed other", compatible: true, organization: "other" },
    ]);
    const result = await productionProjectResolution(request("resolve"), environment(tx));
    expect((await result!.json() as { candidates: Array<{ projectRef: string }> }).candidates.map(c => c.projectRef)).toEqual([X, Y]);
  });

  it("follows every pagination offset and refuses a truncated successful page", async () => {
    const paths: string[] = [];
    const complete = await discoverPlannerCandidates(async path => {
      paths.push(path);
      if (path === "/v1/organizations") return Response.json([{ id: "org-id", slug: "personal", name: "Personal" }]);
      if (path.endsWith("offset=0")) return Response.json({ projects: [{ ref: X, name: "X" }], pagination: { count: 2, limit: 100, offset: 0 } });
      if (path.endsWith("offset=1")) return Response.json({ projects: [{ ref: Y, name: "Y" }], pagination: { count: 2, limit: 100, offset: 1 } });
      if (path.endsWith("/database/migrations")) return Response.json([]);
      return Response.json({ ref: path.endsWith(X) ? X : Y });
    });
    expect(complete).toEqual([]);
    expect(paths.filter(p => p.includes("/organizations/personal/projects?"))).toEqual([
      "/v1/organizations/personal/projects?limit=100&offset=0",
      "/v1/organizations/personal/projects?limit=100&offset=1",
    ]);
    const truncated = await discoverPlannerCandidates(async path => path === "/v1/organizations"
      ? Response.json([{ id: "org-id", slug: "personal", name: "Personal" }])
      : Response.json({ projects: [], pagination: { count: 2, limit: 100, offset: 0 } }));
    expect(truncated).toBeNull();
    const changingTotal = await discoverPlannerCandidates(async path => path === "/v1/organizations"
      ? Response.json([{ id: "org-id", slug: "personal", name: "Personal" }])
      : path.endsWith("offset=0")
      ? Response.json({ projects: [{ ref: X }], pagination: { count: 2, limit: 100, offset: 0 } })
      : Response.json({ projects: [], pagination: { count: 1, limit: 100, offset: 1 } }));
    expect(changingTotal).toBeNull();
  });

  it("rejects an injected ref that was not in verified discovery", async () => {
    const tx = transaction(), calls = managementResponses([{ ref: X, name: "cloud", compatible: true }]);
    const response = await productionProjectResolution(request("adopt", X), environment(tx));
    expect(response!.status).toBe(403);
    expect(calls).toHaveLength(0);
  });

  it("rechecks an explicitly selected ref and adopts only that compatible backend", async () => {
    const tx = transaction(), calls = managementResponses([{ ref: X, name: "cloud", compatible: true }, { ref: Y, name: "other", compatible: true }]);
    const env = environment(tx);
    await productionProjectResolution(request("resolve"), env);
    calls.length = 0;
    const response = await productionProjectResolution(request("adopt", X), env);
    expect(response!.status).toBe(200);
    expect((await response!.json() as { projectRef: string }).projectRef).toBe(X);
    expect(calls.some(c => c.url.includes("/v1/projects/" + Y))).toBe(false);
    expect(calls.some(c => c.url.endsWith("/v1/projects") && c.method === "POST")).toBe(false);
  });

  it("fails closed on listing errors, incomplete pages, and partial migrations", async () => {
    for (const setup of [
      { projects: [] as Project[], fail: "/organizations/personal/projects?", status: 502 },
      { projects: [{ ref: X, name: "partial", compatible: true, partial: true }], fail: undefined, status: undefined },
    ]) {
      const calls = managementResponses(setup.projects, { fail: setup.fail, status: setup.status });
      const result = await productionProjectResolution(request("resolve"), environment());
      expect(result!.status).toBe(502);
      expect(calls.some(c => c.method === "POST" && c.url.endsWith("/v1/projects"))).toBe(false);
    }
    const incomplete = await discoverPlannerCandidates(async path => path === "/v1/organizations"
      ? Response.json([{ id: "a", name: "A", slug: "personal" }])
      : Response.json({ projects: [], pagination: { count: 1, limit: 100, offset: 0 } }));
    expect(incomplete).toBeNull();
  });

  it("checks exact local X before any broad discovery and preserves it on 401, 429, and 502", async () => {
    for (const status of [401, 403, 429, 502]) {
      const calls = managementResponses([{ ref: X, name: "cloud", compatible: true }], { fail: "/v1/projects/" + X, status });
      const response = await productionProjectCheck(checkRequest(X), environment());
      expect(await response!.json()).toMatchObject({ projectExists: null, projectStatus: "indeterminate" });
      expect(calls.map(c => c.url)).toEqual(["https://api.supabase.com/v1/projects/" + X]);
    }
  });

  it("reports exact 404 as missing without discovery or replacement", async () => {
    const calls = managementResponses([]);
    const response = await productionProjectCheck(checkRequest(X), environment());
    expect(await response!.json()).toMatchObject({ projectExists: false, projectStatus: "missing" });
    expect(calls.map(c => c.url)).toEqual(["https://api.supabase.com/v1/projects/" + X]);
  });

  it("treats incompatible local X as recovery rather than mutating it", async () => {
    const tx = transaction(), calls = managementResponses([{ ref: X, name: "bad", compatible: false }, { ref: Y, name: "renamed", compatible: true }]);
    const response = await productionProjectCheck(checkRequest(X), environment(tx));
    expect(await response!.json()).toMatchObject({ projectStatus: "legacy_candidates", candidates: [{ projectRef: Y }] });
    expect(tx.discovered()).toEqual([Y]);
    expect(calls.some(c => c.method === "PATCH" || c.url.endsWith("/v1/projects") && c.method === "POST")).toBe(false);
  });
});

describe("creation-only coordination", () => {
  it("creates only after verified zero discovery and a creation-context reservation", async () => {
    const tx = transaction(), env = environment(tx), calls = managementResponses([]);
    await productionProjectResolution(request("resolve"), env);
    tx.select();
    const response = await productionFetch(createRequest(), env);
    expect(response!.status).toBe(200);
    expect((await response!.json() as { projectRef: string }).projectRef).toBe(X);
    expect(calls.filter(c => c.url.endsWith("/v1/projects") && c.method === "POST")).toHaveLength(1);
    expect(env.objects.get("creation:personal")?.holder()).toBe(TX);
  });

  it("rechecks after reservation and offers a newly appeared candidate instead of creating", async () => {
    const projects: Project[] = [], tx = transaction(), env = environment(tx), calls = managementResponses(projects);
    await productionProjectResolution(request("resolve"), env);
    tx.select();
    projects.push({ ref: X, name: "new cloud", compatible: true });
    const response = await productionFetch(createRequest(), env);
    expect(response!.status).toBe(409);
    expect(await response!.json()).toEqual({ error: "candidate_discovery_changed" });
    expect(tx.discovered()).toEqual([X]);
    expect(env.objects.get("creation:personal")?.holder()).toBeNull();
    expect(calls.filter(c => c.url.endsWith("/v1/projects") && c.method === "POST")).toHaveLength(0);
  });

  it("keeps the selected creation destination after a fresh zero-candidate recheck", async () => {
    const tx = transaction(), calls = managementResponses([]);
    await tx.recordDiscovery("capability", []);
    tx.select();
    const response = await productionProjectResolution(request("resolve"), environment(tx));
    expect(await response!.json()).toMatchObject({ state: "organization_selected" });
    expect(calls.filter(c => c.url.endsWith("/v1/projects") && c.method === "POST")).toHaveLength(0);
  });

  it("blocks a concurrent create and retains the guard after uncertain POST", async () => {
    const tx = transaction(), env = environment(tx), calls = managementResponses([], { createStatus: 502 });
    await productionProjectResolution(request("resolve"), env);
    tx.select();
    const response = await productionFetch(createRequest(), env);
    expect(response!.status).toBe(502);
    expect(env.objects.get("creation:personal")?.holder()).toBe(TX);
    expect(await env.objects.get("creation:personal")!.object.reserveCreation("android")).toBe("other");
    expect(calls.filter(c => c.url.endsWith("/v1/projects") && c.method === "POST")).toHaveLength(1);
  });

  it("allows only one external POST for concurrent devices in one creation context", async () => {
    const objects = new Map<string, ReturnType<typeof guardObject>>();
    const linux = transaction(), android = transaction();
    await linux.recordDiscovery("capability", []);
    await android.recordDiscovery("capability", []);
    linux.select();
    android.select();
    const calls = managementResponses([]);
    const results = await Promise.all([
      productionFetch(createRequest(TX), environment(linux, objects)),
      productionFetch(createRequest("abcdef0123456789abcdef0123456789"), environment(android, objects)),
    ]);
    expect(results.map(r => r!.status).sort()).toEqual([200, 409]);
    expect(calls.filter(c => c.url.endsWith("/v1/projects") && c.method === "POST")).toHaveLength(1);
  });

  it("releases the creation guard only after the created project reaches READY", async () => {
    managementResponses([{ ref: X, name: "new", compatible: true }]);
    const base = transaction();
    const worker = {
      ...base,
      get: async () => ({ state: "verifying", projectRef: X }),
      claimOperation: async () => ({ nonce: "verify-nonce", projectRef: X }),
      finishVerification: async () => ({ state: "ready", projectRef: X }),
      createContext: async () => ({ organizationSlug: "personal" }),
    };
    const env = environment(worker);
    const guard = env.MANAGEMENT_ACCOUNT_PROJECT.get("creation:personal");
    expect(await guard.reserveCreation(TX)).toBe("self");
    const response = await productionFetch(new Request("https://worker.test/v1/provisioning/transactions/" + TX + "/verify", {
      method: "POST", headers: { authorization: "Provisioning capability", "content-type": "application/json" }, body: "{}",
    }), env);
    expect(response!.status).toBe(200);
    expect(env.objects.get("creation:personal")?.holder()).toBeNull();
  });

  it("keeps old account mappings isolated from the new creation namespace", async () => {
    const env = environment();
    const old = env.MANAGEMENT_ACCOUNT_PROJECT.get("management:legacy");
    expect(await old.bind(X, TX)).toMatchObject({ kind: "bound" });
    const guard = env.MANAGEMENT_ACCOUNT_PROJECT.get("creation:personal");
    expect(await guard.reserveCreation(TX)).toBe("self");
    expect((await old.current())?.project_ref).toBe(X);
    expect(await guard.current()).toBeNull();
    expect(env.objects.get("creation:personal")?.holder()).toBe(TX);
  });

  it("does not collide between different creation organizations", async () => {
    const env = environment();
    expect(await env.MANAGEMENT_ACCOUNT_PROJECT.get("creation:personal").reserveCreation("linux")).toBe("self");
    expect(await env.MANAGEMENT_ACCOUNT_PROJECT.get("creation:other").reserveCreation("android")).toBe("self");
    expect(await env.MANAGEMENT_ACCOUNT_PROJECT.get("creation:personal").reserveCreation("android")).toBe("other");
  });
});

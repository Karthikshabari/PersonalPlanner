import titleHistoryRuntimeTest from "../../supabase/tests/database/title_history_conflict_ordering_test.sql";
import { MIGRATIONS, SCHEMA_VERIFICATION_SQL } from "./migrations";
import { ProvisioningTransaction, plannerEmailConfirmationPage, productionFetch, productionManagementAuthorization, productionOAuthCallback } from "./production";

export { ProvisioningTransaction };

const AUTHORIZE_URL = "https://api.supabase.com/v1/oauth/authorize";
const TOKEN_URL = "https://api.supabase.com/v1/oauth/token";
const ORGANIZATIONS_URL = "https://api.supabase.com/v1/organizations";
const CALLBACK_PATH = "/oauth/callback";
const FLOW_COOKIE = "__Host-pp_oauth_flow";
const SESSION_COOKIE = "__Host-pp_oauth_session";
const FLOW_TTL_SECONDS = 10 * 60;
const SESSION_TTL_SECONDS = 50 * 60;
const SEAL_CONTEXT = new TextEncoder().encode(
  "personal-planner-provisioning-poc-v1",
);
const RUNTIME_TEST_SHA256 =
  "02da1ed16dd46c7c8f41d788506a309a2bcfa744f8e85b058301523c133c7760";

type OAuthFlow = {
  state: string;
  verifier: string;
  issuedAt: number;
};

type OAuthSession = {
  accessToken: string;
  expiresAt: number;
  csrf?: string;
  project?: ProjectSession;
};

type ProjectSession = {
  organizationSlug: string;
  name: string;
  requestedAt: number;
  databasePassword?: string;
  ref?: string;
};

type Organization = {
  id: string;
  name: string;
  slug: string;
};

type Project = {
  ref: string;
  name: string;
  organizationSlug: string;
  status: string;
  createdAt?: string;
};

function securityHeaders(contentType: string): Headers {
  return new Headers({
    "cache-control": "no-store",
    "content-security-policy":
      "default-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
    "content-type": contentType,
    "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff",
  });
}

function html(body: string, status = 200, cookies: string[] = []): Response {
  const headers = securityHeaders("text/html; charset=utf-8");
  for (const cookie of cookies) {
    headers.append("set-cookie", cookie);
  }

  return new Response(
    `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Personal Planner</title><body><main><h1>Personal Planner</h1>${body}</main></body></html>`,
    { status, headers },
  );
}

function escapeHtml(value: string): string {
  return value.replace(
    /[&<>"']/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      })[character] ?? character,
  );
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

function base64UrlDecode(value: string): Uint8Array {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/").padEnd(
    Math.ceil(value.length / 4) * 4,
    "=",
  );
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function base64Encode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function randomToken(byteLength: number): string {
  return base64UrlEncode(crypto.getRandomValues(new Uint8Array(byteLength)));
}

async function sha256Base64Url(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return base64UrlEncode(new Uint8Array(digest));
}

async function cookieKey(secret: string): Promise<CryptoKey> {
  const keyBytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(secret),
  );
  return crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
}

async function seal(payload: object, secret: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = new TextEncoder().encode(JSON.stringify(payload));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: SEAL_CONTEXT },
    await cookieKey(secret),
    plaintext,
  );
  const combined = new Uint8Array(iv.length + ciphertext.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(ciphertext), iv.length);
  return base64UrlEncode(combined);
}

async function unseal<T>(value: string, secret: string): Promise<T | null> {
  try {
    const combined = base64UrlDecode(value);
    if (combined.byteLength <= 12) return null;
    const plaintext = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: combined.slice(0, 12),
        additionalData: SEAL_CONTEXT,
      },
      await cookieKey(secret),
      combined.slice(12),
    );
    return JSON.parse(new TextDecoder().decode(plaintext)) as T;
  } catch {
    return null;
  }
}

function readCookie(request: Request, name: string): string | null {
  const header = request.headers.get("cookie");
  if (header === null) return null;

  for (const part of header.split(";")) {
    const separator = part.indexOf("=");
    if (separator < 0) continue;
    if (part.slice(0, separator).trim() === name) {
      return part.slice(separator + 1).trim();
    }
  }
  return null;
}

function secureCookie(name: string, value: string, maxAge: number): string {
  return `${name}=${value}; Max-Age=${maxAge}; Path=/; HttpOnly; Secure; SameSite=Lax`;
}

function clearCookie(name: string): string {
  return `${name}=; Max-Age=0; Path=/; HttpOnly; Secure; SameSite=Lax`;
}

async function timingSafeEqual(left: string, right: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [leftDigest, rightDigest] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(left)),
    crypto.subtle.digest("SHA-256", encoder.encode(right)),
  ]);
  const leftBytes = new Uint8Array(leftDigest);
  const rightBytes = new Uint8Array(rightDigest);
  let difference = 0;
  for (let index = 0; index < leftBytes.length; index += 1) {
    difference |= leftBytes.at(index)! ^ rightBytes.at(index)!;
  }
  return difference === 0;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asOrganization(value: unknown): Organization | null {
  if (!isRecord(value)) return null;
  const { id, name, slug } = value;
  return typeof id === "string" &&
    typeof name === "string" &&
    typeof slug === "string"
    ? { id, name, slug }
    : null;
}

function asProject(value: unknown): Project | null {
  if (!isRecord(value)) return null;
  const ref = typeof value.ref === "string"
    ? value.ref
    : typeof value.id === "string"
    ? value.id
    : null;
  const organizationSlug = typeof value.organization_slug === "string"
    ? value.organization_slug
    : "";
  if (
    ref === null ||
    typeof value.name !== "string" ||
    typeof value.status !== "string"
  ) {
    return null;
  }
  return {
    ref,
    name: value.name,
    organizationSlug,
    status: value.status,
    createdAt: typeof value.inserted_at === "string"
      ? value.inserted_at
      : typeof value.created_at === "string"
      ? value.created_at
      : undefined,
  };
}

async function readSession(request: Request, env: Env): Promise<OAuthSession | null> {
  const cookie = readCookie(request, SESSION_COOKIE);
  if (cookie === null) return null;
  const session = await unseal<OAuthSession>(cookie, env.OAUTH_SESSION_KEY);
  if (
    session === null ||
    typeof session.accessToken !== "string" ||
    !Number.isFinite(session.expiresAt) ||
    session.expiresAt <= Date.now()
  ) {
    return null;
  }
  return session;
}

async function sessionCookie(session: OAuthSession, env: Env): Promise<string> {
  const remainingSeconds = Math.max(
    1,
    Math.floor((session.expiresAt - Date.now()) / 1000),
  );
  const sealed = await seal(session, env.OAUTH_SESSION_KEY);
  return secureCookie(SESSION_COOKIE, sealed, remainingSeconds);
}

async function managementFetch(
  path: string,
  accessToken: string,
  init: RequestInit = {},
): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set("authorization", `Bearer ${accessToken}`);
  if (init.body !== undefined) headers.set("content-type", "application/json");
  return fetch(`https://api.supabase.com${path}`, {
    ...init,
    headers,
    signal: AbortSignal.timeout(20_000),
  });
}

function sanitizeUpstreamText(value: string): string {
  return value
    .replace(/eyJ[A-Za-z0-9._-]+/gu, "[redacted-token]")
    .replace(/sb_(?:secret|publishable)_[A-Za-z0-9_-]+/gu, "[redacted-api-key]")
    .replace(/sba_[A-Za-z0-9_-]+/gu, "[redacted-oauth-secret]")
    .replace(/[\u0000-\u001f\u007f]/gu, " ")
    .slice(0, 300);
}

async function sanitizedUpstreamError(response: Response): Promise<string> {
  const contentLength = Number(response.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > 4096) {
    return "upstream response omitted because it exceeded the diagnostic limit";
  }
  const raw = (await response.text()).slice(0, 4096);
  try {
    const payload: unknown = JSON.parse(raw);
    if (!isRecord(payload)) return "upstream returned a non-object error";
    const safeFields = ["code", "error", "message", "status"]
      .flatMap((key) => {
        const value = payload[key];
        return typeof value === "string" || typeof value === "number"
          ? [`${key}=${sanitizeUpstreamText(String(value))}`]
          : [];
      });
    return safeFields.length === 0
      ? "upstream returned an error without safe diagnostic fields"
      : safeFields.join("; ");
  } catch {
    return "upstream returned a non-JSON error";
  }
}

async function oauthStart(env: Env): Promise<Response> {
  const state = randomToken(32);
  const verifier = randomToken(48);
  const flow: OAuthFlow = { state, verifier, issuedAt: Date.now() };
  const sealedFlow = await seal(flow, env.OAUTH_SESSION_KEY);
  const authorizationUrl = new URL(AUTHORIZE_URL);
  authorizationUrl.search = new URLSearchParams({
    client_id: env.SUPABASE_OAUTH_CLIENT_ID,
    code_challenge: await sha256Base64Url(verifier),
    code_challenge_method: "S256",
    redirect_uri: env.SUPABASE_OAUTH_REDIRECT_URI,
    response_type: "code",
    state,
  }).toString();

  const headers = securityHeaders("text/plain; charset=utf-8");
  headers.set("location", authorizationUrl.toString());
  headers.append("set-cookie", secureCookie(FLOW_COOKIE, sealedFlow, FLOW_TTL_SECONDS));
  return new Response(null, { status: 302, headers });
}

async function exchangeCode(
  code: string,
  verifier: string,
  env: Env,
): Promise<{ accessToken: string; expiresIn: number } | null> {
  const credentials = new TextEncoder().encode(
    `${env.SUPABASE_OAUTH_CLIENT_ID}:${env.SUPABASE_OAUTH_CLIENT_SECRET}`,
  );
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: {
      authorization: `Basic ${base64Encode(credentials)}`,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      code,
      code_verifier: verifier,
      grant_type: "authorization_code",
      redirect_uri: env.SUPABASE_OAUTH_REDIRECT_URI,
    }),
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) return null;

  const payload: unknown = await response.json();
  if (!isRecord(payload) || typeof payload.access_token !== "string") return null;
  const expiresIn =
    typeof payload.expires_in === "number" && Number.isFinite(payload.expires_in)
      ? payload.expires_in
      : SESSION_TTL_SECONDS;
  return { accessToken: payload.access_token, expiresIn };
}

async function loadOrganizations(accessToken: string): Promise<Organization[] | null> {
  const response = await fetch(ORGANIZATIONS_URL, {
    headers: { authorization: `Bearer ${accessToken}` },
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) return null;

  const payload: unknown = await response.json();
  if (!Array.isArray(payload)) return null;
  const organizations = payload.map(asOrganization).filter((item) => item !== null);
  return organizations.length === payload.length ? organizations : null;
}

function projectNameForNow(now: Date): string {
  const stamp = now.toISOString().replaceAll(/[-:.]/gu, "").slice(0, 15).toLowerCase();
  return `personal-planner-provisioning-poc-${stamp}`;
}

async function projectSelection(request: Request, env: Env): Promise<Response> {
  const session = await readSession(request, env);
  if (session === null) {
    return html(
      '<p>The authorization session expired. <a href="/oauth/start">Authorize Supabase again</a>.</p>',
      401,
    );
  }

  const organizations = await loadOrganizations(session.accessToken);
  const selected = organizations?.find(
    (organization) => organization.slug === env.POC_ORGANIZATION_SLUG,
  );
  if (selected === undefined) {
    return html("<p>The selected organization is not available to this authorization.</p>", 403);
  }

  if (session.project?.ref !== undefined) {
    return html(
      `<p>This browser session already created project <code>${escapeHtml(session.project.ref)}</code>.</p><p><a href="/poc/status">Check readiness</a></p>`,
    );
  }

  const preparedSession: OAuthSession = session.project === undefined
    ? {
        ...session,
        csrf: randomToken(32),
        project: {
          organizationSlug: selected.slug,
          name: projectNameForNow(new Date()),
          requestedAt: Date.now(),
          databasePassword: randomToken(32),
        },
      }
    : session;
  const project = preparedSession.project!;
  const cookie = await sessionCookie(preparedSession, env);
  return html(
    `<p>Ready to create exactly one disposable project.</p><dl><dt>Organization</dt><dd><strong>${escapeHtml(selected.name)}</strong> — <code>${escapeHtml(selected.slug)}</code></dd><dt>Project</dt><dd><code>${escapeHtml(project.name)}</code></dd></dl><p>No existing project will be modified. The database password is encrypted in this short-lived browser session and will not be displayed.</p><form method="post" action="/poc/projects"><input type="hidden" name="csrf" value="${escapeHtml(preparedSession.csrf!)}"><button type="submit">Create disposable POC project</button></form>`,
    200,
    [cookie],
  );
}

async function findPreparedProject(
  session: OAuthSession,
): Promise<Project | null | "collision" | "error"> {
  const project = session.project!;
  const query = new URLSearchParams({ limit: "100", search: project.name });
  const response = await managementFetch(
    `/v1/organizations/${encodeURIComponent(project.organizationSlug)}/projects?${query}`,
    session.accessToken,
  );
  if (!response.ok) return "error";
  const payload: unknown = await response.json();
  if (!isRecord(payload) || !Array.isArray(payload.projects)) return "error";
  const exact = payload.projects
    .map(asProject)
    .filter(
      (candidate): candidate is Project =>
        candidate !== null && candidate.name === project.name,
    );
  if (exact.length === 0) return null;
  const candidate = exact.at(0);
  if (exact.length !== 1 || candidate?.createdAt === undefined) {
    return "collision";
  }
  const createdAt = Date.parse(candidate.createdAt);
  if (!Number.isFinite(createdAt) || createdAt < project.requestedAt - 120_000) {
    return "collision";
  }
  return candidate;
}

async function createProject(request: Request, env: Env): Promise<Response> {
  const session = await readSession(request, env);
  if (
    session === null ||
    session.csrf === undefined ||
    session.project === undefined ||
    session.project.organizationSlug !== env.POC_ORGANIZATION_SLUG
  ) {
    return html("<p>The prepared provisioning session is missing or expired.</p>", 401);
  }

  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (!Number.isFinite(contentLength) || contentLength > 2048) {
    return html("<p>The request is invalid.</p>", 400);
  }
  const form = await request.formData();
  const csrf = form.get("csrf");
  if (typeof csrf !== "string" || !(await timingSafeEqual(session.csrf, csrf))) {
    return html("<p>The request could not be validated.</p>", 403);
  }

  if (session.project.ref !== undefined) {
    return html(
      `<p>The disposable project already exists: <code>${escapeHtml(session.project.ref)}</code>.</p><p><a href="/poc/status">Check readiness</a></p>`,
    );
  }

  const recovered = await findPreparedProject(session);
  if (recovered === "collision") {
    return html(
      "<p>A project-name collision was detected. Provisioning stopped without creating another project.</p>",
      409,
    );
  }
  if (recovered === "error") {
    return html("<p>Existing-project recovery could not be checked. No create call was made.</p>", 502);
  }

  let created = recovered;
  if (created === null) {
    if (session.project.databasePassword === undefined) {
      return html("<p>The prepared database credential is unavailable.</p>", 409);
    }
    const response = await managementFetch("/v1/projects", session.accessToken, {
      method: "POST",
      body: JSON.stringify({
        name: session.project.name,
        organization_slug: session.project.organizationSlug,
        db_pass: session.project.databasePassword,
        region_selection: { type: "smartGroup", code: "apac" },
      }),
    });
    if (!response.ok) {
      console.error(
        JSON.stringify({ event: "project_create_failed", status: response.status }),
      );
      return html(
        `<p>Supabase rejected project creation (HTTP ${response.status}). No retry was attempted.</p>`,
        502,
      );
    }
    const payload: unknown = await response.json();
    created = asProject(payload);
    if (created === null) {
      return html("<p>Supabase returned an unexpected project response.</p>", 502);
    }
  }

  if (
    created.name !== session.project.name ||
    !/^[a-z]{20}$/u.test(created.ref)
  ) {
    return html("<p>The created project identity did not pass validation.</p>", 502);
  }

  const updatedSession: OAuthSession = {
    ...session,
    project: { ...session.project, ref: created.ref },
  };
  const cookie = await sessionCookie(updatedSession, env);
  console.info(
    JSON.stringify({
      event: recovered === null ? "project_created" : "project_create_recovered",
      projectRef: created.ref,
      projectName: created.name,
      organizationSlug: session.project.organizationSlug,
    }),
  );
  const headers = securityHeaders("text/plain; charset=utf-8");
  headers.set("location", "/poc/status");
  headers.append("set-cookie", cookie);
  return new Response(null, { status: 303, headers });
}

async function reconcileProject(request: Request, env: Env): Promise<Response> {
  const session = await readSession(request, env);
  if (session === null) {
    return html(
      '<p>The authorization session expired. <a href="/oauth/start">Authorize Supabase again</a>.</p>',
      401,
    );
  }
  if (
    session.project !== undefined &&
    (session.project.name !== env.POC_PROJECT_NAME ||
      session.project.organizationSlug !== env.POC_ORGANIZATION_SLUG)
  ) {
    return html(
      "<p>The sealed POC transaction identifies a different project. Reconciliation stopped.</p>",
      409,
    );
  }

  const query = new URLSearchParams({ limit: "100", search: env.POC_PROJECT_NAME });
  const response = await managementFetch(
    `/v1/organizations/${encodeURIComponent(env.POC_ORGANIZATION_SLUG)}/projects?${query}`,
    session.accessToken,
  );
  if (!response.ok) {
    const diagnostic = await sanitizedUpstreamError(response);
    console.error(
      JSON.stringify({ event: "project_reconcile_failed", status: response.status, diagnostic }),
    );
    return html(
      `<p>Project reconciliation failed (HTTP ${response.status}): ${escapeHtml(diagnostic)}.</p>`,
      502,
    );
  }
  const payload: unknown = await response.json();
  if (!isRecord(payload) || !Array.isArray(payload.projects)) {
    return html("<p>Project reconciliation returned an unexpected response.</p>", 502);
  }
  const exact = payload.projects
    .map(asProject)
    .filter(
      (candidate): candidate is Project =>
        candidate !== null && candidate.name === env.POC_PROJECT_NAME,
    );
  const matched = exact.at(0);
  if (exact.length !== 1 || matched === undefined || !/^[a-z]{20}$/u.test(matched.ref)) {
    return html(
      `<p>Expected exactly one project named <code>${escapeHtml(env.POC_PROJECT_NAME)}</code>; found ${exact.length}. No project was changed.</p>`,
      409,
    );
  }

  const updatedSession: OAuthSession = {
    ...session,
    csrf: session.csrf ?? randomToken(32),
    project: session.project === undefined
      ? {
          organizationSlug: env.POC_ORGANIZATION_SLUG,
          name: env.POC_PROJECT_NAME,
          requestedAt: matched.createdAt === undefined
            ? Date.now()
            : Date.parse(matched.createdAt),
          ref: matched.ref,
        }
      : { ...session.project, ref: matched.ref },
  };
  const cookie = await sessionCookie(updatedSession, env);
  console.info(
    JSON.stringify({
      event: "project_reconciled",
      projectRef: matched.ref,
      projectName: matched.name,
      organizationSlug: env.POC_ORGANIZATION_SLUG,
    }),
  );
  const headers = securityHeaders("text/plain; charset=utf-8");
  headers.set("location", "/poc/status");
  headers.append("set-cookie", cookie);
  return new Response(null, { status: 303, headers });
}

async function projectStatus(request: Request, env: Env): Promise<Response> {
  const session = await readSession(request, env);
  const project = session?.project;
  if (
    session === null ||
    project?.ref === undefined ||
    project.organizationSlug !== env.POC_ORGANIZATION_SLUG
  ) {
    return html("<p>No disposable project is associated with this session.</p>", 401);
  }

  const projectResponse = await managementFetch(
    `/v1/projects/${encodeURIComponent(project.ref)}`,
    session.accessToken,
  );
  if (!projectResponse.ok) {
    return html(
      `<p>Project status is temporarily unavailable (HTTP ${projectResponse.status}). Refresh to retry.</p>`,
      502,
    );
  }
  const current = asProject(await projectResponse.json());
  if (current === null || current.ref !== project.ref || current.name !== project.name) {
    return html("<p>Project identity verification failed.</p>", 409);
  }

  const healthQuery = new URLSearchParams();
  for (const service of ["auth", "db", "pooler", "realtime", "rest", "storage"]) {
    healthQuery.append("services", service);
  }
  const healthResponse = await managementFetch(
    `/v1/projects/${encodeURIComponent(project.ref)}/health?${healthQuery}`,
    session.accessToken,
  );
  if (!healthResponse.ok) {
    const diagnostic = await sanitizedUpstreamError(healthResponse);
    console.error(
      JSON.stringify({
        event: "project_health_failed",
        status: healthResponse.status,
        diagnostic,
      }),
    );
    return html(
      `<p>Service health is temporarily unavailable (HTTP ${healthResponse.status}): ${escapeHtml(diagnostic)}. Refresh to retry.</p>`,
      502,
    );
  }
  const health: unknown = await healthResponse.json();
  const servicesReady = Array.isArray(health) &&
    health.length === 6 &&
    health.every(
      (service) =>
        isRecord(service) &&
        service.healthy === true &&
        service.status === "ACTIVE_HEALTHY",
    );
  if (current.status !== "ACTIVE_HEALTHY" || !servicesReady) {
    return html(
      `<meta http-equiv="refresh" content="10"><p>Project <code>${escapeHtml(project.ref)}</code> is provisioning. Status: <code>${escapeHtml(current.status)}</code>.</p><p>This page retries automatically every 10 seconds.</p>`,
      202,
    );
  }

  const keysResponse = await managementFetch(
    `/v1/projects/${encodeURIComponent(project.ref)}/api-keys`,
    session.accessToken,
  );
  if (!keysResponse.ok) {
    return html(`<p>Publishable-key metadata is unavailable (HTTP ${keysResponse.status}).</p>`, 502);
  }
  const keys: unknown = await keysResponse.json();
  const publishableMetadata = Array.isArray(keys)
    ? keys.find(
        (key) => isRecord(key) && key.type === "publishable" && typeof key.id === "string",
      )
    : undefined;
  if (!isRecord(publishableMetadata) || typeof publishableMetadata.id !== "string") {
    return html("<p>No publishable key was returned. No privileged key was requested.</p>", 502);
  }
  const keyResponse = await managementFetch(
    `/v1/projects/${encodeURIComponent(project.ref)}/api-keys/${encodeURIComponent(publishableMetadata.id)}?reveal=true`,
    session.accessToken,
  );
  if (!keyResponse.ok) {
    return html(`<p>The publishable key could not be retrieved (HTTP ${keyResponse.status}).</p>`, 502);
  }
  const key: unknown = await keyResponse.json();
  if (
    !isRecord(key) ||
    key.type !== "publishable" ||
    typeof key.api_key !== "string" ||
    !key.api_key.startsWith("sb_publishable_")
  ) {
    return html("<p>The returned client key did not pass publishable-key validation.</p>", 502);
  }

  console.info(
    JSON.stringify({ event: "project_ready", projectRef: project.ref, serviceCount: 6 }),
  );
  return html(
    `<p>The disposable project is healthy.</p><dl><dt>Project ref</dt><dd><code>${escapeHtml(project.ref)}</code></dd><dt>Project URL</dt><dd><code>https://${escapeHtml(project.ref)}.supabase.co</code></dd><dt>Publishable key</dt><dd><code>${escapeHtml(key.api_key)}</code></dd></dl><p>No secret or service-role key was requested.</p>`,
  );
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function validateBundledMigrations(): Promise<boolean> {
  const digests = await Promise.all(MIGRATIONS.map((migration) => sha256Hex(migration.query)));
  return digests.every((digest, index) => digest === MIGRATIONS.at(index)?.sha256);
}

function migrationWasApplied(
  migration: (typeof MIGRATIONS)[number],
  history: Array<Record<string, unknown>>,
): boolean {
  const version = migration.name.slice(0, 14);
  const shortName = migration.name.slice(15);
  return history.some((entry) => {
    const entryVersion = typeof entry.version === "string" ? entry.version : "";
    const entryName = typeof entry.name === "string" ? entry.name : "";
    return entryName === migration.name ||
      `${entryVersion}_${entryName}` === migration.name ||
      (entryVersion === version && entryName === shortName);
  });
}

async function readMigrationHistory(
  session: OAuthSession,
  projectRef: string,
): Promise<
  | { kind: "ok"; history: Array<Record<string, unknown>> }
  | { kind: "error"; status: number; diagnostic: string }
> {
  const response = await managementFetch(
    `/v1/projects/${encodeURIComponent(projectRef)}/database/migrations`,
    session.accessToken,
  );
  if (!response.ok) {
    return {
      kind: "error",
      status: response.status,
      diagnostic: await sanitizedUpstreamError(response),
    };
  }
  const payload: unknown = await response.json();
  if (!Array.isArray(payload) || !payload.every(isRecord)) {
    return { kind: "error", status: 502, diagnostic: "unexpected migration-history response" };
  }
  return { kind: "ok", history: payload };
}

async function migrationCapability(request: Request, env: Env): Promise<Response> {
  const session = await readSession(request, env);
  if (
    session === null ||
    session.project?.ref !== env.POC_PROJECT_REF ||
    session.project.name !== env.POC_PROJECT_NAME ||
    session.project.organizationSlug !== env.POC_ORGANIZATION_SLUG
  ) {
    return html("<p>The exact POC project session is missing or expired.</p>", 401);
  }
  if (!(await validateBundledMigrations())) {
    console.error(JSON.stringify({ event: "bundled_migration_digest_mismatch" }));
    return html("<p>The bundled migration digests do not match the repository baseline.</p>", 500);
  }

  const result = await readMigrationHistory(session, env.POC_PROJECT_REF);
  if (result.kind === "error") {
    console.info(
      JSON.stringify({
        event: "migration_api_capability_unavailable",
        status: result.status,
        diagnostic: result.diagnostic,
      }),
    );
    return html(
      `<p>The official migration-management API is unavailable for this project (HTTP ${result.status}): ${escapeHtml(result.diagnostic)}.</p><p>No migration was applied.</p>`,
      result.status === 403 ? 200 : 502,
    );
  }

  const applied = MIGRATIONS.map((migration) =>
    migrationWasApplied(migration, result.history)
  );
  const appliedCount = applied.filter(Boolean).length;
  const isPrefix = applied.every((value, index) => value || applied.slice(index).every((rest) => !rest));
  if (!isPrefix) {
    return html(
      "<p>The canonical migration history is non-contiguous. Automatic migration stopped.</p>",
      409,
    );
  }
  if (appliedCount === MIGRATIONS.length) {
    return html(
      `<p>All ${MIGRATIONS.length} canonical migrations are present in official migration history.</p>`,
    );
  }

  const csrf = session.csrf ?? randomToken(32);
  const updatedSession: OAuthSession = { ...session, csrf };
  const cookie = await sessionCookie(updatedSession, env);
  const pending = MIGRATIONS.slice(appliedCount)
    .map((migration) => `<li><code>${escapeHtml(migration.name)}.sql</code></li>`)
    .join("");
  return html(
    `<p>The official migration-management API is available. ${appliedCount} of ${MIGRATIONS.length} canonical migrations are already applied.</p><p>Pending migrations:</p><ol>${pending}</ol><form method="post" action="/poc/migrations"><input type="hidden" name="csrf" value="${escapeHtml(csrf)}"><button type="submit">Apply canonical migrations</button></form>`,
    200,
    [cookie],
  );
}

async function applyMigrations(request: Request, env: Env): Promise<Response> {
  const session = await readSession(request, env);
  if (
    session === null ||
    session.csrf === undefined ||
    session.project?.ref !== env.POC_PROJECT_REF ||
    session.project.name !== env.POC_PROJECT_NAME ||
    session.project.organizationSlug !== env.POC_ORGANIZATION_SLUG
  ) {
    return html("<p>The exact POC project session is missing or expired.</p>", 401);
  }
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (!Number.isFinite(contentLength) || contentLength > 2048) {
    return html("<p>The request is invalid.</p>", 400);
  }
  const form = await request.formData();
  const csrf = form.get("csrf");
  if (typeof csrf !== "string" || !(await timingSafeEqual(session.csrf, csrf))) {
    return html("<p>The request could not be validated.</p>", 403);
  }
  if (!(await validateBundledMigrations())) {
    return html("<p>The bundled migration digests do not match the repository baseline.</p>", 500);
  }

  const initial = await readMigrationHistory(session, env.POC_PROJECT_REF);
  if (initial.kind === "error") {
    return html(
      `<p>Migration history could not be read (HTTP ${initial.status}): ${escapeHtml(initial.diagnostic)}.</p>`,
      502,
    );
  }

  for (const migration of MIGRATIONS) {
    if (migrationWasApplied(migration, initial.history)) continue;
    const response = await managementFetch(
      `/v1/projects/${encodeURIComponent(env.POC_PROJECT_REF)}/database/migrations`,
      session.accessToken,
      {
        method: "POST",
        body: JSON.stringify({ name: migration.name, query: migration.query }),
      },
    );
    if (!response.ok) {
      const diagnostic = await sanitizedUpstreamError(response);
      console.error(
        JSON.stringify({
          event: "migration_apply_failed",
          migration: migration.name,
          status: response.status,
          diagnostic,
        }),
      );
      return html(
        `<p>Migration <code>${escapeHtml(migration.name)}</code> failed (HTTP ${response.status}): ${escapeHtml(diagnostic)}.</p><p>Refresh the migration page to reconcile official history before retrying.</p>`,
        502,
      );
    }
    initial.history.push({ name: migration.name });
    console.info(
      JSON.stringify({ event: "migration_applied", migration: migration.name }),
    );
  }

  const headers = securityHeaders("text/plain; charset=utf-8");
  headers.set("location", "/poc/migrations");
  return new Response(null, { status: 303, headers });
}


function extractVerificationRow(payload: unknown): Record<string, unknown> | null {
  if (Array.isArray(payload) && isRecord(payload.at(0))) return payload.at(0)!;
  if (!isRecord(payload)) return null;
  if (Array.isArray(payload.result) && isRecord(payload.result.at(0))) {
    return payload.result.at(0)!;
  }
  if (Array.isArray(payload.data) && isRecord(payload.data.at(0))) {
    return payload.data.at(0)!;
  }
  return null;
}

async function verifySchema(request: Request, env: Env): Promise<Response> {
  const session = await readSession(request, env);
  if (
    session === null ||
    session.project?.ref !== env.POC_PROJECT_REF ||
    session.project.name !== env.POC_PROJECT_NAME ||
    session.project.organizationSlug !== env.POC_ORGANIZATION_SLUG
  ) {
    return html("<p>The exact POC project session is missing or expired.</p>", 401);
  }
  const history = await readMigrationHistory(session, env.POC_PROJECT_REF);
  if (
    history.kind !== "ok" ||
    !MIGRATIONS.every((migration) => migrationWasApplied(migration, history.history))
  ) {
    return html("<p>The complete canonical migration history was not confirmed.</p>", 409);
  }

  const response = await managementFetch(
    `/v1/projects/${encodeURIComponent(env.POC_PROJECT_REF)}/database/query`,
    session.accessToken,
    {
      method: "POST",
      // The Management API's read_only role correctly cannot execute RPCs that
      // are restricted to authenticated Planner users. The SQL itself remains
      // a fixed SELECT; use the normal Management query role to inspect the
      // capability result without changing production grants.
      body: JSON.stringify({ query: SCHEMA_VERIFICATION_SQL, read_only: false }),
    },
  );
  if (!response.ok) {
    const diagnostic = await sanitizedUpstreamError(response);
    console.error(
      JSON.stringify({ event: "schema_verification_query_failed", status: response.status, diagnostic }),
    );
    return html(
      `<p>Read-only schema verification failed (HTTP ${response.status}): ${escapeHtml(diagnostic)}.</p>`,
      502,
    );
  }
  const row = extractVerificationRow(await response.json());
  if (row === null) {
    return html("<p>The verification query returned an unexpected result shape.</p>", 502);
  }

  const checks = [
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
  ] as const;
  const failed = checks.filter((check) => row[check] !== true);
  const list = checks
    .map(
      (check) =>
        `<li>${escapeHtml(check)}: <strong>${row[check] === true ? "PASS" : "FAIL"}</strong></li>`,
    )
    .join("");
  const capabilities = isRecord(row.capabilities)
    ? escapeHtml(JSON.stringify(row.capabilities))
    : "unexpected";
  console.info(
    JSON.stringify({ event: "schema_verification_completed", passed: failed.length === 0 }),
  );
  return html(
    `<p>Fixed SELECT-only schema verification: <strong>${failed.length === 0 ? "PASS" : "FAIL"}</strong>.</p><ul>${list}</ul><p>Capabilities: <code>${capabilities}</code></p>`,
    failed.length === 0 ? 200 : 409,
  );
}

function buildRuntimeTestHarness(source: string): string | null {
  const assertionPattern = /^select (ok|is|throws_ok)\(/gmu;
  const assertions = source.match(assertionPattern);
  if (assertions?.length !== 43 || !source.includes("select plan(43);")) return null;
  if (!source.includes("select * from finish();\nrollback;")) return null;

  return source
    .replace(
      "select plan(43);",
      "create temporary table planner_poc_tap_results(result text) on commit drop;\n" +
        "grant insert, select on table pg_temp.planner_poc_tap_results to authenticated;\n" +
        "insert into planner_poc_tap_results(result) select plan(43);",
    )
    .replace(
      assertionPattern,
      "insert into planner_poc_tap_results(result) select $1(",
    )
    .replace(
      "select * from finish();\nrollback;",
      "insert into planner_poc_tap_results(result) select * from finish();\n" +
        "select jsonb_build_object(\n" +
        "  'assertions', count(*) filter (where result ~ '^(ok|not ok) [0-9]+ - '),\n" +
        "  'passed', count(*) filter (where result ~ '^ok [0-9]+ - '),\n" +
        "  'failures', count(*) filter (where result ~ '^not ok [0-9]+ - '),\n" +
        "  'plans', count(*) filter (where result = '1..43')\n" +
        ") as runtime_summary from planner_poc_tap_results;\n" +
        "rollback;",
    );
}

function findRuntimeSummary(value: unknown, depth = 0): Record<string, unknown> | null {
  if (depth > 8) return null;
  if (isRecord(value)) {
    if (
      typeof value.assertions === "number" &&
      typeof value.passed === "number" &&
      typeof value.failures === "number" &&
      typeof value.plans === "number"
    ) {
      return value;
    }
    for (const item of Object.values(value)) {
      const summary = findRuntimeSummary(item, depth + 1);
      if (summary !== null) return summary;
    }
  } else if (Array.isArray(value)) {
    for (const item of value) {
      const summary = findRuntimeSummary(item, depth + 1);
      if (summary !== null) return summary;
    }
  }
  return null;
}

async function runtimeTestPage(request: Request, env: Env): Promise<Response> {
  const session = await readSession(request, env);
  if (
    session === null ||
    session.csrf === undefined ||
    session.project?.ref !== env.POC_PROJECT_REF ||
    session.project.name !== env.POC_PROJECT_NAME ||
    session.project.organizationSlug !== env.POC_ORGANIZATION_SLUG
  ) {
    return html("<p>The exact POC project session is missing or expired.</p>", 401);
  }
  return html(
    `<p>The repository's existing 43-assertion pgTAP test will run inside its own transaction and finish with <code>ROLLBACK</code>. No test rows will persist.</p><form method="post" action="/poc/runtime-test"><input type="hidden" name="csrf" value="${escapeHtml(session.csrf)}"><button type="submit">Run rolled-back pgTAP verification</button></form>`,
  );
}

async function runRuntimeTest(request: Request, env: Env): Promise<Response> {
  const session = await readSession(request, env);
  if (
    session === null ||
    session.csrf === undefined ||
    session.project?.ref !== env.POC_PROJECT_REF ||
    session.project.name !== env.POC_PROJECT_NAME ||
    session.project.organizationSlug !== env.POC_ORGANIZATION_SLUG
  ) {
    return html("<p>The exact POC project session is missing or expired.</p>", 401);
  }
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (!Number.isFinite(contentLength) || contentLength > 2048) {
    return html("<p>The request is invalid.</p>", 400);
  }
  const form = await request.formData();
  const csrf = form.get("csrf");
  if (typeof csrf !== "string" || !(await timingSafeEqual(session.csrf, csrf))) {
    return html("<p>The request could not be validated.</p>", 403);
  }
  if ((await sha256Hex(titleHistoryRuntimeTest)) !== RUNTIME_TEST_SHA256) {
    return html("<p>The bundled pgTAP test digest does not match the repository baseline.</p>", 500);
  }
  const harness = buildRuntimeTestHarness(titleHistoryRuntimeTest);
  if (harness === null) {
    return html("<p>The pgTAP harness could not identify exactly 43 assertions.</p>", 500);
  }

  const response = await managementFetch(
    `/v1/projects/${encodeURIComponent(env.POC_PROJECT_REF)}/database/query`,
    session.accessToken,
    {
      method: "POST",
      body: JSON.stringify({ query: harness, read_only: false }),
    },
  );
  if (!response.ok) {
    const diagnostic = await sanitizedUpstreamError(response);
    console.error(
      JSON.stringify({ event: "runtime_test_failed", status: response.status, diagnostic }),
    );
    return html(
      `<p>The rolled-back runtime test failed to execute (HTTP ${response.status}): ${escapeHtml(diagnostic)}.</p>`,
      502,
    );
  }

  const payload: unknown = await response.json();
  const summary = findRuntimeSummary(payload);
  const assertions = summary?.assertions ?? 0;
  const passedAssertions = summary?.passed ?? 0;
  const failures = summary?.failures ?? 0;
  const plans = summary?.plans ?? 0;
  const passed = assertions === 43 && passedAssertions === 43 && failures === 0 && plans === 1;
  console.info(
    JSON.stringify({
      event: "runtime_test_completed",
      assertions,
      passedAssertions,
      failures,
      plans,
      passed,
    }),
  );
  if (!passed) {
    const diagnostic = escapeHtml(JSON.stringify(payload).slice(0, 12_000));
    return html(
      `<p>The test transaction rolled back, but its response could not be confirmed as 43 passing assertions.</p><p>Observed assertions: ${assertions}; passing: ${passedAssertions}; failing: ${failures}; plans: ${plans}.</p><details><summary>Bounded response shape</summary><pre>${diagnostic}</pre></details>`,
      409,
    );
  }
  return html(
    "<p>Hosted PostgreSQL runtime verification: <strong>PASS</strong>.</p><p>Assertions: 43; failures: 0. The transaction was rolled back.</p>",
  );
}

async function oauthCallback(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (url.searchParams.has("error")) {
    return html(
      "<p>Supabase authorization was cancelled or denied. No project was changed.</p>",
      400,
      [clearCookie(FLOW_COOKIE)],
    );
  }

  const code = url.searchParams.get("code");
  const returnedState = url.searchParams.get("state");
  const flowCookie = readCookie(request, FLOW_COOKIE);
  if (code === null || returnedState === null || flowCookie === null) {
    return html("<p>The OAuth response is incomplete. Start authorization again.</p>", 400);
  }

  const flow = await unseal<OAuthFlow>(flowCookie, env.OAUTH_SESSION_KEY);
  const fresh =
    flow !== null &&
    Number.isFinite(flow.issuedAt) &&
    Date.now() - flow.issuedAt >= 0 &&
    Date.now() - flow.issuedAt <= FLOW_TTL_SECONDS * 1000;
  if (!fresh || flow === null || !(await timingSafeEqual(flow.state, returnedState))) {
    return html(
      "<p>The OAuth state is invalid or expired. Start authorization again.</p>",
      400,
      [clearCookie(FLOW_COOKIE)],
    );
  }

  const token = await exchangeCode(code, flow.verifier, env);
  if (token === null) {
    console.error(JSON.stringify({ event: "oauth_token_exchange_failed" }));
    return html(
      "<p>Supabase authorization could not be completed. No project was changed.</p>",
      502,
      [clearCookie(FLOW_COOKIE)],
    );
  }

  const organizations = await loadOrganizations(token.accessToken);
  if (organizations === null) {
    console.error(JSON.stringify({ event: "organization_discovery_failed" }));
    return html(
      "<p>Organizations could not be loaded. No project was changed.</p>",
      502,
      [clearCookie(FLOW_COOKIE)],
    );
  }

  const sessionSeconds = Math.max(
    60,
    Math.min(SESSION_TTL_SECONDS, Math.floor(token.expiresIn) - 60),
  );
  const session: OAuthSession = {
    accessToken: token.accessToken,
    expiresAt: Date.now() + sessionSeconds * 1000,
  };
  const sealedSession = await seal(session, env.OAUTH_SESSION_KEY);
  const choices = organizations.length === 0
    ? "<p>No organizations with the requested access were returned.</p>"
    : `<p>Authorization succeeded. Select an organization for the disposable POC project, then return its name and slug to Codex:</p><ul>${organizations
        .map(
          (organization) =>
            `<li><strong>${escapeHtml(organization.name)}</strong> — <code>${escapeHtml(organization.slug)}</code></li>`,
        )
        .join("")}</ul>`;

  console.info(
    JSON.stringify({ event: "oauth_callback_succeeded", organizationCount: organizations.length }),
  );
  return html(choices, 200, [
    clearCookie(FLOW_COOKIE),
    secureCookie(SESSION_COOKIE, sealedSession, sessionSeconds),
  ]);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const productionCallback = await productionOAuthCallback(request, env);
    if (productionCallback !== null) return productionCallback;
    const managementAuthorization = await productionManagementAuthorization(
      request,
      env,
    );
    if (managementAuthorization !== null) return managementAuthorization;
    const production = await productionFetch(request, env);
    if (production !== null) return production;
    const url = new URL(request.url);

    // Planner user email confirmation landing page.
    //
    // Supabase Auth always redirects the browser to the configured redirect
    // target after it verifies a confirmation token. Landing here means a
    // device without the app (or a browser that refuses the custom scheme)
    // still sees an explicit result instead of a blank page.
    if (url.pathname === "/auth/confirmed") {
      return plannerEmailConfirmationPage(request);
    }

    if (request.method === "POST" && url.pathname === "/poc/migrations") {
      return applyMigrations(request, env);
    }

    if (request.method === "POST" && url.pathname === "/poc/runtime-test") {
      return runRuntimeTest(request, env);
    }

    if (request.method === "POST" && url.pathname === "/poc/projects") {
      return html("<p>Project creation is permanently disabled for this POC run.</p>", 410);
    }

    if (request.method !== "GET") {
      return new Response("Method not allowed", {
        status: 405,
        headers: { allow: "GET" },
      });
    }

    if (url.pathname === "/health") {
      return Response.json(
        { status: "ok", phase: env.POC_PHASE },
        { headers: { "cache-control": "no-store" } },
      );
    }

    if (url.pathname === "/oauth/start") {
      return oauthStart(env);
    }

    if (url.pathname === CALLBACK_PATH) {
      return oauthCallback(request, env);
    }

    if (url.pathname === "/poc/create") {
      return html("<p>Project creation is permanently disabled for this POC run.</p>", 410);
    }

    if (url.pathname === "/poc/reconcile") {
      return reconcileProject(request, env);
    }

    if (url.pathname === "/poc/status") {
      return projectStatus(request, env);
    }

    if (url.pathname === "/poc/migrations") {
      return migrationCapability(request, env);
    }

    if (url.pathname === "/poc/verify") {
      return verifySchema(request, env);
    }

    if (url.pathname === "/poc/runtime-test") {
      return runtimeTestPage(request, env);
    }

    if (url.pathname !== "/") {
      return new Response("Not found", { status: 404 });
    }

    return html(
      '<p>OAuth proof is ready.</p><p><a href="/oauth/start">Authorize Supabase</a></p>',
    );
  },
} satisfies ExportedHandler<Env>;

import { afterEach, describe, expect, it, vi } from "vitest";
import { PROVISIONING_WORKER_REVISION, logProvisioningResponse, productionProjectResolution } from "../src/production";

const TX = "0123456789abcdef0123456789abcdef";
const REF = "abcdefghijklmnopqrst";

function throwingTransaction(message: string) {
  return {
    get: async () => { throw new Error(message); },
    managementTokenStatus: async () => { throw new Error(message); },
  };
}

function environment(worker: Record<string, unknown>) {
  return {
    PROVISIONING_TRANSACTION: { idFromName: (name: string) => name, get: () => worker },
    MANAGEMENT_ACCOUNT_PROJECT: { idFromName: (name: string) => name, get: () => ({}) },
  };
}

function request(action: "resolve" | "adopt") {
  return new Request(`https://worker.test/v1/provisioning/transactions/${TX}/${action}`, {
    method: "POST",
    headers: { authorization: "Provisioning capability", "content-type": "application/json" },
    body: JSON.stringify(action === "adopt" ? { projectRef: REF } : {}),
  });
}

const resolveUrl = `https://worker.test/v1/provisioning/transactions/${TX}/resolve`;

afterEach(() => { vi.restoreAllMocks(); });

describe("resolve and adopt map Durable Object errors", () => {
  it("an expired transaction answers 410 provisioning_expired", async () => {
    for (const action of ["resolve", "adopt"] as const) {
      const response = await productionProjectResolution(request(action), environment(throwingTransaction("expired")) as any);
      expect(response!.status).toBe(410);
      expect(await response!.json()).toEqual({ error: "provisioning_expired" });
    }
  });

  it("a wrong capability answers 401 capability_invalid", async () => {
    for (const action of ["resolve", "adopt"] as const) {
      const response = await productionProjectResolution(request(action), environment(throwingTransaction("forbidden")) as any);
      expect(response!.status).toBe(401);
      expect(await response!.json()).toEqual({ error: "capability_invalid" });
    }
  });

  it("a stale step answers 409 state_conflict", async () => {
    for (const action of ["resolve", "adopt"] as const) {
      const response = await productionProjectResolution(request(action), environment(throwingTransaction("illegal_transition")) as any);
      expect(response!.status).toBe(409);
      expect(await response!.json()).toEqual({ error: "state_conflict" });
    }
  });

  it("an unknown failure is still a logged 500 internal_error", async () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    for (const action of ["resolve", "adopt"] as const) {
      const response = await productionProjectResolution(request(action), environment(throwingTransaction("boom")) as any);
      expect(response!.status).toBe(500);
      expect(await response!.json()).toEqual({ error: "internal_error" });
    }
    expect(spy).toHaveBeenCalledTimes(2);
  });
});

describe("provisioning response logging", () => {
  it("logs a permanent rejection as a warning with route, status and code only", async () => {
    const spy = vi.spyOn(console, "warn").mockImplementation(() => {});
    const response = Response.json({ error: "project_deleted" }, { status: 410 });
    const returned = await logProvisioningResponse(new Request(resolveUrl, { method: "POST" }), response);
    expect(returned).toBe(response);
    expect(spy).toHaveBeenCalledTimes(1);
    const first = String(spy.mock.calls[0]![0]);
    expect(JSON.parse(first)).toEqual({ event: "provisioning_http_rejected", route: "/v1/provisioning/transactions/:id/resolve", status: 410, code: "project_deleted" });
    expect(first).not.toContain(TX);
  });

  it("keeps the normal waiting answer at info level", async () => {
    const info = vi.spyOn(console, "info").mockImplementation(() => {});
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    await logProvisioningResponse(new Request(resolveUrl, { method: "POST" }), Response.json({ error: "oauth_expired" }, { status: 401 }));
    expect(info).toHaveBeenCalledTimes(1);
    const line = JSON.parse(String(info.mock.calls[0]![0]));
    expect(line.code).toBe("oauth_expired");
    expect(line.event).toBe("provisioning_http_rejected");
    expect(warn).not.toHaveBeenCalled();
  });

  it("logs a server failure as an error", async () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    await logProvisioningResponse(new Request(resolveUrl, { method: "POST" }), Response.json({ error: "temporarily_unavailable" }, { status: 502 }));
    expect(spy).toHaveBeenCalledTimes(1);
    expect(JSON.parse(String(spy.mock.calls[0]![0]))).toEqual({ event: "provisioning_http_failure", route: "/v1/provisioning/transactions/:id/resolve", status: 502 });
  });

  it("does not log a success", async () => {
    const info = vi.spyOn(console, "info").mockImplementation(() => {});
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    await logProvisioningResponse(new Request(resolveUrl, { method: "POST" }), Response.json({ state: "authorization_pending" }));
    expect(info).not.toHaveBeenCalled();
    expect(warn).not.toHaveBeenCalled();
    expect(error).not.toHaveBeenCalled();
  });

  it("tolerates a body that is not JSON", async () => {
    const spy = vi.spyOn(console, "info").mockImplementation(() => {});
    await logProvisioningResponse(new Request(resolveUrl, { method: "POST" }), new Response("<html></html>", { status: 400 }));
    expect(spy).toHaveBeenCalledTimes(1);
    expect(JSON.parse(String(spy.mock.calls[0]![0])).code).toBeNull();
  });

  it("leaves the response body readable", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const returned = await logProvisioningResponse(new Request(resolveUrl, { method: "POST" }), Response.json({ error: "project_deleted" }, { status: 410 }));
    expect(await returned.json()).toEqual({ error: "project_deleted" });
  });
});

describe("revision marker", () => {
  it("names this Worker build", () => {
    expect(PROVISIONING_WORKER_REVISION).toBe("2026-10-cloud-setup-c4");
  });
});

import { DurableObject } from "cloudflare:workers";

/** Legacy account mappings remain isolated; new creation guards use creation:slug object IDs. */
export class ManagementAccountProject extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS ownership (id INTEGER PRIMARY KEY CHECK(id=1), project_ref TEXT, transaction_id TEXT, organization_slug TEXT, project_name TEXT)");
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS creation_guard (id INTEGER PRIMARY KEY CHECK(id=1), transaction_id TEXT NOT NULL)");
    });
  }

  private row(): { project_ref: string | null; transaction_id: string | null; organization_slug: string | null; project_name: string | null } | null {
    return this.ctx.storage.sql.exec<{ project_ref: string | null; transaction_id: string | null; organization_slug: string | null; project_name: string | null }>("SELECT project_ref, transaction_id, organization_slug, project_name FROM ownership WHERE id=1").toArray()[0] ?? null;
  }

  async current() { return this.row(); }

  /** Guard one in-flight creation in a verified organization. This stores no project ownership. */
  async reserveCreation(transactionId: string) {
    const row = this.ctx.storage.sql.exec<{ transaction_id: string }>("SELECT transaction_id FROM creation_guard WHERE id=1").toArray()[0];
    if (row) return row.transaction_id === transactionId ? "self" : "other";
    this.ctx.storage.sql.exec("INSERT INTO creation_guard (id, transaction_id) VALUES (1, ?)", transactionId);
    return "self";
  }

  private creationOwner(): string | null {
    return this.ctx.storage.sql.exec<{ transaction_id: string }>("SELECT transaction_id FROM creation_guard WHERE id=1").toArray()[0]?.transaction_id ?? null;
  }

  /** Worker-internal identity of the transaction that currently blocks creation. */
  async currentCreationOwner(): Promise<string | null> {
    return this.creationOwner();
  }

  /**
   * Retires a guard only after the Worker proved that the exact project ref
   * durably recorded by [expectedTransactionId] now returns authoritative 404.
   * The project ref is required at this internal boundary so callers cannot
   * accidentally turn an owner-only stale check into a release operation.
   */
  async releaseConfirmedMissingCreation(expectedTransactionId: string, expectedProjectRef: string) {
    if (!/^[a-f0-9]{32}$/u.test(expectedTransactionId) || !/^[a-z]{20}$/u.test(expectedProjectRef)) return { kind: "conflict" as const };
    const owner = this.creationOwner();
    if (owner !== expectedTransactionId) return { kind: "conflict" as const };
    this.ctx.storage.sql.exec("DELETE FROM creation_guard WHERE id=1 AND transaction_id=?", expectedTransactionId);
    return { kind: "released" as const };
  }

  /** Release only after a proven pre-create abort or a fully verified READY project. */
  async releaseCreation(transactionId: string) {
    this.ctx.storage.sql.exec("DELETE FROM creation_guard WHERE id=1 AND transaction_id=?", transactionId);
  }

  /** The first exact binding wins. A stale local profile can never overwrite it. */
  async bind(projectRef: string, transactionId: string) {
    const row = this.row();
    if (row?.project_ref) return { kind: row.project_ref === projectRef ? "bound" : "conflict", projectRef: row.project_ref };
    if (row?.transaction_id && row.transaction_id !== transactionId) return { kind: "reserved", projectRef: null };
    this.ctx.storage.sql.exec("INSERT INTO ownership (id, project_ref, transaction_id) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET project_ref=excluded.project_ref, transaction_id=excluded.transaction_id, organization_slug=NULL, project_name=NULL", projectRef, transactionId);
    return { kind: "bound", projectRef };
  }

  /** Persist the intent before the external create call. No lease can expire into another create. */
  async reserve(transactionId: string, organizationSlug: string, projectName: string) {
    const row = this.row();
    if (row?.project_ref) return { kind: "mapped", projectRef: row.project_ref };
    if (row?.transaction_id) return { kind: row.transaction_id === transactionId ? "reserved_by_self" : "reserved_by_other", projectRef: null };
    this.ctx.storage.sql.exec("INSERT INTO ownership (id, project_ref, transaction_id, organization_slug, project_name) VALUES (1, NULL, ?, ?, ?)", transactionId, organizationSlug, projectName);
    return { kind: "reserved_by_self", projectRef: null };
  }

  /** Explicit replacement only after the Worker rechecked the exact mapped ref as 404. */
  async clearConfirmedDeleted(projectRef: string) {
    const row = this.row();
    if (!row?.project_ref || row.project_ref !== projectRef) return { kind: "conflict", projectRef: row?.project_ref ?? null };
    this.ctx.storage.sql.exec("DELETE FROM ownership WHERE id=1 AND project_ref=?", projectRef);
    return { kind: "cleared", projectRef: null };
  }
}

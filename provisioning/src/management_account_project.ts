import { DurableObject } from "cloudflare:workers";

/** One SQLite-backed object per verified Supabase Management gotrue_id. */
export class ManagementAccountProject extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS ownership (id INTEGER PRIMARY KEY CHECK(id=1), project_ref TEXT, transaction_id TEXT, organization_slug TEXT, project_name TEXT)");
    });
  }

  private row(): { project_ref: string | null; transaction_id: string | null; organization_slug: string | null; project_name: string | null } | null {
    return this.ctx.storage.sql.exec<{ project_ref: string | null; transaction_id: string | null; organization_slug: string | null; project_name: string | null }>("SELECT project_ref, transaction_id, organization_slug, project_name FROM ownership WHERE id=1").toArray()[0] ?? null;
  }

  async current() { return this.row(); }

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

import { DurableObject } from "cloudflare:workers";
import { MIGRATIONS as CANONICAL_MIGRATIONS, SCHEMA_VERIFICATION_SQL } from "./migrations";

const API="https://api.supabase.com", TX_TTL_MS=3_600_000, CREATE_LEASE_MS=90_000, OP_LEASE_MS=120_000, MAX_CREATE=2, MAX_OPS=8, MAX_BODY=4096, MAX_ORGANIZATIONS=100;
/**
 * How long a *pending* Management authorization may stay uncompleted.
 *
 * This is a browser round-trip window, not a retention period for a working
 * credential: the Worker releases (revokes) the OAuth grant as soon as the
 * operation the authorization was requested for has finished. Personal Planner
 * therefore holds no Management credential after setup reaches READY.
 */
export const MANAGEMENT_WINDOW_MS=15*60*1000;
const STATES=["authorization_pending","organization_selected","project_creating","project_reconciliation_required","project_retry_authorized","project_waiting","migrating","migration_reconciliation_required","verifying","ready","terminal_error","expired"] as const;
type State=typeof STATES[number]; type Code="oauth_expired"|"oauth_state_invalid"|"organization_not_found"|"organization_discovery_failed"|"project_creation_failed"|"project_identity_ambiguous"|"migration_failed"|"migration_history_mismatch"|"migration_bundle_invalid"|"verification_failed"|"verification_indeterminate"|"runtime_config_unavailable"|"provisioning_expired"|"rate_limited"|"operation_in_progress"|"invalid_request"|"revocation_failed"|"mapping_conflict"|"project_deleted"|"project_not_deleted"|"project_not_ready"|"candidate_discovery_failed"|"temporarily_unavailable";
type Op={kind:"create"|"migration"|"verification";nonce:string;startedAt:number;leaseExpiresAt:number};
type Tx={schema:2;state:State;createdAt:number;updatedAt:number;expiresAt:number;accessHash:string;oauthState?:string;oauthStateHash?:string;oauthVerifier?:string;oauthStateUsed?:boolean;oauthPurpose?:"provisioning"|"management";subject?:string;organizationSlug?:string;requestedProjectName?:string;idempotencyKey?:string;projectRef?:string;createAttempts:number;expensiveAttempts:number;operation?:Op;tokenCiphertext?:string;tokenExpiresAt?:number;verification?:boolean;runtimeConfig?:RuntimeConfig;error?:Code;
refreshCipher?:string;grantExpiresAt?:number;oauthAuthorizedAt?:number;oauthRevokedAt?:number;oauthReleaseUnconfirmed?:boolean;emailRedirectConfigured?:string;discoveryEmptyAt?:number;oauthFailure?:boolean};
export type Migration={name:string;query:string;sha256:string}; export type MigrationHistory={version?:string;name?:string}[]; type Management=(path:string,init?:RequestInit)=>Promise<Response>; export type VerificationResult="passed"|"assertion_failed"|"indeterminate"; export type MigrationResult={kind:"complete"}|{kind:"indeterminate"}|{kind:"failed";code:"migration_history_mismatch"|"migration_bundle_invalid"};
/**
 * The only client-safe runtime configuration a provisioned backend exposes.
 *
 * `emailConfirmationRedirect` is the exact Auth redirect this Worker verified
 * for the project, so the app can only ever send a confirmation email a value
 * that project's own allow list accepts. It is absent for a backend verified
 * before this field existed, and the app then keeps its original scheme-based
 * callback.
 */
type RuntimeConfig={projectRef:string;projectUrl:string;publishableKey:string;emailConfirmationRedirect?:string};
/** A user-owned Supabase organization offered for selection. */
export type Organization={id:string;name:string;slug:string};
/**
 * Response of POST /v1/provisioning/transactions.
 *
 * `accessToken` here is the short-lived provisioning capability for this
 * transaction. It is never a Supabase session token, never a Management
 * token, and must be stored separately from the client-safe runtime
 * configuration. It is deliberately not part of RuntimeConfig.
 */
export type ProvisioningGrant={transactionId:string;accessToken:string;authorizationUrl:string;expiresIn:number};
const NEXT:Record<State,readonly State[]>={authorization_pending:["organization_selected","ready","terminal_error","expired"],organization_selected:["project_creating","ready","terminal_error","expired"],project_creating:["project_reconciliation_required","project_waiting","expired"],project_reconciliation_required:["project_retry_authorized","project_waiting","terminal_error","expired"],project_retry_authorized:["project_creating","terminal_error","expired"],project_waiting:["migrating","expired"],migrating:["migration_reconciliation_required","verifying","terminal_error","expired"],migration_reconciliation_required:["migrating","terminal_error","expired"],verifying:["ready","terminal_error","expired"],ready:["expired"],terminal_error:["expired"],expired:[]};
export function canTransition(a:State,b:State){return NEXT[a].includes(b);} function record(v:unknown):v is Record<string,unknown>{return !!v&&typeof v==="object"&&!Array.isArray(v);} function nonce(){return crypto.randomUUID().replaceAll("-","");} function secret(){return btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replaceAll("+","-").replaceAll("/","_").replaceAll("=","");}
export function createReservationAllowed(state:State,createAttempts:number){return(state==="organization_selected"||state==="project_retry_authorized")&&createAttempts<MAX_CREATE;} export function oauthCredentialSaveAllowed(state:State,oauthStateUsed:boolean,storedStateHash:string|undefined,providedStateHash:string,transactionExpiresAt:number,tokenExpiresAt:number,now:number){return state==="authorization_pending"&&oauthStateUsed&&!!storedStateHash&&same(providedStateHash,storedStateHash)&&now<transactionExpiresAt&&tokenExpiresAt>now;} export function operationLeaseActive(operation:Op|undefined,now:number){return !!operation&&operation.leaseExpiresAt>now;}
async function hash(v:string){const d=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v));return btoa(String.fromCharCode(...new Uint8Array(d)));} function same(a:string,b:string){const x=Uint8Array.from(atob(a),c=>c.charCodeAt(0)),y=Uint8Array.from(atob(b),c=>c.charCodeAt(0));let d=x.length^y.length;for(let i=0;i<x.length;i++)d|=x[i]!^(y[i]??0);return d===0;} function move(t:Tx,s:State,code?:Code):Tx{if(!NEXT[t.state].includes(s))throw Error("illegal_transition");return {...t,state:s,updatedAt:Date.now(),error:code};}
function headers(){return new Headers({"cache-control":"no-store","content-type":"application/json","x-content-type-options":"nosniff","referrer-policy":"no-referrer","content-security-policy":"default-src 'none'; frame-ancestors 'none'; base-uri 'none'"});} function fail(code:Code,status=400){return Response.json({error:code},{status,headers:headers()});} function publicTx(t:Tx){const{accessHash,oauthState,oauthStateHash,oauthVerifier,oauthStateUsed,tokenCiphertext,tokenExpiresAt,operation,runtimeConfig,refreshCipher,grantExpiresAt,oauthAuthorizedAt,oauthRevokedAt,oauthPurpose,oauthReleaseUnconfirmed,emailRedirectConfigured,discoveryEmptyAt,oauthFailure,subject,...rest}=t;return{...rest,authorizationCompleted:subject!==undefined,authorizationFailed:t.state==="authorization_pending"&&subject===undefined&&(oauthFailure===true||(oauthStateUsed===true&&Date.now()-t.updatedAt>45_000)),operation:operation&&{kind:operation.kind,leaseExpiresAt:operation.leaseExpiresAt},runtimeConfig:t.state==="ready"&&validRuntimeConfig(runtimeConfig)?{projectRef:runtimeConfig.projectRef,projectUrl:runtimeConfig.projectUrl,publishableKey:runtimeConfig.publishableKey,...(runtimeConfig.emailConfirmationRedirect===undefined?{}:{emailConfirmationRedirect:runtimeConfig.emailConfirmationRedirect})}:null};}
async function cryptoKey(s:string){return crypto.subtle.importKey("raw",await crypto.subtle.digest("SHA-256",new TextEncoder().encode(s)),"AES-GCM",false,["encrypt","decrypt"]);} async function seal(v:string,s:string){const iv=crypto.getRandomValues(new Uint8Array(12));const e=await crypto.subtle.encrypt({name:"AES-GCM",iv,additionalData:new TextEncoder().encode("pp-provisioning-v2")},await cryptoKey(s),new TextEncoder().encode(v));return btoa(String.fromCharCode(...iv,...new Uint8Array(e)));} async function unseal(v:string,s:string){try{const x=Uint8Array.from(atob(v),c=>c.charCodeAt(0));const p=await crypto.subtle.decrypt({name:"AES-GCM",iv:x.slice(0,12),additionalData:new TextEncoder().encode("pp-provisioning-v2")},await cryptoKey(s),x.slice(12));return new TextDecoder().decode(p);}catch{return null;}}

/** Canonical Planner Auth callback URI. Mirrors AuthCallback.redirectUrl in lib/core/config/auth_callback.dart. */
export const PLANNER_AUTH_CALLBACK_URI="com.personalplanner.personalplanner://login-callback";
/**
 * Canonical Planner Management-authorization callback URI. Mirrors
 * ManagementCallback.redirectUrl in lib/core/config/management_callback.dart.
 *
 * The browser cannot answer a provisioning transaction, so it hands control
 * back to the app with this link. It carries no transaction id, capability,
 * Management token, or authorization code: the app already knows its own
 * durable attempt and simply resumes it.
 */
export const PLANNER_MANAGEMENT_CALLBACK_URI="com.personalplanner.personalplanner://management-callback";
/**
 * Path of the Worker-rendered Planner email confirmation landing page.
 *
 * Supabase Auth (GoTrue) always redirects the browser to `redirect_to` after it
 * verifies a token, so the only way to guarantee a usable page instead of a
 * blank/unknown-scheme page is to land on this HTTPS page first and let it hand
 * the PKCE authorization code back to the app.
 */
export const PLANNER_EMAIL_CONFIRMATION_PATH="/auth/confirmed";
/** Absolute email confirmation landing page for one Worker origin, or null. */
export function plannerEmailConfirmationUri(origin:string):string|null{try{const u=new URL(origin);return u.protocol==="https:"&&u.host.length>0?`${u.origin}${PLANNER_EMAIL_CONFIRMATION_PATH}`:null;}catch{return null;}}
/** Upper bound on Auth redirect entries this Worker carries forward. */
const MAX_AUTH_REDIRECT_ENTRIES=32;
function validAuthRedirectUri(v:unknown):v is string{return typeof v==="string"&&v.length>0&&v.length<=256&&/^[a-z][a-z0-9+._-]*:\/\/[^,\s]+$/iu.test(v);}
/**
 * Merges every Planner callback URI into an existing comma-separated Supabase
 * Auth redirect allow list without discarding or duplicating entries.
 *
 * Returns null when the input cannot be trusted, so the caller stays retryable
 * instead of overwriting configuration this Worker does not own.
 */
export function mergeAuthRedirectAllowLists(existing:unknown,redirectUris:readonly string[]):{list:string;changed:boolean}|null{if(redirectUris.length===0)return null;if(existing!==undefined&&existing!==null&&typeof existing!=="string")return null;if(redirectUris.some(v=>!validAuthRedirectUri(v)))return null;const entries=(typeof existing==="string"?existing:"").split(",").map(v=>v.trim()).filter(v=>v.length>0);if(entries.some(v=>!validAuthRedirectUri(v)))return null;const next=[...entries];let changed=false;for(const redirectUri of redirectUris){if(next.includes(redirectUri))continue;if(next.length>=MAX_AUTH_REDIRECT_ENTRIES)return null;next.push(redirectUri);changed=true;}return{list:next.join(","),changed};}
/** Single-URI form of [mergeAuthRedirectAllowLists]. */
export function mergeAuthRedirectAllowList(existing:unknown,redirectUri:string):{list:string;changed:boolean}|null{return mergeAuthRedirectAllowLists(existing,[redirectUri]);}
/**
 * Ensures a project's Supabase Auth config allows the canonical Planner
 * callbacks, preserving every redirect URL that was already configured.
 *
 * Reads the current config, patches the merged list, and re-reads it, so an
 * accepted-but-unapplied update is never mistaken for a ready backend. Only
 * this confidential Worker performs it; Flutter never receives a Management
 * token. Returning false keeps provisioning in its retryable verifying state
 * instead of publishing a backend whose confirmation email cannot return to
 * the app.
 */
export async function ensureAuthRedirectConfigured(ref:string,call:Management,extraUris:readonly string[]=[]):Promise<boolean>{if(!validProjectRef(ref))return false;const required=[PLANNER_AUTH_CALLBACK_URI,...extraUris];const path=`/v1/projects/${encodeURIComponent(ref)}/config/auth`;try{const current=await call(path);if(!current.ok)return false;const payload:unknown=await current.json();if(!record(payload))return false;const plan=mergeAuthRedirectAllowLists(payload.uri_allow_list,required);if(!plan)return false;if(plan.changed){const patched=await call(path,{method:"PATCH",headers:{"content-type":"application/json"},body:JSON.stringify({uri_allow_list:plan.list})});if(!patched.ok)return false;}const confirmed=await call(path);if(!confirmed.ok)return false;const after:unknown=await confirmed.json();if(!record(after)||typeof after.uri_allow_list!=="string")return false;const entries=after.uri_allow_list.split(",").map(v=>v.trim());return required.every(uri=>entries.includes(uri));}catch{return false;}}

export class ProvisioningTransaction extends DurableObject<Env>{
 constructor(ctx:DurableObjectState,env:Env){super(ctx,env);ctx.blockConcurrencyWhile(async()=>this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS transaction_record (id INTEGER PRIMARY KEY CHECK(id=1), body TEXT NOT NULL)"));}
 private load():Tx|null{const r=this.ctx.storage.sql.exec<{body:string}>("SELECT body FROM transaction_record WHERE id=1").toArray()[0];return r?JSON.parse(r.body) as Tx:null;} private save(t:Tx){this.ctx.storage.sql.exec("INSERT INTO transaction_record (id,body) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body",JSON.stringify(t));}
/**
 * Ends the provisioning transaction and destroys every credential it held: the
 * Management access token, any sealed refresh token, pending OAuth state, and
 * operation leases. Nothing Management-related outlives the attempt it belongs
 * to, so a transaction that never reaches READY cannot leave a grant behind.
 */
 private expire(t:Tx){this.save({...t,state:"expired",updatedAt:Date.now(),oauthState:undefined,oauthStateHash:undefined,oauthVerifier:undefined,oauthStateUsed:undefined,oauthPurpose:undefined,tokenCiphertext:undefined,tokenExpiresAt:undefined,refreshCipher:undefined,grantExpiresAt:undefined,operation:undefined});}
 private sealRefresh(token:string|undefined):Promise<string|undefined>{return token===undefined?Promise.resolve(undefined):seal(token,this.env.OAUTH_SESSION_KEY);}
 /** Capability check against a durable record whose transaction already ended. */
 private async authDurable(a:string):Promise<Tx>{const h=await this.prepare(a),t=this.load();if(!t||!same(h,t.accessHash))throw Error("forbidden");return t;}
 /** The Management refresh token of an attempt that has not released it yet. */
 async takeManagementRefresh(a:string):Promise<string|null>{const t=await this.authDurable(a),now=Date.now();if(!t.refreshCipher||!t.grantExpiresAt||t.oauthRevokedAt!==undefined||now>=t.grantExpiresAt)return null;return unseal(t.refreshCipher,this.env.OAUTH_SESSION_KEY);}
 /** Status of the durable Management grant, for the app's Advanced section. */
 async managementAuthorizationStatus(a:string){const t=await this.authDurable(a),now=Date.now();const retained=t.refreshCipher!==undefined&&t.oauthRevokedAt===undefined&&t.grantExpiresAt!==undefined&&now<t.grantExpiresAt;const pending=t.oauthPurpose==="management"&&t.oauthStateHash!==undefined&&!t.oauthStateUsed&&t.grantExpiresAt!==undefined&&now<t.grantExpiresAt;return{authorized:retained,pending,revokedAt:t.oauthRevokedAt??null,authorizationExpiresAt:t.grantExpiresAt??null,releaseUnconfirmed:t.oauthReleaseUnconfirmed===true,emailConfirmationRedirect:t.emailRedirectConfigured??null};}
 /**
  * Ends the Worker's use of the Management authorization: revokes the OAuth
  * grant through Supabase's documented revocation endpoint while the refresh
  * token is still held, then destroys every retained credential.
  *
  * This is what keeps the architecture least-privilege: the grant exists only
  * for the operation it was requested for. If Supabase cannot be reached, the
  * credential is still destroyed and the record says the revocation could not
  * be confirmed, so the app can tell the user to remove the application in
  * their Supabase account instead of pretending the grant is gone.
  */
 async releaseManagementGrant():Promise<{released:boolean;revoked:boolean;unconfirmed:boolean}>{
  const t=this.load();if(t===null)return{released:false,revoked:false,unconfirmed:false};
  const cipher=t.refreshCipher,clientId=this.env.SUPABASE_OAUTH_CLIENT_ID,clientSecret=this.env.SUPABASE_OAUTH_CLIENT_SECRET;
  let revoked=false,unconfirmed=false;
  if(cipher!==undefined){
   // Any retained grant that is not successfully revoked is reported as
   // unconfirmed, including the case where this Worker has no client
   // credentials to attempt the revocation with.
   const refresh=await unseal(cipher,this.env.OAUTH_SESSION_KEY);
   if(refresh!==null&&typeof clientId==="string"&&clientId.length>0&&typeof clientSecret==="string"&&clientSecret.length>0){
    try{const response=await fetch(`${API}/v1/oauth/revoke`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({client_id:clientId,client_secret:clientSecret,refresh_token:refresh}),signal:AbortSignal.timeout(8_000)});revoked=response.status===204;}catch{revoked=false;}
   }
   unconfirmed=!revoked;
  }
  const live=this.load();if(live!==null)this.save({...live,refreshCipher:undefined,tokenCiphertext:undefined,tokenExpiresAt:undefined,oauthState:undefined,oauthStateHash:undefined,oauthVerifier:undefined,oauthStateUsed:undefined,oauthPurpose:undefined,oauthAuthorizedAt:live.oauthAuthorizedAt??Date.now(),oauthRevokedAt:revoked?Date.now():live.oauthRevokedAt,oauthReleaseUnconfirmed:unconfirmed?true:undefined,updatedAt:Date.now()});
  return{released:true,revoked,unconfirmed};
 }
 /**
  * Starts a fresh Supabase Management authorization for this installation.
  *
  * Allowed once the transaction is durable, including after READY and after the
  * provisioning transaction itself expired: nothing in the provisioning state
  * machine is modified, so re-authorizing can never create, migrate, or verify
  * anything. It exists only for the management operation it is requested for
  * (currently the email-confirmation redirect check) and the grant is released
  * again as soon as that operation has run.
  */
 async beginManagementAuthorization(a:string){const t=await this.authDurable(a),now=Date.now();if(!t.projectRef||!validProjectRef(t.projectRef))throw Error("invalid_request");const state=secret(),verifier=secret(),oauthStateHash=await hash(state),grantExpiresAt=now+MANAGEMENT_WINDOW_MS;this.save({...t,oauthState:state,oauthStateHash,oauthVerifier:verifier,oauthStateUsed:false,oauthPurpose:"management",grantExpiresAt,updatedAt:now});await this.ctx.storage.setAlarm(now<t.expiresAt?t.expiresAt:grantExpiresAt);return{state,verifier,expiresIn:Math.floor(grantExpiresAt/1000)};}
 /** Records a successful revocation and drops every retained credential. */
 async markManagementRevoked(a:string){const t=await this.authDurable(a);this.save({...t,refreshCipher:undefined,oauthRevokedAt:Date.now(),oauthState:undefined,oauthStateHash:undefined,oauthVerifier:undefined,oauthStateUsed:undefined,oauthPurpose:undefined,tokenCiphertext:undefined,tokenExpiresAt:undefined,updatedAt:Date.now()});}
 private async prepare(access:string){return hash(access);} private authPrepared(h:string):Tx{const t=this.load();if(!t||!same(h,t.accessHash))throw Error("forbidden");if(Date.now()>=t.expiresAt||t.state==="expired"){this.expire(t);throw Error("expired");}return t;} private async auth(a:string){return this.authPrepared(await this.prepare(a));}
 async create(a:string,state:string,verifier:string){const[h,sh]=await Promise.all([this.prepare(a),hash(state)]);if(this.load())return publicTx(this.load()!);const now=Date.now();this.save({schema:2,state:"authorization_pending",createdAt:now,updatedAt:now,expiresAt:now+TX_TTL_MS,accessHash:h,oauthState:state,oauthStateHash:sh,oauthVerifier:verifier,createAttempts:0,expensiveAttempts:0});await this.ctx.storage.setAlarm(now+TX_TTL_MS);return publicTx(this.load()!);} async get(a:string){return publicTx(await this.auth(a));}
 /**
  * Claims one pending OAuth response.
  *
  * A claim is only valid for the exact state this Durable Object issued, for
  * the purpose it was issued for: the provisioning authorization of a live
  * `authorization_pending` transaction, or a Management re-authorization whose
  * browser round-trip is still within its window. A claim is single-use.
  */
 async oauthCallback(state:string){const h=await hash(state),t=this.load();if(!t||t.oauthStateUsed||!t.oauthStateHash||!same(h,t.oauthStateHash))return null;const now=Date.now(),management=t.oauthPurpose==="management";const live=management?t.grantExpiresAt!==undefined&&now<t.grantExpiresAt:t.state==="authorization_pending"&&now<t.expiresAt;if(!live){if(t.state!=="expired"&&now>=t.expiresAt)this.expire(t);return null;}this.save({...t,oauthStateUsed:true,updatedAt:now});return{verifier:t.oauthVerifier!,management};}
 /** A claimed callback that failed is visible to polling and can retry within this transaction. */
 async markOAuthFailure(state:string){const h=await hash(state),t=this.load();if(!t||t.oauthStateUsed!==true||!t.oauthStateHash||!same(h,t.oauthStateHash))return false;this.save({...t,oauthFailure:true,oauthState:undefined,oauthVerifier:undefined,updatedAt:Date.now()});return true;}
 /** Issues fresh PKCE state only after the previous callback was consumed without authorization. */
 async retryProvisioningAuthorization(a:string){const t=await this.auth(a);if(t.state!=="authorization_pending"||t.subject!==undefined||t.oauthStateUsed!==true)throw Error("invalid_request");const state=secret(),verifier=secret();this.save({...t,oauthState:state,oauthStateHash:await hash(state),oauthVerifier:verifier,oauthStateUsed:false,oauthFailure:undefined,updatedAt:Date.now()});return{state,verifier};}
 /**
  * Stores the exchanged credentials for a claimed OAuth response.
  *
  * [refreshToken] is retained sealed only for the operation that needs it and
  * is destroyed (after a revocation attempt) as soon as provisioning reaches
  * READY or a re-authorization has done its work. It is never returned by any
  * route; only the Worker's own revocation call reads it.
  */
 async saveOAuthFromCallback(state:string,token:string,refreshToken:string|undefined,expiresAt:number,subject:string,emailConfirmationRedirect?:string){const [h,cipher]=await Promise.all([hash(state),seal(token,this.env.OAUTH_SESSION_KEY)]);const t=this.load(),now=Date.now();if(t&&now>=t.expiresAt)this.expire(t);const current=this.load();if(!current)throw Error("oauth_expired");
 if(current.oauthPurpose==="management"){if(current.oauthStateUsed!==true||!current.oauthStateHash||!same(h,current.oauthStateHash)||current.grantExpiresAt===undefined||now>=current.grantExpiresAt||current.oauthRevokedAt!==undefined)throw Error("oauth_expired");const refresh=await this.sealRefresh(refreshToken);this.save({...current,subject,tokenCiphertext:cipher,tokenExpiresAt:expiresAt,oauthAuthorizedAt:now,oauthRevokedAt:undefined,refreshCipher:refresh??current.refreshCipher,oauthState:undefined,oauthStateHash:undefined,oauthVerifier:undefined,oauthStateUsed:undefined,oauthFailure:undefined,oauthPurpose:undefined,updatedAt:now});return;}
 if(!oauthCredentialSaveAllowed(current.state,!!current.oauthStateUsed,current.oauthStateHash,h,current.expiresAt,expiresAt,now))throw Error("oauth_expired");const refresh=await this.sealRefresh(refreshToken);this.save({...current,subject,tokenCiphertext:cipher,tokenExpiresAt:expiresAt,oauthAuthorizedAt:now,oauthRevokedAt:undefined,refreshCipher:refresh??current.refreshCipher,grantExpiresAt:current.grantExpiresAt??now+MANAGEMENT_WINDOW_MS,oauthState:undefined,oauthStateHash:undefined,oauthVerifier:undefined,oauthStateUsed:undefined,oauthFailure:undefined,updatedAt:now});}
 async saveOAuth(a:string,token:string,expiresAt:number,subject:string){const[h,cipher]=await Promise.all([this.prepare(a),seal(token,this.env.OAUTH_SESSION_KEY)]);const t=this.authPrepared(h),now=Date.now();if(t.state!=="authorization_pending"||expiresAt<=now)throw Error("oauth_expired");this.save({...t,subject,tokenCiphertext:cipher,tokenExpiresAt:expiresAt,oauthState:undefined,oauthStateHash:undefined,oauthVerifier:undefined,updatedAt:now});return publicTx(this.load()!);}
 async owner(a:string){const t=await this.auth(a);return t.subject??null;}
 async markDiscoveryEmpty(a:string){const t=await this.auth(a);if(t.state!=="authorization_pending"||!t.subject)throw Error("illegal_transition");this.save({...t,discoveryEmptyAt:Date.now(),updatedAt:Date.now()});}
 async adoptReady(a:string,config:RuntimeConfig){const t=await this.auth(a);if((t.state!=="authorization_pending"&&t.state!=="organization_selected")||!validRuntimeConfig(config))throw Error("illegal_transition");this.save(move({...t,projectRef:config.projectRef,runtimeConfig:config,verification:true,tokenCiphertext:undefined,tokenExpiresAt:undefined},"ready"));await this.releaseManagementGrant();return publicTx(this.load()!);}
 async selectOrganization(a:string,org:string,name:string,key:string){const t=await this.auth(a);if(t.state!=="authorization_pending"||!/^[a-z0-9-]{3,80}$/u.test(org)||!/^personal-planner-[a-z0-9-]{3,55}$/u.test(name)||key.length<32)throw Error("invalid_request");this.save(move({...t,organizationSlug:org,requestedProjectName:name,idempotencyKey:key},"organization_selected"));return publicTx(this.load()!);}
 async createContext(a:string){const t=await this.auth(a);return{state:t.state,projectRef:t.projectRef,organizationSlug:t.organizationSlug,requestedProjectName:t.requestedProjectName,operation:t.operation,discoveryEmptyAt:t.discoveryEmptyAt};}
 async reserveCreate(a:string){const t=await this.auth(a);if(!createReservationAllowed(t.state,t.createAttempts)||!t.organizationSlug||!t.requestedProjectName)throw Error("illegal_transition");const now=Date.now(),op:Op={kind:"create",nonce:nonce(),startedAt:now,leaseExpiresAt:now+CREATE_LEASE_MS};this.save(move({...t,createAttempts:t.createAttempts+1,operation:op},"project_creating"));return{nonce:op.nonce,organizationSlug:t.organizationSlug,requestedProjectName:t.requestedProjectName};}
 async claimCreateReconciliation(a:string){const t=await this.auth(a);if(t.state==="project_creating"){if(t.operation?.kind!=="create"||operationLeaseActive(t.operation,Date.now()))throw Error("operation_in_progress");this.save(move({...t,operation:undefined},"project_reconciliation_required","project_creation_failed"));}else if(t.state!=="project_reconciliation_required")throw Error("illegal_transition");return publicTx(this.load()!);}
 async createUncertain(a:string,n:string){const t=await this.auth(a);if(t.state!=="project_creating"||t.operation?.kind!=="create"||t.operation.nonce!==n)throw Error("stale_operation");this.save(move({...t,operation:undefined},"project_reconciliation_required","project_creation_failed"));}
 async recordProject(a:string,n:string,ref:string,recovered=false){const t=await this.auth(a),ok=recovered?t.state==="project_reconciliation_required":t.state==="project_creating"&&t.operation?.kind==="create"&&t.operation.nonce===n;if(!ok||!/^[a-z]{20}$/u.test(ref))throw Error("stale_operation");this.save(move({...t,projectRef:ref,operation:undefined},"project_waiting"));return publicTx(this.load()!);} async reconciliationAbsent(a:string){const t=await this.auth(a);if(t.state!=="project_reconciliation_required")throw Error("illegal_transition");this.save(move(t,"project_retry_authorized"));return publicTx(this.load()!);} async reconciliationAmbiguous(a:string){const t=await this.auth(a);if(t.state!=="project_reconciliation_required")throw Error("illegal_transition");this.save(move(t,"terminal_error","project_identity_ambiguous"));}
 async managementToken(a:string){const h=await this.prepare(a),t=this.authPrepared(h),cipher=t.tokenCiphertext,tokenExpiry=t.tokenExpiresAt;if(!cipher||!tokenExpiry||tokenExpiry<=Date.now())return null;const value=await unseal(cipher,this.env.OAUTH_SESSION_KEY),current=this.authPrepared(h);return current.tokenCiphertext===cipher&&current.tokenExpiresAt===tokenExpiry?value:null;}
 async claimOperation(a:string,kind:"migration"|"verification"){const t=await this.auth(a),now=Date.now();if(kind==="migration"&&t.state==="migrating"){if(t.operation?.kind!=="migration"||t.operation.leaseExpiresAt>now)throw Error("operation_in_progress");this.save(move({...t,operation:undefined},"migration_reconciliation_required","migration_failed"));throw Error("reconciliation_required");}const allowed=kind==="migration"?(t.state==="project_waiting"||t.state==="migration_reconciliation_required"):t.state==="verifying";if(!allowed||!t.projectRef||t.expensiveAttempts>=MAX_OPS)throw Error("illegal_transition");if(t.operation&&t.operation.leaseExpiresAt>now)throw Error("operation_in_progress");const op:Op={kind,nonce:nonce(),startedAt:now,leaseExpiresAt:now+OP_LEASE_MS},owned={...t,operation:op,expensiveAttempts:t.expensiveAttempts+1,updatedAt:now};this.save(kind==="verification"?owned:move(owned,"migrating"));return{nonce:op.nonce,projectRef:t.projectRef};}
 async finishMigration(a:string,n:string,result:MigrationResult){const t=await this.auth(a);if(t.state!=="migrating"||t.operation?.kind!=="migration"||t.operation.nonce!==n)throw Error("stale_operation");if(result.kind==="complete")this.save(move({...t,operation:undefined},"verifying"));else if(result.kind==="failed")this.save(move({...t,operation:undefined},"terminal_error",result.code));else this.save(move({...t,operation:undefined},"migration_reconciliation_required","migration_failed"));return publicTx(this.load()!);}
 /**
  * Completes fixed verification.
  *
  * A passed verification means provisioning is over, so the Worker also
  * releases the Management authorization it was holding: the OAuth grant is
  * revoked through Supabase's documented endpoint and every retained credential
  * is destroyed. Nothing Management-related survives READY.
  */
 async finishVerification(a:string,n:string,result:VerificationResult,runtimeConfig?:RuntimeConfig){const t=await this.auth(a);if(t.state!=="verifying"||t.operation?.kind!=="verification"||t.operation.nonce!==n)throw Error("stale_operation");if(result==="passed"){if(!validRuntimeConfig(runtimeConfig))throw Error("runtime_config_unavailable");this.save(move({...t,operation:undefined,verification:true,runtimeConfig,tokenCiphertext:undefined,tokenExpiresAt:undefined},"ready"));await this.releaseManagementGrant();}else if(result==="assertion_failed"){this.save(move({...t,operation:undefined,verification:false,tokenCiphertext:undefined,tokenExpiresAt:undefined},"terminal_error","verification_failed"));await this.releaseManagementGrant();}else this.save({...t,operation:undefined,updatedAt:Date.now(),error:"verification_indeterminate"});return publicTx(this.load()!);}
 /**
  * Ends an expired transaction. Expiry is also the backstop for least
  * privilege: any credential the transaction still holds (including a Management
  * refresh token of an attempt that never completed) is destroyed with it, so
  * nothing outlives the provisioning attempt it belongs to.
  */
 override async alarm(){const t=this.load();if(t&&Date.now()>=t.expiresAt&&t.state!=="expired")this.expire(t);}
}

async function json(r:Request){const n=Number(r.headers.get("content-length")??"0");if(!Number.isFinite(n)||n>MAX_BODY)return null;const x=await r.text();if(new TextEncoder().encode(x).byteLength>MAX_BODY)return null;try{const v:unknown=JSON.parse(x);return record(v)?v:null;}catch{return null;}} function cap(r:Request){const a=r.headers.get("authorization");return a?.startsWith("Provisioning ")?a.slice(13):null;} function tx(env:Env,id:string){return env.PROVISIONING_TRANSACTION.get(env.PROVISIONING_TRANSACTION.idFromName(`tx:${id}`));} function account(env:Env,subject:string){return env.MANAGEMENT_ACCOUNT_PROJECT.get(env.MANAGEMENT_ACCOUNT_PROJECT.idFromName(`management:${subject}`));} function projectRef(v:unknown){return record(v)&&(typeof v.ref==="string"?v.ref:typeof v.id==="string"?v.id:null)||null;} function management(token:string,path:string,init:RequestInit={}){const h=new Headers(init.headers);h.set("authorization",`Bearer ${token}`);return fetch(`${API}${path}`,{...init,headers:h,signal:AbortSignal.timeout(20_000)});}
async function sha(v:string){const d=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v));return Array.from(new Uint8Array(d),b=>b.toString(16).padStart(2,"0")).join("");} async function validBundle(){const h=await Promise.all(CANONICAL_MIGRATIONS.map(m=>sha(m.query)));return h.every((v,i)=>v===CANONICAL_MIGRATIONS[i]?.sha256);} export function reconcileMigrations(e:readonly Migration[],h:MigrationHistory):{next:number;error?:"migration_history_mismatch";unusable?:true}{const identities:HistoryIdentity[]=[];for(const raw of h){const identity=usableHistoryIdentity(raw);if(identity===null)return{next:0,unusable:true};identities.push(identity);}const index=new Map<string,number>();e.forEach((m,i)=>index.set(m.name,i));const seen=new Set<number>();let next=0;for(const identity of identities){const resolved=canonicalIdentity(identity,index);if(resolved.kind==="contradictory")return{next:0,error:"migration_history_mismatch"};if(resolved.kind==="foreign")continue;if(seen.has(resolved.index)||resolved.index!==next)return{next:0,error:"migration_history_mismatch"};seen.add(resolved.index);next=resolved.index+1;}return{next};}
/** Identity fields of one migration-history row, after runtime validation. */
type HistoryIdentity={name:string;version:string|null};
/**
 * Validates the identity fields of one history row.
 *
 * Returns null when the row cannot be trusted. The Management API always names
 * a migration, so a missing, empty, or non-string `name`, or a `version` that is
 * present but not a usable string, makes the whole response unusable. An explicit
 * `version: null` is treated as "no version".
 */
function usableHistoryIdentity(value:unknown):HistoryIdentity|null{if(!record(value))return null;const name=value.name;if(typeof name!=="string"||name.length===0)return null;const version=value.version;if(version===undefined||version===null)return{name,version:null};if(typeof version!=="string"||version.length===0)return null;return{name,version};}
type CanonicalIdentity={kind:"canonical";index:number}|{kind:"foreign"}|{kind:"contradictory"};
/**
 * Resolves one validated row to a canonical migration, a foreign row, or
 * contradictory evidence.
 *
 * An exact canonical full `name` identifies that migration on its own. Real
 * hosted Supabase history stores a separate `version` that is not necessarily
 * that migration's timestamp prefix, so a full name is never rejected for a
 * differing `version`. The alternate `<version>_<short-name>` representation is
 * still supported. Evidence is contradictory only when both interpretations
 * resolve to *different* canonical migrations. Rows that are not ours (platform
 * or external migrations) stay allowed and are ignored.
 */
function canonicalIdentity(row:HistoryIdentity,index:Map<string,number>):CanonicalIdentity{const direct=index.get(row.name),paired=row.version===null?undefined:index.get(`${row.version}_${row.name}`);if(direct!==undefined&&paired!==undefined&&direct!==paired)return{kind:"contradictory"};if(direct!==undefined)return{kind:"canonical",index:direct};if(paired!==undefined)return{kind:"canonical",index:paired};return{kind:"foreign"};}
/** Sanitized history shapes for diagnostics: field types and lengths only, never values. */
function historyShape(h:MigrationHistory):(string|number)[][]{return h.slice(0,8).map(x=>{const name=x?.name,version=x?.version;return[typeof name,typeof version,typeof name==="string"?name.length:0,typeof version==="string"?version.length:0];});}
/** Authoritative remote history contradicts canonical Planner order or identity. */
function historyMismatch(h:MigrationHistory):MigrationResult{console.info(JSON.stringify({event:"migration_history_mismatch",entries:h.length,shape:historyShape(h)}));return{kind:"failed",code:"migration_history_mismatch"};}
/** The history payload cannot be trusted, so nothing may be posted until it can. */
function historyUnusable(h:MigrationHistory):MigrationResult{console.info(JSON.stringify({event:"migration_history_unusable",entries:h.length,shape:historyShape(h)}));return{kind:"indeterminate"};}
export async function runCanonicalMigrations(ref:string,call:Management,options:{bundlesValid?:()=>Promise<boolean>}={}):Promise<MigrationResult>{if(!/^[a-z]{20}$/u.test(ref))return{kind:"failed",code:"migration_history_mismatch"};
if(!(await (options.bundlesValid??validBundle)()))return{kind:"failed",code:"migration_bundle_invalid"};const history=async()=>{try{const r=await call(`/v1/projects/${encodeURIComponent(ref)}/database/migrations`),p:unknown=r.ok?await r.json():null;return Array.isArray(p)&&p.every(record)?p as MigrationHistory:null;}catch{return null;}};let h=await history();if(!h)return{kind:"indeterminate"};let plan=reconcileMigrations(CANONICAL_MIGRATIONS,h);if(plan.unusable)return historyUnusable(h);if(plan.error)return historyMismatch(h);for(let i=plan.next;i<CANONICAL_MIGRATIONS.length;i++){const m=CANONICAL_MIGRATIONS[i]!;try{await call(`/v1/projects/${encodeURIComponent(ref)}/database/migrations`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({name:m.name,query:m.query})});}catch{return{kind:"indeterminate"};}h=await history();if(!h)return{kind:"indeterminate"};plan=reconcileMigrations(CANONICAL_MIGRATIONS,h);if(plan.unusable)return historyUnusable(h);if(plan.error)return historyMismatch(h);if(plan.next<=i)return{kind:"indeterminate"};}return{kind:"complete"};}
const CHECKS=["required_tables_exist","rls_enabled","required_rpcs_exist","protocol_v2_authenticated_execute","capability_grants_correct","f03_helper_private","f03_validates_branch_before_union","f03_wrappers_active","recurrence_provenance_present","relationships_owner_scoped","direct_authenticated_writes_revoked","capability_payload_current"] as const; export async function runFixedVerification(ref:string,call:Management,readOnly=false):Promise<VerificationResult>{if(!/^[a-z]{20}$/u.test(ref))return"indeterminate";try{const r=await call(`/v1/projects/${encodeURIComponent(ref)}/database/query`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({query:SCHEMA_VERIFICATION_SQL,read_only:readOnly})});if(!r.ok)return"indeterminate";const p:unknown=await r.json(),row=Array.isArray(p)&&record(p[0])?p[0]:record(p)&&Array.isArray(p.result)&&record(p.result[0])?p.result[0]:record(p)&&Array.isArray(p.data)&&record(p.data[0])?p.data[0]:null;return row&&CHECKS.every(k=>typeof row[k]==="boolean")?CHECKS.every(k=>row[k]===true)?"passed":"assertion_failed":"indeterminate";}catch{return"indeterminate";}}
type Compatibility="valid"|"invalid"|"missing"|"retryable";
/** Discovery reads six canonical migration identities and the fixed schema/RLS/capability checks. */
export async function plannerCompatibility(ref:string,call:Management):Promise<Compatibility>{
 if(!validProjectRef(ref))return"invalid";
 try{
  const exact=await call(`/v1/projects/${encodeURIComponent(ref)}`);
  if(exact.status===404)return"missing";
  if(!exact.ok)return"retryable";
  const detail:unknown=await exact.json();if(!record(detail)||projectRef(detail)!==ref)return"retryable";
  const historyResponse=await call(`/v1/projects/${encodeURIComponent(ref)}/database/migrations`);
  if(!historyResponse.ok)return"retryable";
  const history:unknown=await historyResponse.json();
  if(!Array.isArray(history)||!history.every(record))return"retryable";
  const plan=reconcileMigrations(CANONICAL_MIGRATIONS,history as MigrationHistory);
  if(plan.unusable)return"retryable";
  if(plan.error)return"retryable";
  // A canonical prefix means provisioning may still be underway. Treat it as
  // uncertain so discovery cannot report zero and offer another project.
  if(plan.next>0&&plan.next<CANONICAL_MIGRATIONS.length)return"retryable";
  if(plan.next===0)return"invalid";
  const schema=await runFixedVerification(ref,call,true);
  return schema==="passed"?"valid":"retryable";
 }catch{return"retryable";}
}
export type PlannerCandidate={projectRef:string;name:string;region?:string;createdAt?:string};
/** Full Management list only when there is no account mapping. An incomplete list never means zero. */
export async function discoverPlannerCandidates(call:Management):Promise<PlannerCandidate[]|null>{
 try{
  const response=await call("/v1/projects");if(!response.ok)return null;
  const payload:unknown=await response.json();
  const projects=Array.isArray(payload)?payload:record(payload)&&Array.isArray(payload.projects)?payload.projects:null;
  if(!projects||projects.length>=100)return null;
  const candidates:PlannerCandidate[]=[];
  for(const item of projects){
   const ref=projectRef(item);if(!validProjectRef(ref)||!record(item))return null;
   const compatible=await plannerCompatibility(ref,call);
   if(compatible==="retryable")return null;
   if(compatible!=="valid")continue;
   candidates.push({projectRef:ref,name:typeof item.name==="string"&&item.name.length<=200?item.name:ref,...(typeof item.region==="string"&&item.region.length<=80?{region:item.region}:{}),...(typeof item.created_at==="string"&&item.created_at.length<=80?{createdAt:item.created_at}:{})});
  }
  return candidates;
 }catch{return null;}
}
async function readyMappedProject(d:DurableObjectStub<ProvisioningTransaction>,access:string,ref:string,token:string,origin:string):Promise<Response>{
 const call=(path:string,init:RequestInit={})=>management(token,path,init);
 const compatible=await plannerCompatibility(ref,call);
 if(compatible==="missing"){console.info(JSON.stringify({event:"project_confirmed_deleted"}));return fail("project_deleted",410);}
 if(compatible!=="valid"){console.info(JSON.stringify({event:compatible==="invalid"?"project_not_ready":"project_verify_retryable_failure"}));return fail("project_not_ready",502);}
 const confirmationUri=plannerEmailConfirmationUri(origin);
 if(!(await ensureAuthRedirectConfigured(ref,call,confirmationUri===null?[]:[confirmationUri])))return fail("temporarily_unavailable",502);
 const config=await fetchRuntimeConfig(ref,call,confirmationUri===null?{}:{emailConfirmationRedirect:confirmationUri});
 if(!config)return fail("runtime_config_unavailable",502);
 console.info(JSON.stringify({event:"project_verify_ok"}));
 return Response.json(await d.adoptReady(access,config),{headers:headers()});
}
/** Exact mapping first; only unbound accounts may enumerate legacy candidates. */
export async function productionProjectResolution(r:Request,env:Env):Promise<Response|null>{
 const u=new URL(r.url),match=/^\/v1\/provisioning\/transactions\/([a-f0-9]{32})\/(resolve|adopt|replace-deleted)$/u.exec(u.pathname);
 if(!match)return null;
 if(r.method!=="POST")return new Response(null,{status:405,headers:new Headers({allow:"POST","cache-control":"no-store"})});
 const access=cap(r),input=await json(r);if(!access||!input)return fail("invalid_request",401);
 const d=tx(env,match[1]!),snapshot=await d.get(access);
 if(snapshot.state==="ready")return Response.json(snapshot,{headers:headers()});
 if(snapshot.state!=="authorization_pending"&&snapshot.state!=="organization_selected")return fail("invalid_request",409);
 const token=await d.managementToken(access),subject=await d.owner(access);
 if(!token||!subject)return fail("oauth_expired",401);
 const owner=account(env,subject),mapping=await owner.current();
 const proposed=typeof input.projectRef==="string"?input.projectRef:null;
 if(match[2]==="replace-deleted"){
  const mappedRef=mapping?.project_ref;
  if(!validProjectRef(mappedRef))return fail("mapping_conflict",409);
  let response:Response;
  try{response=await management(token,`/v1/projects/${encodeURIComponent(mappedRef)}`);}catch{return fail("temporarily_unavailable",502);}
  if(response.status!==404)return fail(response.ok?"project_not_deleted":"temporarily_unavailable",response.ok?409:502);
  const cleared=await owner.clearConfirmedDeleted(mappedRef);
  if(cleared.kind!=="cleared")return fail("mapping_conflict",409);
  console.info(JSON.stringify({event:"confirmed_deleted_mapping_cleared"}));
  return Response.json({kind:"mapping_cleared"},{headers:headers()});
 }
 if(mapping?.project_ref){
  if(proposed&&mapping.project_ref!==proposed)return Response.json({error:"mapping_conflict",projectRef:mapping.project_ref},{status:409,headers:headers()});
  console.info(JSON.stringify({event:"account_mapping_found"}));
  return readyMappedProject(d,access,mapping.project_ref,token,u.origin);
 }
 if(mapping?.transaction_id)return fail("operation_in_progress",409);
 if(snapshot.state!=="authorization_pending")return fail("invalid_request",409);
 if(match[2]==="adopt"){
  if(!validProjectRef(proposed))return fail("invalid_request");
  const compatibility=await plannerCompatibility(proposed,(p,i={})=>management(token,p,i));
  if(compatibility==="missing")return fail("project_deleted",410);
  if(compatibility==="retryable")return fail("temporarily_unavailable",502);
  if(compatibility!=="valid")return fail("verification_failed",409);
  const bound=await owner.bind(proposed,match[1]!);
  if(bound.kind!=="bound")return Response.json({error:"mapping_conflict",projectRef:bound.projectRef},{status:409,headers:headers()});
  console.info(JSON.stringify({event:"project_mapping_persisted"}));
  return readyMappedProject(d,access,proposed,token,u.origin);
 }
 if(proposed!==null)return fail("invalid_request");
 console.info(JSON.stringify({event:"account_mapping_missing"}));
 const candidates=await discoverPlannerCandidates((p,i={})=>management(token,p,i));
 if(candidates===null){console.info(JSON.stringify({event:"candidate_discovery_retryable_failure"}));return fail("candidate_discovery_failed",502);}
 if(candidates.length===0)await d.markDiscoveryEmpty(access);
 return Response.json({kind:"candidates",candidates},{headers:headers()});
}
async function accountScopedCreate(d:DurableObjectStub<ProvisioningTransaction>,env:Env,id:string,access:string,op:string):Promise<Response>{
 let c=await d.createContext(access);
 if(c.projectRef)return Response.json(await d.get(access),{headers:headers()});
 const token=await d.managementToken(access),subject=await d.owner(access);
 if(!token||!subject)return fail("oauth_expired",401);
 if(!c.discoveryEmptyAt)return fail("invalid_request",409);
 const owner=account(env,subject);
 const bound=await owner.current();
 if(bound?.project_ref)return Response.json({error:"mapping_conflict",projectRef:bound.project_ref},{status:409,headers:headers()});
 if(bound?.transaction_id&&bound.transaction_id!==id)return fail("operation_in_progress",409);
 if(c.state==="project_creating"){try{await d.claimCreateReconciliation(access);}catch{return fail("operation_in_progress",409);}}
 c=await d.createContext(access);
 if(c.state==="project_reconciliation_required"){
  // An uncertain POST has no trustworthy project_ref. A Management project
  // list (even a single exact name match) cannot prove which project it made.
  // Keep the account reservation so another device cannot issue a second POST.
  return fail("project_identity_ambiguous",409);
 }
 if(op==="reconcile")return fail("invalid_request",409);
 if((c.state!=="organization_selected"&&c.state!=="project_retry_authorized")||!c.organizationSlug||!c.requestedProjectName)return fail("invalid_request",409);
 const reservation=await owner.reserve(id,c.organizationSlug,c.requestedProjectName);
 if(reservation.kind==="mapped")return Response.json({error:"mapping_conflict",projectRef:reservation.projectRef},{status:409,headers:headers()});
 if(reservation.kind==="reserved_by_other")return fail("operation_in_progress",409);
 const attempt=await d.reserveCreate(access);
 console.info(JSON.stringify({event:"project_creation_started"}));
 try{
  const response=await management(token,"/v1/projects",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({name:attempt.requestedProjectName,organization_slug:attempt.organizationSlug,db_pass:secret(),region_selection:{type:"smartGroup",code:"apac"}})});
  const ref=response.ok?projectRef(await response.json()):null;
  if(!validProjectRef(ref)){await d.createUncertain(access,attempt.nonce);return fail("project_creation_failed",502);}
  const binding=await owner.bind(ref,id);
  if(binding.kind!=="bound")return fail("mapping_conflict",409);
  console.info(JSON.stringify({event:"project_mapping_persisted"}));
  return Response.json(await d.recordProject(access,attempt.nonce,ref),{headers:headers()});
 }catch{try{await d.createUncertain(access,attempt.nonce);}catch{}return fail("project_creation_failed",502);}
}
async function ready(ref:string,token:string){try{const r=await management(token,`/v1/projects/${encodeURIComponent(ref)}`),p:unknown=r.ok?await r.json():null;return record(p)&&p.status==="ACTIVE_HEALTHY";}catch{return false;}}
function validProjectRef(v:unknown):v is string{return typeof v==="string"&&/^[a-z]{20}$/u.test(v);}
function validRuntimeConfig(c:unknown):c is RuntimeConfig{return record(c)&&validProjectRef(c.projectRef)&&typeof c.projectUrl==="string"&&typeof c.publishableKey==="string"&&c.projectUrl===`https://${c.projectRef}.supabase.co`&&/^sb_publishable_[A-Za-z0-9_-]{16,256}$/u.test(c.publishableKey)&&(c.emailConfirmationRedirect===undefined||validAuthRedirectUri(c.emailConfirmationRedirect));}
function runtimeConfigFor(ref:string,publishableKey:string,emailConfirmationRedirect?:string):RuntimeConfig{return{projectRef:ref,projectUrl:`https://${ref}.supabase.co`,publishableKey,...(emailConfirmationRedirect===undefined?{}:{emailConfirmationRedirect})};}
/** Reads the project client key from Supabase Management and keeps only the publishable key. Secret keys are filtered out before anything is read, and an unusable response (no publishable key, several publishable keys, 429/5xx/network/malformed) returns null so provisioning stays retryable instead of publishing a fake ready configuration. */
export async function fetchRuntimeConfig(ref:string,call:Management,options:{emailConfirmationRedirect?:string}={}):Promise<RuntimeConfig|null>{if(!validProjectRef(ref))return null;try{const list=await call(`/v1/projects/${encodeURIComponent(ref)}/api-keys`);if(!list.ok)return null;const payload:unknown=await list.json();if(!Array.isArray(payload))return null;const publishable=payload.filter(e=>record(e)&&e.type==="publishable"&&typeof e.id==="string"&&/^[A-Za-z0-9_-]{1,128}$/u.test(e.id));if(publishable.length!==1)return null;const id=(publishable[0] as {id:string}).id,revealed=await call(`/v1/projects/${encodeURIComponent(ref)}/api-keys/${encodeURIComponent(id)}?reveal=true`);if(!revealed.ok)return null;const key:unknown=await revealed.json();if(!record(key)||key.type!=="publishable"||typeof key.api_key!=="string")return null;return /^sb_publishable_[A-Za-z0-9_-]{16,256}$/u.test(key.api_key)?runtimeConfigFor(ref,key.api_key,options.emailConfirmationRedirect):null;}catch{return null;}}
/** Maps the Management organization list into a bounded, production-owned shape. The upstream payload is never forwarded, and an unusable or oversized response returns null so discovery stays retryable. */
export async function listOrganizations(call:Management):Promise<Organization[]|null>{try{const r=await call("/v1/organizations"),p:unknown=r.ok?await r.json():null;if(!Array.isArray(p)||p.length>MAX_ORGANIZATIONS)return null;const out:Organization[]=[];for(const e of p){if(!record(e)||typeof e.id!=="string"||e.id.length===0||e.id.length>64||typeof e.name!=="string"||e.name.length>200||typeof e.slug!=="string"||e.slug.length===0||e.slug.length>120)return null;out.push({id:e.id,name:e.name,slug:e.slug});}return out;}catch{return null;}}
export async function productionFetch(r:Request,env:Env):Promise<Response|null>{const u=new URL(r.url);if(!u.pathname.startsWith("/v1/provisioning"))return null;if(r.method!=="GET"&&r.method!=="POST")return new Response(null,{status:405,headers:new Headers({allow:"GET, POST","cache-control":"no-store"})});try{if(u.pathname==="/v1/provisioning/transactions"&&r.method==="POST"){if(!(await json(r)))return fail("invalid_request");const id=nonce(),a=secret(),s=secret(),v=secret();await tx(env,id).create(a,s,v);const z=new URL(`${API}/v1/oauth/authorize`);z.search=new URLSearchParams({client_id:env.SUPABASE_OAUTH_CLIENT_ID,redirect_uri:env.SUPABASE_OAUTH_REDIRECT_URI,response_type:"code",code_challenge_method:"S256",code_challenge:await pkce(v),state:`${id}.${s}`}).toString();return Response.json({transactionId:id,accessToken:a,authorizationUrl:z.toString(),expiresIn:TX_TTL_MS/1000},{headers:headers()});}const m=/^\/v1\/provisioning\/transactions\/([a-f0-9]{32})(?:\/(organizations|organization|create|reconcile|migrate|verify))?$/u.exec(u.pathname),a=cap(r);if(!m)return fail("invalid_request",404);if(!a)return fail("invalid_request",401);const d=tx(env,m[1]!),op=m[2];if(r.method==="GET"&&!op)return Response.json(await d.get(a),{headers:headers()});if(op==="organizations"){if(r.method!=="GET")return fail("invalid_request");const t=await d.managementToken(a);if(!t)return fail("oauth_expired",401);const c=await d.createContext(a);if(c.state!=="authorization_pending"||!c.discoveryEmptyAt)return fail("invalid_request",409);const subject=await d.owner(a);if(!subject||await account(env,subject).current())return fail("mapping_conflict",409);const organizations=await listOrganizations((p,i={})=>management(t,p,i));if(organizations===null)return fail("organization_discovery_failed",502);return Response.json({organizations},{headers:headers()});}if(r.method!=="POST")return fail("invalid_request");const input=await json(r);if(!input)return fail("invalid_request");if(op==="organization"){const t=await d.managementToken(a);if(!t)return fail("oauth_expired",401);const slug=String(input.slug??""),o=await management(t,"/v1/organizations"),p:unknown=o.ok?await o.json():null;if(!Array.isArray(p)||!p.some(x=>record(x)&&x.slug===slug))return fail("organization_not_found",403);return Response.json(await d.selectOrganization(a,slug,String(input.projectName??""),String(input.idempotencyKey??"")),{headers:headers()});}if(op==="create"||op==="reconcile")return accountScopedCreate(d,env,m[1]!,a,op);
if(op==="migrate"){const t=await d.managementToken(a);if(!t)return fail("oauth_expired",401);const c=await d.claimOperation(a,"migration");if(!(await ready(c.projectRef,t)))return Response.json(await d.finishMigration(a,c.nonce,{kind:"indeterminate"}),{status:202,headers:headers()});const x=await runCanonicalMigrations(c.projectRef,(p,i={})=>management(t,p,i));return Response.json(await d.finishMigration(a,c.nonce,x),{status:x.kind==="complete"?200:202,headers:headers()});}if(op==="verify"){if((await d.get(a)).state==="ready")return Response.json(await d.get(a),{headers:headers()});const t=await d.managementToken(a);if(!t)return fail("oauth_expired",401);const c=await d.claimOperation(a,"verification"),x=await runFixedVerification(c.projectRef,(p,i={})=>management(t,p,i));if(x!=="passed")return Response.json(await d.finishVerification(a,c.nonce,x),{status:x==="indeterminate"?202:200,headers:headers()});const confirmationUri=plannerEmailConfirmationUri(u.origin),redirectReady=await ensureAuthRedirectConfigured(c.projectRef,(p,i={})=>management(t,p,i),confirmationUri===null?[]:[confirmationUri]);if(!redirectReady)return Response.json(await d.finishVerification(a,c.nonce,"indeterminate"),{status:202,headers:headers()});const runtimeConfig=await fetchRuntimeConfig(c.projectRef,(p,i={})=>management(t,p,i),confirmationUri===null?{}:{emailConfirmationRedirect:confirmationUri});if(!runtimeConfig)return Response.json(await d.finishVerification(a,c.nonce,"indeterminate"),{status:202,headers:headers()});return Response.json(await d.finishVerification(a,c.nonce,"passed",runtimeConfig),{status:200,headers:headers()});}return fail("invalid_request");}catch(e){const x=e instanceof Error?e.message:"",code:Code=x==="expired"?"provisioning_expired":x==="operation_in_progress"?"operation_in_progress":x==="oauth_expired"?"oauth_expired":x==="runtime_config_unavailable"?"runtime_config_unavailable":"invalid_request";return fail(code,code==="provisioning_expired"?410:code==="operation_in_progress"?409:code==="runtime_config_unavailable"?502:400);}}
/** HTML-escapes every dynamic value that reaches a hand-off page. */
function escapeHtml(value:string):string{return value.replace(/[&<>"']/gu,(character)=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[character]??character);}
const PAGE_STYLE=":root{color-scheme:dark}body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#121212;color:#f5f3ff;font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif}main{max-width:34rem;padding:2rem}img{height:3rem;margin-bottom:1.5rem}h1{font-size:1.5rem;margin:0 0 .75rem}p{line-height:1.55;margin:0 0 1rem;color:#ded9f5}.muted{font-size:.9rem;color:#a9a2c9}a.button{display:inline-block;background:#7c5cfc;color:#fff;text-decoration:none;padding:.7rem 1.25rem;border-radius:.6rem;font-weight:600}";
/** Browser hand-off page. No external resource, no form, and no inline data. */
function browserPage(options:{title:string;heading:string;body:string;actionHref?:string;actionLabel?:string;autoOpenHref?:string;muted?:string}):string{
  const action=options.actionHref!==undefined&&options.actionLabel!==undefined
    ?`<p><a class="button" id="open-planner" href="${escapeHtml(options.actionHref)}" rel="noreferrer">${escapeHtml(options.actionLabel)}</a></p>`
    :"";
  // The custom-scheme attempt runs inside a hidden frame, so a browser that
  // refuses the scheme still keeps this usable page (and its button) on screen.
  const autoOpen=options.autoOpenHref!==undefined
    ?`<script>(function(){var target=${JSON.stringify(options.autoOpenHref)};window.addEventListener("load",function(){try{var f=document.createElement("iframe");f.style.display="none";f.src=target;document.body.appendChild(f);window.setTimeout(function(){f.remove();},2000);}catch(e){}});})();</script>`
    :"";
  const muted=options.muted!==undefined?`<p class="muted">${escapeHtml(options.muted)}</p>`:"";
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>${escapeHtml(options.title)}</title><style>${PAGE_STYLE}</style></head><body><main><h1>${escapeHtml(options.heading)}</h1><p>${escapeHtml(options.body)}</p>${action}${muted}</main>${autoOpen}</body></html>`;
}
/** Script/style-capable CSP for the hand-off pages. No external loads. */
function pageHeaders():Headers{return new Headers({"cache-control":"no-store","content-security-policy":"default-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; frame-src com.personalplanner.personalplanner:","content-type":"text/html; charset=utf-8","referrer-policy":"no-referrer","x-content-type-options":"nosniff"});}
function pageResponse(body:string,status=200):Response{return new Response(body,{status,headers:pageHeaders()});}
/** Successful Supabase (Management) authorization: hand control back to the app. */
export function managementAuthorizationCompletedPage():string{return browserPage({title:"Personal Planner",heading:"Supabase authorization completed",body:"Personal Planner can now continue with your cloud setup. Return to the app to finish the remaining steps.",actionHref:`${PLANNER_MANAGEMENT_CALLBACK_URI}?result=completed`,actionLabel:"Open Personal Planner",autoOpenHref:`${PLANNER_MANAGEMENT_CALLBACK_URI}?result=completed`,muted:"You can close this page after returning to Personal Planner."});}
/** The user declined, or Supabase rejected, the authorization request. */
export function managementAuthorizationDeniedPage():string{return browserPage({title:"Personal Planner",heading:"Supabase authorization was cancelled",body:"Nothing was created or changed. You can return to Personal Planner and start the authorization again whenever you are ready.",actionHref:`${PLANNER_MANAGEMENT_CALLBACK_URI}?result=cancelled`,actionLabel:"Open Personal Planner",autoOpenHref:`${PLANNER_MANAGEMENT_CALLBACK_URI}?result=cancelled`,muted:"You can close this page after returning to Personal Planner."});}
/** The authorization response could not be matched to a live request. */
export function managementAuthorizationInvalidPage():string{return browserPage({title:"Personal Planner",heading:"This authorization link is no longer valid",body:"The Supabase authorization could not be matched to a request from this device. Nothing was created or changed.",actionHref:`${PLANNER_MANAGEMENT_CALLBACK_URI}?result=invalid`,actionLabel:"Open Personal Planner",autoOpenHref:`${PLANNER_MANAGEMENT_CALLBACK_URI}?result=invalid`,muted:"You can close this page after returning to Personal Planner."});}
/** The authorization code could not be exchanged. No secret is ever shown. */
export function managementAuthorizationFailedPage():string{return browserPage({title:"Personal Planner",heading:"Supabase authorization could not be completed",body:"Personal Planner could not finish talking to Supabase. Nothing was created or changed, and no credentials were stored.",actionHref:`${PLANNER_MANAGEMENT_CALLBACK_URI}?result=failed`,actionLabel:"Open Personal Planner",autoOpenHref:`${PLANNER_MANAGEMENT_CALLBACK_URI}?result=failed`,muted:"You can close this page after returning to Personal Planner."});}
/**
 * Planner user email confirmation landing page.
 *
 * Supabase Auth verifies the emailed token and then redirects the browser here,
 * so a device without the app (or with a browser that refuses the custom
 * scheme) still gets an explicit result instead of a blank page. When the
 * redirect carries a PKCE authorization code, the page offers to hand that code
 * to Personal Planner; a device that did not start the registration simply
 * returns to the app and logs in, which is the account-level verification this
 * flow promises. No token, session, or verifier is ever part of this page.
 */
export function plannerEmailConfirmationPage(request:Request):Response{
  const u=new URL(request.url);
  const code=u.searchParams.get("code");
  const errorCode=u.searchParams.get("error_code")??u.searchParams.get("error");
  const safeError=typeof errorCode==="string"&&/^[a-z0-9_]{1,64}$/iu.test(errorCode)?errorCode:"";
  const hasError=errorCode!==null||u.searchParams.get("error_description")!==null;
  if(hasError){return pageResponse(browserPage({title:"Personal Planner",heading:"This confirmation link could not be used",body:"The link may be expired, already used, or no longer valid. Nothing was changed on this device.",actionHref:PLANNER_AUTH_CALLBACK_URI,actionLabel:"Open Personal Planner",autoOpenHref:PLANNER_AUTH_CALLBACK_URI,muted:"Return to Personal Planner and sign in, or request a new confirmation email."}),400);}
  if(code===null||!/^[A-Za-z0-9._~+/=-]{4,512}$/u.test(code)){return pageResponse(browserPage({title:"Personal Planner",heading:"This confirmation link is incomplete",body:"Personal Planner could not read a confirmation code from this link. Nothing was changed on this device.",actionHref:PLANNER_AUTH_CALLBACK_URI,actionLabel:"Open Personal Planner",autoOpenHref:PLANNER_AUTH_CALLBACK_URI,muted:"Return to Personal Planner and sign in, or request a new confirmation email."}),400);}
  const deepLink=`${PLANNER_AUTH_CALLBACK_URI}?code=${encodeURIComponent(code)}`;
  return pageResponse(browserPage({title:"Personal Planner",heading:"Email verified successfully",body:"Your Planner account is confirmed. You can return to Personal Planner and log in on this device. Opening the confirmation on another device does not sign that device in.",actionHref:deepLink,actionLabel:"Open Personal Planner",autoOpenHref:deepLink,muted:"If you opened this link on a different device than the one you registered from, simply return to that device and log in. You can close this page after returning to Personal Planner."}));
}
export async function productionOAuthCallback(r:Request,env:Env):Promise<Response|null>{
  const u=new URL(r.url);
  if(u.pathname!=="/oauth/callback")return null;
  const returnedState=u.searchParams.get("state");
  if(returnedState===null||!returnedState.includes("."))return pageResponse(managementAuthorizationInvalidPage(),400);
  const split=returnedState.split(".",2),id=split[0],s=split[1];
  if(id===undefined||s===undefined||s.length===0||!/^[a-f0-9]{32}$/u.test(id))return pageResponse(managementAuthorizationInvalidPage(),400);
  if(u.searchParams.get("error")!==null){const d=tx(env,id),claim=await d.oauthCallback(s);if(claim!==null)await d.markOAuthFailure(s);return pageResponse(managementAuthorizationDeniedPage(),400);}
  const code=u.searchParams.get("code");
  if(code===null||code.length===0||code.length>4096){const d=tx(env,id),claim=await d.oauthCallback(s);if(claim!==null)await d.markOAuthFailure(s);return pageResponse(managementAuthorizationInvalidPage(),400);}
  const d=tx(env,id);
  const claim=await d.oauthCallback(s);
  if(claim===null)return pageResponse(managementAuthorizationInvalidPage(),400);
  const basic=btoa(`${env.SUPABASE_OAUTH_CLIENT_ID}:${env.SUPABASE_OAUTH_CLIENT_SECRET}`);
  let response:Response;
  try{response=await fetch(`${API}/v1/oauth/token`,{method:"POST",headers:{authorization:`Basic ${basic}`,"content-type":"application/x-www-form-urlencoded"},body:new URLSearchParams({code,code_verifier:claim.verifier,grant_type:"authorization_code",redirect_uri:env.SUPABASE_OAUTH_REDIRECT_URI}),signal:AbortSignal.timeout(15_000)});}catch{await d.markOAuthFailure(s);console.error(JSON.stringify({event:"oauth_token_exchange_unavailable"}));return pageResponse(managementAuthorizationFailedPage(),502);}
  if(!response.ok){await d.markOAuthFailure(s);console.error(JSON.stringify({event:"oauth_token_exchange_failed",status:response.status}));return pageResponse(managementAuthorizationFailedPage(),502);}
  let p:unknown;
  try{p=await response.json();}catch{await d.markOAuthFailure(s);console.error(JSON.stringify({event:"oauth_token_exchange_invalid_response"}));return pageResponse(managementAuthorizationFailedPage(),502);}
  if(!record(p)||typeof p.access_token!=="string"){await d.markOAuthFailure(s);console.error(JSON.stringify({event:"oauth_token_exchange_invalid_response"}));return pageResponse(managementAuthorizationFailedPage(),502);}
  const expires=typeof p.expires_in==="number"&&p.expires_in>60?p.expires_in:300;
  const refreshToken=typeof p.refresh_token==="string"&&p.refresh_token.length>=16&&p.refresh_token.length<=4096?p.refresh_token:undefined;
  // OAuth's token payload is not an account identity. The authenticated
  // Management profile supplies the stable gotrue_id used to key ownership.
  let subject:string;
  let profileStatus:number|null=null;
  try{const profile=await management(p.access_token,"/v1/profile");profileStatus=profile.status;const identity:unknown=profile.ok?await profile.json():null;if(!record(identity)||typeof identity.gotrue_id!=="string"||!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(identity.gotrue_id))throw Error("invalid_identity");subject=identity.gotrue_id.toLowerCase();}catch{await d.markOAuthFailure(s);console.error(JSON.stringify({event:"management_identity_unavailable",status:profileStatus}));return pageResponse(managementAuthorizationFailedPage(),502);}
  // A management re-authorization is the only chance to repair the email
  // confirmation redirect of an already-provisioned project.
  const confirmationUri=claim.management?plannerEmailConfirmationUri(u.origin):null;
  try{await d.saveOAuthFromCallback(s,p.access_token,refreshToken,Date.now()+expires*1000,subject,confirmationUri??undefined);}catch{await d.markOAuthFailure(s);console.error(JSON.stringify({event:"oauth_callback_not_live"}));return pageResponse(managementAuthorizationInvalidPage(),400);}
  console.info(JSON.stringify({event:"oauth_callback_succeeded",management:claim.management}));
  return pageResponse(managementAuthorizationCompletedPage());
}
async function pkce(v:string){const d=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v));return btoa(String.fromCharCode(...new Uint8Array(d))).replaceAll("+","-").replaceAll("/","_").replaceAll("=","");}
async function provisioningAuthorizationUrl(env:Env,id:string,state:string,verifier:string){const authorize=new URL(`${API}/v1/oauth/authorize`);authorize.search=new URLSearchParams({client_id:env.SUPABASE_OAUTH_CLIENT_ID,redirect_uri:env.SUPABASE_OAUTH_REDIRECT_URI,response_type:"code",code_challenge_method:"S256",code_challenge:await pkce(verifier),state:`${id}.${state}`}).toString();return authorize.toString();}
/**
 * Capability-authenticated Management authorization lifecycle of one durable
 * installation record.
 *
 * This route never mutates the provisioning state machine: it can only start a
 * fresh Supabase Management authorization, report whether a Management
 * credential is currently held, or revoke one. "Disconnect Supabase access" is a
 * real server-side revocation through Supabase's official
 * `POST /v1/oauth/revoke` endpoint, authenticated with this Worker's own client
 * credentials plus the user's OAuth refresh token. No Management token, refresh
 * token, or client secret is ever returned to the app.
 *
 * When the Worker holds no credential (the normal state after READY, because
 * the grant is released as soon as provisioning finishes), revocation reports
 * `revoked:false, reason:"not_retained"` instead of pretending it succeeded.
 */
/**
 * Authoritatively checks whether the project a device already uses still exists.
 *
 * The app can only learn this from Supabase itself, so the check runs inside a
 * Management authorization the user just granted in the browser (the device
 * starts the flow and then calls here with its short-lived capability):
 *
 * * 200 from the Management API is authoritative "exists" (the reported status
 *   is returned so a paused/inactive project is described accurately);
 * * 404 is authoritative "missing" — the user deleted the project;
 * * 401/403, 429, 5xx, transport failures and timeouts are `indeterminate` and
 *   must never be reported as deletion.
 *
 * The Management credential exists only for this check: it is released (the
 * OAuth grant is revoked through Supabase's documented endpoint) before the
 * response is returned, so nothing Management-related is retained afterwards.
 */
export async function productionProjectCheck(r:Request,env:Env):Promise<Response|null>{
  const u=new URL(r.url);
  const match=/^\/v1\/provisioning\/transactions\/([a-f0-9]{32})\/project-check$/u.exec(u.pathname);
  if(match===null)return null;
  if(r.method!=="POST")return new Response(null,{status:405,headers:new Headers({allow:"POST","cache-control":"no-store"})});
  const access=cap(r);
  if(access===null)return fail("invalid_request",401);
  const input=await json(r);
  if(input===null)return fail("invalid_request",400);
  const projectRef=typeof input.projectRef==="string"?input.projectRef:"";
  if(!validProjectRef(projectRef))return fail("invalid_request",400);
  const d=tx(env,match[1]!);
  try{
    const token=await d.managementToken(access);
    if(token===null)return fail("oauth_expired",401);
    const subject=await d.owner(access);
    if(!subject)return fail("oauth_expired",401);
    const owner=account(env,subject),mapping=await owner.current();
    if(mapping?.project_ref&&mapping.project_ref!==projectRef)return Response.json({error:"mapping_conflict",projectRef:mapping.project_ref},{status:409,headers:headers()});
    if(mapping?.transaction_id&&mapping.transaction_id!==match[1]){await d.releaseManagementGrant();return fail("operation_in_progress",409);}
    let projectExists:boolean|null=null,projectStatus="indeterminate",emailConfirmationRedirect:string|null=null;
    const compatible=await plannerCompatibility(projectRef,(path,init={})=>management(token,path,init));
    if(compatible==="missing"){projectExists=false;projectStatus="missing";}
    if(compatible==="invalid"){projectExists=null;projectStatus="not_compatible";}
    if(compatible==="retryable"){projectExists=null;projectStatus="indeterminate";}
    if(!mapping?.project_ref&&(compatible==="missing"||compatible==="invalid")){
      const candidates=await discoverPlannerCandidates((path,init={})=>management(token,path,init));
      if(candidates===null){await d.releaseManagementGrant();return fail("candidate_discovery_failed",502);}
      if(candidates.length>0)return Response.json({projectExists:null,projectStatus:"legacy_candidates",emailConfirmationRedirect:null,candidates,grantReleased:false},{headers:headers()});
      await d.releaseManagementGrant();
      return Response.json({projectExists:null,projectStatus:"legacy_empty",emailConfirmationRedirect:null,candidates:[],grantReleased:true},{headers:headers()});
    }
    if(compatible==="valid"){
      const binding=await owner.bind(projectRef,match[1]!);
      if(binding.kind!=="bound"){await d.releaseManagementGrant();return Response.json({error:"mapping_conflict",projectRef:binding.projectRef},{status:409,headers:headers()});}
      console.info(JSON.stringify({event:mapping?.project_ref?"account_mapping_found":"project_mapping_persisted"}));
      projectExists=true;projectStatus="verified";
    }
    if(projectExists===true){
      const confirmationUri=plannerEmailConfirmationUri(u.origin);
      const configured=await ensureAuthRedirectConfigured(projectRef,(path,init={})=>management(token,path,init),confirmationUri===null?[]:[confirmationUri]);
      if(configured)emailConfirmationRedirect=confirmationUri;
      else{projectExists=null;projectStatus="indeterminate";}
    }
    // Least privilege: this credential existed only for this check.
    await d.releaseManagementGrant();
    console.info(JSON.stringify({event:"project_check_completed",projectExists,projectStatus}));
    return Response.json({projectExists,projectStatus,emailConfirmationRedirect,grantReleased:true},{headers:headers()});
  }catch(error){
    const message=error instanceof Error?error.message:"";
    if(message==="expired")return fail("provisioning_expired",410);
    if(message==="forbidden")return fail("invalid_request",401);
    return fail("invalid_request",400);
  }
}
export async function productionManagementAuthorization(r:Request,env:Env):Promise<Response|null>{
  const u=new URL(r.url);
  const match=/^\/v1\/provisioning\/transactions\/([a-f0-9]{32})\/authorization(?:\/(start|revoke|retry))?$/u.exec(u.pathname);
  if(match===null)return null;
  const id=match[1]!,action=match[2],access=cap(r);
  if(access===null)return fail("invalid_request",401);
  const d=tx(env,id);
  try{
    if(action===undefined){
      if(r.method!=="GET")return new Response(null,{status:405,headers:new Headers({allow:"GET","cache-control":"no-store"})});
      return Response.json(await d.managementAuthorizationStatus(access),{headers:headers()});
    }
    if(r.method!=="POST")return new Response(null,{status:405,headers:new Headers({allow:"POST","cache-control":"no-store"})});
    if(action==="retry"){
      const grant=await d.retryProvisioningAuthorization(access);
      return Response.json({authorizationUrl:await provisioningAuthorizationUrl(env,id,grant.state,grant.verifier)},{headers:headers()});
    }
    if(action==="start"){
      const grant=await d.beginManagementAuthorization(access);
      const authorize=new URL(`${API}/v1/oauth/authorize`);
      authorize.search=new URLSearchParams({client_id:env.SUPABASE_OAUTH_CLIENT_ID,redirect_uri:env.SUPABASE_OAUTH_REDIRECT_URI,response_type:"code",code_challenge_method:"S256",code_challenge:await pkce(grant.verifier),state:`${id}.${grant.state}`}).toString();
      return Response.json({authorizationUrl:authorize.toString(),expiresIn:grant.expiresIn},{headers:headers()});
    }
    const refreshToken=await d.takeManagementRefresh(access);
    if(refreshToken===null)return Response.json({revoked:false,reason:"not_retained"},{headers:headers()});
    const response=await fetch(`${API}/v1/oauth/revoke`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({client_id:env.SUPABASE_OAUTH_CLIENT_ID,client_secret:env.SUPABASE_OAUTH_CLIENT_SECRET,refresh_token:refreshToken}),signal:AbortSignal.timeout(15_000)});
    if(response.status===204){await d.markManagementRevoked(access);console.info(JSON.stringify({event:"management_authorization_revoked"}));return Response.json({revoked:true,reason:"revoked"},{headers:headers()});}
    console.error(JSON.stringify({event:"management_revocation_failed",status:response.status}));
    return fail("revocation_failed",response.status===429?429:502);
  }catch(error){
    const message=error instanceof Error?error.message:"";
    if(message==="forbidden")return fail("invalid_request",401);
    return fail("invalid_request",400);
  }
}
export function redact(v:string){return v.replace(/(?:Bearer\s+|Basic\s+)?(?:eyJ[A-Za-z0-9._-]+|sb_(?:secret|publishable)_[A-Za-z0-9_-]+|sba_[A-Za-z0-9_-]+|[A-Za-z0-9_-]{24,})(?=\b)/gu,"[redacted]").replace(/(authorization|cookie|password|code|refresh_token)=[^\s&]+/giu,"$1=[redacted]").slice(0,300);}
export default{fetch:(r:Request,e:Env)=>productionFetch(r,e).then(x=>x??new Response("Not found",{status:404}))}satisfies ExportedHandler<Env>;

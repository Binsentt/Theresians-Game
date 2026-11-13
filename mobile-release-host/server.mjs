import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { pipeline } from "node:stream/promises";
import { Transform } from "node:stream";
import { fileURLToPath } from "node:url";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_BUNDLE_ID = "com.theresiansquest.game";
const MAX_METADATA_BYTES = 128 * 1024;
const MAX_IPA_BYTES = 2 * 1024 * 1024 * 1024;
const MAX_NOTES_LENGTH = 24_000;
const MAX_CAPABILITY_SECONDS = 24 * 60 * 60;

function json(response, status, value, extraHeaders = {}) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    ...extraHeaders,
  });
  response.end(JSON.stringify(value));
}

function text(response, status, value, contentType = "text/plain; charset=utf-8", extraHeaders = {}) {
  response.writeHead(status, {
    "Content-Type": contentType,
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    ...extraHeaders,
  });
  response.end(value);
}

function secureEquals(left, right) {
  const a = Buffer.from(String(left));
  const b = Buffer.from(String(right));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function validateBaseUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error("OTA_PUBLIC_BASE_URL must be an absolute HTTPS URL.");
  }
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) {
    throw new Error("OTA_PUBLIC_BASE_URL must use HTTPS and contain no credentials, query, or fragment.");
  }
  if (url.pathname !== "/" || /(^|\.)github\.com$/i.test(url.hostname) || /(^|\.)githubusercontent\.com$/i.test(url.hostname)) {
    throw new Error("OTA_PUBLIC_BASE_URL must be a dedicated HTTPS host, not a GitHub URL or path.");
  }
  return url;
}

function validReleaseId(value) {
  return /^[0-9]+\.[0-9]+\.[0-9]+-[1-9][0-9]*$/.test(value);
}

function validateMetadata(value, expectedId, bundleId) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Release metadata must be a JSON object.");
  const { release_id, bundle_id, marketing_version, build_number, source_commit, ipa_sha256, release_notes } = value;
  if (release_id !== expectedId || !validReleaseId(release_id)) throw new Error("Release ID must match the validated version-build format.");
  if (bundle_id !== bundleId) throw new Error("Release bundle ID does not match the configured application.");
  if (typeof marketing_version !== "string" || !/^\d+\.\d+\.\d+$/.test(marketing_version)) throw new Error("Marketing version must be major.minor.patch.");
  if (release_id !== `${marketing_version}-${build_number}` || !Number.isSafeInteger(Number(build_number)) || Number(build_number) < 1 || Number(build_number) > 2147483647) {
    throw new Error("Release ID, marketing version, and positive build number must agree.");
  }
  if (typeof source_commit !== "string" || !/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/i.test(source_commit)) throw new Error("Source commit must be a full Git SHA.");
  if (typeof ipa_sha256 !== "string" || !/^[0-9a-f]{64}$/i.test(ipa_sha256)) throw new Error("IPA SHA-256 must contain 64 hexadecimal characters.");
  if (typeof release_notes !== "string" || release_notes.length > MAX_NOTES_LENGTH) throw new Error("Release notes must be text within the configured size limit.");
  return {
    release_id,
    bundle_id,
    marketing_version,
    build_number: String(build_number),
    source_commit: source_commit.toLowerCase(),
    ipa_sha256: ipa_sha256.toLowerCase(),
    release_notes,
  };
}

function createManifest({ ipaUrl, bundleId, marketingVersion, buildNumber, releaseId, title }) {
  const ipa = new URL(ipaUrl);
  if (ipa.protocol !== "https:" || ipa.username || ipa.password || ipa.hash || /(^|\.)github\.com$/i.test(ipa.hostname) || /(^|\.)githubusercontent\.com$/i.test(ipa.hostname)) {
    throw new Error("Manifest IPA URL must be a dedicated HTTPS URL without credentials, a fragment, or GitHub hosting.");
  }
  if (bundleId !== DEFAULT_BUNDLE_ID) throw new Error("Unexpected manifest bundle identifier.");
  if (!/^\d+\.\d+\.\d+$/.test(marketingVersion)) throw new Error("Invalid manifest marketing version.");
  if (!/^[1-9][0-9]*$/.test(String(buildNumber)) || !Number.isSafeInteger(Number(buildNumber)) || Number(buildNumber) > 2147483647) throw new Error("Invalid manifest build number.");
  if (releaseId !== `${marketingVersion}-${buildNumber}`) throw new Error("Release ID must match the marketing version and build number.");
  const escape = (value) => String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&apos;");
  return `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n  <key>items</key>\n  <array>\n    <dict>\n      <key>assets</key>\n      <array>\n        <dict>\n          <key>kind</key><string>software-package</string>\n          <key>url</key><string>${escape(ipa.toString())}</string>\n        </dict>\n      </array>\n      <key>metadata</key>\n      <dict>\n        <key>bundle-identifier</key><string>${escape(bundleId)}</string>\n        <key>bundle-version</key><string>${escape(buildNumber)}</string>\n        <key>kind</key><string>software</string>\n        <key>title</key><string>${escape(title)}</string>\n      </dict>\n    </dict>\n  </array>\n</dict>\n</plist>\n`;
}

async function readBody(request, limit) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > limit) throw Object.assign(new Error("Request body exceeds the allowed size."), { status: 413 });
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

function readCookie(header, name) {
  for (const part of (header || "").split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) return rest.join("=");
  }
  return "";
}

function hashFile(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("error", reject);
    stream.on("end", () => resolve(hash.digest("hex")));
  });
}

function rangeFor(header, size) {
  if (!header) return null;
  const match = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!match || (!match[1] && !match[2])) return false;
  let start = match[1] ? Number(match[1]) : Math.max(0, size - Number(match[2]));
  let end = match[2] && match[1] ? Number(match[2]) : size - 1;
  if (!match[1]) end = size - 1;
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end < start || start >= size) return false;
  return { start, end: Math.min(end, size - 1) };
}

function createApp(config) {
  const baseUrl = validateBaseUrl(config.publicBaseUrl);
  if (!config.installPassword || Buffer.byteLength(config.installPassword) < 16) throw new Error("OTA_INSTALL_PASSWORD must be at least 16 bytes.");
  if (!config.uploadToken || Buffer.byteLength(config.uploadToken) < 32) throw new Error("OTA_UPLOAD_TOKEN must be at least 32 bytes.");
  if (!config.capabilitySecret || Buffer.byteLength(config.capabilitySecret) < 32) throw new Error("OTA_CAPABILITY_SECRET must be at least 32 bytes.");
  const bundleId = config.bundleId || DEFAULT_BUNDLE_ID;
  if (bundleId !== DEFAULT_BUNDLE_ID) throw new Error("OTA_BUNDLE_ID must remain com.theresiansquest.game.");
  const sessionSeconds = Number(config.sessionSeconds || 3600);
  const capabilitySeconds = Number(config.capabilitySeconds || 21600);
  if (!Number.isInteger(sessionSeconds) || sessionSeconds < 300 || sessionSeconds > 86400) throw new Error("OTA_SESSION_SECONDS must be 300–86400.");
  if (!Number.isInteger(capabilitySeconds) || capabilitySeconds < 600 || capabilitySeconds > MAX_CAPABILITY_SECONDS) throw new Error("OTA_CAPABILITY_SECONDS must be 600–86400.");
  const storage = path.resolve(config.storageDir);
  const stagingDir = path.join(storage, "staging");
  const releasesDir = path.join(storage, "releases");
  const limiter = new Map();
  let publishQueue = Promise.resolve();

  const ensureStore = async () => {
    await fs.promises.mkdir(stagingDir, { recursive: true, mode: 0o700 });
    await fs.promises.mkdir(releasesDir, { recursive: true, mode: 0o700 });
  };
  const latestPath = path.join(storage, "latest.json");
  const releasePath = (id) => path.join(releasesDir, id);
  const stagingPath = (id) => path.join(stagingDir, id);
  const sign = (scope, id, expiry) => crypto.createHmac("sha256", config.capabilitySecret).update(`${scope}\n${id}\n${expiry}`).digest("hex");
  const capabilityUrl = (scope, id, expiry) => {
    const route = scope === "manifest" ? "manifest.plist" : "app.ipa";
    const url = new URL(`/ota/${encodeURIComponent(id)}/${route}`, baseUrl);
    url.searchParams.set("e", String(expiry));
    url.searchParams.set("s", sign(scope, id, expiry));
    return url.toString();
  };
  const validCapability = (scope, id, url) => {
    if ([...url.searchParams.keys()].sort().join(",") !== "e,s" || url.searchParams.getAll("e").length !== 1 || url.searchParams.getAll("s").length !== 1) return false;
    const expiryText = url.searchParams.get("e") || "";
    const signature = url.searchParams.get("s") || "";
    if (!/^\d{10}$/.test(expiryText) || !/^[0-9a-f]{64}$/.test(signature)) return false;
    const expiry = Number(expiryText);
    const now = Math.floor(Date.now() / 1000);
    if (expiry < now || expiry > now + MAX_CAPABILITY_SECONDS) return false;
    return secureEquals(signature, sign(scope, id, expiry));
  };
  const verifySession = (request) => {
    const value = readCookie(request.headers.cookie, "ota_session");
    const [expiryText, signature, extra] = value.split(".");
    if (extra || !/^\d{10}$/.test(expiryText || "") || !/^[0-9a-f]{64}$/.test(signature || "")) return false;
    const expiry = Number(expiryText);
    return expiry >= Math.floor(Date.now() / 1000) && secureEquals(signature, sign("session", "install", expiry));
  };
  const verifyAdmin = (request) => {
    const header = request.headers.authorization || "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    return secureEquals(token, config.uploadToken);
  };
  const rateAllowed = (ip) => {
    const now = Date.now();
    if (limiter.size > 10000) {
      for (const [key, value] of limiter) if (now - value.start > 15 * 60 * 1000) limiter.delete(key);
    }
    const item = limiter.get(ip);
    if (!item || now - item.start > 15 * 60 * 1000) {
      limiter.set(ip, { start: now, count: 1 });
      return true;
    }
    item.count += 1;
    return item.count <= 8;
  };
  const loadRelease = async (id) => {
    if (!validReleaseId(id)) return null;
    const folder = releasePath(id);
    const folderStat = await fs.promises.lstat(folder);
    if (!folderStat.isDirectory()) throw new Error("Published release directory is not a regular directory.");
    const metadataPath = path.join(folder, "release.json");
    const ipaPath = path.join(folder, "app.ipa");
    const [metadataStat, ipaStat] = await Promise.all([
      fs.promises.lstat(metadataPath),
      fs.promises.lstat(ipaPath),
    ]);
    if (!metadataStat.isFile() || !ipaStat.isFile() || ipaStat.size < 1) {
      throw new Error("Published release metadata or IPA is missing or not a regular nonempty file.");
    }
    const metadata = JSON.parse(await fs.promises.readFile(metadataPath, "utf8"));
    return { metadata, ipaPath: path.join(folder, "app.ipa"), ipaSize: ipaStat.size };
  };
  const historyError = (message) => Object.assign(new Error(message), { status: 409 });
  const inspectPublishedHistory = async () => {
    const entries = await fs.promises.readdir(releasesDir, { withFileTypes: true });
    const releases = new Map();
    let highest = null;
    for (const entry of entries) {
      if (!entry.isDirectory() || !validReleaseId(entry.name)) {
        throw historyError("Published release storage contains an unexpected entry; stop and inspect release history.");
      }
      let release;
      try {
        release = await loadRelease(entry.name);
        release.metadata = validateMetadata(release.metadata, entry.name, bundleId);
      } catch {
        throw historyError(`Published release ${entry.name} is missing, malformed, or incompatible; stop and inspect release history.`);
      }
      const buildNumber = Number(release.metadata.build_number);
      if (releases.has(buildNumber)) {
        throw historyError(`Published release history contains duplicate build number ${buildNumber}; explicit recovery is required.`);
      }
      releases.set(buildNumber, release);
      if (!highest || buildNumber > Number(highest.metadata.build_number)) highest = release;
    }

    let raw;
    try {
      raw = await fs.promises.readFile(latestPath, "utf8");
    } catch (error) {
      if (error.code === "ENOENT") {
        if (releases.size > 0) throw historyError("Latest release pointer is missing while published releases exist; explicit recovery is required.");
        return { latest: null, highest: null, releases };
      }
      throw error;
    }
    let value;
    try {
      value = JSON.parse(raw);
    } catch {
      throw historyError("Latest release pointer is malformed; explicit recovery is required.");
    }
    if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).length !== 1 || typeof value.release_id !== "string") {
      throw historyError("Latest release pointer is malformed; explicit recovery is required.");
    }
    const latest = [...releases.values()].find((release) => release.metadata.release_id === value.release_id);
    if (!latest) throw historyError("Latest release pointer references a missing or invalid release; explicit recovery is required.");
    if (!highest || latest.metadata.release_id !== highest.metadata.release_id) {
      throw historyError("Latest release pointer contradicts published build history; explicit recovery is required.");
    }
    if (await hashFile(latest.ipaPath) !== latest.metadata.ipa_sha256) {
      throw historyError("Latest published release failed its integrity check; explicit recovery is required.");
    }
    return { latest, highest, releases };
  };
  const readLatest = async () => {
    const history = await inspectPublishedHistory();
    return history.latest;
  };
  const writeLatest = async (id) => {
    const tempLatest = `${latestPath}.${crypto.randomUUID()}.tmp`;
    await fs.promises.writeFile(tempLatest, JSON.stringify({ release_id: id }), { flag: "wx", mode: 0o600 });
    await fs.promises.rename(tempLatest, latestPath);
  };

  return http.createServer(async (request, response) => {
    try {
      await ensureStore();
      const url = new URL(request.url || "/", baseUrl);
      const route = url.pathname;
      if (request.method === "GET" && route === "/healthz") return json(response, 200, { status: "ok" });
      if (request.headers.host !== baseUrl.host) return text(response, 400, "Invalid host.");
      if (request.method === "GET" && (route === "/" || route === "/install")) {
        const html = await fs.promises.readFile(path.join(ROOT, "public", "index.html"));
        return text(response, 200, html, "text/html; charset=utf-8", { "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; form-action 'self'; frame-ancestors 'none'; base-uri 'none'; object-src 'none'" });
      }
      if (request.method === "GET" && route === "/app.js") {
        const script = await fs.promises.readFile(path.join(ROOT, "public", "app.js"));
        return text(response, 200, script, "text/javascript; charset=utf-8");
      }
      if (request.method === "GET" && route === "/style.css") {
        const style = await fs.promises.readFile(path.join(ROOT, "public", "style.css"));
        return text(response, 200, style, "text/css; charset=utf-8");
      }
      if (request.method === "POST" && route === "/api/session") {
        const ip = request.headers["x-real-ip"] || request.socket.remoteAddress || "unknown";
        if (!rateAllowed(ip)) return json(response, 429, { error: "Too many attempts. Wait and try again." }, { "Retry-After": "900" });
        let body;
        try { body = JSON.parse((await readBody(request, 4096)).toString("utf8")); }
        catch { return json(response, 400, { error: "Invalid login request." }); }
        if (!secureEquals(body.password || "", config.installPassword)) return json(response, 401, { error: "Access code was not accepted." });
        const expiry = Math.floor(Date.now() / 1000) + sessionSeconds;
        const cookie = `ota_session=${expiry}.${sign("session", "install", expiry)}; Path=/; Max-Age=${sessionSeconds}; HttpOnly; Secure; SameSite=Strict`;
        return json(response, 200, { authenticated: true }, { "Set-Cookie": cookie });
      }
      if (request.method === "POST" && route === "/api/logout") {
        return json(response, 200, { signed_out: true }, { "Set-Cookie": "ota_session=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Strict" });
      }
      if (request.method === "GET" && route === "/api/release") {
        if (!verifySession(request)) return json(response, 401, { error: "Sign in to view releases." });
        const latest = await readLatest();
        if (!latest) return json(response, 404, { error: "No approved mobile release is available yet." });
        const expiry = Math.floor(Date.now() / 1000) + capabilitySeconds;
        return json(response, 200, {
          bundle_id: latest.metadata.bundle_id,
          marketing_version: latest.metadata.marketing_version,
          build_number: latest.metadata.build_number,
          release_notes: latest.metadata.release_notes,
          source_commit: latest.metadata.source_commit,
          manifest_url: capabilityUrl("manifest", latest.metadata.release_id, expiry),
        });
      }
      if (request.method === "GET" && route === "/admin/health") {
        if (!verifyAdmin(request)) return json(response, 401, { error: "Release upload is not authorized." });
        return json(response, 200, { ready: true });
      }
      const otaRoute = /^\/ota\/([0-9]+\.[0-9]+\.[0-9]+-[1-9][0-9]*)\/(manifest\.plist|app\.ipa)$/.exec(route);
      if (request.method === "GET" && otaRoute) {
        const [, id, leaf] = otaRoute;
        const scope = leaf === "manifest.plist" ? "manifest" : "ipa";
        if (!validCapability(scope, id, url)) return text(response, 403, "Installation link is invalid or expired.");
        const release = await loadRelease(id);
        if (!release) return text(response, 404, "Release not found.");
        if (scope === "manifest") {
          const ipaUrl = capabilityUrl("ipa", id, Number(url.searchParams.get("e")));
          const manifest = createManifest({ ipaUrl, bundleId: release.metadata.bundle_id, marketingVersion: release.metadata.marketing_version, buildNumber: release.metadata.build_number, releaseId: release.metadata.release_id, title: "Theresian's Quest" });
          return text(response, 200, manifest, "application/xml; charset=utf-8");
        }
        const range = rangeFor(request.headers.range, release.ipaSize);
        if (range === false) return text(response, 416, "Invalid byte range.", "text/plain; charset=utf-8", { "Content-Range": `bytes */${release.ipaSize}` });
        const headers = {
          "Content-Type": "application/octet-stream",
          "Accept-Ranges": "bytes",
          "Content-Disposition": `attachment; filename="TheresiansQuest-${release.metadata.marketing_version}-${release.metadata.build_number}.ipa"`,
          "Cache-Control": "private, no-store",
          "X-Content-Type-Options": "nosniff",
        };
        if (range) {
          headers["Content-Range"] = `bytes ${range.start}-${range.end}/${release.ipaSize}`;
          headers["Content-Length"] = String(range.end - range.start + 1);
          response.writeHead(206, headers);
          return await pipeline(fs.createReadStream(release.ipaPath, { start: range.start, end: range.end }), response);
        }
        headers["Content-Length"] = String(release.ipaSize);
        response.writeHead(200, headers);
        return await pipeline(fs.createReadStream(release.ipaPath), response);
      }
      const adminMeta = /^\/admin\/releases\/([0-9]+\.[0-9]+\.[0-9]+-[1-9][0-9]*)$/.exec(route);
      const adminIpa = /^\/admin\/releases\/([0-9]+\.[0-9]+\.[0-9]+-[1-9][0-9]*)\/ipa$/.exec(route);
      const adminPublish = /^\/admin\/releases\/([0-9]+\.[0-9]+\.[0-9]+-[1-9][0-9]*)\/publish$/.exec(route);
      if ((adminMeta || adminIpa || adminPublish) && !verifyAdmin(request)) return json(response, 401, { error: "Release upload is not authorized." });
      if (request.method === "POST" && adminMeta) {
        const id = adminMeta[1];
        if (fs.existsSync(releasePath(id)) || fs.existsSync(path.join(stagingPath(id), "release.json"))) return json(response, 409, { error: "This release identifier already exists." });
        const body = JSON.parse((await readBody(request, MAX_METADATA_BYTES)).toString("utf8"));
        const metadata = validateMetadata(body, id, bundleId);
        const dir = stagingPath(id);
        await fs.promises.mkdir(dir, { recursive: false, mode: 0o700 });
        await fs.promises.writeFile(path.join(dir, "release.json"), JSON.stringify(metadata), { flag: "wx", mode: 0o600 });
        return json(response, 201, { staged: true, release_id: id });
      }
      if (request.method === "PUT" && adminIpa) {
        const id = adminIpa[1];
        const dir = stagingPath(id);
        const metadata = JSON.parse(await fs.promises.readFile(path.join(dir, "release.json"), "utf8"));
        const target = path.join(dir, "app.ipa");
        if (fs.existsSync(target)) {
          const existingHash = await hashFile(target);
          if (existingHash === metadata.ipa_sha256) return json(response, 200, { staged: true, sha256: existingHash, already_uploaded: true });
          return json(response, 409, { error: "A different IPA is already staged for this build." });
        }
        const temp = path.join(dir, `app.ipa.${crypto.randomUUID()}.part`);
        const hash = crypto.createHash("sha256");
        let bytes = 0;
        const meter = new Transform({
          transform(chunk, encoding, callback) {
            bytes += chunk.length;
            if (bytes > MAX_IPA_BYTES) return callback(Object.assign(new Error("IPA exceeds the size limit."), { status: 413 }));
            hash.update(chunk);
            callback(null, chunk);
          },
        });
        try {
          await pipeline(request, meter, fs.createWriteStream(temp, { flags: "wx", mode: 0o600 }));
          const actual = hash.digest("hex");
          if (actual !== metadata.ipa_sha256) throw Object.assign(new Error("Uploaded IPA SHA-256 does not match signed build metadata."), { status: 422 });
          await fs.promises.rename(temp, target);
          return json(response, 201, { staged: true, sha256: actual, bytes });
        } catch (error) {
          await fs.promises.rm(temp, { force: true });
          throw error;
        }
      }
      if (request.method === "POST" && adminPublish) {
        const id = adminPublish[1];
        const publish = async () => {
          const staged = stagingPath(id);
          const finalDir = releasePath(id);
          const history = await inspectPublishedHistory();
          if (fs.existsSync(finalDir)) {
            const existing = history.latest?.metadata.release_id === id ? history.latest : null;
            if (!existing) return { status: 409, body: { error: "Only the current latest release may be retried; older releases cannot be promoted." } };
            return { status: 200, body: { published: true, already_published: true, release_id: id, marketing_version: existing.metadata.marketing_version, build_number: existing.metadata.build_number } };
          }
          const metadata = JSON.parse(await fs.promises.readFile(path.join(staged, "release.json"), "utf8"));
          validateMetadata(metadata, id, bundleId);
          const actualHash = await hashFile(path.join(staged, "app.ipa"));
          if (actualHash !== metadata.ipa_sha256) return { status: 422, body: { error: "Staged IPA integrity check failed." } };
          if (history.highest && Number(metadata.build_number) <= Number(history.highest.metadata.build_number)) return { status: 409, body: { error: "Build number must be higher than every published build." } };
          await fs.promises.rename(staged, finalDir);
          await writeLatest(id);
          return { status: 201, body: { published: true, release_id: id, marketing_version: metadata.marketing_version, build_number: metadata.build_number } };
        };
        const result = publishQueue.then(publish, publish);
        publishQueue = result.then(() => undefined, () => undefined);
        const published = await result;
        return json(response, published.status, published.body);
      }
      return json(response, 404, { error: "Not found." });
    } catch (error) {
      if (!response.headersSent) return json(response, error.status || 400, { error: error.status ? error.message : "Request failed validation." });
      response.destroy(error);
    }
  });
}

export { createApp, createManifest, validateBaseUrl, validateMetadata };

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const secretFrom = (name) => {
    const file = process.env[`${name}_FILE`];
    if (file) return fs.readFileSync(file, "utf8").replace(/[\r\n]+$/, "");
    return process.env[name] || "";
  };
  const config = {
    publicBaseUrl: process.env.OTA_PUBLIC_BASE_URL || "",
    storageDir: process.env.OTA_STORAGE_DIR || "/data",
    installPassword: secretFrom("OTA_INSTALL_PASSWORD"),
    uploadToken: secretFrom("OTA_UPLOAD_TOKEN"),
    capabilitySecret: secretFrom("OTA_CAPABILITY_SECRET"),
    bundleId: process.env.OTA_BUNDLE_ID || DEFAULT_BUNDLE_ID,
    sessionSeconds: process.env.OTA_SESSION_SECONDS || "3600",
    capabilitySeconds: process.env.OTA_CAPABILITY_SECONDS || "21600",
  };
  try {
    const app = createApp(config);
    const port = Number(process.env.PORT || 3000);
    app.listen(port, "0.0.0.0", () => console.log(`Private iOS OTA host listening on ${port}.`));
  } catch (error) {
    console.error(`Configuration error: ${error.message}`);
    process.exit(1);
  }
}

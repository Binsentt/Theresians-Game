import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { createApp, createManifest, validateBaseUrl, validateMetadata } from "../server.mjs";
import { main as generateManifest } from "../../tools/generate_ios_ota_manifest.mjs";

const bundleId = "com.theresiansquest.game";
const ipaBytes = Buffer.from("synthetic-ipa-fixture");
const sha = crypto.createHash("sha256").update(ipaBytes).digest("hex");
const metadata = {
  release_id: "1.2.3-101",
  bundle_id: bundleId,
  marketing_version: "1.2.3",
  build_number: "101",
  source_commit: "a".repeat(40),
  ipa_sha256: sha,
  release_notes: "Improved progress saving. <script>alert(1)</script>",
};

function request(server, method, requestPath, headers = {}, body = Buffer.alloc(0)) {
  const address = server.address();
  return new Promise((resolve, reject) => {
    const req = http.request({
      host: "127.0.0.1",
      port: address.port,
      method,
      path: requestPath,
      headers: { Host: "ota.example.test", ...headers },
    }, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
    });
    req.on("error", reject);
    req.end(body);
  });
}

async function withServer(callback) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "theresian-ota-test-"));
  const server = createApp({
    publicBaseUrl: "https://ota.example.test",
    storageDir: directory,
    installPassword: "test-install-code-that-is-long-enough",
    uploadToken: "u".repeat(40),
    capabilitySecret: "c".repeat(40),
    capabilitySeconds: 3600,
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try { await callback(server, directory); }
  finally {
    await new Promise((resolve) => server.close(resolve));
    await fs.rm(directory, { recursive: true, force: true });
  }
}

const auth = { Authorization: `Bearer ${"u".repeat(40)}` };
const releaseBytes = (buildNumber) => Buffer.from(`synthetic-ipa-${buildNumber}`);
const releaseMetadata = (buildNumber, bytes) => ({
  ...metadata,
  release_id: `1.2.3-${buildNumber}`,
  build_number: String(buildNumber),
  ipa_sha256: crypto.createHash("sha256").update(bytes).digest("hex"),
  release_notes: `Synthetic build ${buildNumber}`,
});

async function stageRelease(server, buildNumber, bytes = releaseBytes(buildNumber)) {
  const details = releaseMetadata(buildNumber, bytes);
  const created = await request(server, "POST", `/admin/releases/${details.release_id}`, { ...auth, "Content-Type": "application/json" }, Buffer.from(JSON.stringify(details)));
  assert.equal(created.status, 201);
  const uploaded = await request(server, "PUT", `/admin/releases/${details.release_id}/ipa`, auth, bytes);
  assert.equal(uploaded.status, 201);
  return details.release_id;
}

async function publishRelease(server, releaseId) {
  return request(server, "POST", `/admin/releases/${releaseId}/publish`, auth);
}

test("manifest embeds the approved bundle, marketing version, build, and escaped HTTPS IPA URL", () => {
  const manifest = createManifest({
    ipaUrl: "https://install.example.test/ota/1.2.3-101/app.ipa?e=1799999999&s=abc",
    bundleId,
    marketingVersion: "1.2.3",
    buildNumber: "101",
    releaseId: "1.2.3-101",
    title: "Theresian's Quest & Learning",
  });
  assert.match(manifest, /<key>bundle-identifier<\/key><string>com\.theresiansquest\.game<\/string>/);
  assert.match(manifest, /<key>bundle-version<\/key><string>101<\/string>/);
  assert.match(manifest, /Theresian&apos;s Quest &amp; Learning/);
  assert.match(manifest, /https:\/\/install\.example\.test\/ota\/1\.2\.3-101\/app\.ipa\?e=1799999999&amp;s=abc/);
});

test("manifest refuses insecure, credentialed, GitHub, wrong-app, and mismatched version inputs", () => {
  const base = { bundleId, marketingVersion: "1.2.3", buildNumber: "101", releaseId: "1.2.3-101", title: "Theresian's Quest" };
  for (const ipaUrl of ["http://install.example.test/app.ipa", "https://user:pass@install.example.test/a.ipa", "https://github.com/private/release.ipa", "https://install.example.test/a.ipa#fragment"]) {
    assert.throws(() => createManifest({ ...base, ipaUrl }));
  }
  assert.throws(() => createManifest({ ...base, bundleId: "com.other.game", ipaUrl: "https://install.example.test/a.ipa" }));
  assert.throws(() => createManifest({ ...base, buildNumber: "102", ipaUrl: "https://install.example.test/a.ipa" }));
  assert.throws(() => createManifest({ ...base, releaseId: "1.2.3-102", ipaUrl: "https://install.example.test/a.ipa" }));
  assert.throws(() => createManifest({ ...base, marketingVersion: "v1", ipaUrl: "https://install.example.test/a.ipa" }));
});

test("standalone manifest generator writes a non-overwriting plist from explicit matching release inputs", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "theresian-manifest-test-"));
  try {
    const output = path.join(directory, "manifest.plist");
    const args = [
      "--ipa-url", "https://install.example.test/ota/1.2.3-101/app.ipa?e=1799999999&s=abc",
      "--bundle-id", bundleId,
      "--marketing-version", "1.2.3",
      "--build-number", "101",
      "--release-id", "1.2.3-101",
      "--title", "Theresian's Quest",
      "--output", output,
    ];
    assert.equal(generateManifest(args), 0);
    const content = await fs.readFile(output, "utf8");
    assert.match(content, /com\.theresiansquest\.game/);
    assert.match(content, /<string>101<\/string>/);
    const originalError = console.error;
    console.error = () => {};
    try {
      assert.equal(generateManifest(args), 1, "generator must refuse to overwrite an existing manifest");
    } finally {
      console.error = originalError;
    }
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("hosting base URL must be dedicated HTTPS without path or credentials", () => {
  assert.equal(validateBaseUrl("https://install.example.test").origin, "https://install.example.test");
  for (const value of ["http://install.example.test", "https://u:p@install.example.test", "https://github.com", "https://install.example.test/subpath"]) {
    assert.throws(() => validateBaseUrl(value));
  }
});

test("release metadata binds bundle, version, build, commit, and IPA digest", () => {
  assert.equal(validateMetadata(metadata, metadata.release_id, bundleId).ipa_sha256, sha);
  assert.throws(() => validateMetadata({ ...metadata, bundle_id: "other.app" }, metadata.release_id, bundleId));
  assert.throws(() => validateMetadata({ ...metadata, release_id: "1.2.3-102" }, metadata.release_id, bundleId));
  assert.throws(() => validateMetadata({ ...metadata, ipa_sha256: "invalid" }, metadata.release_id, bundleId));
  assert.throws(() => validateMetadata({ ...metadata, source_commit: "abc" }, metadata.release_id, bundleId));
});

test("unauthorized upload is rejected and protected install page returns only a signed installer capability after login", async () => {
  await withServer(async (server) => {
    const page = await request(server, "GET", "/install");
    assert.equal(page.status, 200);
    assert.match(page.body.toString(), /Release notes/);
    assert.match(page.body.toString(), /Install or update on this iPhone/);
    const denied = await request(server, "POST", "/admin/releases/1.2.3-101", { "Content-Type": "application/json" }, Buffer.from(JSON.stringify(metadata)));
    assert.equal(denied.status, 401);
    assert.equal((await request(server, "GET", "/admin/health")).status, 401);
    const adminHealth = await request(server, "GET", "/admin/health", { Authorization: `Bearer ${"u".repeat(40)}` });
    assert.equal(adminHealth.status, 200);
    assert.deepEqual(JSON.parse(adminHealth.body), { ready: true });
    const before = await request(server, "GET", "/api/release");
    assert.equal(before.status, 401);
    const login = await request(server, "POST", "/api/session", { "Content-Type": "application/json" }, Buffer.from(JSON.stringify({ password: "test-install-code-that-is-long-enough" })));
    assert.equal(login.status, 200);
    assert.match(login.headers["set-cookie"][0], /HttpOnly; Secure; SameSite=Strict/);
    const response = await request(server, "GET", "/api/release", { Cookie: login.headers["set-cookie"][0].split(";")[0] });
    assert.equal(response.status, 404);
  });
});

test("upload, digest verification, release publication, manifest fetch, and ranged IPA download work end-to-end", async () => {
  await withServer(async (server) => {
    const auth = { Authorization: `Bearer ${"u".repeat(40)}` };
    const post = await request(server, "POST", `/admin/releases/${metadata.release_id}`, { ...auth, "Content-Type": "application/json" }, Buffer.from(JSON.stringify(metadata)));
    assert.equal(post.status, 201);
    const put = await request(server, "PUT", `/admin/releases/${metadata.release_id}/ipa`, { ...auth, "Content-Type": "application/octet-stream" }, ipaBytes);
    assert.equal(put.status, 201);
    assert.equal(JSON.parse(put.body).sha256, sha);
    const published = await request(server, "POST", `/admin/releases/${metadata.release_id}/publish`, auth);
    assert.equal(published.status, 201);

    const login = await request(server, "POST", "/api/session", { "Content-Type": "application/json" }, Buffer.from(JSON.stringify({ password: "test-install-code-that-is-long-enough" })));
    const cookie = login.headers["set-cookie"][0].split(";")[0];
    const release = await request(server, "GET", "/api/release", { Cookie: cookie });
    assert.equal(release.status, 200);
    const details = JSON.parse(release.body);
    assert.equal(details.bundle_id, bundleId);
    assert.equal(details.marketing_version, "1.2.3");
    assert.equal(details.build_number, "101");
    assert.match(details.manifest_url, /^https:\/\/ota\.example\.test\/ota\/1\.2\.3-101\/manifest\.plist\?/);

    const manifestUrl = new URL(details.manifest_url);
    const manifest = await request(server, "GET", `${manifestUrl.pathname}${manifestUrl.search}`);
    assert.equal(manifest.status, 200);
    assert.match(manifest.headers["content-type"], /application\/xml/);
    assert.match(manifest.body.toString(), /com\.theresiansquest\.game/);
    assert.match(manifest.body.toString(), /<string>101<\/string>/);
    const ipaUrlText = /<key>url<\/key><string>([^<]+)<\/string>/.exec(manifest.body.toString())[1].replaceAll("&amp;", "&");
    const ipaUrl = new URL(ipaUrlText);
    const range = await request(server, "GET", `${ipaUrl.pathname}${ipaUrl.search}`, { Range: "bytes=1-3" });
    assert.equal(range.status, 206);
    assert.equal(range.body.toString(), "ynt");
    assert.equal(range.headers["accept-ranges"], "bytes");
    const expired = new URL(ipaUrl);
    expired.searchParams.set("e", "1000000000");
    assert.equal((await request(server, "GET", `${expired.pathname}${expired.search}`)).status, 403);
  });
});

test("staged IPA hash mismatch cannot be published and build numbers must increase", async () => {
  await withServer(async (server) => {
    const auth = { Authorization: `Bearer ${"u".repeat(40)}` };
    const wrong = { ...metadata, release_id: "1.2.3-101", ipa_sha256: "0".repeat(64) };
    assert.equal((await request(server, "POST", `/admin/releases/${wrong.release_id}`, { ...auth, "Content-Type": "application/json" }, Buffer.from(JSON.stringify(wrong)))).status, 201);
    assert.equal((await request(server, "PUT", `/admin/releases/${wrong.release_id}/ipa`, auth, ipaBytes)).status, 422);
    assert.equal((await request(server, "POST", `/admin/releases/${wrong.release_id}/publish`, auth)).status, 400);
  });
});

test("the first valid release is accepted when storage and latest pointer are empty", async () => {
  await withServer(async (server, directory) => {
    const id = await stageRelease(server, 1);
    const result = await publishRelease(server, id);
    assert.equal(result.status, 201);
    assert.deepEqual(JSON.parse(await fs.readFile(path.join(directory, "latest.json"), "utf8")), { release_id: id });
  });
});

test("a missing latest pointer with a published release rejects both lower and higher promotions", async () => {
  for (const attemptedBuild of [50, 201]) {
    await withServer(async (server, directory) => {
      const current = await stageRelease(server, 200);
      assert.equal((await publishRelease(server, current)).status, 201);
      await fs.unlink(path.join(directory, "latest.json"));
      const attempted = await stageRelease(server, attemptedBuild);
      const rejected = await publishRelease(server, attempted);
      assert.equal(rejected.status, 409);
      assert.match(JSON.parse(rejected.body).error, /explicit recovery is required/);
      assert.equal(await fs.stat(path.join(directory, "releases", current, "app.ipa")).then((stat) => stat.size > 0), true);
      await assert.rejects(fs.stat(path.join(directory, "releases", attempted)));
      await assert.rejects(fs.stat(path.join(directory, "latest.json")));
    });
  }
});

test("a missing pointer with multiple published releases fails closed", async () => {
  await withServer(async (server, directory) => {
    const first = await stageRelease(server, 200);
    assert.equal((await publishRelease(server, first)).status, 201);
    const second = await stageRelease(server, 201);
    assert.equal((await publishRelease(server, second)).status, 201);
    await fs.unlink(path.join(directory, "latest.json"));
    const attempted = await stageRelease(server, 202);
    assert.equal((await publishRelease(server, attempted)).status, 409);
    assert.equal(await fs.stat(path.join(directory, "releases", first, "app.ipa")).then((stat) => stat.size > 0), true);
    assert.equal(await fs.stat(path.join(directory, "releases", second, "app.ipa")).then((stat) => stat.size > 0), true);
  });
});

test("an older pointer contradicting newer published history cannot be used for promotion or reads", async () => {
  await withServer(async (server, directory) => {
    const first = await stageRelease(server, 200);
    assert.equal((await publishRelease(server, first)).status, 201);
    const second = await stageRelease(server, 201);
    assert.equal((await publishRelease(server, second)).status, 201);
    await fs.writeFile(path.join(directory, "latest.json"), JSON.stringify({ release_id: first }));
    const candidate = await stageRelease(server, 202);
    assert.equal((await publishRelease(server, candidate)).status, 409);
    const login = await request(server, "POST", "/api/session", { "Content-Type": "application/json" }, Buffer.from(JSON.stringify({ password: "test-install-code-that-is-long-enough" })));
    assert.equal((await request(server, "GET", "/api/release", { Cookie: login.headers["set-cookie"][0].split(";")[0] })).status, 409);
  });
});

test("malformed, dangling, and corrupt latest pointers fail closed", async () => {
  await withServer(async (server, directory) => {
    const first = await stageRelease(server, 200);
    assert.equal((await publishRelease(server, first)).status, 201);
    const latestPath = path.join(directory, "latest.json");
    const candidate = await stageRelease(server, 201);

    await fs.writeFile(latestPath, "{not-json");
    assert.equal((await publishRelease(server, candidate)).status, 409);
    await fs.writeFile(latestPath, JSON.stringify({ release_id: "1.2.3-999" }));
    assert.equal((await publishRelease(server, candidate)).status, 409);
    await fs.writeFile(latestPath, JSON.stringify({ release_id: first }));
    await fs.writeFile(path.join(directory, "releases", first, "app.ipa"), Buffer.from("corrupt"));
    assert.equal((await publishRelease(server, candidate)).status, 409);
    assert.equal(await fs.stat(path.join(directory, "releases", first, "app.ipa")).then((stat) => stat.size), Buffer.byteLength("corrupt"));
  });
});

test("only the current latest release is idempotently retryable; older releases cannot be promoted", async () => {
  await withServer(async (server, directory) => {
    const first = await stageRelease(server, 200);
    assert.equal((await publishRelease(server, first)).status, 201);
    const second = await stageRelease(server, 201);
    assert.equal((await publishRelease(server, second)).status, 201);
    const retryLatest = await publishRelease(server, second);
    assert.equal(retryLatest.status, 200);
    assert.equal(JSON.parse(retryLatest.body).already_published, true);
    assert.equal((await publishRelease(server, first)).status, 409);
    assert.deepEqual(JSON.parse(await fs.readFile(path.join(directory, "latest.json"), "utf8")), { release_id: second });
  });
});

test("an interrupted publication requires explicit pointer recovery and then permits a latest retry", async () => {
  await withServer(async (server, directory) => {
    const first = await stageRelease(server, 200);
    assert.equal((await publishRelease(server, first)).status, 201);
    const interrupted = await stageRelease(server, 201);
    await fs.rename(path.join(directory, "staging", interrupted), path.join(directory, "releases", interrupted));

    const rejectedRetry = await publishRelease(server, interrupted);
    assert.equal(rejectedRetry.status, 409);
    assert.match(JSON.parse(rejectedRetry.body).error, /contradicts published build history/);
    assert.equal(await fs.stat(path.join(directory, "releases", interrupted, "app.ipa")).then((stat) => stat.size > 0), true);

    // Simulate an authorized operator's explicit recovery after verifying the immutable release metadata and IPA digest.
    const releasePath = path.join(directory, "releases", interrupted);
    const recoveredMetadata = JSON.parse(await fs.readFile(path.join(releasePath, "release.json"), "utf8"));
    assert.equal(crypto.createHash("sha256").update(await fs.readFile(path.join(releasePath, "app.ipa"))).digest("hex"), recoveredMetadata.ipa_sha256);
    await fs.writeFile(path.join(directory, "latest.json"), JSON.stringify({ release_id: interrupted }));
    const recoveredRetry = await publishRelease(server, interrupted);
    assert.equal(recoveredRetry.status, 200);
    assert.equal(JSON.parse(recoveredRetry.body).already_published, true);
  });
});

test("concurrent release publication cannot move the latest pointer backwards", async () => {
  await withServer(async (server) => {
    const auth = { Authorization: `Bearer ${"u".repeat(40)}` };
    const stage = async (buildNumber, bytes) => {
      const releaseId = `1.2.3-${buildNumber}`;
      const digest = crypto.createHash("sha256").update(bytes).digest("hex");
      const details = { ...metadata, release_id: releaseId, build_number: String(buildNumber), ipa_sha256: digest, release_notes: `Release build ${buildNumber}` };
      const created = await request(server, "POST", `/admin/releases/${releaseId}`, { ...auth, "Content-Type": "application/json" }, Buffer.from(JSON.stringify(details)));
      assert.equal(created.status, 201);
      const uploaded = await request(server, "PUT", `/admin/releases/${releaseId}/ipa`, auth, bytes);
      assert.equal(uploaded.status, 201);
      return releaseId;
    };
    const olderId = await stage(101, Buffer.from("ipa-101"));
    const newerId = await stage(102, Buffer.from("ipa-102"));
    const results = await Promise.all([
      request(server, "POST", `/admin/releases/${olderId}/publish`, auth),
      request(server, "POST", `/admin/releases/${newerId}/publish`, auth),
    ]);
    assert.ok(results.every((result) => result.status === 201 || result.status === 409));
    const login = await request(server, "POST", "/api/session", { "Content-Type": "application/json" }, Buffer.from(JSON.stringify({ password: "test-install-code-that-is-long-enough" })));
    const cookie = login.headers["set-cookie"][0].split(";")[0];
    const latest = await request(server, "GET", "/api/release", { Cookie: cookie });
    assert.equal(latest.status, 200);
    assert.equal(JSON.parse(latest.body).build_number, "102");
  });
});

test("a broken latest pointer fails closed instead of allowing build-number rollback", async () => {
  await withServer(async (server, directory) => {
    const auth = { Authorization: `Bearer ${"u".repeat(40)}` };
    await fs.writeFile(path.join(directory, "latest.json"), JSON.stringify({ release_id: "1.2.3-999" }));
    const bytes = Buffer.from("ipa-102");
    const older = { ...metadata, release_id: "1.2.3-102", build_number: "102", ipa_sha256: crypto.createHash("sha256").update(bytes).digest("hex") };
    assert.equal((await request(server, "POST", `/admin/releases/${older.release_id}`, { ...auth, "Content-Type": "application/json" }, Buffer.from(JSON.stringify(older)))).status, 201);
    assert.equal((await request(server, "PUT", `/admin/releases/${older.release_id}/ipa`, auth, bytes)).status, 201);
    assert.equal((await request(server, "POST", `/admin/releases/${older.release_id}/publish`, auth)).status, 409);
    const login = await request(server, "POST", "/api/session", { "Content-Type": "application/json" }, Buffer.from(JSON.stringify({ password: "test-install-code-that-is-long-enough" })));
    const cookie = login.headers["set-cookie"][0].split(";")[0];
    assert.equal((await request(server, "GET", "/api/release", { Cookie: cookie })).status, 409);
  });
});

test("install page contract uses text-only release rendering and user-initiated install instructions", async () => {
  const html = await fs.readFile(new URL("../public/index.html", import.meta.url), "utf8");
  const script = await fs.readFile(new URL("../public/app.js", import.meta.url), "utf8");
  assert.match(html, /name="viewport"/);
  assert.match(html, /Open this page in Safari/);
  assert.match(html, /Keep the existing game installed/);
  assert.match(html, /Release notes/);
  assert.match(script, /release-notes"\)\.textContent/);
  assert.doesNotMatch(script, /\.innerHTML\s*=/);
  assert.match(script, /manifest\.protocol !== "https:"/);
});

#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createManifest } from "../mobile-release-host/server.mjs";

function argumentsMap(argv) {
  const values = new Map();
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i];
    if (!key?.startsWith("--") || !argv[i + 1] || values.has(key)) throw new Error("Arguments must be unique --name value pairs.");
    values.set(key, argv[i + 1]);
  }
  return values;
}

function main(argv) {
  try {
    const args = argumentsMap(argv);
    const required = ["--ipa-url", "--bundle-id", "--marketing-version", "--build-number", "--release-id", "--title", "--output"];
    for (const key of required) if (!args.has(key)) throw new Error(`Missing required argument ${key}.`);
    const output = path.resolve(args.get("--output"));
    const manifest = createManifest({
      ipaUrl: args.get("--ipa-url"),
      bundleId: args.get("--bundle-id"),
      marketingVersion: args.get("--marketing-version"),
      buildNumber: args.get("--build-number"),
      releaseId: args.get("--release-id"),
      title: args.get("--title"),
    });
    fs.writeFileSync(output, manifest, { flag: "wx", mode: 0o600 });
    console.log(`Wrote OTA manifest for ${args.get("--bundle-id")} ${args.get("--marketing-version")} (${args.get("--build-number")}).`);
    return 0;
  } catch (error) {
    console.error(`OTA manifest generation failed: ${error.message}`);
    return 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = main(process.argv.slice(2));
export { argumentsMap, main };

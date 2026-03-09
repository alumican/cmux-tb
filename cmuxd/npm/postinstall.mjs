#!/usr/bin/env node
/**
 * postinstall script for the cmuxd npm package.
 * Downloads the pre-built binary from GitHub releases for the current platform.
 */
import { createWriteStream, mkdirSync, chmodSync, existsSync, readFileSync } from "fs"
import { resolve, dirname } from "path"
import { fileURLToPath } from "url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const platform = process.platform // darwin, linux
const arch = process.arch         // arm64, x64

const binaryName = `cmuxd-${platform}-${arch}`
const binDir = resolve(__dirname, "bin")
const binaryPath = resolve(binDir, binaryName)

// Skip if binary already exists (e.g., local build or cached)
if (existsSync(binaryPath)) {
  process.exit(0)
}

// Also skip if a local Zig build exists (development mode)
const localBuild = resolve(__dirname, "..", "zig-out", "bin", "cmuxd")
if (existsSync(localBuild)) {
  process.exit(0)
}

// Read version from package.json
const pkg = JSON.parse(readFileSync(resolve(__dirname, "package.json"), "utf-8"))
const version = pkg.version
const repo = "manaflow-ai/cmux"
const tag = `cmuxd-v${version}`
const url = `https://github.com/${repo}/releases/download/${tag}/${binaryName}`

console.log(`Downloading cmuxd ${version} for ${platform}-${arch}...`)
mkdirSync(binDir, { recursive: true })

try {
  const response = await fetch(url, { redirect: "follow" })

  if (!response.ok) {
    // Non-fatal: binary not available yet (e.g., dev install before release)
    console.warn(`cmuxd binary not available: ${response.status} ${response.statusText}`)
    console.warn(`URL: ${url}`)
    console.warn("You can build locally with: cd cmuxd && zig build")
    process.exit(0)
  }

  const file = createWriteStream(binaryPath)
  const reader = response.body.getReader()
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    file.write(value)
  }
  file.end()
  await new Promise((resolve) => file.on("finish", resolve))

  chmodSync(binaryPath, 0o755)
  console.log(`cmuxd installed: ${binaryPath}`)
} catch (err) {
  // Non-fatal: network error during install
  console.warn(`Failed to download cmuxd: ${err.message}`)
  console.warn("You can build locally with: cd cmuxd && zig build")
  process.exit(0)
}

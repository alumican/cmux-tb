#!/usr/bin/env node
import { spawn } from "child_process"
import { resolve, dirname } from "path"
import { fileURLToPath } from "url"
import { existsSync } from "fs"

const __dirname = dirname(fileURLToPath(import.meta.url))
const platform = process.platform
const arch = process.arch

// Look for the binary in several locations:
// 1. Downloaded by postinstall: ./bin/cmuxd-{platform}-{arch}
// 2. Local Zig build:           ../zig-out/bin/cmuxd
const candidates = [
  resolve(__dirname, "bin", `cmuxd-${platform}-${arch}`),
  resolve(__dirname, "..", "zig-out", "bin", "cmuxd"),
]

const binaryPath = candidates.find((p) => existsSync(p))

if (!binaryPath) {
  console.error(`cmuxd binary not found for ${platform}-${arch}`)
  console.error("Searched:")
  for (const c of candidates) console.error(`  ${c}`)
  console.error("\nRun 'npm install' to download, or 'cd cmuxd && zig build' to build locally.")
  process.exit(1)
}

// Forward args: `cmuxd --port 3778` or `cmuxd server --port 3778`
const args = process.argv.slice(2)
if (args[0] === "server") args.shift()

const child = spawn(binaryPath, args, {
  stdio: "inherit",
  env: process.env,
})

child.on("error", (err) => {
  console.error(`Failed to start cmuxd: ${err.message}`)
  process.exit(1)
})

child.on("exit", (code, signal) => {
  if (signal) process.exit(1)
  process.exit(code ?? 0)
})

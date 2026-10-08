#!/usr/bin/env bun
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("../install.sh", import.meta.url));
const child = Bun.spawn(["sh", script, "--setup", ...process.argv.slice(2)], {
	stdin: "inherit",
	stdout: "inherit",
	stderr: "inherit",
});
const interrupt = () => child.kill("SIGINT");
const terminate = () => child.kill("SIGTERM");
process.on("SIGINT", interrupt);
process.on("SIGTERM", terminate);
try {
	process.exitCode = await child.exited;
} finally {
	process.off("SIGINT", interrupt);
	process.off("SIGTERM", terminate);
}

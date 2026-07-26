import { serve } from "@hono/node-server";
import { createApp } from "./routes.js";
import { migrate } from "./db.js";

const hostname = process.env.HOST ?? "0.0.0.0";

function resolveHttpPort(): number {
  const port = Number(process.env.HTTP_PORT ?? process.env.PORT ?? 3000);
  if (port === 5432) {
    console.warn("PORT=5432 is Postgres; using 8080 for HTTP instead.");
    return 8080;
  }
  return port;
}

const port = resolveHttpPort();

function main() {
  const app = createApp();

  serve({ fetch: app.fetch, port, hostname }, (info) => {
    console.log(`community-api listening on http://${info.address}:${info.port}`);
    console.log(
      `HTTP_PORT=${process.env.HTTP_PORT ?? "-"} PORT=${process.env.PORT ?? "-"} ` +
        `DATABASE_URL=${process.env.DATABASE_URL ? "set" : "MISSING"}`
    );
    void runMigrations();
  });
}

async function runMigrations() {
  if (!process.env.DATABASE_URL) {
    console.error(
      "DATABASE_URL is not set — API will start but data endpoints will fail. " +
        "In Railway: add Postgres and reference its DATABASE_URL on this service."
    );
    return;
  }

  for (let attempt = 1; attempt <= 5; attempt += 1) {
    try {
      await migrate();
      console.log("database migration complete");
      return;
    } catch (err) {
      console.error(`database migration attempt ${attempt} failed:`, err);
      if (attempt < 5) {
        await new Promise((r) => setTimeout(r, attempt * 2000));
      }
    }
  }
}

main();

const path = require("path");
const fs = require("fs/promises");
const Hexo = require("hexo");

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

async function routeDataToBuffer(data) {
  if (data == null) return Buffer.alloc(0);
  if (Buffer.isBuffer(data)) return data;
  if (typeof data === "string") return Buffer.from(data);
  if (typeof data.on === "function") return streamToBuffer(data);
  return Buffer.from(String(data));
}

async function main() {
  const baseDir = process.cwd();
  const publicDir = path.join(baseDir, "public");
  const hexo = new Hexo(baseDir, {});

  await hexo.init();
  await fs.rm(publicDir, { recursive: true, force: true });
  await hexo.load();

  const routes = hexo.route.list();
  for (const routePath of routes) {
    const destPath = path.join(publicDir, routePath);
    await fs.mkdir(path.dirname(destPath), { recursive: true });
    const data = hexo.route.get(routePath);
    const content = await routeDataToBuffer(data);
    await fs.writeFile(destPath, content);
  }

  console.log(`safe-generate wrote ${routes.length} files.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

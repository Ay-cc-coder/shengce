import { chromium } from "playwright-core";
import { mkdir } from "node:fs/promises";
import path from "node:path";

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const BASE = process.env.BASE_URL || "http://127.0.0.1:5173";
const PASSWORD = process.env.APP_PASSWORD || "dev-pass";
const OUT = path.resolve(process.cwd(), "../docs/screenshots");

const pages = [
  { path: "/", name: "01-overview", full: true, fold: true },
  { path: "/recordings", name: "02-recordings", full: false },
  { path: "/calls", name: "04-calls", full: true },
  { path: "/actions", name: "05-actions", full: false },
  { path: "/library", name: "06-library", full: false },
  { path: "/setup", name: "07-setup", full: true },
];

async function login(context) {
  const page = await context.newPage();
  await page.goto(`${BASE}/login`, { waitUntil: "networkidle" });
  await page.fill('input[type="password"]', PASSWORD);
  await Promise.all([
    page.waitForURL((url) => !url.pathname.startsWith("/login"), { timeout: 20000 }),
    page.click('button[type="submit"]'),
  ]);
  await page.waitForLoadState("networkidle");
  return page;
}

async function settle(page) {
  await page.evaluate(async () => {
    await document.fonts.ready;
    await new Promise((resolve) => setTimeout(resolve, 350));
  });
}

async function shot(page, name, fullPage) {
  await page.screenshot({
    path: path.join(OUT, `${name}.png`),
    fullPage,
    animations: "disabled",
  });
  console.log("saved", name, fullPage ? "full" : "viewport");
}

async function main() {
  await mkdir(OUT, { recursive: true });
  const browser = await chromium.launch({
    executablePath: CHROME,
    headless: true,
    args: ["--font-render-hinting=none"],
  });

  const desktop = await browser.newContext({
    viewport: { width: 1440, height: 1000 },
    deviceScaleFactor: 1.5,
    colorScheme: "light",
    reducedMotion: "reduce",
  });
  const errors = [];
  const page = await login(desktop);
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  page.on("pageerror", (error) => errors.push(String(error)));

  for (const entry of pages) {
    await page.goto(`${BASE}${entry.path}`, { waitUntil: "networkidle" });
    await settle(page);
    await shot(page, entry.name, entry.full);
    if (entry.fold) {
      await page.screenshot({ path: path.join(OUT, `${entry.name}-fold.png`), fullPage: false });
    }
  }

  await page.goto(`${BASE}/recordings`, { waitUntil: "networkidle" });
  await settle(page);
  const first = page.locator(".rec-row__title").first();
  if (await first.count()) {
    await first.click();
    await page.waitForLoadState("networkidle");
    await settle(page);
    await shot(page, "03-recording-detail", false);
    await page.screenshot({ path: path.join(OUT, "03-recording-detail-full.png"), fullPage: true });
  }

  await page.goto(`${BASE}/calls`, { waitUntil: "networkidle" });
  await settle(page);
  const call = page.locator(".rec-row__title").first();
  if (await call.count()) {
    await call.click();
    await page.waitForLoadState("networkidle");
    await settle(page);
    await shot(page, "03b-call-detail", false);
  }

  await page.goto(`${BASE}/`, { waitUntil: "networkidle" });
  await settle(page);
  const play = page.locator(".deck .play-button").first();
  if (await play.count()) {
    await play.click();
    await page.waitForTimeout(1600);
    await page.screenshot({ path: path.join(OUT, "10-player-bar.png"), fullPage: false });
  }

  const mobile = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
    colorScheme: "light",
    reducedMotion: "reduce",
  });
  const mobilePage = await login(mobile);
  await mobilePage.goto(`${BASE}/`, { waitUntil: "networkidle" });
  await settle(mobilePage);
  await shot(mobilePage, "08-mobile-overview", false);
  await mobilePage.evaluate(() => window.scrollTo(0, 880));
  await mobilePage.waitForTimeout(250);
  await shot(mobilePage, "08b-mobile-overview-scroll", false);
  await mobilePage.goto(`${BASE}/recordings`, { waitUntil: "networkidle" });
  await settle(mobilePage);
  const mobileFirst = mobilePage.locator(".rec-row__title").first();
  if (await mobileFirst.count()) {
    await mobileFirst.click();
    await mobilePage.waitForLoadState("networkidle");
    await settle(mobilePage);
    await shot(mobilePage, "09-mobile-recording", false);
  }
  await mobilePage.goto(`${BASE}/`, { waitUntil: "networkidle" });
  await settle(mobilePage);
  const mobilePlay = mobilePage.locator(".deck .play-button").first();
  if (await mobilePlay.count()) {
    await mobilePlay.click();
    await mobilePage.waitForTimeout(1400);
    await shot(mobilePage, "10b-mobile-player", false);
  }

  const loginContext = await browser.newContext({
    viewport: { width: 1440, height: 1000 },
    deviceScaleFactor: 1.5,
    colorScheme: "light",
    reducedMotion: "reduce",
  });
  const loginPage = await loginContext.newPage();
  await loginPage.goto(`${BASE}/login`, { waitUntil: "networkidle" });
  await settle(loginPage);
  await shot(loginPage, "00-login", false);

  console.log("console errors:", errors.length ? errors : "none");
  await browser.close();
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

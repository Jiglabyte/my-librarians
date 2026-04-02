import { Hono } from "hono";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod/v4";
import { prisma } from "../prisma";
import { auth } from "../auth";

type Variables = {
  user: typeof auth.$Infer.Session.user | null;
  session: typeof auth.$Infer.Session.session | null;
};

const app = new Hono<{ Variables: Variables }>();

app.get("/today", async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const today = new Date().toISOString().split("T")[0];
  const entry = await prisma.timesheetEntry.findFirst({
    where: { userId: user.id, date: today },
    orderBy: { createdAt: "desc" },
  });
  return c.json({ data: entry });
});

app.get("/entries", async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const { startDate, endDate } = c.req.query();
  const entries = await prisma.timesheetEntry.findMany({
    where: {
      userId: user.id,
      ...(startDate && endDate ? { date: { gte: startDate, lte: endDate } } : {}),
    },
    orderBy: { date: "desc" },
  });
  return c.json({ data: entries });
});

app.post("/clock-in", zValidator("json", z.object({
  method: z.enum(["manual", "qr", "nfc"]).default("manual"),
  location: z.string().optional(),
  isOffsite: z.boolean().default(false),
  projectName: z.string().optional(),
})), async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const body = c.req.valid("json");
  const today = new Date().toISOString().split("T")[0] ?? "";
  const now = new Date();
  const timeIn = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
  const existing = await prisma.timesheetEntry.findFirst({
    where: { userId: user.id, date: today, status: "in_progress" },
  });
  if (existing) {
    return c.json({ error: { message: "Already clocked in today", code: "ALREADY_CLOCKED_IN" } }, 400);
  }
  const entry = await prisma.timesheetEntry.create({
    data: {
      id: crypto.randomUUID(),
      userId: user.id,
      date: today,
      timeIn,
      clockInMethod: body.method,
      locationIn: body.location,
      isOffsite: body.isOffsite,
      projectName: body.projectName,
      status: "in_progress",
    },
  });
  return c.json({ data: entry });
});

app.post("/clock-out", zValidator("json", z.object({
  entryId: z.string(),
  method: z.enum(["manual", "qr", "nfc"]).default("manual"),
  location: z.string().optional(),
  comment: z.string().optional(),
})), async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const body = c.req.valid("json");
  const now = new Date();
  const timeOut = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
  const entry = await prisma.timesheetEntry.findFirst({
    where: { id: body.entryId, userId: user.id },
  });
  if (!entry) return c.json({ error: { message: "Entry not found", code: "NOT_FOUND" } }, 404);
  if (!entry.timeIn) return c.json({ error: { message: "Not clocked in", code: "NOT_CLOCKED_IN" } }, 400);
  const inParts = entry.timeIn.split(":");
  const outParts = timeOut.split(":");
  const inHours = parseInt(inParts[0] ?? "0", 10);
  const inMinutes = parseInt(inParts[1] ?? "0", 10);
  const outHours = parseInt(outParts[0] ?? "0", 10);
  const outMinutes = parseInt(outParts[1] ?? "0", 10);
  const totalMinutes = (outHours * 60 + outMinutes) - (inHours * 60 + inMinutes);
  const totalHours = totalMinutes / 60;
  const updated = await prisma.timesheetEntry.update({
    where: { id: body.entryId },
    data: {
      timeOut,
      clockOutMethod: body.method,
      locationOut: body.location,
      comment: body.comment,
      totalHours: Math.max(0, totalHours),
      status: "submitted",
    },
  });
  return c.json({ data: updated });
});

app.patch("/entries/:id", zValidator("json", z.object({
  comment: z.string().optional(),
  isOffsite: z.boolean().optional(),
  projectName: z.string().optional(),
})), async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const { id } = c.req.param();
  const body = c.req.valid("json");
  const entry = await prisma.timesheetEntry.findFirst({ where: { id, userId: user.id } });
  if (!entry) return c.json({ error: { message: "Entry not found", code: "NOT_FOUND" } }, 404);
  const updated = await prisma.timesheetEntry.update({ where: { id }, data: body });
  return c.json({ data: updated });
});

app.get("/stats", async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split("T")[0];
  const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().split("T")[0];
  const entries = await prisma.timesheetEntry.findMany({
    where: { userId: user.id, date: { gte: startOfMonth, lte: endOfMonth }, status: { not: "in_progress" } },
  });
  const totalHours = entries.reduce((sum, e) => sum + (e.totalHours || 0), 0);
  const daysWorked = entries.length;
  return c.json({ data: { totalHours, daysWorked } });
});

app.post("/manual-entry", zValidator("json", z.object({
  date: z.string(),
  timeIn: z.string(),
  timeOut: z.string(),
  comment: z.string().optional(),
  isOffsite: z.boolean().default(false),
  projectName: z.string().optional(),
})), async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const body = c.req.valid("json");
  const existing = await prisma.timesheetEntry.findFirst({
    where: { userId: user.id, date: body.date },
  });
  if (existing) {
    return c.json({ error: { message: "Entry already exists for this date", code: "DUPLICATE" } }, 400);
  }
  const [inH, inM] = body.timeIn.split(":").map(Number);
  const [outH, outM] = body.timeOut.split(":").map(Number);
  const totalMinutes = ((outH ?? 0) * 60 + (outM ?? 0)) - ((inH ?? 0) * 60 + (inM ?? 0));
  const totalHours = Math.max(0, totalMinutes / 60);
  const entry = await prisma.timesheetEntry.create({
    data: {
      id: crypto.randomUUID(),
      userId: user.id,
      date: body.date,
      timeIn: body.timeIn,
      timeOut: body.timeOut,
      clockInMethod: "manual",
      clockOutMethod: "manual",
      comment: body.comment,
      isOffsite: body.isOffsite,
      projectName: body.projectName,
      totalHours,
      status: "submitted",
    },
  });
  return c.json({ data: entry });
});

app.put("/entries/:id", zValidator("json", z.object({
  timeIn: z.string().optional(),
  timeOut: z.string().optional(),
  comment: z.string().optional(),
  isOffsite: z.boolean().optional(),
  projectName: z.string().optional(),
})), async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const { id } = c.req.param();
  const body = c.req.valid("json");
  const entry = await prisma.timesheetEntry.findFirst({ where: { id, userId: user.id } });
  if (!entry) return c.json({ error: { message: "Entry not found", code: "NOT_FOUND" } }, 404);
  const newTimeIn = body.timeIn ?? entry.timeIn;
  const newTimeOut = body.timeOut ?? entry.timeOut;
  let totalHours = entry.totalHours;
  if (newTimeIn && newTimeOut) {
    const [inH, inM] = newTimeIn.split(":").map(Number);
    const [outH, outM] = newTimeOut.split(":").map(Number);
    const totalMinutes = ((outH ?? 0) * 60 + (outM ?? 0)) - ((inH ?? 0) * 60 + (inM ?? 0));
    totalHours = Math.max(0, totalMinutes / 60);
  }
  const updated = await prisma.timesheetEntry.update({
    where: { id },
    data: {
      ...(body.timeIn ? { timeIn: body.timeIn } : {}),
      ...(body.timeOut ? { timeOut: body.timeOut } : {}),
      ...(body.comment !== undefined ? { comment: body.comment } : {}),
      ...(body.isOffsite !== undefined ? { isOffsite: body.isOffsite } : {}),
      ...(body.projectName !== undefined ? { projectName: body.projectName } : {}),
      totalHours,
      status: "submitted",
    },
  });
  return c.json({ data: updated });
});

app.delete("/entries/:id", async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const { id } = c.req.param();
  const entry = await prisma.timesheetEntry.findFirst({ where: { id, userId: user.id } });
  if (!entry) return c.json({ error: { message: "Entry not found", code: "NOT_FOUND" } }, 404);
  if (entry.status === "in_progress") {
    return c.json({ error: { message: "Clock out before deleting", code: "ENTRY_IN_PROGRESS" } }, 400);
  }
  await prisma.timesheetEntry.delete({ where: { id } });
  return c.json({ data: { deleted: true } });
});

export default app;

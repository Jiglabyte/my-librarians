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

app.get("/", async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const requests = await prisma.leaveRequest.findMany({
    where: { userId: user.id },
    orderBy: { createdAt: "desc" },
  });
  return c.json({ data: requests });
});

app.post("/", zValidator("json", z.object({
  leaveType: z.enum(["annual", "sick", "away_from_office", "public_holiday", "emergency", "day_off"]),
  startDate: z.string(),
  endDate: z.string(),
  comment: z.string().optional(),
  status: z.string().optional(),
})), async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const body = c.req.valid("json");
  const request = await prisma.leaveRequest.create({
    data: {
      id: crypto.randomUUID(),
      userId: user.id,
      leaveType: body.leaveType,
      startDate: body.startDate,
      endDate: body.endDate,
      comment: body.comment,
      status: body.status ?? "approved",
    },
  });
  return c.json({ data: request });
});

app.delete("/:id", async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const { id } = c.req.param();
  const request = await prisma.leaveRequest.findFirst({ where: { id, userId: user.id } });
  if (!request) return c.json({ error: { message: "Leave request not found", code: "NOT_FOUND" } }, 404);
  await prisma.leaveRequest.delete({ where: { id } });
  return c.json({ data: { success: true } });
});

export default app;

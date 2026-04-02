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
  const profile = await prisma.user.findUnique({ where: { id: user.id } });
  return c.json({ data: profile });
});

app.patch("/", zValidator("json", z.object({
  name: z.string().optional(),
  department: z.string().optional(),
  employeeId: z.string().optional(),
})), async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const body = c.req.valid("json");
  const updated = await prisma.user.update({ where: { id: user.id }, data: body });
  return c.json({ data: updated });
});

export default app;

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

app.get("/location", async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const settings = await prisma.locationSettings.findUnique({ where: { userId: user.id } });
  return c.json({ data: settings });
});

app.put("/location", zValidator("json", z.object({
  latitude: z.number().optional(),
  longitude: z.number().optional(),
  radius: z.number().int().min(50).max(5000).default(200),
  address: z.string().optional(),
  enabled: z.boolean().default(false),
})), async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const body = c.req.valid("json");
  const settings = await prisma.locationSettings.upsert({
    where: { userId: user.id },
    create: {
      id: crypto.randomUUID(),
      userId: user.id,
      ...body,
    },
    update: body,
  });
  return c.json({ data: settings });
});

export default app;

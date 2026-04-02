import { Hono } from "hono";
import { prisma } from "../prisma";
import { auth } from "../auth";
import { env } from "../env";

type Variables = {
  user: typeof auth.$Infer.Session.user | null;
  session: typeof auth.$Infer.Session.session | null;
};

const app = new Hono<{ Variables: Variables }>();

async function getMSToken(): Promise<string | null> {
  const tenantId = env.MS_TENANT_ID;
  const clientId = env.MS_CLIENT_ID;
  const clientSecret = env.MS_CLIENT_SECRET;
  if (!tenantId || !clientId || !clientSecret) return null;
  const res = await fetch(
    `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`,
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "client_credentials",
        client_id: clientId,
        client_secret: clientSecret,
        scope: "https://graph.microsoft.com/.default",
      }),
    }
  );
  if (!res.ok) return null;
  const data = (await res.json()) as { access_token?: string };
  return data.access_token ?? null;
}

app.post("/excel", async (c) => {
  const user = c.get("user");
  if (!user)
    return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);

  const token = await getMSToken();
  if (!token) {
    return c.json({
      error: {
        message: "Microsoft Graph not configured. Add MS_TENANT_ID, MS_CLIENT_ID, MS_CLIENT_SECRET to environment.",
        code: "MS_NOT_CONFIGURED",
      },
    }, 503);
  }

  const now = new Date();
  const startDate = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split("T")[0]!;
  const endDate = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().split("T")[0]!;
  const monthLabel = now.toLocaleDateString("en-US", { month: "long", year: "numeric" });

  const entries = await prisma.timesheetEntry.findMany({
    where: { userId: user.id, date: { gte: startDate, lte: endDate } },
    orderBy: { date: "asc" },
  });

  const leaves = await prisma.leaveRequest.findMany({
    where: { userId: user.id, startDate: { gte: startDate }, endDate: { lte: endDate } },
    orderBy: { startDate: "asc" },
  });

  const csvLines = [
    `MTA Timesheet — ${monthLabel}`,
    `Employee: ${user.name}`,
    `Email: ${user.email}`,
    `Exported: ${new Date().toLocaleString()}`,
    "",
    "Date,Day,Time In,Time Out,Total Hours,Method,Status,Project,Notes",
    ...entries.map((e) => {
      const d = new Date(e.date + "T12:00:00");
      const day = d.toLocaleDateString("en-US", { weekday: "short" });
      return [
        e.date, day, e.timeIn ?? "", e.timeOut ?? "",
        e.totalHours?.toFixed(2) ?? "", e.clockInMethod ?? "manual",
        e.status, e.projectName ?? "",
        `"${(e.comment ?? "").replace(/"/g, '""')}"`,
      ].join(",");
    }),
    "",
    "LEAVE & TIME OFF",
    "Type,Start Date,End Date,Days,Notes",
    ...leaves.map((l) => {
      const days = Math.ceil(
        (new Date(l.endDate).getTime() - new Date(l.startDate).getTime()) / 86400000
      ) + 1;
      return [
        l.leaveType, l.startDate, l.endDate, String(days),
        `"${(l.comment ?? "").replace(/"/g, '""')}"`,
      ].join(",");
    }),
  ].join("\n");

  const fileName = `MTA_Timesheet_${monthLabel.replace(" ", "_")}.csv`;
  const uploadUrl = `https://graph.microsoft.com/v1.0/users/${user.email}/drive/root:/MTA Timesheets/${fileName}:/content`;

  const uploadRes = await fetch(uploadUrl, {
    method: "PUT",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "text/csv" },
    body: csvLines,
  });

  if (!uploadRes.ok) {
    const errText = await uploadRes.text();
    console.error("Graph upload failed:", errText);
    return c.json({
      error: {
        message: "Failed to upload to OneDrive. Check Graph API permissions (Files.ReadWrite.All).",
        code: "UPLOAD_FAILED",
      },
    }, 500);
  }

  const uploadData = (await uploadRes.json()) as { webUrl?: string; id?: string };

  return c.json({
    data: {
      webUrl: uploadData.webUrl,
      fileName,
      month: monthLabel,
      entriesCount: entries.length,
      leavesCount: leaves.length,
    },
  });
});

app.get("/status", async (c) => {
  const user = c.get("user");
  if (!user)
    return c.json({ error: { message: "Unauthorized", code: "UNAUTHORIZED" } }, 401);
  const configured = !!(env.MS_TENANT_ID && env.MS_CLIENT_ID && env.MS_CLIENT_SECRET);
  return c.json({ data: { configured } });
});

export default app;

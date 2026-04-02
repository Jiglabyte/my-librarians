import { authClient } from "../auth/auth-client";

interface ApiResponse<T> {
  data: T;
}

const baseUrl = process.env.EXPO_PUBLIC_BACKEND_URL!;

const request = async <T>(
  url: string,
  options: { method?: string; body?: string } = {}
): Promise<T> => {
  const fullUrl = `${baseUrl}${url}`;
  const cookie = authClient.getCookie();

  console.log(`[API] ${options.method ?? "GET"} ${url} | cookie=${cookie ? "present" : "MISSING"}`);

  let response: Response;
  try {
    response = await fetch(fullUrl, {
      ...options,
      credentials: "include",
      headers: {
        ...(options.body ? { "Content-Type": "application/json" } : {}),
        Cookie: cookie,
      },
    });
  } catch (networkErr: any) {
    console.error(`[API] Network error for ${url}:`, networkErr?.message ?? networkErr);
    throw new Error("Network error - please check your connection.");
  }

  console.log(`[API] ${url} -> ${response.status}`);

  if (response.status === 204) {
    return undefined as T;
  }

  const contentType = response.headers.get("content-type");
  if (contentType?.includes("application/json")) {
    const json = await response.json();

    if (!response.ok || json.error) {
      const msg = json.error?.message ?? `Request failed with status ${response.status}`;
      const code = json.error?.code ?? "UNKNOWN";
      console.error(`[API] Error ${url}: ${code} - ${msg}`);
      const err = new Error(msg);
      (err as any).code = code;
      throw err;
    }

    return (json as ApiResponse<T>).data;
  }

  if (!response.ok) {
    const text = await response.text().catch(() => "");
    console.error(`[API] Non-JSON error ${url}: ${response.status} ${text}`);
    throw new Error(`Request failed with status ${response.status}`);
  }

  return undefined as T;
};

export const api = {
  get: <T>(url: string) => request<T>(url),
  post: <T>(url: string, body: unknown) =>
    request<T>(url, { method: "POST", body: JSON.stringify(body) }),
  put: <T>(url: string, body: unknown) =>
    request<T>(url, { method: "PUT", body: JSON.stringify(body) }),
  delete: <T>(url: string) => request<T>(url, { method: "DELETE" }),
  patch: <T>(url: string, body: unknown) =>
    request<T>(url, { method: "PATCH", body: JSON.stringify(body) }),
};

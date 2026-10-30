import { createHmac, randomBytes } from "node:crypto";
import { IyzicoHttp } from "../payments/iyzico";

/**
 * iyzico IYZWSv2 imzalı HTTP istemcisi. DOĞRULANMAMIŞ: imza biçimi iyzico dokümanına göre
 * (HMAC-SHA256(secret, randomKey + uriPath + body), Authorization: IYZWSv2 base64(...)) yazıldı,
 * sandbox ile denenmedi.
 */
export function iyzicoHttp(opts: { baseUrl: string; apiKey: string; secretKey: string }): IyzicoHttp {
  return {
    async post(path, body) {
      const json = JSON.stringify(body);
      const randomKey = `${Date.now()}${randomBytes(6).toString("hex")}`;
      const signature = createHmac("sha256", opts.secretKey).update(randomKey + path + json, "utf8").digest("hex");
      const auth = Buffer.from(`apiKey:${opts.apiKey}&randomKey:${randomKey}&signature:${signature}`).toString("base64");
      const res = await fetch(opts.baseUrl + path, {
        method: "POST",
        headers: { "content-type": "application/json", accept: "application/json", authorization: `IYZWSv2 ${auth}`, "x-iyzi-rnd": randomKey },
        body: json,
        signal: AbortSignal.timeout(15_000),
      });
      const out: unknown = await res.json().catch(() => ({}));
      if (typeof out !== "object" || out === null) return {};
      return out as Record<string, unknown>;
    },
  };
}

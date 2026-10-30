import { describe, expect, it } from "vitest";
import { ANON } from "./deletion";
import { ANONYMIZE_PATCHES, executeAccountDeletion } from "./executeDeletion";

function setup(facts: { pending?: boolean; dues?: boolean; regs?: boolean } = {}) {
  const log: string[] = [];
  return {
    log,
    deps: {
      store: {
        anonymize: async (c: string) => (log.push(`anon:${c}`), 2),
        deleteWhereUser: async (c: string) => (log.push(`del:${c}`), 3),
        deleteUserDoc: async () => void log.push("userdoc"),
      },
      auth: { deleteUser: async () => void log.push("auth") },
      facts: {
        hasPendingPayments: async () => facts.pending ?? false,
        hasOutstandingDues: async () => facts.dues ?? false,
        hasFutureEventRegistrations: async () => facts.regs ?? false,
      },
    },
  };
}

describe("hesap silme yürütücüsü", () => {
  it("mali kayıtları anonimleştirir, kişisel kayıtları siler ve hesabı EN SON siler", async () => {
    const { deps, log } = setup();
    const r = await executeAccountDeletion(deps, "u1");
    expect(r).toEqual({ done: true, anonymized: 12, deleted: 3 });
    expect(log[log.length - 1]).toBe("auth");
    expect(log[log.length - 2]).toBe("userdoc");
    expect(log.filter((l) => l.startsWith("anon:")).length).toBe(Object.keys(ANONYMIZE_PATCHES).length);
  });

  it("onaydan sonra ortaya çıkan engel yürütmeyi durdurur, hiçbir şey silinmez", async () => {
    const { deps, log } = setup({ dues: true, regs: true });
    expect(await executeAccountDeletion(deps, "u1")).toEqual({ done: false, blockers: ["outstanding_dues", "future_event_registrations"] });
    expect(log.length).toBe(0);
  });

  it("yamalar kişiyi koparır ama tutar/durum alanlarına dokunmaz", () => {
    for (const patch of Object.values(ANONYMIZE_PATCHES)) {
      expect(patch["userId"]).toBe(ANON);
      expect("amountMinor" in patch).toBe(false);
      expect("status" in patch).toBe(false);
    }
  });
});

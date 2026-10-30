import { EventDoc, RegistrationDoc } from "./capacity";

/**
 * Veritabanından bağımsız transaction arayüzü. Üretimde Firestore transaction'ı
 * (ayrı, ince bir adaptör: firebase-admin eklenince), testlerde bellek içi iyimser
 * (optimistic) depo kullanılır. Servis mantığı yalnızca bu arayüze bağımlıdır.
 */
export interface Tx {
  getEvent(id: string): Promise<EventDoc | null>;
  putEvent(event: EventDoc): Promise<void>;
  getRegistration(id: string): Promise<RegistrationDoc | null>;
  listRegistrations(eventId: string): Promise<RegistrationDoc[]>;
  createRegistration(reg: Omit<RegistrationDoc, "id">): Promise<RegistrationDoc>;
  updateRegistration(id: string, patch: Partial<Omit<RegistrationDoc, "id">>): Promise<void>;
}

export interface TxRunner {
  run<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
}

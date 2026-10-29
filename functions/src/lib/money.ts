/** Tutarlar kuruş (minor unit) cinsinden TAM SAYI olarak taşınır; double kullanılmaz. */
export interface Money {
  readonly amountMinor: number;
  readonly currency: string;
}

export function assertValidMoney(m: Money): void {
  if (!Number.isSafeInteger(m.amountMinor)) {
    throw new Error("amountMinor güvenli bir tam sayı olmalı");
  }
  if (m.amountMinor <= 0) {
    throw new Error("amountMinor sıfırdan büyük olmalı");
  }
  if (!/^[A-Z]{3}$/.test(m.currency)) {
    throw new Error("currency 3 harfli ISO kodu olmalı");
  }
}

/** İstemcinin gönderdiği tutar sunucudaki beklenen tutarla BİREBİR eşleşmeli. */
export function moneyEquals(a: Money, b: Money): boolean {
  return a.amountMinor === b.amountMinor && a.currency === b.currency;
}

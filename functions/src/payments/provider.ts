import { Money, assertValidMoney } from "../lib/money";
import { PaymentStatus } from "./paymentState";

export interface CreateSessionInput {
  /** Bizim benzersiz işlem kimliğimiz (idempotency anahtarı olarak da kullanılır). */
  readonly paymentId: string;
  readonly amount: Money;
  readonly description: string;
}

export interface PaymentSession {
  readonly providerRef: string;
  /** Kullanıcının yönlendirileceği/yükleneceği ödeme sayfası; simülasyonda null. */
  readonly checkoutUrl: string | null;
  /** true ise bu işlem GERÇEK TAHSİLAT DEĞİLDİR. */
  readonly simulated: boolean;
}

/** Sağlayıcıdan bağımsız arayüz. Gerçek sağlayıcı (iyzico/PayTR) Aşama 8'de eklenir. */
export interface PaymentProvider {
  readonly name: string;
  createSession(input: CreateSessionInput): Promise<PaymentSession>;
  /** Sağlayıcıdan sunucu-sunucu durum sorgusu (webhook gelmezse mutabakat için). */
  getStatus(providerRef: string): Promise<PaymentStatus>;
}

/** Sağlayıcı yapılandırılana kadar kullanılan simülasyon. Para hareketi YAPMAZ. */
export class SimulatedProvider implements PaymentProvider {
  readonly name = "simulation";
  private readonly statuses = new Map<string, PaymentStatus>();

  async createSession(input: CreateSessionInput): Promise<PaymentSession> {
    assertValidMoney(input.amount);
    const providerRef = `SIM-${input.paymentId}`;
    this.statuses.set(providerRef, "pending");
    return { providerRef, checkoutUrl: null, simulated: true };
  }

  async getStatus(providerRef: string): Promise<PaymentStatus> {
    const status = this.statuses.get(providerRef);
    if (!status) throw new Error(`Bilinmeyen sağlayıcı referansı: ${providerRef}`);
    return status;
  }

  /** Yalnızca testlerde/simülasyon arayüzünde sonucu belirlemek için. */
  simulateResult(providerRef: string, status: PaymentStatus): void {
    this.statuses.set(providerRef, status);
  }
}

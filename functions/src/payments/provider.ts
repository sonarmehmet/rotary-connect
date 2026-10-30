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

/** Sağlayıcının sunucu-sunucu bildirdiği kesin sonuç (tutar dahil). */
export interface ProviderResult {
  readonly status: PaymentStatus;
  readonly amountMinor: number | null;
  readonly currency: string | null;
  readonly failureCode?: string;
}

/** Sağlayıcıdan bağımsız arayüz. Gerçek sağlayıcı (iyzico/PayTR) Aşama 8'de eklenir. */
export interface PaymentProvider {
  readonly name: string;
  createSession(input: CreateSessionInput): Promise<PaymentSession>;
  /** Sağlayıcıdan sunucu-sunucu durum sorgusu (webhook gelmezse mutabakat için). */
  getStatus(providerRef: string): Promise<PaymentStatus>;
  /**
   * Durum + SAĞLAYICININ bildirdiği tutar. Varsa webhook ve mutabakat BUNU kullanır (tutar
   * doğrulaması sağlayıcıdan gelir, kendi kaydımızdan değil). Yoksa yalnızca simülasyon içindir.
   */
  getResult?(providerRef: string): Promise<ProviderResult>;
  /** Para iadesi. `idempotencyKey` aynıysa sağlayıcıda tekrar iade OLUŞMAMALI. Hata fırlatır. */
  refund?(providerRef: string, amountMinor: number, idempotencyKey: string): Promise<void>;
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

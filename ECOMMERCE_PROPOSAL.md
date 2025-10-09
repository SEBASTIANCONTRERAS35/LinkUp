# Sistema de E-Commerce P2P para StadiumConnect Pro

**Última actualización:** 7 de octubre de 2025
**Estado:** Propuesta técnica - Pendiente implementación
**Categoría CSC 2025:** App Inclusiva

---

## 📋 Resumen Ejecutivo

Propuesta de sistema de comercio P2P offline para StadiumConnect Pro que permite transacciones entre compradores y vendedores durante eventos masivos sin dependencia de infraestructura de red celular, utilizando la red mesh existente de MeshRed + sistema criptográfico de créditos pre-cargados.

---

## ❌ Limitaciones Técnicas Investigadas

### Apple Pay P2P Offline - NO VIABLE

**Hallazgos de investigación (Octubre 2025):**

- ❌ **Apple Pay requiere internet** para todas las transferencias P2P
- ❌ **Tap to Cash (iOS 18)** también requiere WiFi/celular obligatoriamente
- ❌ **NFC solo funciona offline** para terminales POS certificadas, no entre usuarios finales
- ✅ **Apple Pay funciona offline** SOLO para pagos a comercios con terminal, no iPhone-a-iPhone

**Fuentes:**
- Apple Support: "Tap to Cash requires stable Wi-Fi or cellular connection"
- Developer Forums: "NFC-based P2P payments require internet for fund transfer"
- Payment providers: Offline mode solo disponible para merchant POS con store-and-forward

**Conclusión:** Necesitamos solución alternativa basada en tokens/créditos locales.

---

## ✅ Soluciones Viables Propuestas

### Comparativa de 3 Opciones

| Opción | Funcionamiento Offline | Complejidad | Riesgo Fraude | Viabilidad 2 Semanas |
|--------|----------------------|-------------|---------------|---------------------|
| 1. Stadium Wallet (Tokens) | ✅ 100% | Media | Bajo (con mitigaciones) | ✅ Alta |
| 2. Pay-Later Deferred | ⚠️ 80% | Baja | Alto | ✅ Alta |
| 3. Hybrid QR + Mesh | ❌ 30% | Baja | Muy bajo | ✅ Alta |

---

## 🏆 OPCIÓN RECOMENDADA: Stadium Wallet con Tokens Criptográficos

### Concepto Central

Sistema de **créditos pre-cargados** del estadio + vouchers digitales firmados criptográficamente que circulan vía red mesh offline, sin requerir infraestructura centralizada durante el evento.

### Arquitectura Técnica

#### Frameworks iOS Requeridos

```swift
import CryptoKit                // Firmas digitales Ed25519
import MultipeerConnectivity    // Red mesh (ya existente en MeshRed)
import PassKit                  // Apple Pay para pre-carga online
import Security                 // Keychain Secure Enclave
import SwiftUI                  // UI nativa
import CoreData                 // Persistencia de transacciones
```

#### Flujo del Usuario - 3 Fases

##### **FASE 1: Pre-evento (CON INTERNET)**

1. Usuario abre app y selecciona "Cargar Stadium Credits"
2. Elige monto: $10, $20, $50, $100 (conversion 1:1 - $20 = 20 créditos)
3. Paga con Apple Pay estándar
4. Backend del estadio:
   - Valida pago
   - Genera certificado digital firmado con clave privada del estadio
   - Envía créditos firmados al wallet del usuario
5. App genera par de llaves criptográficas locales (si es primera vez):
   - **Clave privada:** Almacenada en Keychain Secure Enclave
   - **Clave pública:** Registrada en backend del estadio
6. Saldo se almacena localmente con firma del estadio

**Seguridad:** Certificado incluye `userID`, `amount`, `timestamp`, `eventID`, firmado con HMAC-SHA256.

---

##### **FASE 2: Durante el evento (SIN INTERNET - MESH ONLY)**

**A) Descubrimiento de vendedores**

1. Vendedor registrado inicia "Merchant Mode"
2. App del vendedor hace broadcast cada 5 segundos vía mesh:
   ```swift
   MerchantBroadcast {
       merchantID: "VENDOR_123"
       merchantName: "Tacos El Azteca"
       location: CLLocation
       catalog: [Product]
       publicKey: Data
   }
   ```
3. Clientes cercanos (<50m) reciben notificación:
   - "Tacos El Azteca a 15 metros - Ver menú"
   - Integración con UWB (LinkFinder) muestra dirección exacta

**B) Navegación de catálogo**

4. Cliente tap en notificación → abre catálogo offline
5. Ve productos con:
   - Foto (almacenada local en cache)
   - Nombre: "Taco de Carnitas"
   - Precio: 3 créditos
   - Disponibilidad: "✅ Disponible (23 restantes)"

**C) Proceso de compra**

6. Cliente agrega productos al carrito
7. Revisa total: 3 tacos + 1 refresco = 11 créditos
8. Tap en "Comprar con Stadium Wallet"
9. App genera transacción firmada:
   ```swift
   SignedTransaction {
       txID: UUID()
       buyerPublicKey: Data
       merchantPublicKey: Data
       items: [CartItem]
       totalAmount: 11
       timestamp: Date()
       signature: Data  // Firmado con clave privada del comprador
   }
   ```
10. Transacción se envía vía mesh al vendedor
11. **Validación del vendedor (LOCAL):**
    - ✅ Firma válida (verifica con clave pública del comprador)
    - ✅ TxID único (no duplicado en su ledger local)
    - ✅ Timestamp reciente (<5 minutos)
    - ✅ Productos disponibles en inventario
12. Vendedor envía confirmación firmada vía mesh
13. **Actualizaciones locales (ambos dispositivos):**
    - Comprador: Balance 20 → 9 créditos
    - Vendedor: Balance 0 → +11 créditos pendientes liquidación
    - Ambos: Agregan transacción a TransactionLedger local

**D) Reclamación del producto**

14. Cliente recibe QR code único:
    ```swift
    ClaimToken {
        txID: UUID
        items: ["3x Taco Carnitas", "1x Coca-Cola"]
        claimCode: "A7X9-2K4P"  // 8 dígitos alfanuméricos
        expiresAt: Date (30 minutos)
        signature: Data
    }
    ```
15. Cliente muestra QR al vendedor
16. Vendedor escanea → valida firma → marca como "Entregado"
17. Cliente recibe producto físico

**Prevención de fraude en esta fase:**
- ❌ **Doble gasto:** TransactionLedger local detecta TxID duplicado
- ❌ **Balance negativo:** App no permite compra si saldo insuficiente
- ❌ **QR clonado:** Firma digital + expiración de 30 min
- ❌ **Replay attack:** Timestamp + nonce único por transacción

---

##### **FASE 3: Post-evento (CON INTERNET)**

18. Cuando dispositivos recuperan conexión:
    - Background sync automático se activa
    - TransactionLedger local se envía a backend del estadio
    - Backend valida:
      - ✅ Todas las firmas
      - ✅ No hay doble gasto cross-device
      - ✅ Balances cuadran
19. **Liquidación para vendedores:**
    - Backend transfiere créditos → dinero real
    - Depósito bancario en 24-48 horas
    - Vendedor recibe notificación: "Liquidación completada: $234.50"
20. **Análisis de fraude:**
    - ML detecta patrones sospechosos:
      - Transacciones con timestamps imposibles
      - Velocidad de gasto anómala
      - Vendedores con tasa de rechazo alta
    - Casos flagged para revisión manual

---

### Componentes de Software

#### 1. StadiumWallet (Core)

```swift
@Observable
class StadiumWallet {
    // MARK: - Properties
    private let privateKey: SecKey          // Keychain Secure Enclave
    public let publicKey: SecKey
    private(set) var balance: Int           // Créditos disponibles
    private(set) var pendingTx: [Transaction] // Cola de sync

    // MARK: - Crypto Operations
    func signTransaction(_ tx: Transaction) throws -> Data {
        // CryptoKit Ed25519 signing
        let signature = try privateKey.signature(for: tx.dataToSign)
        return signature.rawRepresentation
    }

    func verifyTransaction(_ tx: SignedTransaction) -> Bool {
        // Verify signature with sender's public key
        guard let senderKey = tx.senderPublicKey else { return false }
        return senderKey.isValidSignature(tx.signature, for: tx.dataToSign)
    }

    // MARK: - Balance Management
    func deductBalance(_ amount: Int) throws {
        guard balance >= amount else {
            throw WalletError.insufficientFunds
        }
        balance -= amount
        saveToKeychain()
    }

    func addBalance(_ amount: Int) {
        balance += amount
        saveToKeychain()
    }

    // MARK: - Server Sync
    func syncWithServer() async throws {
        let response = try await APIClient.shared.syncLedger(pendingTx)
        // Handle reconciliation if server rejects any tx
        processSyncResponse(response)
    }
}
```

---

#### 2. MerchantBroadcaster

```swift
@Observable
class MerchantBroadcaster {
    // MARK: - Properties
    var catalog: [Product]
    var merchantInfo: MerchantProfile
    private var broadcastTimer: Timer?

    // MARK: - Broadcasting
    func startBroadcasting() {
        broadcastTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.sendCatalogBroadcast()
        }
    }

    private func sendCatalogBroadcast() {
        let message = MerchantBroadcastMessage(
            merchantID: merchantInfo.id,
            merchantName: merchantInfo.name,
            location: LocationManager.shared.currentLocation,
            catalog: catalog.filter { $0.isAvailable },
            publicKey: merchantInfo.publicKey
        )

        // Send via existing MeshNetworkManager
        NetworkManager.shared.broadcast(message, priority: .location)
    }

    // MARK: - Order Processing
    func receiveOrder(_ order: SignedOrder) async -> OrderConfirmation {
        // 1. Verify signature
        guard StadiumWallet.shared.verifyTransaction(order) else {
            return OrderConfirmation(status: .rejected, reason: "Invalid signature")
        }

        // 2. Check for duplicate
        guard !TransactionLedger.shared.contains(order.txID) else {
            return OrderConfirmation(status: .rejected, reason: "Duplicate transaction")
        }

        // 3. Verify inventory
        guard hasInventoryFor(order.items) else {
            return OrderConfirmation(status: .rejected, reason: "Out of stock")
        }

        // 4. Record transaction
        try? TransactionLedger.shared.append(order)

        // 5. Generate claim token
        let claimToken = generateClaimToken(for: order)

        // 6. Update inventory
        deductInventory(order.items)

        return OrderConfirmation(
            status: .accepted,
            claimToken: claimToken,
            estimatedReadyTime: Date().addingTimeInterval(300) // 5 min
        )
    }
}
```

---

#### 3. TransactionLedger

```swift
@Observable
class TransactionLedger {
    // MARK: - Properties
    private(set) var transactions: [SignedTransaction] = []
    private let storage = CoreDataStack.shared

    // MARK: - Append-Only Operations
    func append(_ tx: SignedTransaction) throws {
        // 1. Check for duplicate
        guard !contains(tx.txID) else {
            throw LedgerError.duplicateTransaction
        }

        // 2. Verify signature
        guard tx.verify() else {
            throw LedgerError.invalidSignature
        }

        // 3. Append to in-memory array
        transactions.append(tx)

        // 4. Persist to CoreData
        try storage.save(tx)
    }

    func contains(_ txID: UUID) -> Bool {
        return transactions.contains { $0.txID == txID }
    }

    // MARK: - Fraud Detection
    func detectDoubleSpend() -> [Transaction] {
        var seenTxIDs = Set<UUID>()
        var duplicates: [Transaction] = []

        for tx in transactions {
            if seenTxIDs.contains(tx.txID) {
                duplicates.append(tx)
            } else {
                seenTxIDs.insert(tx.txID)
            }
        }

        return duplicates
    }

    func detectSuspiciousPatterns() -> [FraudAlert] {
        var alerts: [FraudAlert] = []

        // Pattern 1: Spending rate > 10 credits/minute
        let recentTx = transactions.filter { $0.timestamp > Date().addingTimeInterval(-60) }
        let recentTotal = recentTx.reduce(0) { $0 + $1.amount }
        if recentTotal > 10 {
            alerts.append(.highSpendingRate(amount: recentTotal))
        }

        // Pattern 2: Transactions with same timestamp
        let groupedByTime = Dictionary(grouping: transactions) { $0.timestamp }
        for (time, txs) in groupedByTime where txs.count > 1 {
            alerts.append(.simultaneousTransactions(count: txs.count, time: time))
        }

        return alerts
    }

    // MARK: - Export for Sync
    func exportForSync() -> Data {
        let encoder = JSONEncoder()
        return try! encoder.encode(transactions)
    }
}
```

---

#### 4. Integración con NetworkManager Existente

```swift
// Nuevos tipos de mensaje para e-commerce
enum ECommerceMessageType: Codable {
    case merchantBroadcast(MerchantBroadcastMessage)
    case productQuery(merchantID: String)
    case purchaseOrder(SignedOrder)
    case orderConfirmation(OrderConfirmation)
    case claimToken(ClaimToken)
}

// Extensión de NetworkMessage para e-commerce
extension NetworkMessage {
    static func ecommerce(
        _ type: ECommerceMessageType,
        from sender: MCPeerID
    ) -> NetworkMessage {
        let content = try! JSONEncoder().encode(type)
        return NetworkMessage(
            id: UUID(),
            senderID: sender.displayName,
            content: String(data: content, encoding: .utf8)!,
            timestamp: Date(),
            type: .location,  // Reusa prioridad location
            requiresAck: true
        )
    }
}

// Handler en NetworkManager
extension NetworkManager {
    func handleECommerceMessage(_ message: NetworkMessage) {
        guard let data = message.content.data(using: .utf8),
              let type = try? JSONDecoder().decode(ECommerceMessageType.self, from: data) else {
            return
        }

        switch type {
        case .merchantBroadcast(let broadcast):
            MerchantDiscoveryService.shared.addMerchant(broadcast)
        case .purchaseOrder(let order):
            MerchantBroadcaster.shared.receiveOrder(order)
        case .orderConfirmation(let confirmation):
            OrderTracker.shared.updateOrder(confirmation)
        // ... otros casos
        }
    }
}
```

---

### Arquitectura del Sistema

```
┌─────────────────────────────────────────────────────────────────┐
│              StadiumConnect Pro E-Commerce Layer                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────┐         ┌──────────────────────┐    │
│  │   CLIENT DEVICE      │         │   MERCHANT DEVICE    │    │
│  │                      │         │                      │    │
│  │  ┌────────────────┐ │         │ ┌────────────────┐  │    │
│  │  │ StadiumWallet  │ │         │ │ MerchantBroadcaster│ │    │
│  │  │ Balance: 20    │ │         │ │ Catalog: [...]  │  │    │
│  │  │ PrivKey: 🔐    │ │         │ │ PubKey: 🔑      │  │    │
│  │  └────────────────┘ │         │ └────────────────┘  │    │
│  │                      │         │                      │    │
│  │  ┌────────────────┐ │  Mesh   │ ┌────────────────┐  │    │
│  │  │ Transaction    │◄├─────────┤►│ Transaction    │  │    │
│  │  │ Ledger (Local) │ │ Network │ │ Ledger (Local) │  │    │
│  │  └────────────────┘ │         │ └────────────────┘  │    │
│  │                      │         │                      │    │
│  │  ┌────────────────┐ │         │ ┌────────────────┐  │    │
│  │  │ Order UI       │ │         │ │ Order Manager  │  │    │
│  │  │ Cart View      │ │         │ │ POS Interface  │  │    │
│  │  └────────────────┘ │         │ └────────────────┘  │    │
│  └──────────────────────┘         └──────────────────────┘    │
│             │                               │                  │
│             └───────────────┬───────────────┘                  │
│                             │                                  │
│                    ┌────────▼─────────┐                       │
│                    │ MeshNetworkManager│                       │
│                    │  (Existing from   │                       │
│                    │   MeshRed Base)   │                       │
│                    └──────────────────┘                       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐    │
│  │           CryptoKit Security Layer                    │    │
│  │  • Ed25519 Signature Algorithm                       │    │
│  │  • Keychain Secure Enclave Storage                   │    │
│  │  • HMAC-SHA256 for Stadium Certificates              │    │
│  │  • Transaction Verification                          │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐    │
│  │           CoreData Persistence Layer                  │    │
│  │  • Transaction History                                │    │
│  │  • Merchant Catalog Cache                             │    │
│  │  • Sync Queue Management                              │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 │ When Internet Available
                                 ▼
                  ┌────────────────────────────┐
                  │   BACKEND SERVER           │
                  │   (Stadium Infrastructure) │
                  │                            │
                  │  • Ledger Validation       │
                  │  • Double-Spend Detection  │
                  │  • Credit Liquidation      │
                  │  • Fraud Analysis (ML)     │
                  │  • Vendor Payouts          │
                  │  • Apple Pay Integration   │
                  │  • Analytics Dashboard     │
                  └────────────────────────────┘
```

---

### Modelos de Datos

```swift
// Product.swift
struct Product: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let price: Int  // En créditos
    let imageURL: String?
    let category: ProductCategory
    var stockQuantity: Int
    var isAvailable: Bool { stockQuantity > 0 }
}

enum ProductCategory: String, Codable {
    case food, beverage, merchandise, services
}

// Transaction.swift
struct SignedTransaction: Codable, Identifiable {
    let id: UUID  // TxID único
    let buyerPublicKey: Data
    let merchantPublicKey: Data
    let items: [CartItem]
    let totalAmount: Int
    let timestamp: Date
    let signature: Data
    let nonce: String  // Prevenir replay attacks

    var dataToSign: Data {
        // Serializa todo excepto signature
        var data = Data()
        data.append(id.uuidString.data(using: .utf8)!)
        data.append(buyerPublicKey)
        data.append(merchantPublicKey)
        data.append("\(totalAmount)".data(using: .utf8)!)
        data.append("\(timestamp.timeIntervalSince1970)".data(using: .utf8)!)
        data.append(nonce.data(using: .utf8)!)
        return data
    }

    func verify() -> Bool {
        // Implementado en StadiumWallet
        return StadiumWallet.shared.verifyTransaction(self)
    }
}

// CartItem.swift
struct CartItem: Codable {
    let product: Product
    let quantity: Int
    var subtotal: Int { product.price * quantity }
}

// ClaimToken.swift
struct ClaimToken: Codable {
    let txID: UUID
    let items: [String]  // Nombres legibles para UI
    let claimCode: String  // "A7X9-2K4P"
    let expiresAt: Date
    let signature: Data

    func toQRCode() -> UIImage {
        // Genera QR con JSONEncoder + CIFilter
    }
}

// OrderConfirmation.swift
struct OrderConfirmation: Codable {
    enum Status: String, Codable {
        case accepted, rejected, preparing, ready
    }

    let status: Status
    let claimToken: ClaimToken?
    let estimatedReadyTime: Date?
    let rejectionReason: String?
}
```

---

### Seguridad y Prevención de Fraude

#### Mecanismos Implementados

##### 1. Criptografía de Clave Pública (Ed25519)

```swift
// Generación segura de llaves
let privateKey = P256.Signing.PrivateKey()
let publicKey = privateKey.publicKey

// Firma de transacción
let signature = try! privateKey.signature(for: transaction.dataToSign)

// Verificación
if publicKey.isValidSignature(signature, for: transaction.dataToSign) {
    // Transacción válida
}
```

**Ventajas:**
- ✅ Imposible falsificar transacciones sin clave privada
- ✅ Cada transacción es única y verificable
- ✅ No se puede modificar una transacción después de firmada

---

##### 2. Prevención de Doble Gasto (Double-Spend)

**Nivel Local (Durante evento offline):**

```swift
func validateTransaction(_ tx: SignedTransaction) -> Bool {
    // Check 1: TxID único
    guard !ledger.contains(tx.id) else {
        logFraudAttempt(.duplicateTxID(tx.id))
        return false
    }

    // Check 2: Balance suficiente (para compradores)
    if tx.buyerPublicKey == myPublicKey {
        guard wallet.balance >= tx.totalAmount else {
            return false
        }
    }

    // Check 3: Timestamp razonable (no del futuro, no muy viejo)
    let now = Date()
    guard tx.timestamp <= now &&
          tx.timestamp > now.addingTimeInterval(-300) else {  // Max 5 min old
        return false
    }

    return true
}
```

**Nivel Servidor (Post-evento):**

```swift
// Backend validation endpoint
func validateLedger(_ ledger: [SignedTransaction]) -> ValidationResult {
    var globalTxIDs = Set<UUID>()
    var fraudulentTxs: [SignedTransaction] = []

    for tx in ledger {
        // Cross-device double-spend detection
        if globalTxIDs.contains(tx.id) {
            fraudulentTxs.append(tx)
            flagUserForReview(tx.buyerPublicKey)
        } else {
            globalTxIDs.insert(tx.id)
        }

        // Verify signatures again server-side
        if !tx.verify(using: publicKeyDatabase) {
            fraudulentTxs.append(tx)
        }
    }

    return ValidationResult(
        valid: ledger.count - fraudulentTxs.count,
        fraudulent: fraudulentTxs
    )
}
```

---

##### 3. Límites de Seguridad

```swift
struct SecurityLimits {
    static let maxCreditsPerWallet = 500         // Max 500 créditos
    static let maxCreditsPerTransaction = 50     // Max 50 créditos por compra
    static let maxTransactionsPerMinute = 5      // Anti-spam
    static let transactionTimeoutSeconds = 300   // 5 minutos para confirmar
    static let claimTokenExpiryMinutes = 30      // QR expira en 30 min
    static let maxPendingTransactions = 20       // Cola de sync limitada
}

// Enforcement
func attemptPurchase(amount: Int) throws {
    guard amount <= SecurityLimits.maxCreditsPerTransaction else {
        throw WalletError.transactionLimitExceeded
    }

    let recentTxs = ledger.transactions(since: Date().addingTimeInterval(-60))
    guard recentTxs.count < SecurityLimits.maxTransactionsPerMinute else {
        throw WalletError.rateLimitExceeded
    }

    // Proceed with purchase...
}
```

---

##### 4. Protección de Claves Privadas

```swift
// Almacenamiento en Keychain Secure Enclave
class KeychainManager {
    static func storePrivateKey(_ key: P256.Signing.PrivateKey) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecAttrApplicationTag as String: "com.stadium.wallet.privatekey",
            kSecValueData as String: key.rawRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }
}
```

**Características:**
- ✅ Clave nunca sale del Secure Enclave
- ✅ Requiere autenticación biométrica (Face ID/Touch ID) para firmar
- ✅ No exportable, no extraíble del dispositivo
- ✅ Protegida contra jailbreak y malware

---

##### 5. Detección de Patrones Fraudulentos (ML Backend)

```python
# Backend fraud detection model (pseudocode)
class FraudDetector:
    def analyze_transaction(self, tx: Transaction) -> FraudScore:
        score = 0

        # Feature 1: Velocidad de gasto
        user_history = get_user_transactions(tx.buyer_id)
        spending_rate = calculate_spending_rate(user_history)
        if spending_rate > THRESHOLD_HIGH:
            score += 30

        # Feature 2: Geolocation imposible
        if has_impossible_geolocation(user_history):
            score += 50  # Ej: compra en 2 lugares a >1km en <1 min

        # Feature 3: Patrón de vendedor sospechoso
        merchant_stats = get_merchant_stats(tx.merchant_id)
        if merchant_stats.rejection_rate > 0.3:  # >30% rechazos
            score += 20

        # Feature 4: Timestamp clustering
        if has_timestamp_clustering(user_history):
            score += 40  # Múltiples tx con mismo timestamp

        # Feature 5: Nuevo usuario con gasto alto
        if tx.buyer_age_days < 1 and tx.amount > 100:
            score += 25

        return FraudScore(
            score=score,
            action="block" if score > 70 else "review" if score > 40 else "allow"
        )
```

**Acciones según score:**
- **0-40:** ✅ Transacción permitida automáticamente
- **41-70:** ⚠️ Flagged para revisión manual en 24h
- **71-100:** ❌ Bloqueada, usuario contactado

---

#### Matriz de Riesgos y Mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación | Estado |
|--------|-------------|---------|------------|--------|
| Usuario clona wallet a 2 dispositivos | Media | Alto | Keychain no exportable + backend detecta TxID duplicado | ✅ Mitigado |
| Vendedor acepta tx y no entrega producto | Media | Medio | Sistema de ratings + depósito en garantía | ⚠️ Parcial |
| Ataque man-in-the-middle en mesh | Baja | Alto | Firmas digitales en cada mensaje | ✅ Mitigado |
| Usuario hackea app para modificar balance local | Baja | Alto | Balance validado server-side en sync + firmas del estadio | ✅ Mitigado |
| Vendedor malicioso crea productos falsos | Media | Medio | Vendedores pre-registrados con KYC + auditoría | ✅ Mitigado |
| QR claim token fotografiado y reusado | Alta | Bajo | Expiración 30 min + marca como "usado" tras escaneo | ✅ Mitigado |
| Replay attack (reenvío de tx antigua) | Media | Alto | Nonce único + timestamp validation | ✅ Mitigado |

---

### Plan de Implementación - 5 Días

#### **Día 1: Wallet Core + Crypto** (8 horas)

**Objetivo:** Implementar generación de llaves, firma y verificación

**Tareas:**
- [ ] `StadiumWallet.swift` - Clase base con CryptoKit
- [ ] Generación de par de llaves Ed25519
- [ ] Almacenamiento en Keychain Secure Enclave
- [ ] Métodos `signTransaction()` y `verifyTransaction()`
- [ ] UI básica: WalletView con balance display
- [ ] Tests unitarios de firma/verificación

**Entregables:**
```swift
// Demo funcional:
let wallet = StadiumWallet()
let tx = Transaction(amount: 10, merchant: "TEST")
let signed = wallet.signTransaction(tx)
print(wallet.verifyTransaction(signed))  // true
```

---

#### **Día 2: Transaction Ledger + Models** (8 horas)

**Objetivo:** Sistema de registro de transacciones y modelos de datos

**Tareas:**
- [ ] `TransactionLedger.swift` - Append-only log
- [ ] `Product.swift`, `Transaction.swift`, `ClaimToken.swift` models
- [ ] CoreData stack para persistencia
- [ ] Métodos de detección de doble gasto local
- [ ] UI: TransactionHistoryView
- [ ] Tests: Duplicate detection

**Entregables:**
```swift
// Demo funcional:
let ledger = TransactionLedger()
try ledger.append(signedTx)
let duplicates = ledger.detectDoubleSpend()  // []
```

---

#### **Día 3: Merchant System + Mesh Integration** (10 horas)

**Objetivo:** Sistema de vendedores y comunicación mesh

**Tareas:**
- [ ] `MerchantBroadcaster.swift` - Catálogo broadcast
- [ ] `MerchantDiscoveryService.swift` - Cliente recibe broadcasts
- [ ] Integración con `NetworkManager` existente
- [ ] Nuevos message types: `ECommerceMessageType`
- [ ] UI: MerchantListView + ProductCatalogView
- [ ] Tests: Multi-device con 2 simuladores

**Entregables:**
```swift
// Demo funcional:
// Device A (Vendedor):
broadcaster.startBroadcasting()

// Device B (Cliente):
// Recibe notificación: "Tacos El Azteca - 15m"
```

---

#### **Día 4: Purchase Flow + Claim Tokens** (10 horas)

**Objetivo:** Flujo completo de compra y reclamación

**Tareas:**
- [ ] UI: CartView + CheckoutView
- [ ] Lógica de compra: Generar tx firmada → enviar vía mesh
- [ ] `OrderManager.swift` - Tracking de órdenes
- [ ] Generación de QR con CIFilter
- [ ] Validación de claim tokens
- [ ] UI: ClaimTokenView + ScannerView
- [ ] Tests: Flujo end-to-end

**Entregables:**
```swift
// Demo funcional:
// 1. Cliente agrega 3 tacos al carrito
// 2. Compra con wallet
// 3. Recibe QR
// 4. Vendedor escanea QR
// 5. Marca como entregado
```

---

#### **Día 5: Polish + Testing + Security** (8 horas)

**Objetivo:** Refinamiento, testing exhaustivo, hardening de seguridad

**Tareas:**
- [ ] Implementar todos los `SecurityLimits`
- [ ] Añadir biometric authentication para compras >20 créditos
- [ ] Fraud detection patterns básicos
- [ ] Error handling robusto (network failures, etc.)
- [ ] UI/UX polish: loading states, animations
- [ ] Accessibility: VoiceOver labels
- [ ] Testing multi-device con 3-4 simuladores
- [ ] Documentación de API

**Entregables:**
```swift
// Demo completo:
// - 2 clientes + 1 vendedor
// - 5 productos diferentes
// - 10 transacciones concurrentes
// - Manejo de errores (insufficient funds, out of stock)
// - Detección de fraude (double-spend attempt)
```

---

### Integración con StadiumConnect Pro Existente

#### Componentes Reutilizables

##### 1. MeshNetworkManager (Base de MeshRed)

```swift
// Ya existente - solo agregar handlers
extension NetworkManager {
    func sendECommerceMessage(_ message: ECommerceMessageType, to peer: MCPeerID) {
        let networkMsg = NetworkMessage.ecommerce(message, from: myPeerID)
        send(networkMsg, to: peer)
    }
}
```

##### 2. LinkFinder (UWB Integration)

```swift
// Usar para mostrar dirección exacta al vendedor
class MerchantNavigator {
    func navigateToMerchant(_ merchant: MerchantProfile) {
        // Usar UWBLocationService existente
        let direction = UWBLocationService.shared.getDirection(to: merchant.uwbToken)

        // UI: Flecha apuntando + distancia
        showARNavigationOverlay(direction: direction, distance: merchant.distance)
    }
}
```

##### 3. LinkFencing (Geofencing)

```swift
// Notificaciones contextuales de comercio
extension LinkFenceManager {
    func setupCommerceZones() {
        // Zona de concesiones
        addZone(
            name: "Concessions",
            radius: 50,
            onEntry: {
                NotificationManager.send("🍕 Hambre? Tacos a 10m - Ver menú")
            }
        )

        // Zona de merchandise
        addZone(
            name: "Merchandise",
            radius: 30,
            onEntry: {
                NotificationManager.send("🎽 Jerseys oficiales disponibles")
            }
        )
    }
}
```

---

### Casos de Uso para Demo CSC 2025

#### **Demo 1: Compra Básica de Cerveza** (2 minutos)

**Setup:**
- iPhone A (Cliente): Wallet con 50 créditos
- iPhone B (Vendedor): "Cervecería Corona" con 10 productos

**Script:**
1. Vendedor inicia "Merchant Mode"
2. Cliente recibe notificación push: "🍺 Cervecería Corona a 8 metros"
3. Cliente tap → ve catálogo con fotos
4. Agrega "Cerveza Corona 355ml - 8 créditos" al carrito
5. Tap "Comprar" → Face ID authentication
6. ✅ Transacción completada en 2 segundos (sin internet)
7. Recibe QR de reclamación
8. Vendedor escanea QR → entrega cerveza
9. Balance actualizado: 50 → 42 créditos

**Narración para jueces:**
> "Estamos en el minuto 87 del México vs. Argentina. 80,000 personas tienen celular activado. Las redes están colapsadas. Pero con StadiumConnect Pro, puedes comprar tu cerveza en 2 segundos sin depender de internet. Todo funciona via Bluetooth mesh."

---

#### **Demo 2: Descubrimiento de Food Trucks con LinkFinder** (3 minutos)

**Setup:**
- 3 iPhones como vendedores: "Tacos", "Hot Dogs", "Elotes"
- 1 iPhone como cliente
- Usar UWB real (dispositivos físicos, no simulador)

**Script:**
1. Cliente abre "Buscar Comida"
2. Mapa mesh muestra 3 vendedores con pines
3. Cliente busca "tacos" → filtro muestra solo "Tacos El Azteca"
4. Tap → activa navegación LinkFinder (UWB)
5. Flecha AR aparece apuntando al vendedor: "15 metros → "
6. Cliente camina hacia el vendedor (demo en vivo caminando)
7. Distancia actualiza: 15m → 10m → 5m → 2m
8. Llega al vendedor → ve menú con fotos
9. Ordena 3 tacos + 1 refresco = 15 créditos
10. Paga con wallet → recibe QR
11. Vendedor escanea → confirma "Listo en 5 minutos"

**Narración:**
> "Combina nuestro mesh network con Ultra-Wideband para localización centimétrica. No solo encuentras comida - te guiamos exactamente hasta el vendedor en medio de una multitud de 80,000 personas."

---

#### **Demo 3: Prevención de Fraude en Tiempo Real** (2 minutos)

**Setup:**
- 1 iPhone "atacante" con wallet clonado (simulado)
- 1 iPhone vendedor legítimo

**Script:**
1. Cliente legítimo compra 1 hot dog - 5 créditos
2. Transacción exitosa, balance 50 → 45
3. Atacante intenta reenviar la MISMA transacción (replay attack)
4. Sistema detecta:
   - ❌ TxID duplicado en ledger
   - ❌ Timestamp viejo (>5 minutos)
5. Vendedor rechaza automáticamente
6. UI muestra: "⚠️ Fraude detectado - Transacción bloqueada"
7. Log de seguridad registra el intento

**Mostrar también:**
- Intento de gastar 200 créditos con balance de 50 → rechazado
- Intento de 10 compras en 1 minuto → rate limit bloqueado

**Narración:**
> "Seguridad es crítica en pagos offline. Usamos firmas Ed25519 - el mismo algoritmo que Bitcoin - más detección multi-capa de fraude. Cada transacción es única, verificable y no puede ser replicada."

---

#### **Demo 4: Sincronización Post-Evento** (1 minuto)

**Setup:**
- Cliente con 10 transacciones offline en ledger
- Vendedor con 50 ventas registradas
- Backend mock server

**Script:**
1. Mostrar ledger local: 10 transacciones pendientes sync
2. Conectar WiFi (simulado)
3. App detecta conexión → inicia sync automático
4. Loading indicator: "Sincronizando transacciones..."
5. Backend valida:
   - ✅ 10/10 firmas válidas
   - ✅ No double-spend detectado
   - ✅ Balances cuadran
6. Cliente: Historial actualizado con timestamps de servidor
7. Vendedor: Balance muestra "💰 $234.50 - Liquidación en proceso"
8. Notificación: "Transferencia bancaria: 1-2 días hábiles"

**Narración:**
> "Cuando el evento termina y recuperas internet, todo se sincroniza automáticamente. Nuestro backend valida cada transacción, detecta fraude cross-device, y liquida a los vendedores. Ellos reciben dinero real en su cuenta bancaria en 48 horas."

---

### Pitch para Jueces CSC 2025

#### Problema Identificado (30 segundos)

> "Durante el Mundial FIFA 2026 en el Estadio Azteca, 80,000 personas intentarán usar celular simultáneamente. Las redes colapsarán. Apple Pay no funciona sin internet. Stripe, Square, PayPal - todos requieren conectividad. Los vendedores pierden ventas. Los fans pierden la experiencia. Necesitamos una solución que funcione **cuando la infraestructura falla**."

---

#### Nuestra Solución (45 segundos)

> "StadiumConnect Pro introduce **Stadium Wallet** - el primer sistema de pagos P2P completamente offline para iOS. Funciona con 3 tecnologías:
>
> 1. **Mesh Network** via Bluetooth - comunicación sin infraestructura
> 2. **Criptografía Ed25519** - firmas digitales nivel militar
> 3. **Ultra-Wideband** - localización centimétrica
>
> Pre-cargas créditos con Apple Pay antes del evento. Durante el juego, compras comida, bebidas, merchandise - todo via mesh offline. Las transacciones se validan localmente con firmas criptográficas. Después del evento, se sincroniza con internet y vendedores reciben su dinero."

---

#### Diferenciación (30 segundos)

> "Ninguna otra plataforma hace esto. Square necesita terminal de $300. Apple Pay necesita internet. Nosotros solo necesitamos iPhones. Además, usamos UWB para guiarte exactamente hasta el vendedor - no solo 'cerca', sino centímetros de precisión. Y todo construido con tecnología 100% nativa de Apple - CryptoKit, MultipeerConnectivity, NearbyInteraction."

---

#### Impacto Social (30 segundos)

> "No solo para el Mundial. Imagina:
> - **Desastres naturales**: Pagos cuando internet colapsa
> - **Zonas rurales**: Comercio sin infraestructura
> - **Eventos masivos**: Cualquier estadio, festival, concierto
> - **Inclusión**: Vendedores informales acceden a pagos digitales sin terminal caro
>
> Democratizamos los pagos digitales para funcionar en las peores condiciones."

---

#### Cierre (15 segundos)

> "StadiumConnect Pro no es solo una app del hackathon. Es la infraestructura de comercio del futuro - descentralizada, resiliente, y accesible. Cuando la infraestructura falla, nosotros seguimos funcionando. Gracias."

---

### Comparativa con Competencia

| Característica | StadiumConnect Pro | Square Stadium | Retail Cloud | Apple Tap to Cash |
|---------------|-------------------|----------------|--------------|-------------------|
| **Offline P2P** | ✅ Sí (mesh) | ❌ No | ⚠️ Store-forward solo | ❌ Requiere internet |
| **Requiere Hardware** | ❌ Solo iPhone | ✅ Terminal ($299+) | ✅ POS + iPad ($1000+) | ❌ Solo iPhone |
| **Descubrimiento Mesh** | ✅ Sí | ❌ No | ❌ No | ❌ No |
| **Localización UWB** | ✅ Centímetros | ❌ No | ❌ No | ❌ No |
| **Costo Setup** | **$0** | $299-500 | $1000-3000 | $0 |
| **Funciona sin celular** | ✅ Sí | ⚠️ Limitado | ❌ No | ❌ No |
| **Liquidación Vendedores** | 24-48h | Instant | Instant | Instant |
| **Prevención Fraude** | ✅ Crypto + ML | ✅ PCI-DSS | ✅ PCI-DSS | ✅ Apple Secure |
| **Open Source** | ⚠️ Potencial | ❌ No | ❌ No | ❌ No |

---

### Escalabilidad y Futuro

#### Post-Mundial 2026

**Año 1 (2026-2027):**
- Implementación en 10 estadios mexicanos
- Partnership con Femsa (Oxxo) para vendedores registrados
- 50,000 transacciones en eventos masivos

**Año 2 (2027-2028):**
- Expansión a conciertos y festivales (Vive Latino, Pal Norte)
- API pública para third-party vendors
- 500,000 transacciones/año

**Año 3+ (2028+):**
- Mercados informales (tianguis, mercados)
- Zonas rurales sin infraestructura
- Emergency commerce (desastres naturales)
- 5M+ transacciones/año

---

#### Modelo de Negocio

**Revenue Streams:**

1. **Comisión por transacción**: 2.5% (vs. 2.9% de Square)
   - Ejemplo: $10 compra → $0.25 fee
   - Split: 1.5% estadio + 1% plataforma

2. **Suscripción vendedores**: $19/mes
   - Dashboard de analytics
   - Inventario management
   - Marketing push notifications

3. **Licencia a estadios**: $5,000/evento
   - White-label solution
   - Custom branding
   - Soporte técnico dedicado

4. **Data analytics**: $10,000/año (agregado, anónimo)
   - Heatmaps de tráfico
   - Productos más vendidos
   - Optimización de ubicaciones

**Proyección 3 años:**
- Año 1: $150K revenue (10 estadios, 50K tx)
- Año 2: $1.2M revenue (50 venues, 500K tx)
- Año 3: $8M revenue (200 venues, 5M tx)

---

### Consideraciones Legales y Compliance

#### Regulatorio

**México - CONDUSEF:**
- ✅ Stadium Credits son "vales" no regulados como dinero electrónico
- ✅ Similar a fichas de casino o puntos de lealtad
- ⚠️ Requiere Terms & Conditions claros: no reembolsables, no transferibles fuera del evento

**PCI-DSS:**
- ✅ Pre-carga con Apple Pay (Apple es PCI-compliant)
- ✅ No almacenamos tarjetas, solo tokens
- ✅ Créditos del estadio no son "stored value" regulado

**KYC/AML:**
- ⚠️ Vendedores requieren registro con ID oficial
- ⚠️ Límite de $10,000 MXN/día para prevenir lavado
- ✅ Logging de transacciones para auditoría

---

#### Términos y Condiciones

**Stadium Credits:**
- Válidos solo durante el evento (no expiran hasta 24h después)
- No reembolsables en dinero (solo en créditos)
- No transferibles entre usuarios
- Propiedad del estadio, no del usuario
- Conversión 1:1 con MXN para simplicidad

**Privacidad:**
- Transacciones pseudónimas (solo public keys visibles en mesh)
- Backend conoce identidad para compliance
- Datos encriptados en tránsito (TLS 1.3)
- Retención 7 años para auditoría

---

### Testing y QA

#### Test Matrix

| Escenario | Dispositivos | Condiciones | Expected Result |
|-----------|-------------|-------------|----------------|
| Compra básica | 2 (C+V) | Mesh only | ✅ Tx completa <3s |
| 10 clientes concurrentes | 11 (10C+1V) | Mesh only | ✅ No colisiones |
| Double-spend attack | 2 (C+V) | Replay tx | ❌ Rechazado |
| Insufficient funds | 2 (C+V) | Balance=5, compra=10 | ❌ Rechazado |
| Out of stock | 2 (C+V) | Producto qty=0 | ❌ Rechazado |
| QR expiry | 2 (C+V) | Claim después 30min | ❌ Rechazado |
| Network disruption | 2 (C+V) | Desconectar mid-tx | ⚠️ Retry automático |
| Sync after offline | 1 (C) | 50 tx offline → online | ✅ Sync completo |
| Multi-hop relay | 4 (C-R1-R2-V) | Cliente a 100m vendedor | ✅ Tx via relays |
| Background mode | 2 (C+V) | App backgrounded | ⚠️ Limitado iOS |

---

#### Performance Benchmarks

**Targets:**

- Transaction latency: <3 segundos (mesh discovery + signing + confirmation)
- Mesh range: 50 metros directo, 150m con 2 relays
- Battery impact: <5% por hora (background mesh)
- Concurrent vendors: 50 broadcasts sin degradación
- Storage: <10MB por 1000 transacciones

---

### Documentación para Vendedores

#### Onboarding Guide (1 página)

**Paso 1: Registro**
1. Descargar StadiumConnect Pro
2. Seleccionar "Soy Vendedor"
3. Completar KYC: ID oficial + comprobante domicilio
4. Subir foto del negocio
5. Agregar cuenta bancaria para liquidación

**Paso 2: Configuración**
1. Crear catálogo (max 50 productos)
2. Subir fotos (optimizadas para mesh)
3. Configurar precios en créditos
4. Definir inventario inicial

**Paso 3: Durante el Evento**
1. Activar "Modo Vendedor" al llegar al estadio
2. App comienza broadcast automático
3. Recibir órdenes → Escanear QR → Entregar producto
4. Monitorear inventario en tiempo real

**Paso 4: Post-Evento**
1. Cerrar "Modo Vendedor"
2. Revisar dashboard de ventas
3. Esperar liquidación bancaria (24-48h)
4. Revisar analytics para próximo evento

---

### Open Questions / Decisiones Pendientes

1. **¿Backend propio o third-party?**
   - Opción A: Firebase + Cloud Functions (rápido, caro)
   - Opción B: AWS Lambda + DynamoDB (flexible, complejo)
   - Opción C: Custom Swift server (Vapor framework)
   - **Recomendación:** Firebase para MVP, migrar a AWS después

2. **¿Liquidación directa o via procesador?**
   - Opción A: Stripe Connect (2.9% fee, simple)
   - Opción B: Integración bancaria directa (SPEI, complejo)
   - **Recomendación:** Stripe Connect para MVP

3. **¿Soportar Android?**
   - ⚠️ MultipeerConnectivity es iOS-only
   - Alternativa: Nearby Connections API (Android)
   - Requiere protocol bridge para interop
   - **Decisión:** Solo iOS para hackathon, Android en roadmap

4. **¿Sistema de ratings para vendedores?**
   - ✅ Sí, crítico para confianza
   - Post-transacción: "Califica tu experiencia 1-5⭐"
   - Vendedores con <3.5⭐ flagged para revisión

5. **¿Refunds y disputas?**
   - ⚠️ Complicado en sistema offline
   - Propuesta: Botón "Reportar problema" → ticket soporte
   - Staff del estadio resuelve manualmente
   - Refund en créditos, no dinero

---

## 🎯 Conclusión y Next Steps

### Por qué Stadium Wallet es la solución correcta:

1. ✅ **Tecnológicamente viable** - Solo usa frameworks nativos iOS
2. ✅ **Socialmente impactante** - Funciona cuando todo lo demás falla
3. ✅ **Comercialmente viable** - Modelo de negocio claro
4. ✅ **Diferenciado** - Ningún competidor hace esto
5. ✅ **Implementable en 2 semanas** - Plan realista con MeshRed base

### Próximos pasos para implementación:

- [ ] **Día 1:** Core wallet + crypto (8h)
- [ ] **Día 2:** Transaction ledger + models (8h)
- [ ] **Día 3:** Merchant system + mesh (10h)
- [ ] **Día 4:** Purchase flow + QR (10h)
- [ ] **Día 5:** Polish + testing (8h)

**Total: 44 horas de desarrollo (~1 semana con equipo de 2)**

---

### ¿Proceder con implementación?

Si apruebas esta propuesta, comenzamos con Día 1 inmediatamente. El código base de MeshRed ya nos da ~40% del trabajo (networking, message queue, peer discovery). Solo necesitamos agregar la capa de e-commerce encima.

**¿Preguntas o ajustes antes de empezar?**

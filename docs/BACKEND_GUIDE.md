# KOMEKCI SMS – Backend Geliştirici Rehberi

Bu doküman, mobil uygulamanın (Flutter / Android) SMS'leri nasıl takip ettiğini ve backend'in hangi API'leri sağlaması gerektiğini anlatır. Kaynak: `lib/app/home/controllers/home_controller.dart`, `lib/app/services/payment_api_service.dart`, `android/.../MainActivity.kt`.

## 1. Genel akış

```
Banka/operatör SMS'i (gönderen numara "...0801")
        │
        ▼
Android telefon (uygulama açık)
  ├─ canlı dinleme (SMS_RECEIVED broadcast)
  └─ her 1 dk'da inbox taraması (kaçan SMS'ler için)
        │  regex ile parse: tutar, gönderen telefon, zaman
        ▼
GET  /api/phone          → alıcı (receiver) numarasını al
POST /api/transactions   → işlemi backend'e bildir
        │
        ▼
Telefon yerelde durum kodunu saklar, hata olursa tekrar dener
```

Uygulama bir **SMS → HTTP köprüsüdür**: telefon SMS'i okur, ayrıştırır ve backend'e iletir. Backend'in işi bu işlemi kaydetmek (ve muhtemelen ilgili kullanıcıya bakiye/ödeme işlemek).

Base URL (uygulamada sabit): `https://komekchi.brandsforlesstm.com/api`

## 2. SMS'ler nasıl takip ediliyor?

### 2.1 Hangi SMS'ler işleniyor
- Sadece gönderen adresi **`0801` ile biten** SMS'ler (`senderNumber.endsWith("0801")`).
- Sadece uygulama **ilk kez açıldıktan sonra** gelen SMS'ler. İlk açılışta bir "cutoff" zamanı kaydedilir; ondan eski SMS'ler hiçbir zaman gönderilmez.
- İzinler: `READ_SMS`, `RECEIVE_SMS`, `READ_PHONE_STATE`, `READ_PHONE_NUMBERS`.

### 2.2 İki yakalama yolu
1. **Canlı dinleme:** Native Android `BroadcastReceiver` (`android.provider.Telephony.SMS_RECEIVED`) SMS geldiği anda Flutter'a event gönderir.
2. **Inbox taraması:** Açılışta ve her **1 dakikada bir** `content://sms/inbox` taranır (`address LIKE '%0801'`). Uygulama kapalıyken/arka planda gelen SMS'ler bir sonraki açılışta buradan yakalanır.

> Önemli: Kalıcı arka plan servisi **yok**. SMS dinleme ve tarama yalnızca uygulama açıkken çalışır. Telefon kapalı/uygulama kapalıysa işlemler gecikmeli gelir.

### 2.3 SMS formatları ve parse
Üç değer çıkarılır: **tutar**, **gönderen telefon**, **zaman**.

| Tip | SMS örneği | Regex | sender |
|---|---|---|---|
| Normal ödeme | `17/10/2026 17:39:07 gecirilen 20.00 manat. Su 99371821848` | `(\d+[.,]\d{1,2}) manat\. Su (\d{11})` | SMS'teki 11 haneli numara |
| Terminal top-up | `Sizin hasabynyz 20.00 manat kopeldi...` | `Sizin hasabynyz (\d+[.,]\d{1,2}) manat kopeldi.*` | sabit metin `"Terminaldan Gecdi"` |

- Tutarda virgül noktaya çevrilir (`20,00` → `20.00`).
- **Zaman:** SMS gövdesinde `dd/MM/yyyy HH:mm:ss` varsa o kullanılır; yoksa telefonun SMS alma zamanı (yerel saat) bu formata çevrilir. **Saat dilimi bilgisi yok** – yerel telefon saati (Türkmenistan, UTC+5) varsayın.
- Hiçbir formata uymayan SMS'ler yok sayılır, backend'e hiç gelmez.

### 2.4 Tekrar (duplicate) önleme – telefon tarafı
- Aynı SMS hem canlı hem inbox'tan gelebilir. Telefon, SMS **gövdesini (body)** anahtar olarak kullanır; aynı gövde ikinci kez kaydedilmez/gönderilmez. Gövde işlem zamanını içerdiği için farklı ödemeler farklı sayılır.
- Kayıt **POST'tan önce** "pending" (`statusCode = 0`) olarak eklenir, böylece eş zamanlı iki yol aynı işlemi iki kez göndermez.

## 3. Backend'in sağlaması gereken API'ler

### 3.1 `GET /api/phone` – Alıcı numarası
Her işlemden **önce** çağrılır (işlem başına bir kez). Hata alırsa işlem gönderilmez (lokal durum 503 olarak loglanır, sonra tekrar denenir).

İstek header: `Accept: application/json`, timeout 15 sn.

Başarılı yanıt (2xx). Uygulama esnektir, şu anahtarları sırayla arar ve iç içe `Map`'lerde 4 seviyeye kadar iner: `phone`, `phone_number`, `number`, `receiver`, `data`. Önerilen biçim:

```json
{ "data": { "phone": "+99364030911" } }
```

Numara formatı doğrulanır; kabul edilen girdiler: `+993XXXXXXXX`, `993XXXXXXXX`, `XXXXXXXX` (8 hane → `+993` eklenir). Boşluk/parantez/tire temizlenir. Geçersizse işlem **gönderilmez**.

Hata yanıtı (örnek, 404):
```json
{ "error": "На данный момент нет доступных номеров." }
```
Hata mesajı için sırayla `message_ru`, `error`, `message` alanları okunur ve kullanıcıya gösterilir.

> Anlam: backend hangi alıcı numarasının aktif olduğunu belirler (numara havuzu/rotasyon). Müsait numara yoksa 404 dönün.

### 3.2 `POST /api/transactions` – İşlemi bildir

Headers:
```
Accept: application/json
Content-Type: application/json; charset=UTF-8
```
Timeout: 15 sn. Authorization header **yok**; kimlik doğrulama body'deki `token` ile yapılır.

Body:
```json
{
  "sender": "+99371821848",
  "receiver": "+99364030911",
  "amount": 20,
  "token": "<odeme-tokeni>",
  "time": "2026-10-17 17:39:07"
}
```

| Alan | Tip | Açıklama |
|---|---|---|
| `sender` | string | Parse edilen telefon, başına `+` eklenir. Terminal top-up'ta değer `"+Terminaldan Gecdi"` olur (bkz. §6). |
| `receiver` | string | `GET /api/phone`'dan gelen `+993XXXXXXXX`. |
| `amount` | number | Manat. `> 0` olmalı; `20` veya `20.5` gibi JSON number. |
| `token` | string | Cihazda ayarlardan girilen ödeme tokeni (kodda yok). Backend bu token ile cihazı/hesabı doğrular. |
| `time` | string | `YYYY-MM-DD HH:mm:ss`, yerel saat, saat dilimi yok. |

Beklenen yanıt:
- **2xx** → başarılı. Gövde önemli değil (örn. `{"success":true}`). Telefon yalnızca status koduna bakar.
- **Diğer her kod** → hata olarak loglanır ve **otomatik tekrar denenir** (bkz. §4). Yanıt gövdesi cihazdaki hata loguna yazılır, o yüzden anlamlı hata mesajı dönün (örn. `401 {"error":"invalid token"}`, `422 {"error":"..."}`).

## 4. Hata ve retry davranışı (idempotency için kritik)

Telefon her işlem için bir `statusCode` saklar:

| statusCode | Anlamı | Otomatik retry? |
|---|---|---|
| `0` | Beklemede / belirsiz (ağ hatası, timeout, bağlantı kopması). İstek sunucuya ulaşmış olabilir. | **Hayır** (çift ödeme riski). Kullanıcı listeden elle tekrar gönderir. |
| `2xx` | Başarılı | Hayır |
| `400` | Yerel doğrulama hatası (geçersiz tutar / token girilmemiş) | Evet |
| `503` | Alıcı numarası alınamadı (`/api/phone` hatası) | Evet |
| Diğer (4xx/5xx sunucu yanıtı) | Sunucu hatası | **Evet, her 1 dakikada** bir (başarılı olana kadar) |

Sonuçları backend için:

1. **İşlem idempotent olmalı.** Şu senaryolarda aynı işlem backend'e birden fazla gelebilir:
   - Timeout olmuş ama sunucu işlemi kaydetmiş → kullanıcı elle tekrar gönderir.
   - Sunucu 5xx dönmüş ama aslında kaydetmiş → dakikada bir tekrar gelir.
   - Aynı SMS silinip uygulama yeniden kurulursa (cutoff sıfırlanır, yeni SMS'ler tekrar sayılabilir).
   Telefon tarafında **idempotency key / transaction id gönderilmiyor**. Önerilen duplicate anahtarı: `sender + amount + time` (+ gerekirse `receiver`). Aynı anahtar tekrar gelirse **2xx** dönün (yeniden işlem yapmayın) ki telefon retry döngüsünden çıksın. Eğer duplicate için 4xx/409 dönerseniz telefon her dakika tekrar dener.
2. Kalıcı hatalar (ör. `401` geçersiz token) dakikada bir tekrar edilir. Rate limit düşünün.
3. Zaman aşımı 15 sn; yanıtı hızlı dönün, ağır işi asenkron yapın.

## 5. Telefonda saklanan veriler (referans)

Yerel kayıt (GetStorage `phoneNumberList`), her SMS için:

```json
{
  "id": "<subId>-<phone>-<money>-<dateMillis>",
  "phone": "99371821848",
  "money": "20.00",
  "dateMillis": 1760711947000,
  "subId": 1,
  "time": "17/10/2026 17:39:07",
  "body": "<SMS gövdesi>",
  "statusCode": 200
}
```

Hata günlüğü: başarısız her POST (istek gövdesi – token `***` maskelenmiş –, status, yanıt gövdesi) cihazda son 200 kayıt olarak tutulur. Backend yanıt gövdesi burada görüntülenir.

## 6. Backend geliştiricisinin dikkat etmesi gereken noktalar

- **Terminal top-up SMS'inde `sender` = `"+Terminaldan Gecdi"`** gönderilir (`+` bile eklenir; telefon numarası değil). Backend bunu gerçek bir telefon olarak doğrulamamalı; bu değeri özel tip olarak ele alın (veya mobil tarafta ayrı alan eklenmesini isteyin).
- Token body'de taşınıyor; **HTTPS zorunlu**, loglarda token'ı maskeleyin.
- `time` saat dilimsizdir; yerel saat (UTC+5) varsayın veya mobil tarafta ISO-8601 + offset istenebilir.
- Uygulama kapalıyken SMS gelirse işlem ancak uygulama tekrar açılınca (inbox taramasında) iletilir; gecikme normaldir.
- SMS gövdesinin tamamı backend'e **gönderilmez**; sadece sender/amount/time gelir. Doğrulama için SMS içeriğine ihtiyaç duyuluyorsa mobil tarafa eklenmeli.
- Bir `/api/phone` çağrısı işlem başına yapılır; endpoint'in sık çağrıya dayanıklı olması gerekir.

## 7. Özet: minimum backend kontratı

```
GET  /api/phone
  200 → { "data": { "phone": "+993XXXXXXXX" } }
  404 → { "error": "..." }

POST /api/transactions
  body: { sender, receiver, amount, token, time }
  2xx → kabul edildi (duplicate dahil, idempotent)
  4xx/5xx → telefon dakikada bir tekrar dener (anlamlı hata mesajı dönün)
```

# Kolon Kolon Açıklama

Aşağıda her bir `CASE` ifadesinin ne yaptığını, hangi veri kalitesi problemini yakaladığını ve dikkat edilmesi gereken noktaları tek tek bulacaksın. Bu kolonlar tipik olarak bir **Bronze katmanında veri kalite bayrakları (data quality flags)** üretmek için kullanılır: `1` = problem var, `0` = sorun yok.

---

### 1. `BosMusteriAdi`
```sql
CASE WHEN LTRIM(RTRIM(ISNULL(b.MusteriAdi, N''))) = N'' THEN 1 ELSE 0 END
```
- **Ne yapar:** `MusteriAdi` alanı `NULL` ise boş stringe çevirir, başındaki/sonundaki boşlukları kırpar ve boş kalıp kalmadığını kontrol eder.
- **Yakaladığı problem:** Müşteri adının **NULL, boş string veya sadece boşluklardan** oluşması.
- **Not:** `N''` kullanımı Unicode string olduğunu belirtir; `nvarchar` kolonlar için doğrudur.

---

### 2. `BosKategori`
```sql
CASE WHEN LTRIM(RTRIM(ISNULL(b.UrunKategori, N''))) = N'' THEN 1 ELSE 0 END
```
- **Ne yapar:** 1. kolonun aynısı, ama `UrunKategori` için.
- **Yakaladığı problem:** Ürün kategorisinin boş/NULL olması.

---

### 3. `BosTarih`
```sql
CASE WHEN LTRIM(RTRIM(ISNULL(b.SiparisTarihi, N''))) = N'' THEN 1 ELSE 0 END
```
- **Ne yapar:** `SiparisTarihi` alanının boş/NULL olup olmadığını kontrol eder.
- **Yakaladığı problem:** Tarih alanının eksik olması.
- **Not:** `SiparisTarihi` burada bir **string** kolon olarak ele alınıyor (sonradan `LIKE '[0-9][0-9][0-9][0-9]-...'` ile format kontrolü yapıldığına göre kolon `nvarchar`/`varchar` tipinde). Eğer gerçekten `date` tipinde olsaydı `LTRIM(RTRIM(...))` hata verirdi.

---

### 4. `AdetSifirVeyaNegatif`
```sql
CASE WHEN TRY_CAST(LTRIM(RTRIM(b.SiparisAdedi)) AS INT) IS NULL
       OR TRY_CAST(LTRIM(RTRIM(b.SiparisAdedi)) AS INT) <= 0 THEN 1 ELSE 0 END
```
- **Ne yapar:** `SiparisAdedi` metnini `INT`'e çevirmeyi dener.
  - Çevrilemiyorsa (`NULL` dönerse) → 1
  - Çevriliyor ama `<= 0` ise → 1
- **Yakaladığı problem:** Sipariş adedinin **sayısal olmaması, sıfır veya negatif** olması.
- **Not:** `TRY_CAST` kullanıldığı için hatalı veri sorguyu patlatmaz, sadece `NULL` döner. İki kez `TRY_CAST` çağrılması ufak bir performans maliyetidir; `CROSS APPLY` veya CTE ile tek seferde hesaplanabilir.

---

### 5. `YasAralikDisi`
```sql
CASE WHEN TRY_CAST(LTRIM(RTRIM(b.MusteriYas)) AS INT) IS NULL
       OR TRY_CAST(LTRIM(RTRIM(b.MusteriYas)) AS INT) NOT BETWEEN 18 AND 100 THEN 1 ELSE 0 END
```
- **Ne yapar:** `MusteriYas`'ı `INT`'e çevirir.
  - Çevrilemiyorsa → 1
  - Çevriliyor ama **18–100 aralığı dışındaysa** → 1
- **Yakaladığı problem:** Yaşın sayısal olmaması veya mantıksız aralıkta olması (0, 17, 101, 999 vb.).
- **Not:** 18–100 sınırları iş kuralına göre değişebilir (örneğin 0–120 daha geniş olurdu).

---

### 6. `VirgulluOndalik`
```sql
CASE WHEN b.BirimFiyat LIKE N'%,%'
       OR b.UrunMaliyeti LIKE N'%,%'
       OR b.IndirimOrani LIKE N'%,%' THEN 1 ELSE 0 END
```
- **Ne yapar:** Üç parasal/oransal alanda **virgül karakteri** olup olmadığına bakar.
- **Yakaladığı problem:** Türkçe yerelleşimde ondalık ayırıcı virgüldür (`12,50`). Bu değerler SQL Server'da `DECIMAL`'a doğrudan çevrilemez veya yanlış yorumlanır. Bu bayrak, bu tür satırların ayrıca düzeltilmesi gerektiğini işaretler.
- **Not:** Yalnızca `LIKE '%,%'` kontrolü yapar; aslında geçerli binlik ayırıcı virgül de olabilir (`1,234.56`), yani **false positive** üretebilir.

---

### 7. `ISOOlmayanTarih`
```sql
CASE WHEN LTRIM(RTRIM(ISNULL(b.SiparisTarihi, N''))) <> N''
      AND LTRIM(RTRIM(b.SiparisTarihi)) NOT LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' THEN 1 ELSE 0 END
```
- **Ne yapar:** Alan boş **değilse** ve `YYYY-MM-DD` desenine uymuyorsa → 1.
- **Yakaladığı problem:** Tarihin ISO 8601 formatında olmaması (ör. `01.02.2024`, `2024/02/01`, `20240201`).
- **Not:** Bu sadece **desen** kontrolüdür. `2024-13-45` gibi geçersiz bir tarih de bu desenden geçer. Gerçek geçerlilik için `TRY_CONVERT(date, ..., 23)` gerekir. Boş tarih zaten `BosTarih` kolonunda yakalandığı için burada ayrıca hariç tutuluyor.

---

### 8. `IndirimYuzdeOlarak`
```sql
CASE WHEN TRY_CAST(LTRIM(RTRIM(b.IndirimOrani)) AS DECIMAL(18,2)) > 1 THEN 1 ELSE 0 END
```
- **Ne yapar:** İndirim oranını `DECIMAL(18,2)`'ye çevirir; sonuç **1'den büyükse** → 1.
- **Yakaladığı problem:** İndirimin **0–1 aralığında oran** olarak mı (0.15 = %15), yoksa **0–100 aralığında yüzde** olarak mı (15 = %15) tutulduğu tutarsızlığı. 1'den büyük değerler yüzde formatında yazılmış demektir.
- **Not:** `TRY_CAST` başarısız olursa (`NULL`) koşul `NULL` döner ve `CASE` `ELSE 0`'a düşer — yani **çevrilemeyen değerler burada bayraklanmaz**. Bu değerlerin `VirgulluOndalik` kolonunda yakalanması beklenir (eğer virgül içeriyorlarsa).

---

### 9. `TarihDosyaAyiDisi`
```sql
CASE WHEN LTRIM(RTRIM(b.SiparisTarihi)) LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
      AND LEFT(LTRIM(RTRIM(b.SiparisTarihi)), 7) <> LTRIM(RTRIM(b.KaynakAy)) THEN 1 ELSE 0 END
```
- **Ne yapar:** Tarih geçerli ISO desenindeyse, tarihin **ilk 7 karakteri** (`YYYY-MM`) ile `KaynakAy` alanını karşılaştırır; farklıysa → 1.
- **Yakaladığı problem:** Bir dosyadan gelen kayıtların, dosyanın ait olduğu ay ile tutarsız tarih içermesi (ör. `2024-03` dosyasında `2024-05-12` tarihli satır). Bu genelde ETL/veri kaynağı karışmasını gösterir.
- **Not:** `KaynakAy`'ın da `YYYY-MM` formatında olduğu varsayılıyor.

---

### 10. `MusteriIDBicimiBozuk`
```sql
CASE WHEN b.MusteriID COLLATE Latin1_General_100_BIN2 NOT LIKE N'M[0-9][0-9][0-9][0-9][0-9]' THEN 1 ELSE 0 END
```
- **Ne yapar:** `MusteriID`'nin **tam olarak** `M` + 5 rakam (`M12345`) desenine uyup uymadığını kontrol eder.
- **Yakaladığı problem:** Müşteri ID formatının bozulması (küçük `m`, eksik/fazla rakam, harf karışması vb.).
- **`COLLATE Latin1_General_100_BIN2` neden burada?** Bu kritik bir detay:
  - Varsayılan collation büyük/küçük harfe duyarsız olabilir (ör. `Latin1_General_CI_AS`). O durumda `LIKE 'M%'` deseni **`m12345`**'i de kabul ederdi.
  - `_BIN2` ile karşılaştırma **kod noktası bazlı, büyük/küçük harfe duyarlı** hale gelir. Yani `m12345` artık **reddedilir**, sadece gerçek `M12345` geçer.
  - Ayrıca `_BIN2`, `İ`/`I`/`i` gibi Türkçe/Unicode eşdeğerlik sorunlarını da devre dışı bırakır — format kontrolü deterministik olur.
- **Not:** `NOT LIKE` deseni tüm stringi kapsar (`LIKE` zaten tam eşleşme arar, `%` yok). Yani `M12345X` reddedilir.

---

### 11. `UrunIDKatalogDisi`
```sql
CASE WHEN TRY_CAST(SUBSTRING(LTRIM(RTRIM(b.UrunID)), 2, 10) AS INT) IS NULL
       OR TRY_CAST(SUBSTRING(LTRIM(RTRIM(b.UrunID)), 2, 10) AS INT) NOT BETWEEN 1 AND 28 THEN 1 ELSE 0 END
```
- **Ne yapar:** `UrunID`'nin **2. karakterinden itibaren 10 karakterini** alıp `INT`'e çevirir; çevrilemiyorsa veya sonuç **1–28 aralığında değilse** → 1.
- **Yakaladığı problem:** Ürün ID'sinin katalogda tanımlı 1–28 aralığı dışında olması veya sayısal kısmının bozuk olması.
- **Not:** `SUBSTRING(..., 2, 10)` **ilk karakteri atlar** (muhtemelen `P` gibi bir prefix). Ama:
  - `UrunID` 11 karakterden kısaysa `SUBSTRING` daha kısa döner, `TRY_CAST` yine de çalışabilir.
  - **Prefix karakteri doğrulanmıyor** — `X05` de `P05` de geçer. Sadece sayısal kısma bakılıyor.
  - `10` uzunluğu `INT` için fazla; `2147483647`'yi aşan değerler `TRY_CAST`'te `NULL` döner, yani otomatik bayraklanır — ama bu durum katalog aralığıyla ilgili değil, taşma kaynaklı.

---

### 12. `SehirStandartDisi`
```sql
CASE WHEN b.MusteriSehir COLLATE Latin1_General_100_BIN2 NOT IN
          (N'İstanbul', N'Ankara', N'İzmir', N'Bursa', N'Antalya',
           N'Adana', N'Konya', N'Gaziantep', N'Samsun', N'Trabzon')
     THEN 1 ELSE 0 END
```
- **Ne yapar:** Şehir adının izin verilen 10 şehir listesinde olup olmadığını kontrol eder.
- **Yakaladığı problem:** Şehir alanının standart listeye uymaması (yazım hatası, farklı şehir, boş değer vb.).
- **`COLLATE Latin1_General_100_BIN2` neden burada?** En kritik nokta:
  - `İstanbul` içindeki **`İ` (U+0130, büyük noktalı I)** Türkçe'ye özgüdür. Varsayılan `Latin1_General_CI_AS` collation'da `İ` ile `I` **eşit kabul edilebilir**, yani `istanbul`, `Istanbul`, `İstanbul` hepsi geçebilir.
  - `_BIN2` ile bu eşdeğerlik kaldırılır: yalnızca **tam olarak `İstanbul`** (büyük `İ` ile) kabul edilir. `istanbul`, `ISTANBUL`, `Istanbul` reddedilir.
  - Bu, veri standardizasyonu açısından çok sıkı bir kontroldür. Eğer amaç sadece "farklı şehir" yakalamaksa `_CI_AS` daha uygun olurdu; amaç **tam format standardı** ise `_BIN2` doğru tercih.
- **Dikkat:** `NULL` şehir → `NOT IN` **`UNKNOWN`** döner → `CASE` `ELSE 0`'a düşer, yani **NULL şehir bayraklanmaz**. Boş şehir yakalamak istiyorsan `OR b.MusteriSehir IS NULL` eklenmeli.

---

### 13. `TekrarSatir`
```sql
CASE WHEN ROW_NUMBER() OVER (PARTITION BY b.SiparisID, b.SiparisSatirID
                             ORDER BY b.BronzeRowID) > 1
     THEN 1 ELSE 0 END
```
- **Ne yapar:** Her `(SiparisID, SiparisSatirID)` kombinasyonu için satırları `BronzeRowID`'ye göre sıralar ve **ilk satır dışındakileri** işaretler.
- **Yakaladığı problem:** Aynı sipariş satırının **(SiparişID + SiparişSatırID) birden fazla kez** gelmesi (duplicate). En küçük `BronzeRowID` "gerçek" kabul edilir; diğerleri tekrar olarak bayraklanır.
- **Not:**
  - `BronzeRowID` muhtemelen Bronze tablosunun otomatik artan birincil anahtarı; yükleme sırasını temsil eder.
  - Bu kolon **satır bazında hesaplandığı için** aynı sorguda `WHERE TekrarSatir = 0` ile filtrelemek **çalışmaz** (window fonksiyonu `WHERE`'den sonra değerlendirilir). Filtrelemek için CTE/subquery gerekir.
  - `PARTITION BY` içinde `SiparisID` + `SiparisSatirID` birleşimi, satır düzeyinde unique key varsayımına dayanır.

---

## Genel Değerlendirme

| Konu | Gözlem |
|---|---|
| **Amaç** | Bronze katmanında satır bazlı veri kalite bayrakları üretmek (0/1). |
| **Tekrar eden `TRY_CAST`** | 4, 5 ve 11. kolonlarda aynı `TRY_CAST` iki kez çağrılıyor; `CROSS APPLY`/CTE ile tek seferde hesaplanabilir. |
| **`_BIN2` kullanımı** | 10 ve 12. kolonlarda bilinçli tercih: büyük/küçük harf ve Türkçe `İ/I` eşdeğerliğini devre dışı bırakıp sıkı format kontrolü sağlıyor. |
| **Zayıf noktalar** | • 7. kolon sadece desen kontrolü (geçersiz tarih `2024-13-45` geçer).<br>• 8. kolonda `TRY_CAST` `NULL` dönerse `ELSE 0`'a düşüyor, yani bozuk sayı bayraklanmıyor.<br>• 12. kolonda `NULL` şehir bayraklanmıyor.<br>• 11. kolonda prefix karakteri doğrulanmıyor.<br>• 6. kolon binlik ayırıcı virgülü de yakalar (false positive). |
| **Kullanım** | Bu bayraklar genelde `WHERE` yerine önce CTE'de üretilip sonra `WHERE TekrarSatir = 0 AND ...` şeklinde filtrelenir veya kalite raporu için sayım amacıyla kullanılır. |
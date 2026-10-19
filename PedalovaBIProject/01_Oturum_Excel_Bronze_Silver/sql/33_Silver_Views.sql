/* =====================================================================
   33_Silver_Views.sql
   Amaç      : Bronze -> Silver dönüşüm mantığı, 3 katmanlı view olarak:
               1) silver.vw_Sales_Parsed     tip dönüşümü + kırpma + normalizasyon (satır satır, fonksiyonlarla)
               2) silver.vw_CustomerGolden   müşterinin "altın" adı (en sık görülen ad)
               3) silver.vw_Sales_Stage      referans eşleme + 19 DQ kuralı bayrağı + TEMİZ değerler
   Bağımlılık: 11_ (bronze.Sales), 30_ (Ref tablolar), 31_ (fonksiyonlar).
   Collation notu (ÖNEMLİ):
     - Latin1_General_100_BIN2  : birebir (büyük/küçük harf dahil) karşılaştırma
     - Turkish_CI_AS            : Türkçe kurallı, büyük/küçük harf duyarsız (i=İ, ı=I)
     - SQL'de 'abc ' = 'abc' DOĞRUDUR (sondaki boşluk yok sayılır!) -> boşluk kontrolünde DATALENGTH kullanılır.
   ===================================================================== */
USE BikeRetailDW;
GO

/* ---------- 1) silver.vw_Sales_Parsed ---------- */
CREATE OR ALTER VIEW silver.vw_Sales_Parsed
AS
SELECT
    b.BronzeRowID, b.SourceFileName, b.BatchID, b.LoadDateTime,

    LTRIM(RTRIM(b.KaynakAy))                                       AS KaynakAy,
    TRY_CAST(LTRIM(RTRIM(b.SiparisID)) AS BIGINT)                  AS SiparisID,
    TRY_CAST(LTRIM(RTRIM(b.SiparisSatirID)) AS INT)                AS SiparisSatirID,
    LTRIM(RTRIM(b.SiparisTarihi))                                  AS Tarih_T,
    silver.fn_ParseDate(b.SiparisTarihi)                           AS SiparisTarihi,

    b.MusteriID                                                    AS MusteriID_Raw,
    silver.fn_NormalizeCustomerID(b.MusteriID)                     AS CustomerID,
    b.MusteriAdi                                                   AS Ad_Raw,
    LTRIM(RTRIM(b.MusteriAdi))                                     AS Ad_T,
    LTRIM(RTRIM(b.MusteriCinsiyet))                                AS Cinsiyet_T,
    silver.fn_FoldKey(b.MusteriCinsiyet)                           AS CinsiyetKey,
    TRY_CAST(LTRIM(RTRIM(b.MusteriYas)) AS INT)                    AS Yas,
    TRY_CAST(LTRIM(RTRIM(b.MusteriUyelikYili)) AS SMALLINT)        AS UyelikYili,
    b.MusteriSehir                                                 AS Sehir_Raw,
    LTRIM(RTRIM(b.MusteriSehir))                                   AS Sehir_T,
    silver.fn_FoldKey(b.MusteriSehir)                              AS SehirKey,

    LTRIM(RTRIM(b.MagazaID))                                       AS MagazaID_T,
    b.MagazaAdi                                                    AS MagazaAdi_Raw,
    LTRIM(RTRIM(b.MagazaAdi))                                      AS MagazaAdi_T,
    LTRIM(RTRIM(b.SatisKanali))                                    AS Kanal_T,

    LTRIM(RTRIM(b.UrunID))                                         AS UrunID_T,
    b.UrunAdi                                                      AS UrunAdi_Raw,
    LTRIM(RTRIM(b.UrunAdi))                                        AS UrunAdi_T,
    LTRIM(RTRIM(b.UrunKategori))                                   AS Kategori_T,
    LTRIM(RTRIM(b.UrunAltKategori))                                AS AltKategori_T,
    LTRIM(RTRIM(b.UrunMarka))                                      AS Marka_T,

    TRY_CAST(LTRIM(RTRIM(b.SiparisAdedi)) AS INT)                  AS Adet,
    b.BirimFiyat                                                   AS Fiyat_Raw,
    silver.fn_ParseDecimal(b.BirimFiyat)                           AS Fiyat,
    b.UrunMaliyeti                                                 AS Maliyet_Raw,
    silver.fn_ParseDecimal(b.UrunMaliyeti)                         AS Maliyet,
    b.IndirimOrani                                                 AS Indirim_Raw,
    silver.fn_ParseDecimal(b.IndirimOrani)                         AS Indirim,

    LTRIM(RTRIM(b.KampanyaAdi))                                    AS Kampanya_T,
    LTRIM(RTRIM(b.OdemeTipi))                                      AS Odeme_T,
    silver.fn_FoldKey(b.OdemeTipi)                                 AS OdemeKey
FROM bronze.Sales AS b;
GO

/* ---------- 2) silver.vw_CustomerGolden ----------
   Aynı müşterinin adı yüzlerce satırda geçer; kirli varyantlar (boş, BÜYÜK harf, ters sıra...) az sayıdadır.
   En sık görülen (bozulmamış) ad "altın ad" kabul edilir. Gruplama BIN2 ile yapılır ki 'AHMET KAYA' ile
   'Ahmet Kaya' aynı grupta birleşmesin. */
CREATE OR ALTER VIEW silver.vw_CustomerGolden
AS
WITH N AS
(
    SELECT p.CustomerID,
           p.Ad_T COLLATE Latin1_General_100_BIN2 AS Ad_Bin,
           COUNT(*) AS Cnt
    FROM silver.vw_Sales_Parsed AS p
    WHERE p.CustomerID IS NOT NULL
      AND ISNULL(p.Ad_T, N'') <> N''
    GROUP BY p.CustomerID, p.Ad_T COLLATE Latin1_General_100_BIN2
),
R AS
(
    SELECT CustomerID, Ad_Bin,
           ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY Cnt DESC, Ad_Bin) AS rn
    FROM N
)
SELECT CustomerID,
       CAST(Ad_Bin AS NVARCHAR(200)) COLLATE DATABASE_DEFAULT AS GoldenName   -- BIN2'yi dışarı taşıma (collation çakışması olmasın)
FROM R
WHERE rn = 1;
GO

/* ---------- 3) silver.vw_Sales_Stage ---------- */
CREATE OR ALTER VIEW silver.vw_Sales_Stage
AS
WITH J AS      -- referans eşlemeleri + tekrar sırası
(
    SELECT
        p.*,
        mc.TargetValue AS CityStd,
        mg.TargetValue AS GenderStd,
        mp.TargetValue AS PayStd,
        rp.ProductID AS RP_ID, rp.ProductName AS RP_Name, rp.Category AS RP_Category,
        rp.SubCategory AS RP_Sub, rp.Brand AS RP_Brand, rp.BasePrice AS RP_BasePrice,
        rs.StoreID AS RS_ID, rs.StoreName AS RS_Name, rs.Region AS RS_Region,
        cg.GoldenName,
        ROW_NUMBER() OVER (PARTITION BY p.SiparisID, p.SiparisSatirID ORDER BY p.BronzeRowID) AS RN
    FROM silver.vw_Sales_Parsed AS p
    LEFT JOIN silver.RefValueMap AS mc ON mc.MapType = 'City'    AND mc.SourceKey = p.SehirKey
    LEFT JOIN silver.RefValueMap AS mg ON mg.MapType = 'Gender'  AND mg.SourceKey = p.CinsiyetKey
    LEFT JOIN silver.RefValueMap AS mp ON mp.MapType = 'Payment' AND mp.SourceKey = p.OdemeKey
    LEFT JOIN silver.RefProduct  AS rp ON rp.ProductID = p.UrunID_T
    LEFT JOIN silver.RefStore    AS rs ON rs.StoreID   = p.MagazaID_T
    LEFT JOIN silver.vw_CustomerGolden AS cg ON cg.CustomerID = p.CustomerID
),
F AS           -- 19 DQ kuralı: 1 = ihlal
(
    SELECT
        j.*,
        -- Tamlık
        CAST(CASE WHEN ISNULL(j.Ad_T, N'') = N''        THEN 1 ELSE 0 END AS BIT) AS DQ01,
        CAST(CASE WHEN ISNULL(j.Kategori_T, N'') = N''  THEN 1 ELSE 0 END AS BIT) AS DQ02,
        CAST(CASE WHEN ISNULL(j.Tarih_T, N'') = N''     THEN 1 ELSE 0 END AS BIT) AS DQ03,
        -- Geçerlilik
        CAST(CASE WHEN j.Adet IS NULL OR j.Adet <= 0    THEN 1 ELSE 0 END AS BIT) AS DQ04,
        CAST(CASE WHEN j.Yas IS NULL OR j.Yas NOT BETWEEN 18 AND 100 THEN 1 ELSE 0 END AS BIT) AS DQ05,
        CAST(CASE WHEN j.RP_BasePrice IS NOT NULL AND j.Fiyat > 3 * j.RP_BasePrice THEN 1 ELSE 0 END AS BIT) AS DQ06,
        CAST(CASE WHEN j.SiparisTarihi IS NOT NULL
                   AND (LEFT(CONVERT(CHAR(10), j.SiparisTarihi, 23), 7) <> j.KaynakAy
                        OR j.SiparisTarihi > CAST(SYSDATETIME() AS DATE)) THEN 1 ELSE 0 END AS BIT) AS DQ07,
        CAST(CASE WHEN j.Indirim > 1 THEN 1 ELSE 0 END AS BIT) AS DQ08,
        CAST(CASE WHEN j.Fiyat_Raw LIKE N'%,%' OR j.Maliyet_Raw LIKE N'%,%' OR j.Indirim_Raw LIKE N'%,%' THEN 1 ELSE 0 END AS BIT) AS DQ09,
        CAST(CASE WHEN ISNULL(j.Tarih_T, N'') <> N''
                   AND j.Tarih_T NOT LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' THEN 1 ELSE 0 END AS BIT) AS DQ10,
        -- Tutarlılık
        CAST(CASE WHEN j.CityStd IS NULL
                    OR j.Sehir_T COLLATE Latin1_General_100_BIN2 <> j.CityStd THEN 1 ELSE 0 END AS BIT) AS DQ11,
        CAST(CASE WHEN DATALENGTH(j.Ad_Raw)       <> DATALENGTH(j.Ad_T)
                    OR DATALENGTH(j.Sehir_Raw)    <> DATALENGTH(j.Sehir_T)
                    OR DATALENGTH(j.UrunAdi_Raw)  <> DATALENGTH(j.UrunAdi_T)
                    OR DATALENGTH(j.MagazaAdi_Raw) <> DATALENGTH(j.MagazaAdi_T)
                    OR (j.GoldenName IS NOT NULL AND j.Ad_T <> N''
                        AND j.Ad_T COLLATE Turkish_CI_AS = j.GoldenName
                        AND j.Ad_T COLLATE Latin1_General_100_BIN2 <> j.GoldenName)
                    OR (j.RP_ID IS NOT NULL AND j.Marka_T <> N''
                        AND j.Marka_T COLLATE Turkish_CI_AS = j.RP_Brand
                        AND j.Marka_T COLLATE Latin1_General_100_BIN2 <> j.RP_Brand)
                    OR (j.RP_ID IS NOT NULL AND j.Kategori_T <> N''
                        AND j.Kategori_T COLLATE Turkish_CI_AS = j.RP_Category
                        AND j.Kategori_T COLLATE Latin1_General_100_BIN2 <> j.RP_Category)
                  THEN 1 ELSE 0 END AS BIT) AS DQ12,
        CAST(CASE WHEN j.RP_ID IS NOT NULL AND j.Kategori_T <> N''
                   AND j.Kategori_T COLLATE Turkish_CI_AS <> j.RP_Category THEN 1 ELSE 0 END AS BIT) AS DQ13,
        CAST(CASE WHEN j.GenderStd IS NULL OR j.Cinsiyet_T COLLATE Latin1_General_100_BIN2 <> j.GenderStd
                    OR j.PayStd IS NULL    OR j.Odeme_T    COLLATE Latin1_General_100_BIN2 <> j.PayStd THEN 1 ELSE 0 END AS BIT) AS DQ14,
        CAST(CASE WHEN j.GoldenName IS NOT NULL AND j.Ad_T <> N''
                   AND j.Ad_T COLLATE Turkish_CI_AS <> j.GoldenName THEN 1 ELSE 0 END AS BIT) AS DQ15,
        CAST(CASE WHEN j.MusteriID_Raw COLLATE Latin1_General_100_BIN2 NOT LIKE N'M[0-9][0-9][0-9][0-9][0-9]' THEN 1 ELSE 0 END AS BIT) AS DQ16,
        -- Benzersizlik
        CAST(CASE WHEN j.RN > 1 THEN 1 ELSE 0 END AS BIT) AS DQ17,
        -- Bütünlük
        CAST(CASE WHEN j.RP_ID IS NULL THEN 1 ELSE 0 END AS BIT) AS DQ18,
        CAST(CASE WHEN j.RS_ID IS NULL
                    OR j.MagazaAdi_T COLLATE Latin1_General_100_BIN2 <> j.RS_Name THEN 1 ELSE 0 END AS BIT) AS DQ19
    FROM J AS j
)
SELECT
    f.BronzeRowID, f.SourceFileName, f.BatchID, f.LoadDateTime,

    -- ===== TEMİZ DEĞERLER (silver.Sales'e bunlar yazılır) =====
    f.KaynakAy, f.SiparisID, f.SiparisSatirID, f.SiparisTarihi,
    f.CustomerID                                                              AS MusteriID,
    COALESCE(f.GoldenName, NULLIF(f.Ad_T, N''), N'Bilinmiyor')                AS MusteriAdi,
    COALESCE(f.GenderStd, N'Bilinmiyor')                                      AS MusteriCinsiyet,
    CASE WHEN f.Yas BETWEEN 18 AND 100 THEN f.Yas END                         AS MusteriYas,
    f.UyelikYili                                                              AS MusteriUyelikYili,
    COALESCE(f.CityStd, N'Bilinmiyor')                                        AS MusteriSehir,
    f.MagazaID_T                                                              AS MagazaID,
    COALESCE(f.RS_Name, f.MagazaAdi_T)                                        AS MagazaAdi,
    COALESCE(f.RS_Region, N'Bilinmiyor')                                      AS MagazaBolge,
    f.Kanal_T                                                                 AS SatisKanali,
    f.UrunID_T                                                                AS UrunID,
    COALESCE(f.RP_Name, f.UrunAdi_T)                                          AS UrunAdi,
    COALESCE(f.RP_Category, NULLIF(f.Kategori_T, N''), N'Bilinmiyor')         AS UrunKategori,
    COALESCE(f.RP_Sub, f.AltKategori_T)                                       AS UrunAltKategori,
    COALESCE(f.RP_Brand, f.Marka_T)                                           AS UrunMarka,
    f.Adet                                                                    AS SiparisAdedi,
    f.Fiyat                                                                   AS BirimFiyat,
    f.Maliyet                                                                 AS UrunMaliyeti,
    CASE WHEN f.Indirim > 1 THEN f.Indirim / 100.0 ELSE f.Indirim END         AS IndirimOrani,
    f.Kampanya_T                                                              AS KampanyaAdi,
    COALESCE(f.PayStd, N'Bilinmiyor')                                         AS OdemeTipi,

    -- ===== KURAL BAYRAKLARI =====
    f.DQ01, f.DQ02, f.DQ03, f.DQ04, f.DQ05, f.DQ06, f.DQ07, f.DQ08, f.DQ09, f.DQ10,
    f.DQ11, f.DQ12, f.DQ13, f.DQ14, f.DQ15, f.DQ16, f.DQ17, f.DQ18, f.DQ19,

    -- Katalogda olmayan YAPISAL hatalar (anahtar/tip çözülemedi). Bu veri setinde 0 beklenir; satırı karantinaya yollar.
    CAST(CASE WHEN f.CustomerID IS NULL OR f.SiparisID IS NULL OR f.SiparisSatirID IS NULL OR f.UyelikYili IS NULL
                OR f.Fiyat IS NULL OR f.Maliyet IS NULL OR f.Indirim IS NULL
                OR (f.SiparisTarihi IS NULL AND f.DQ03 = 0) THEN 1 ELSE 0 END AS BIT) AS StructuralError,

    -- Karantina kuralları: DQ03, DQ04, DQ06, DQ07, DQ18 (+ yapısal hata)
    CAST(CASE WHEN f.DQ03 = 1 OR f.DQ04 = 1 OR f.DQ06 = 1 OR f.DQ07 = 1 OR f.DQ18 = 1
                OR f.CustomerID IS NULL OR f.SiparisID IS NULL OR f.SiparisSatirID IS NULL OR f.UyelikYili IS NULL
                OR f.Fiyat IS NULL OR f.Maliyet IS NULL OR f.Indirim IS NULL
                OR (f.SiparisTarihi IS NULL AND f.DQ03 = 0) THEN 1 ELSE 0 END AS BIT) AS HasQuarantineRule,

    -- Düzeltilen satır: karantina/tekrar dışı kurallardan en az biri
    CAST(CASE WHEN f.DQ01 = 1 OR f.DQ02 = 1 OR f.DQ05 = 1 OR f.DQ08 = 1 OR f.DQ09 = 1 OR f.DQ10 = 1
                OR f.DQ11 = 1 OR f.DQ12 = 1 OR f.DQ13 = 1 OR f.DQ14 = 1 OR f.DQ15 = 1 OR f.DQ16 = 1
                OR f.DQ19 = 1 THEN 1 ELSE 0 END AS BIT) AS IsCorrected
FROM F AS f;
GO

/* ---------- Kural bazlı ihlal sayıları (hızlı kontrol) ----------
   Beklenen (mevcut veri: 17.997 satır) -> hesapla_beklenen_degerler.py "Kural bazlı ihlal" tablosu:
   DQ01=5 DQ02=2 DQ03=2 DQ04=4 DQ05=3 DQ06=1 DQ07=2 DQ08=2 DQ09=4 DQ10=4 DQ11=5 DQ12=10 DQ13=1 DQ14=5 DQ15=2 DQ16=2 DQ17=29 DQ18=2 DQ19=3 */
SELECT v.RuleCode, SUM(CAST(v.Flag AS INT)) AS IhlalSatir
FROM silver.vw_Sales_Stage AS s
CROSS APPLY (VALUES
    ('DQ01', s.DQ01), ('DQ02', s.DQ02), ('DQ03', s.DQ03), ('DQ04', s.DQ04), ('DQ05', s.DQ05),
    ('DQ06', s.DQ06), ('DQ07', s.DQ07), ('DQ08', s.DQ08), ('DQ09', s.DQ09), ('DQ10', s.DQ10),
    ('DQ11', s.DQ11), ('DQ12', s.DQ12), ('DQ13', s.DQ13), ('DQ14', s.DQ14), ('DQ15', s.DQ15),
    ('DQ16', s.DQ16), ('DQ17', s.DQ17), ('DQ18', s.DQ18), ('DQ19', s.DQ19)
) AS v (RuleCode, Flag)
GROUP BY v.RuleCode
ORDER BY v.RuleCode;
GO

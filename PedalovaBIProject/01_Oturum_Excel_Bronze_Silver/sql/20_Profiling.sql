/* =====================================================================
   20_Profiling.sql
   Amaç      : Veriyi DEĞİŞTİRMEDEN tanımak (Data Discovery / Profiling) ve çıktıyı raporlanabilir view'lara dönüştürmek.
   Bağımlılık: bronze.Sales dolu (11_Bronze_Yukle.sql).
   Üretir    : bronze.vw_DataProfiling   (kolon bazlı profil: kayıt, null, boş, distinct, min/max, tipe uymayan)
               bronze.vw_DirtyDataMetrics (kirli veri metrikleri: kural bazlı etkilenen satır sayısı ve yüzde)
   Excel     : Bu iki view Excel'de Power Query ile okunup PivotTable'a dönüştürülür (m\02_Profiling_Raporu.m).
   ===================================================================== */
USE BikeRetailDW;
GO

/* ---------- A) Ad-hoc keşif sorguları (canlıda tek tek çalıştır) ---------- */

-- A1) Boyut: kaç satır, kaç sipariş, kaç müşteri?
SELECT COUNT(*)                          AS SatirSayisi,
       COUNT(DISTINCT SiparisID)         AS BenzersizSiparisID,
       COUNT(DISTINCT MusteriID)         AS BenzersizMusteriID_Ham,
       COUNT(DISTINCT SourceFileName)    AS DosyaSayisi
FROM bronze.Sales;

-- A2) Şehir yazım varyantları: "aynı şehir kaç farklı yazılmış?"
--     COLLATE BIN2 şart: varsayılan (büyük/küçük harf duyarsız) collation 'ankara' ile 'Ankara'yı TEK grup gösterir.
SELECT MusteriSehir COLLATE Latin1_General_100_BIN2 AS MusteriSehir, COUNT(*) AS Adet
FROM bronze.Sales
GROUP BY MusteriSehir COLLATE Latin1_General_100_BIN2
ORDER BY MusteriSehir COLLATE Latin1_General_100_BIN2;

-- A3) Kategori ve cinsiyet/ödeme değerleri (boş, yazım hatası, kısaltma) - yine BIN2
SELECT UrunKategori COLLATE Latin1_General_100_BIN2 AS UrunKategori, COUNT(*) AS Adet FROM bronze.Sales GROUP BY UrunKategori COLLATE Latin1_General_100_BIN2 ORDER BY 1;
SELECT MusteriCinsiyet COLLATE Latin1_General_100_BIN2 AS MusteriCinsiyet, COUNT(*) AS Adet FROM bronze.Sales GROUP BY MusteriCinsiyet COLLATE Latin1_General_100_BIN2 ORDER BY 1;
SELECT OdemeTipi COLLATE Latin1_General_100_BIN2 AS OdemeTipi, COUNT(*) AS Adet FROM bronze.Sales GROUP BY OdemeTipi COLLATE Latin1_General_100_BIN2 ORDER BY 1;

-- A4) Sayısal alanlarda uç değerler (metin sıralaması YANILTIR: '100' < '20'; bu yüzden TRY_CAST)
SELECT MIN(TRY_CAST(SiparisAdedi AS INT))          AS MinAdet,
       MAX(TRY_CAST(SiparisAdedi AS INT))          AS MaxAdet,
       MIN(TRY_CAST(MusteriYas AS INT))            AS MinYas,
       MAX(TRY_CAST(MusteriYas AS INT))            AS MaxYas,
       MAX(TRY_CAST(BirimFiyat AS DECIMAL(18,2)))  AS MaxFiyat_Parse_Edilebilen,
       SUM(CASE WHEN TRY_CAST(BirimFiyat AS DECIMAL(18,2)) IS NULL THEN 1 ELSE 0 END) AS FiyatParseEdilemeyen
FROM bronze.Sales;

-- A5) Duplicate: aynı (SiparisID, SiparisSatirID) birden fazla mı?
SELECT SiparisID, SiparisSatirID, COUNT(*) AS Tekrar
FROM bronze.Sales
GROUP BY SiparisID, SiparisSatirID
HAVING COUNT(*) > 1
ORDER BY Tekrar DESC, SiparisID;
GO

/* ---------- B) bronze.vw_DataProfiling ---------- */
CREATE OR ALTER VIEW bronze.vw_DataProfiling
AS
WITH U AS                                           -- 25 kolonu (kolon adı, değer) çiftlerine aç (UNPIVOT)
(
    SELECT v.ColumnOrder, v.ColumnName, v.ExpectedType, v.ColumnValue
    FROM bronze.Sales AS s
    CROSS APPLY (VALUES
        (1,  N'KaynakAy',          N'TEXT',   s.KaynakAy),
        (2,  N'SiparisID',         N'NUMBER', s.SiparisID),
        (3,  N'SiparisSatirID',    N'NUMBER', s.SiparisSatirID),
        (4,  N'SiparisTarihi',     N'DATE',   s.SiparisTarihi),
        (5,  N'MusteriID',         N'TEXT',   s.MusteriID),
        (6,  N'MusteriAdi',        N'TEXT',   s.MusteriAdi),
        (7,  N'MusteriCinsiyet',   N'TEXT',   s.MusteriCinsiyet),
        (8,  N'MusteriYas',        N'NUMBER', s.MusteriYas),
        (9,  N'MusteriUyelikYili', N'NUMBER', s.MusteriUyelikYili),
        (10, N'MusteriSehir',      N'TEXT',   s.MusteriSehir),
        (11, N'MagazaID',          N'TEXT',   s.MagazaID),
        (12, N'MagazaAdi',         N'TEXT',   s.MagazaAdi),
        (13, N'MagazaBolge',       N'TEXT',   s.MagazaBolge),
        (14, N'SatisKanali',       N'TEXT',   s.SatisKanali),
        (15, N'UrunID',            N'TEXT',   s.UrunID),
        (16, N'UrunAdi',           N'TEXT',   s.UrunAdi),
        (17, N'UrunKategori',      N'TEXT',   s.UrunKategori),
        (18, N'UrunAltKategori',   N'TEXT',   s.UrunAltKategori),
        (19, N'UrunMarka',         N'TEXT',   s.UrunMarka),
        (20, N'SiparisAdedi',      N'NUMBER', s.SiparisAdedi),
        (21, N'BirimFiyat',        N'NUMBER', s.BirimFiyat),
        (22, N'UrunMaliyeti',      N'NUMBER', s.UrunMaliyeti),
        (23, N'IndirimOrani',      N'NUMBER', s.IndirimOrani),
        (24, N'KampanyaAdi',       N'TEXT',   s.KampanyaAdi),
        (25, N'OdemeTipi',         N'TEXT',   s.OdemeTipi)
    ) AS v (ColumnOrder, ColumnName, ExpectedType, ColumnValue)
),
T AS                                                -- beklenen tipe dönüştürmeyi dene (olmazsa NULL)
(
    SELECT ColumnOrder, ColumnName, ExpectedType, ColumnValue,
           CASE WHEN ExpectedType = N'NUMBER'
                THEN TRY_CAST(NULLIF(LTRIM(RTRIM(ColumnValue)), N'') AS DECIMAL(18,2)) END AS TypedNumber,
           CASE WHEN ExpectedType = N'DATE'
                 AND LTRIM(RTRIM(ColumnValue)) LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                THEN TRY_CONVERT(DATE, LTRIM(RTRIM(ColumnValue)), 23) END                  AS TypedDate
    FROM U
)
SELECT
    ColumnOrder,
    ColumnName,
    ExpectedType,
    COUNT(*)                                                                    AS RecordCount,
    SUM(CASE WHEN ColumnValue IS NULL THEN 1 ELSE 0 END)                        AS NullCount,
    SUM(CASE WHEN LTRIM(RTRIM(ColumnValue)) = N'' THEN 1 ELSE 0 END)            AS BlankCount,
    COUNT(DISTINCT ColumnValue COLLATE Latin1_General_100_BIN2)                 AS DistinctCount,   -- BIN2: 'ankara' ile 'Ankara' AYRI sayılır (sondaki boşluk yine yok sayılır)
    SUM(CASE WHEN ExpectedType IN (N'NUMBER', N'DATE')
              AND NULLIF(LTRIM(RTRIM(ColumnValue)), N'') IS NOT NULL
              AND TypedNumber IS NULL AND TypedDate IS NULL THEN 1 ELSE 0 END)  AS InvalidTypeCount,
    MIN(ColumnValue)                                                            AS MinText,
    MAX(ColumnValue)                                                            AS MaxText,
    COALESCE(CAST(MIN(TypedNumber) AS NVARCHAR(40)), CONVERT(NVARCHAR(10), MIN(TypedDate), 23)) AS MinTyped,
    COALESCE(CAST(MAX(TypedNumber) AS NVARCHAR(40)), CONVERT(NVARCHAR(10), MAX(TypedDate), 23)) AS MaxTyped,
    MIN(LEN(ColumnValue))                                                       AS MinLength,
    MAX(LEN(ColumnValue))                                                       AS MaxLength
FROM T
GROUP BY ColumnOrder, ColumnName, ExpectedType;
GO

/* ---------- C) bronze.vw_DirtyDataMetrics: "kirli veri metrikleri" ---------- */
CREATE OR ALTER VIEW bronze.vw_DirtyDataMetrics
AS
WITH R AS
(
    SELECT
        b.BronzeRowID,
        CASE WHEN LTRIM(RTRIM(ISNULL(b.MusteriAdi, N'')))    = N'' THEN 1 ELSE 0 END AS BosMusteriAdi,
        CASE WHEN LTRIM(RTRIM(ISNULL(b.UrunKategori, N''))) = N'' THEN 1 ELSE 0 END AS BosKategori,
        CASE WHEN LTRIM(RTRIM(ISNULL(b.SiparisTarihi, N''))) = N'' THEN 1 ELSE 0 END AS BosTarih,
        CASE WHEN TRY_CAST(LTRIM(RTRIM(b.SiparisAdedi)) AS INT) IS NULL
               OR TRY_CAST(LTRIM(RTRIM(b.SiparisAdedi)) AS INT) <= 0 THEN 1 ELSE 0 END AS AdetSifirVeyaNegatif,
        CASE WHEN TRY_CAST(LTRIM(RTRIM(b.MusteriYas)) AS INT) IS NULL
               OR TRY_CAST(LTRIM(RTRIM(b.MusteriYas)) AS INT) NOT BETWEEN 18 AND 100 THEN 1 ELSE 0 END AS YasAralikDisi,
        CASE WHEN b.BirimFiyat LIKE N'%,%' OR b.UrunMaliyeti LIKE N'%,%' OR b.IndirimOrani LIKE N'%,%' THEN 1 ELSE 0 END AS VirgulluOndalik,
        CASE WHEN LTRIM(RTRIM(ISNULL(b.SiparisTarihi, N''))) <> N''
              AND LTRIM(RTRIM(b.SiparisTarihi)) NOT LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' THEN 1 ELSE 0 END AS ISOOlmayanTarih,
        CASE WHEN TRY_CAST(LTRIM(RTRIM(b.IndirimOrani)) AS DECIMAL(18,2)) > 1 THEN 1 ELSE 0 END AS IndirimYuzdeOlarak,
        CASE WHEN LTRIM(RTRIM(b.SiparisTarihi)) LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
              AND LEFT(LTRIM(RTRIM(b.SiparisTarihi)), 7) <> LTRIM(RTRIM(b.KaynakAy)) THEN 1 ELSE 0 END AS TarihDosyaAyiDisi,
        CASE WHEN b.MusteriID COLLATE Latin1_General_100_BIN2 NOT LIKE N'M[0-9][0-9][0-9][0-9][0-9]' THEN 1 ELSE 0 END AS MusteriIDBicimiBozuk,
        CASE WHEN TRY_CAST(SUBSTRING(LTRIM(RTRIM(b.UrunID)), 2, 10) AS INT) IS NULL
               OR TRY_CAST(SUBSTRING(LTRIM(RTRIM(b.UrunID)), 2, 10) AS INT) NOT BETWEEN 1 AND 28 THEN 1 ELSE 0 END AS UrunIDKatalogDisi,
        CASE WHEN b.MusteriSehir COLLATE Latin1_General_100_BIN2 NOT IN
                  (N'İstanbul', N'Ankara', N'İzmir', N'Bursa', N'Antalya', N'Adana', N'Konya', N'Gaziantep', N'Samsun', N'Trabzon')
             THEN 1 ELSE 0 END AS SehirStandartDisi,
        CASE WHEN ROW_NUMBER() OVER (PARTITION BY b.SiparisID, b.SiparisSatirID ORDER BY b.BronzeRowID) > 1 THEN 1 ELSE 0 END AS TekrarSatir
    FROM bronze.Sales AS b
),
S AS
(
    SELECT COUNT(*) AS TotalRows,
           SUM(BosMusteriAdi) AS BosMusteriAdi, SUM(BosKategori) AS BosKategori, SUM(BosTarih) AS BosTarih,
           SUM(AdetSifirVeyaNegatif) AS AdetSifirVeyaNegatif, SUM(YasAralikDisi) AS YasAralikDisi,
           SUM(VirgulluOndalik) AS VirgulluOndalik, SUM(ISOOlmayanTarih) AS ISOOlmayanTarih,
           SUM(IndirimYuzdeOlarak) AS IndirimYuzdeOlarak, SUM(TarihDosyaAyiDisi) AS TarihDosyaAyiDisi,
           SUM(MusteriIDBicimiBozuk) AS MusteriIDBicimiBozuk, SUM(UrunIDKatalogDisi) AS UrunIDKatalogDisi,
           SUM(SehirStandartDisi) AS SehirStandartDisi, SUM(TekrarSatir) AS TekrarSatir
    FROM R
)
SELECT m.MetricOrder, m.MetricName, m.AffectedRows, S.TotalRows,
       CAST(100.0 * m.AffectedRows / NULLIF(S.TotalRows, 0) AS DECIMAL(6,2)) AS AffectedPct
FROM S
CROSS APPLY (VALUES
    (1,  N'Boş müşteri adı',                        S.BosMusteriAdi),
    (2,  N'Boş ürün kategorisi',                    S.BosKategori),
    (3,  N'Boş sipariş tarihi',                     S.BosTarih),
    (4,  N'Adet sıfır/negatif',                     S.AdetSifirVeyaNegatif),
    (5,  N'Yaş 18-100 dışında',                     S.YasAralikDisi),
    (6,  N'Virgüllü ondalık (fiyat/maliyet/indirim)', S.VirgulluOndalik),
    (7,  N'Tarih ISO biçiminde değil',              S.ISOOlmayanTarih),
    (8,  N'İndirim oran yerine yüzde (>1)',         S.IndirimYuzdeOlarak),
    (9,  N'Tarih dosya ayıyla uyuşmuyor',           S.TarihDosyaAyiDisi),
    (10, N'MusteriID biçimi bozuk',                 S.MusteriIDBicimiBozuk),
    (11, N'UrunID katalog dışı (yetim)',            S.UrunIDKatalogDisi),
    (12, N'Şehir standart yazımda değil',           S.SehirStandartDisi),
    (13, N'Tekrar eden satır (SiparisID+SatirID)',  S.TekrarSatir)
) AS m (MetricOrder, MetricName, AffectedRows);
GO

/* ---------- D) Kullanım ---------- */
--SELECT * FROM bronze.vw_DataProfiling ORDER BY ColumnOrder; #Çok uzun sürüyor!
SELECT * FROM bronze.vw_DirtyDataMetrics ORDER BY MetricOrder;
GO

/* =====================================================================
   40_Silver_Dogrulama.sql
   Amaç      : Silver sonrası "kalan ihlal = 0" ve önce/sonra kazanımlarını göstermek; uzlaştırma.
   Bağımlılık: 34_Silver_Prosedur.sql (silver.Sales dolu)
   Beklenen  : "KalanIhlal" tablosunda tüm satırlar 0. Aksi halde bir kural/yükleme hatası vardır.
   ===================================================================== */
USE BikeRetailDW;
GO

/* ---------- 1) Uzlaştırma: Bronze = Silver + Karantina + Tekrar ---------- */
SELECT b.Bronze, s.Silver, q.Karantina, d.Tekrar,
       b.Bronze - s.Silver - q.Karantina - d.Tekrar AS Fark          -- 0 olmalı
FROM (SELECT COUNT(*) AS Bronze FROM bronze.Sales) AS b
CROSS JOIN (SELECT COUNT(*) AS Silver FROM silver.Sales) AS s
CROSS JOIN (SELECT COUNT(*) AS Karantina FROM dq.SalesQuarantine) AS q
CROSS JOIN (SELECT COUNT(DISTINCT BronzeRowID) AS Tekrar FROM dq.RuleViolation WHERE RuleCode = 'DQ17') AS d;
GO

/* ---------- 2) Kalan ihlal: Silver'daki satırlar aynı kuralları HÂLÂ ihlal ediyor mu? ---------- */
SELECT Kontrol, Sonuc FROM
(
    SELECT N'DQ01 boş müşteri adı'        AS Kontrol, COUNT(*) AS Sonuc FROM silver.Sales WHERE LTRIM(RTRIM(MusteriAdi)) IN (N'', N'Bilinmiyor')
    UNION ALL SELECT N'DQ04 adet <= 0',                 COUNT(*) FROM silver.Sales WHERE SiparisAdedi <= 0
    UNION ALL SELECT N'DQ05 yaş 18-100 dışı (NULL hariç)', COUNT(*) FROM silver.Sales WHERE MusteriYas IS NOT NULL AND MusteriYas NOT BETWEEN 18 AND 100
    UNION ALL SELECT N'DQ06 aykırı fiyat',              COUNT(*) FROM silver.Sales AS s JOIN silver.RefProduct AS p ON p.ProductID = s.UrunID WHERE s.BirimFiyat > 3 * p.BasePrice
    UNION ALL SELECT N'DQ07 tarih dosya ayı dışı',      COUNT(*) FROM silver.Sales WHERE LEFT(CONVERT(CHAR(10), SiparisTarihi, 23), 7) <> KaynakAy
    UNION ALL SELECT N'DQ08 indirim > 1',               COUNT(*) FROM silver.Sales WHERE IndirimOrani > 1
    UNION ALL SELECT N'DQ11 şehir standart dışı',       COUNT(*) FROM silver.Sales AS s WHERE NOT EXISTS (SELECT 1 FROM silver.RefValueMap AS m WHERE m.MapType = 'City' AND m.TargetValue COLLATE Latin1_General_100_BIN2 = s.MusteriSehir COLLATE Latin1_General_100_BIN2)
    UNION ALL SELECT N'DQ12 baş/son boşluk',            COUNT(*) FROM silver.Sales WHERE DATALENGTH(MusteriAdi) <> DATALENGTH(LTRIM(RTRIM(MusteriAdi))) OR DATALENGTH(UrunAdi) <> DATALENGTH(LTRIM(RTRIM(UrunAdi)))
    UNION ALL SELECT N'DQ13 kategori RefProduct ile uyumsuz', COUNT(*) FROM silver.Sales AS s JOIN silver.RefProduct AS p ON p.ProductID = s.UrunID WHERE s.UrunKategori COLLATE Latin1_General_100_BIN2 <> p.Category COLLATE Latin1_General_100_BIN2
    UNION ALL SELECT N'DQ14 cinsiyet/ödeme tanımsız',   COUNT(*) FROM silver.Sales WHERE MusteriCinsiyet NOT IN (N'Kadın', N'Erkek') OR OdemeTipi NOT IN (N'Kredi Kartı', N'Nakit', N'Havale/EFT')
    UNION ALL SELECT N'DQ15 müşteri başına birden çok ad', COUNT(*) FROM (SELECT MusteriID FROM silver.Sales GROUP BY MusteriID HAVING COUNT(DISTINCT MusteriAdi COLLATE Latin1_General_100_BIN2) > 1) AS x
    UNION ALL SELECT N'DQ16 MusteriID biçimi',          COUNT(*) FROM silver.Sales WHERE MusteriID COLLATE Latin1_General_100_BIN2 NOT LIKE 'M[0-9][0-9][0-9][0-9][0-9]'
    UNION ALL SELECT N'DQ17 tekrar (SiparisID+SatirID)', COUNT(*) FROM (SELECT SiparisID, SiparisSatirID FROM silver.Sales GROUP BY SiparisID, SiparisSatirID HAVING COUNT(*) > 1) AS x
    UNION ALL SELECT N'DQ18 yetim UrunID',              COUNT(*) FROM silver.Sales AS s WHERE NOT EXISTS (SELECT 1 FROM silver.RefProduct AS p WHERE p.ProductID = s.UrunID)
    UNION ALL SELECT N'DQ19 mağaza adı uyumsuz',        COUNT(*) FROM silver.Sales AS s JOIN silver.RefStore AS r ON r.StoreID = s.MagazaID WHERE s.MagazaAdi COLLATE Latin1_General_100_BIN2 <> r.StoreName COLLATE Latin1_General_100_BIN2
) AS k
ORDER BY Kontrol;
GO

/* ---------- 3) Önce / Sonra: ayrı (distinct) değer sayıları (BIN2: büyük/küçük harf ayrı sayılır) ----------
   Beklenen (mevcut veri): şehir 14 -> 10 | cinsiyet 5 -> 2 | ödeme 4 -> 3 | kategori 6 (boş dahil) -> 3
   (Şehirde 'Samsun ' ile 'Samsun' birleşir: SQL karşılaştırmasında sondaki boşluk yok sayılır.) */
SELECT N'Şehir'     AS Alan, (SELECT COUNT(DISTINCT MusteriSehir    COLLATE Latin1_General_100_BIN2) FROM bronze.Sales) AS Bronze, (SELECT COUNT(DISTINCT MusteriSehir    COLLATE Latin1_General_100_BIN2) FROM silver.Sales) AS Silver
UNION ALL SELECT N'Cinsiyet',   (SELECT COUNT(DISTINCT MusteriCinsiyet COLLATE Latin1_General_100_BIN2) FROM bronze.Sales), (SELECT COUNT(DISTINCT MusteriCinsiyet COLLATE Latin1_General_100_BIN2) FROM silver.Sales)
UNION ALL SELECT N'Ödeme tipi', (SELECT COUNT(DISTINCT OdemeTipi       COLLATE Latin1_General_100_BIN2) FROM bronze.Sales), (SELECT COUNT(DISTINCT OdemeTipi       COLLATE Latin1_General_100_BIN2) FROM silver.Sales)
UNION ALL SELECT N'Kategori',   (SELECT COUNT(DISTINCT UrunKategori    COLLATE Latin1_General_100_BIN2) FROM bronze.Sales), (SELECT COUNT(DISTINCT UrunKategori    COLLATE Latin1_General_100_BIN2) FROM silver.Sales);
GO

/* ---------- 4) Satır düzeyi önce/sonra örnekleri: ham değer yan yana temiz değer ----------
   Silver'a giren ama düzeltilen satırlar (IsCorrected = 1). */
SELECT TOP (15)
       s.BronzeRowID,
       b.MusteriSehir AS Sehir_Bronze, s.MusteriSehir AS Sehir_Silver,
       b.MusteriAdi   AS Ad_Bronze,    s.MusteriAdi   AS Ad_Silver,
       b.SiparisTarihi AS Tarih_Bronze, s.SiparisTarihi AS Tarih_Silver,
       b.BirimFiyat   AS Fiyat_Bronze, s.BirimFiyat   AS Fiyat_Silver,
       b.IndirimOrani AS Indirim_Bronze, s.IndirimOrani AS Indirim_Silver
FROM silver.Sales AS s
JOIN bronze.Sales AS b ON b.BronzeRowID = s.BronzeRowID
WHERE s.IsCorrected = 1
ORDER BY s.BronzeRowID;
GO

/* ---------- 5) Karantinadaki satırlar ve nedenleri ---------- */
SELECT QuarantineReason, COUNT(*) AS Satir
FROM dq.SalesQuarantine
GROUP BY QuarantineReason
ORDER BY Satir DESC, QuarantineReason;
GO

/* ---------- 6) Lineage: Silver'daki bir satırdan Bronze'a ve dosyaya geri izle ---------- */
SELECT TOP (3) s.SiparisID, s.SiparisSatirID, s.BronzeRowID, s.SourceFileName, s.BatchID, s.LoadDateTime, s.SilverLoadDateTime
FROM silver.Sales AS s
ORDER BY s.BronzeRowID DESC;
GO

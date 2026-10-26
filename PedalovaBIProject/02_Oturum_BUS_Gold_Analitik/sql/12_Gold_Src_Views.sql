/* =====================================================================
   12_Gold_Src_Views.sql
   Amaç      : Silver -> Gold KAYNAK view'ları. Her boyut/fakt için "Gold'a ne yüklenecek?" sorusunun cevabı.
               Yükleme prosedürleri (13_) yalnızca bu view'lardan okur; dönüşüm mantığı burada okunur ve test edilir.
   Bağımlılık: O1 Silver dolu (silver.Sales, silver.Ref*). 10_Gold_Tablolar.sql (yalnızca 13_ için).
   Kural     : Boyutlar iş anahtarı (CustomerID...) döner; yapay anahtar (Key) prosedürde atanır/aranır.
   ===================================================================== */
USE BikeRetailDW;
GO

/* ---------- DimCustomer: SCD Tip 1 = "son sipariş kazanır" (geçmişi tutmaz, üzerine yazar) ---------- */
CREATE OR ALTER VIEW gold.vw_Src_DimCustomer
AS
WITH L AS     -- müşterinin en son siparişi
(
    SELECT s.*,
           ROW_NUMBER() OVER (PARTITION BY s.MusteriID
                              ORDER BY s.SiparisTarihi DESC, s.SiparisID DESC, s.SiparisSatirID DESC) AS rn
    FROM silver.Sales AS s
),
A AS          -- müşterinin son GEÇERLİ yaşı (geçersiz yaşlar Silver'da NULL'a çevrilmişti)
(
    SELECT s.MusteriID, s.MusteriYas,
           ROW_NUMBER() OVER (PARTITION BY s.MusteriID
                              ORDER BY s.SiparisTarihi DESC, s.SiparisID DESC, s.SiparisSatirID DESC) AS rn
    FROM silver.Sales AS s
    WHERE s.MusteriYas IS NOT NULL
)
SELECT
    l.MusteriID                       AS CustomerID,
    l.MusteriAdi                      AS CustomerName,
    l.MusteriCinsiyet                 AS Gender,
    l.MusteriSehir                    AS City,
    ISNULL((SELECT MAX(r.Region) FROM silver.RefStore AS r
            WHERE r.City = l.MusteriSehir AND r.StoreType = N'Fiziksel'), N'Bilinmiyor') AS Region,
    l.MusteriUyelikYili               AS MembershipYear,
    a.MusteriYas                      AS LatestAge,
    CASE WHEN a.MusteriYas IS NULL THEN N'Bilinmiyor'
         WHEN a.MusteriYas <= 24 THEN N'18-24'
         WHEN a.MusteriYas <= 34 THEN N'25-34'
         WHEN a.MusteriYas <= 44 THEN N'35-44'
         WHEN a.MusteriYas <= 54 THEN N'45-54'
         ELSE N'55+' END              AS AgeGroup
FROM L AS l
LEFT JOIN A AS a ON a.MusteriID = l.MusteriID AND a.rn = 1
WHERE l.rn = 1;
GO

/* ---------- DimProduct / DimStore / DimCampaign: ana veri (Silver referans tabloları) ----------
   Not: Ürün katalogu satılmayan ürünleri de içerir -> boyut satışlardan DEĞİL ana veriden beslenir. */
CREATE OR ALTER VIEW gold.vw_Src_DimProduct
AS
SELECT ProductID, ProductName, Category, SubCategory, Brand
FROM silver.RefProduct;
GO

CREATE OR ALTER VIEW gold.vw_Src_DimStore
AS
SELECT StoreID, StoreName, City, Region, StoreType
FROM silver.RefStore;
GO

CREATE OR ALTER VIEW gold.vw_Src_DimCampaign
AS
SELECT CampaignName, CampaignType, CampaignSeason
FROM silver.RefCampaign;
GO

/* ---------- DimChannel / DimPayment: küçük "gruplama" boyutları (Silver'daki ayrı değerlerden) ---------- */
CREATE OR ALTER VIEW gold.vw_Src_DimChannel
AS
SELECT DISTINCT
       s.SatisKanali AS ChannelName,
       CASE WHEN s.SatisKanali = N'Mağaza' THEN N'Fiziksel' ELSE N'Dijital' END AS ChannelGroup
FROM silver.Sales AS s;
GO

CREATE OR ALTER VIEW gold.vw_Src_DimPayment
AS
SELECT DISTINCT
       s.OdemeTipi AS PaymentType,
       CASE s.OdemeTipi WHEN N'Kredi Kartı' THEN N'Kart'
                        WHEN N'Nakit'       THEN N'Nakit'
                        ELSE N'Banka Transferi' END AS PaymentGroup
FROM silver.Sales AS s;
GO

/* ---------- FactSales: iş anahtarları + ölçüler. Yapay anahtar araması prosedürde (13_) yapılır. ----------
   CROSS APPLY ile ara hesaplar katmanlanır (bir SELECT'te takma ad yeniden kullanılamaz):
     Brüt = Adet x Fiyat ; İndirim = Brüt x Oran ; Net = Brüt - İndirim ; Maliyet = Adet x Birim Maliyet ; Kâr = Net - Maliyet */
CREATE OR ALTER VIEW gold.vw_Src_FactSales
AS
SELECT
    CONVERT(INT, CONVERT(CHAR(8), s.SiparisTarihi, 112)) AS DateKey,
    s.MusteriID    AS CustomerID,
    s.UrunID       AS ProductID,
    s.MagazaID     AS StoreID,
    s.SatisKanali  AS ChannelName,
    s.OdemeTipi    AS PaymentType,
    s.KampanyaAdi  AS CampaignName,
    s.SiparisID    AS OrderID,
    s.SiparisSatirID AS OrderLineID,
    s.SiparisAdedi AS Quantity,
    s.BirimFiyat   AS UnitPrice,
    s.UrunMaliyeti AS UnitCost,
    s.IndirimOrani AS DiscountRate,
    g.Gross        AS GrossAmount,
    d.Disc         AS DiscountAmount,
    g.Gross - d.Disc          AS NetAmount,
    d.Cost         AS CostAmount,
    (g.Gross - d.Disc) - d.Cost AS GrossProfit,
    s.MusteriYas   AS CustomerAgeAtOrder,
    s.SourceFileName,
    s.BatchID
FROM silver.Sales AS s
CROSS APPLY (SELECT CAST(ROUND(s.SiparisAdedi * s.BirimFiyat, 2) AS DECIMAL(14,2)) AS Gross) AS g
CROSS APPLY (SELECT CAST(ROUND(g.Gross * s.IndirimOrani, 2) AS DECIMAL(14,2))      AS Disc,
                    CAST(ROUND(s.SiparisAdedi * s.UrunMaliyeti, 2) AS DECIMAL(14,2)) AS Cost) AS d;
GO

/* ---------- Hızlı bakış (Silver doluysa) ----------
   Beklenen (mevcut veri): müşteri 100 | ürün 28 | mağaza 15 | kampanya 7 | kanal 3 | ödeme 3 | fakt 17.957 */
SELECT (SELECT COUNT(*) FROM gold.vw_Src_DimCustomer) AS Musteri,
       (SELECT COUNT(*) FROM gold.vw_Src_DimProduct)  AS Urun,
       (SELECT COUNT(*) FROM gold.vw_Src_DimStore)    AS Magaza,
       (SELECT COUNT(*) FROM gold.vw_Src_DimCampaign) AS Kampanya,
       (SELECT COUNT(*) FROM gold.vw_Src_DimChannel)  AS Kanal,
       (SELECT COUNT(*) FROM gold.vw_Src_DimPayment)  AS Odeme,
       (SELECT COUNT(*) FROM gold.vw_Src_FactSales)   AS Fakt;
GO

/* =====================================================================
   14_Gold_Dogrulama.sql
   Amaç      : Gold doğrulaması: satır/tutar uzlaştırma (reconciliation), referans bütünlüğü, grain, KPI toplamları.
   Bağımlılık: 13_Gold_Prosedurler.sql çalıştırılmış olmalı.
   Beklenen  : Fark/yetim/bilinmiyor sütunlarının hepsi 0. KPI değerleri yorumlardaki sayılarla aynı
               (hesaplayan araç: python\o2_hesapla.py; veri değişirse aracı yeniden çalıştır).
   ===================================================================== */
USE BikeRetailDW;
GO

/* ---------- 1) Boyut satır sayıları ----------
   Beklenen (mevcut veri): DimDate 1826 | DimCustomer 101 | DimProduct 29 | DimStore 16 | DimChannel 4 | DimPayment 4 | DimCampaign 8
   (Boyutlarda "Bilinmiyor" üyesi dahil; DimCampaign ana veriden 7 kampanya + 1 gelir, satışta yalnızca 3'ü kullanılır.) */
SELECT N'DimDate' AS Tablo, COUNT(*) AS Satir FROM gold.DimDate
UNION ALL SELECT N'DimCustomer', COUNT(*) FROM gold.DimCustomer
UNION ALL SELECT N'DimProduct',  COUNT(*) FROM gold.DimProduct
UNION ALL SELECT N'DimStore',    COUNT(*) FROM gold.DimStore
UNION ALL SELECT N'DimChannel',  COUNT(*) FROM gold.DimChannel
UNION ALL SELECT N'DimPayment',  COUNT(*) FROM gold.DimPayment
UNION ALL SELECT N'DimCampaign', COUNT(*) FROM gold.DimCampaign
UNION ALL SELECT N'FactSales',   COUNT(*) FROM gold.FactSales;
GO

/* ---------- 2) Uzlaştırma (reconciliation): Silver = Gold ----------
   Satır: 17.957 = 17.957 | Net tutar farkı 0,00 | Adet farkı 0 */
SELECT s.SilverSatir, f.FaktSatir, s.SilverSatir - f.FaktSatir AS SatirFarki,
       s.SilverNet,   f.FaktNet,   s.SilverNet - f.FaktNet     AS NetFarki,
       s.SilverAdet,  f.FaktAdet,  s.SilverAdet - f.FaktAdet   AS AdetFarki
FROM (SELECT COUNT(*) AS SilverSatir,
             SUM(CAST(ROUND(SiparisAdedi * BirimFiyat, 2) AS DECIMAL(14,2)))
             - SUM(CAST(ROUND(ROUND(SiparisAdedi * BirimFiyat, 2) * IndirimOrani, 2) AS DECIMAL(14,2))) AS SilverNet,
             SUM(SiparisAdedi) AS SilverAdet
      FROM silver.Sales) AS s
CROSS JOIN (SELECT COUNT(*) AS FaktSatir, SUM(NetAmount) AS FaktNet, SUM(Quantity) AS FaktAdet FROM gold.FactSales) AS f;

-- Dosya/ay bazında satır uzlaştırma. Beklenen: 2023-01 = 5.114 | 2023-02 = 5.112 | 2023-03 = 7.731
SELECT d.YearMonth, COUNT(*) AS FaktSatir
FROM gold.FactSales AS f
JOIN gold.DimDate AS d ON d.DateKey = f.DateKey
GROUP BY d.YearMonth
ORDER BY d.YearMonth;
GO

/* ---------- 3) Referans bütünlüğü: yetim anahtar ve "Bilinmiyor" kullanımı ---------- */
SELECT
    SUM(CASE WHEN d.DateKey     IS NULL THEN 1 ELSE 0 END) AS YetimTarih,
    SUM(CASE WHEN c.CustomerKey IS NULL THEN 1 ELSE 0 END) AS YetimMusteri,
    SUM(CASE WHEN p.ProductKey  IS NULL THEN 1 ELSE 0 END) AS YetimUrun,
    SUM(CASE WHEN s.StoreKey    IS NULL THEN 1 ELSE 0 END) AS YetimMagaza,
    SUM(CASE WHEN h.ChannelKey  IS NULL THEN 1 ELSE 0 END) AS YetimKanal,
    SUM(CASE WHEN y.PaymentKey  IS NULL THEN 1 ELSE 0 END) AS YetimOdeme,
    SUM(CASE WHEN k.CampaignKey IS NULL THEN 1 ELSE 0 END) AS YetimKampanya
FROM gold.FactSales AS f
LEFT JOIN gold.DimDate     AS d ON d.DateKey     = f.DateKey
LEFT JOIN gold.DimCustomer AS c ON c.CustomerKey = f.CustomerKey
LEFT JOIN gold.DimProduct  AS p ON p.ProductKey  = f.ProductKey
LEFT JOIN gold.DimStore    AS s ON s.StoreKey    = f.StoreKey
LEFT JOIN gold.DimChannel  AS h ON h.ChannelKey  = f.ChannelKey
LEFT JOIN gold.DimPayment  AS y ON y.PaymentKey  = f.PaymentKey
LEFT JOIN gold.DimCampaign AS k ON k.CampaignKey = f.CampaignKey;                    -- hepsi 0 (FK zaten zorlar)

-- "Bilinmiyor" (-1) üyesi kullanan fakt satırı. Beklenen: hepsi 0 (Silver temiz olduğu için)
SELECT SUM(CASE WHEN CustomerKey = -1 THEN 1 ELSE 0 END) AS BilinmeyenMusteri,
       SUM(CASE WHEN ProductKey  = -1 THEN 1 ELSE 0 END) AS BilinmeyenUrun,
       SUM(CASE WHEN StoreKey    = -1 THEN 1 ELSE 0 END) AS BilinmeyenMagaza,
       SUM(CASE WHEN ChannelKey  = -1 THEN 1 ELSE 0 END) AS BilinmeyenKanal,
       SUM(CASE WHEN PaymentKey  = -1 THEN 1 ELSE 0 END) AS BilinmeyenOdeme,
       SUM(CASE WHEN CampaignKey = -1 THEN 1 ELSE 0 END) AS BilinmeyenKampanya
FROM gold.FactSales;
GO

/* ---------- 4) Grain kontrolü: (OrderID, OrderLineID) benzersiz mi? Beklenen: 0 tekrar ---------- */
SELECT COUNT(*) AS TekrarEdenGrain
FROM (SELECT OrderID, OrderLineID FROM gold.FactSales GROUP BY OrderID, OrderLineID HAVING COUNT(*) > 1) AS x;

-- Ölçü tutarlılığı: Net = Brüt - İndirim ; Kâr = Net - Maliyet. Beklenen: 0
SELECT SUM(CASE WHEN NetAmount    <> GrossAmount - DiscountAmount THEN 1 ELSE 0 END) AS NetHatali,
       SUM(CASE WHEN GrossProfit  <> NetAmount - CostAmount       THEN 1 ELSE 0 END) AS KarHatali
FROM gold.FactSales;
GO

/* ---------- 5) KPI toplamları (Proje_Sozlesmesi.md §12 tanımlarıyla) ----------
   Beklenen (mevcut veri):
   Brüt 44.518.650,00 | İndirim 3.120.421,00 | Net 41.398.229,00 | Maliyet 28.551.379,75 | Brüt Kâr 12.846.849,25
   Kâr Marjı % 31,03 | Satış Adedi 23.794 | Sipariş 7.269 | AOV 5.695,18 | UPT 3,273 | Ortalama indirim (ağırlıklı) % 7,01 */
SELECT
    SUM(GrossAmount)                                        AS BrutSatis,
    SUM(DiscountAmount)                                     AS IndirimTutari,
    SUM(NetAmount)                                          AS NetSatis,
    SUM(CostAmount)                                         AS Maliyet,
    SUM(GrossProfit)                                        AS BrutKar,
    CAST(100.0 * SUM(GrossProfit) / SUM(NetAmount) AS DECIMAL(6,2))     AS KarMarjiPct,
    SUM(Quantity)                                           AS SatisAdedi,
    COUNT(DISTINCT OrderID)                                 AS SiparisSayisi,
    CAST(SUM(NetAmount) / COUNT(DISTINCT OrderID) AS DECIMAL(12,2))     AS AOV,
    CAST(1.0 * SUM(Quantity) / COUNT(DISTINCT OrderID) AS DECIMAL(6,3)) AS UPT,
    CAST(100.0 * SUM(DiscountAmount) / SUM(GrossAmount) AS DECIMAL(6,2)) AS OrtIndirimPct,
    COUNT(DISTINCT CustomerKey)                             AS MusteriSayisi
FROM gold.FactSales
WHERE CustomerKey <> -1;
GO

/* ---------- 6) Star Schema'nın "tadı": kampanya ve kategori kırılımı (tek JOIN'lik sorgular) ----------
   Beklenen (kampanya):  Kampanya Yok  : 5.112 satır | 2.062 sipariş | Net 10.680.890,25 | ort. indirim % 2,97 | marj % 34,22
                         Ramazan       : 7.731 satır | 3.096 sipariş | Net 20.205.882,25 | ort. indirim % 8,21 | marj % 29,39
                         Yılbaşı       : 5.114 satır | 2.111 sipariş | Net 10.511.456,50 | ort. indirim % 8,57 | marj % 30,95
   Beklenen (kategori):  Aksesuar 8.509.182,50 (marj % 42,84) | Bileşen 12.502.911,50 (% 35,22) | Bisiklet 20.386.135,00 (% 23,53) */
SELECT cp.CampaignName, cp.CampaignType, cp.CampaignSeason,
       COUNT(*) AS Satir, COUNT(DISTINCT f.OrderID) AS Siparis,
       SUM(f.NetAmount) AS NetSatis,
       CAST(100.0 * SUM(f.DiscountAmount) / SUM(f.GrossAmount) AS DECIMAL(6,2)) AS OrtIndirimPct,
       CAST(100.0 * SUM(f.GrossProfit) / SUM(f.NetAmount) AS DECIMAL(6,2))      AS KarMarjiPct
FROM gold.FactSales AS f
JOIN gold.DimCampaign AS cp ON cp.CampaignKey = f.CampaignKey
GROUP BY cp.CampaignName, cp.CampaignType, cp.CampaignSeason
ORDER BY NetSatis DESC;

SELECT p.Category, SUM(f.NetAmount) AS NetSatis,
       CAST(100.0 * SUM(f.GrossProfit) / SUM(f.NetAmount) AS DECIMAL(6,2)) AS KarMarjiPct
FROM gold.FactSales AS f
JOIN gold.DimProduct AS p ON p.ProductKey = f.ProductKey
GROUP BY p.Category
ORDER BY NetSatis DESC;
GO

/* ---------- 7) DimCustomer: yaş grubu dağılımı. Beklenen: 18-24 = 13 | 25-34 = 31 | 35-44 = 26 | 45-54 = 22 | 55+ = 8 ---------- */
SELECT AgeGroup, COUNT(*) AS Musteri
FROM gold.DimCustomer
WHERE CustomerKey <> -1
GROUP BY AgeGroup
ORDER BY AgeGroup;
GO

/* ---------- 8) (Gösterim) Yetim anahtar denemesi: FK'nin işe yaradığı an ----------
   Var olmayan CustomerKey = 9999 ile fakt satırı eklemeyi dene -> Msg 547 (FOREIGN KEY çakışması). İşlem GERİ ALINIR. */
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO gold.FactSales
        (DateKey, CustomerKey, ProductKey, StoreKey, ChannelKey, PaymentKey, CampaignKey, OrderID, OrderLineID,
         Quantity, UnitPrice, UnitCost, DiscountRate, GrossAmount, DiscountAmount, NetAmount, CostAmount, GrossProfit,
         CustomerAgeAtOrder, SourceFileName, BatchID, GoldLoadDateTime)
    VALUES (20230101, 9999, -1, -1, -1, -1, -1, 999999999, 1, 1, 100, 50, 0, 100, 0, 100, 50, 50, 30, N'deneme.csv', NEWID(), SYSDATETIME());
    ROLLBACK TRANSACTION;
    SELECT N'FK çalışmadı (beklenmiyordu)' AS Sonuc;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT ERROR_NUMBER() AS HataNo, ERROR_MESSAGE() AS Mesaj;
END CATCH;
GO

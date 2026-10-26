/* =====================================================================
   15_Gold_Analitik_Views.sql
   Amaç      : Excel analitiği için Gold üzerinde HAZIR veri kümeleri (view). Excel bunlara Power Query ile bağlanır.
               Kolon SIRASI bilinçlidir: Excel Data Analysis ToolPak (Korelasyon / Regresyon) bitişik sütun aralığı ister.
   Bağımlılık: 13_Gold_Prosedurler.sql (gold.FactSales dolu)
   Üretir    : gold.vw_Analytics_SalesLine  satır düzeyi (betimsel istatistik + korelasyon)
               gold.vw_Analytics_Order      sipariş düzeyi (regresyon: Y ilk sütun, X'ler bitişik)
               gold.vw_Analytics_Customer   müşteri düzeyi (K-Means özellikleri)
   Not       : Geçersiz (NULL) yaşı olan satırlar analizden hariç tutulur (ToolPak boş hücreleri kaldıramaz).
   ===================================================================== */
USE BikeRetailDW;
GO

/* ---------- 1) Satır düzeyi ----------
   Sütun sırası: Quantity, DiscountRate, CustomerAgeAtOrder, NetAmount, GrossProfit, UnitPrice  (ilk 6 sütun = analiz aralığı)
   Beklenen: 17.954 satır (17.957 - yaşı NULL olan 3 satır) */
CREATE OR ALTER VIEW gold.vw_Analytics_SalesLine
AS
SELECT
    CAST(f.Quantity AS INT)                    AS Quantity,
    CAST(f.DiscountRate AS DECIMAL(4,2))       AS DiscountRate,
    CAST(f.CustomerAgeAtOrder AS INT)          AS CustomerAgeAtOrder,
    CAST(f.NetAmount AS DECIMAL(14,2))         AS NetAmount,
    CAST(f.GrossProfit AS DECIMAL(14,2))       AS GrossProfit,
    CAST(f.UnitPrice AS DECIMAL(12,2))         AS UnitPrice,
    f.OrderID, f.OrderLineID,
    p.Category, p.SubCategory,
    cp.CampaignName,
    ch.ChannelName
FROM gold.FactSales AS f
JOIN gold.DimProduct  AS p  ON p.ProductKey   = f.ProductKey
JOIN gold.DimCampaign AS cp ON cp.CampaignKey = f.CampaignKey
JOIN gold.DimChannel  AS ch ON ch.ChannelKey  = f.ChannelKey
WHERE f.CustomerAgeAtOrder IS NOT NULL;
GO

/* ---------- 2) Sipariş düzeyi (regresyon veri kümesi) ----------
   Net Satış = f(Sipariş Adedi, İndirim Oranı, Müşteri Yaşı)   -> TAHMİN değil, ETKİ MODELLEME
   Sütun sırası: NetAmount (Y), OrderQty, AvgDiscountRate, CustomerAge (X'ler bitişik)
   Beklenen: 7.269 satır */
CREATE OR ALTER VIEW gold.vw_Analytics_Order
AS
SELECT
    CAST(SUM(f.NetAmount) AS DECIMAL(14,2))                    AS NetAmount,
    CAST(SUM(f.Quantity) AS INT)                               AS OrderQty,
    CAST(AVG(CAST(f.DiscountRate AS DECIMAL(9,6))) AS DECIMAL(9,6)) AS AvgDiscountRate,
    CAST(MAX(f.CustomerAgeAtOrder) AS INT)                     AS CustomerAge,
    f.OrderID,
    MAX(f.CustomerKey)                                         AS CustomerKey,
    MIN(f.DateKey)                                             AS DateKey
FROM gold.FactSales AS f
GROUP BY f.OrderID
HAVING MAX(f.CustomerAgeAtOrder) IS NOT NULL;
GO

/* ---------- 3) Müşteri düzeyi (K-Means özellikleri) ----------
   İş sorusu: "Tüm müşterilere aynı kampanyayı göndermek doğru mu?"
   Özellikler: TotalSpend (Net Satış toplamı), OrderCount (benzersiz sipariş), AvgBasket (= TotalSpend / OrderCount)
   Beklenen: 100 müşteri; TotalSpend ort. 413.982,29 (min 144.709 / max 735.711); OrderCount ort. 72,69 (8..162);
             AvgBasket ort. 8.231,32 (2.340,61 .. 29.241,81) */
CREATE OR ALTER VIEW gold.vw_Analytics_Customer
AS
SELECT
    c.CustomerID,
    CAST(SUM(f.NetAmount) AS DECIMAL(14,2))                              AS TotalSpend,
    COUNT(DISTINCT f.OrderID)                                            AS OrderCount,
    CAST(SUM(f.NetAmount) / COUNT(DISTINCT f.OrderID) AS DECIMAL(14,2))  AS AvgBasket,
    c.CustomerName, c.City, c.AgeGroup
FROM gold.FactSales AS f
JOIN gold.DimCustomer AS c ON c.CustomerKey = f.CustomerKey
WHERE f.CustomerKey <> -1
GROUP BY c.CustomerID, c.CustomerName, c.City, c.AgeGroup;
GO

/* ---------- Kontrol ---------- */
SELECT (SELECT COUNT(*) FROM gold.vw_Analytics_SalesLine) AS SatirDuzeyi,      
       (SELECT COUNT(*) FROM gold.vw_Analytics_Order)     AS SiparisDuzeyi,    
       (SELECT COUNT(*) FROM gold.vw_Analytics_Customer)  AS MusteriDuzeyi;     
GO

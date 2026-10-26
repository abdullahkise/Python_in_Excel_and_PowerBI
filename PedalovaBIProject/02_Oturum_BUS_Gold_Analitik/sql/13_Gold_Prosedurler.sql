/* =====================================================================
   13_Gold_Prosedurler.sql
   Amaç      : Silver -> Gold yükleme prosedürleri (gold.vw_Src_* view'larından).
               Boyutlar: UPSERT (UPDATE + INSERT) -> yapay anahtarlar (Key) yeniden yüklemede DEĞİŞMEZ.
               FactSales: tam yenileme (TRUNCATE + INSERT); boyut anahtarları aranır, bulunamazsa -1 (Bilinmiyor).
   Bağımlılık: 10_, 11_ (tablolar, DimDate), 12_ (view'lar), O1 Silver dolu.
   Sıra      : Önce boyutlar, SONRA fakt (fakt boyut anahtarlarına bağımlıdır). usp_Load_Gold sırayı garanti eder.
   ===================================================================== */
USE BikeRetailDW;
GO

/* ---------- Boyut prosedürleri ---------- */
CREATE OR ALTER PROCEDURE gold.usp_Load_DimCustomer
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d
       SET d.CustomerName = s.CustomerName, d.Gender = s.Gender, d.City = s.City, d.Region = s.Region,
           d.MembershipYear = s.MembershipYear, d.LatestAge = s.LatestAge, d.AgeGroup = s.AgeGroup
    FROM gold.DimCustomer AS d
    JOIN gold.vw_Src_DimCustomer AS s ON s.CustomerID = d.CustomerID
    WHERE d.CustomerKey <> -1;

    INSERT INTO gold.DimCustomer (CustomerID, CustomerName, Gender, City, Region, MembershipYear, LatestAge, AgeGroup)
    SELECT s.CustomerID, s.CustomerName, s.Gender, s.City, s.Region, s.MembershipYear, s.LatestAge, s.AgeGroup
    FROM gold.vw_Src_DimCustomer AS s
    WHERE NOT EXISTS (SELECT 1 FROM gold.DimCustomer AS d WHERE d.CustomerID = s.CustomerID);
END
GO

CREATE OR ALTER PROCEDURE gold.usp_Load_DimProduct
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d
       SET d.ProductName = s.ProductName, d.Category = s.Category, d.SubCategory = s.SubCategory, d.Brand = s.Brand
    FROM gold.DimProduct AS d
    JOIN gold.vw_Src_DimProduct AS s ON s.ProductID = d.ProductID
    WHERE d.ProductKey <> -1;

    INSERT INTO gold.DimProduct (ProductID, ProductName, Category, SubCategory, Brand)
    SELECT s.ProductID, s.ProductName, s.Category, s.SubCategory, s.Brand
    FROM gold.vw_Src_DimProduct AS s
    WHERE NOT EXISTS (SELECT 1 FROM gold.DimProduct AS d WHERE d.ProductID = s.ProductID);
END
GO

CREATE OR ALTER PROCEDURE gold.usp_Load_DimStore
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d
       SET d.StoreName = s.StoreName, d.City = s.City, d.Region = s.Region, d.StoreType = s.StoreType
    FROM gold.DimStore AS d
    JOIN gold.vw_Src_DimStore AS s ON s.StoreID = d.StoreID
    WHERE d.StoreKey <> -1;

    INSERT INTO gold.DimStore (StoreID, StoreName, City, Region, StoreType)
    SELECT s.StoreID, s.StoreName, s.City, s.Region, s.StoreType
    FROM gold.vw_Src_DimStore AS s
    WHERE NOT EXISTS (SELECT 1 FROM gold.DimStore AS d WHERE d.StoreID = s.StoreID);
END
GO

CREATE OR ALTER PROCEDURE gold.usp_Load_DimChannel
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d SET d.ChannelGroup = s.ChannelGroup
    FROM gold.DimChannel AS d
    JOIN gold.vw_Src_DimChannel AS s ON s.ChannelName = d.ChannelName
    WHERE d.ChannelKey <> -1;

    INSERT INTO gold.DimChannel (ChannelName, ChannelGroup)
    SELECT s.ChannelName, s.ChannelGroup
    FROM gold.vw_Src_DimChannel AS s
    WHERE NOT EXISTS (SELECT 1 FROM gold.DimChannel AS d WHERE d.ChannelName = s.ChannelName);
END
GO

CREATE OR ALTER PROCEDURE gold.usp_Load_DimPayment
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d SET d.PaymentGroup = s.PaymentGroup
    FROM gold.DimPayment AS d
    JOIN gold.vw_Src_DimPayment AS s ON s.PaymentType = d.PaymentType
    WHERE d.PaymentKey <> -1;

    INSERT INTO gold.DimPayment (PaymentType, PaymentGroup)
    SELECT s.PaymentType, s.PaymentGroup
    FROM gold.vw_Src_DimPayment AS s
    WHERE NOT EXISTS (SELECT 1 FROM gold.DimPayment AS d WHERE d.PaymentType = s.PaymentType);
END
GO

CREATE OR ALTER PROCEDURE gold.usp_Load_DimCampaign
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d SET d.CampaignType = s.CampaignType, d.CampaignSeason = s.CampaignSeason
    FROM gold.DimCampaign AS d
    JOIN gold.vw_Src_DimCampaign AS s ON s.CampaignName = d.CampaignName
    WHERE d.CampaignKey <> -1;

    INSERT INTO gold.DimCampaign (CampaignName, CampaignType, CampaignSeason)
    SELECT s.CampaignName, s.CampaignType, s.CampaignSeason
    FROM gold.vw_Src_DimCampaign AS s
    WHERE NOT EXISTS (SELECT 1 FROM gold.DimCampaign AS d WHERE d.CampaignName = s.CampaignName);
END
GO

/* ---------- FactSales: anahtar araması (lookup) + -1 kuralı ---------- */
CREATE OR ALTER PROCEDURE gold.usp_Load_FactSales
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME2(0) = SYSDATETIME();

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE gold.FactSales;

        INSERT INTO gold.FactSales
        (
            DateKey, CustomerKey, ProductKey, StoreKey, ChannelKey, PaymentKey, CampaignKey,
            OrderID, OrderLineID,
            Quantity, UnitPrice, UnitCost, DiscountRate, GrossAmount, DiscountAmount, NetAmount, CostAmount, GrossProfit,
            CustomerAgeAtOrder, SourceFileName, BatchID, GoldLoadDateTime
        )
        SELECT
            f.DateKey,                                   -- tarih bulunamazsa FK hatası: DimDate aralığı yetmiyor demektir (bilerek sessiz geçilmez)
            ISNULL(c.CustomerKey, -1),
            ISNULL(p.ProductKey,  -1),
            ISNULL(st.StoreKey,   -1),
            ISNULL(ch.ChannelKey, -1),
            ISNULL(pm.PaymentKey, -1),
            ISNULL(cp.CampaignKey, -1),
            f.OrderID, f.OrderLineID,
            f.Quantity, f.UnitPrice, f.UnitCost, f.DiscountRate, f.GrossAmount, f.DiscountAmount, f.NetAmount, f.CostAmount, f.GrossProfit,
            f.CustomerAgeAtOrder, f.SourceFileName, f.BatchID, @Now
        FROM gold.vw_Src_FactSales AS f
        LEFT JOIN gold.DimCustomer AS c  ON c.CustomerID  = f.CustomerID
        LEFT JOIN gold.DimProduct  AS p  ON p.ProductID   = f.ProductID
        LEFT JOIN gold.DimStore    AS st ON st.StoreID    = f.StoreID
        LEFT JOIN gold.DimChannel  AS ch ON ch.ChannelName = f.ChannelName
        LEFT JOIN gold.DimPayment  AS pm ON pm.PaymentType = f.PaymentType
        LEFT JOIN gold.DimCampaign AS cp ON cp.CampaignName = f.CampaignName;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END
GO

/* ---------- Orkestratör: tüm Gold'u doğru sırayla yükle ve günlüğe yaz ---------- */
CREATE OR ALTER PROCEDURE gold.usp_Load_Gold
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM silver.Sales)
        THROW 50003, N'silver.Sales boş. Önce O1 Silver yüklemesi çalıştırılmalı (silver.usp_Load_Silver_Sales).', 1;
    IF NOT EXISTS (SELECT 1 FROM gold.DimDate)
        THROW 50004, N'gold.DimDate boş. Önce 11_Gold_DimDate.sql çalıştırılmalı.', 1;

    EXEC gold.usp_Load_DimCustomer;
    EXEC gold.usp_Load_DimProduct;
    EXEC gold.usp_Load_DimStore;
    EXEC gold.usp_Load_DimChannel;
    EXEC gold.usp_Load_DimPayment;
    EXEC gold.usp_Load_DimCampaign;
    EXEC gold.usp_Load_FactSales;

    DECLARE @Now DATETIME2(0) = SYSDATETIME();
    INSERT INTO gold.LoadLog (RunDateTime, TableName, LoadedRows, UnknownRows)
    SELECT @Now, N'DimCustomer', COUNT(*), 0 FROM gold.DimCustomer WHERE CustomerKey <> -1
    UNION ALL SELECT @Now, N'DimProduct',  COUNT(*), 0 FROM gold.DimProduct  WHERE ProductKey  <> -1
    UNION ALL SELECT @Now, N'DimStore',    COUNT(*), 0 FROM gold.DimStore    WHERE StoreKey    <> -1
    UNION ALL SELECT @Now, N'DimChannel',  COUNT(*), 0 FROM gold.DimChannel  WHERE ChannelKey  <> -1
    UNION ALL SELECT @Now, N'DimPayment',  COUNT(*), 0 FROM gold.DimPayment  WHERE PaymentKey  <> -1
    UNION ALL SELECT @Now, N'DimCampaign', COUNT(*), 0 FROM gold.DimCampaign WHERE CampaignKey <> -1
    UNION ALL SELECT @Now, N'FactSales',   COUNT(*),
           SUM(CASE WHEN CustomerKey = -1 OR ProductKey = -1 OR StoreKey = -1 OR ChannelKey = -1
                      OR PaymentKey = -1 OR CampaignKey = -1 THEN 1 ELSE 0 END)
    FROM gold.FactSales;

    SELECT TableName, LoadedRows, UnknownRows FROM gold.LoadLog WHERE RunDateTime = @Now ORDER BY LoadLogID;
END
GO

EXEC gold.usp_Load_Gold;
GO

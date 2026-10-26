/* =====================================================================
   10_Gold_Tablolar.sql
   Amaç      : Gold katmanı (Star Schema): 7 boyut + FactSales + yükleme günlüğü.
               Her boyutta "Bilinmiyor" üyesi (CustomerKey = -1 vb.) hazır gelir (DimDate hariç).
   Bağımlılık: O1 tamamlanmış olmalı (şema gold, veritabanı BikeRetailDW). Silver dolu olması bu dosya için gerekmez.
   Yeniden çalıştırma: Gold tabloları SİLİNİP yeniden oluşturulur (veri gider; 13_ ile tekrar yüklenir).
   Tasarım   : Grain = bir sipariş satırı (OrderID x OrderLineID). Yabancı anahtarlar (FK) veritabanında ZORLANIR.
   ===================================================================== */
USE BikeRetailDW;
GO

/* ---------- Önce çocuk (fact), sonra boyutlar silinir ---------- */
IF OBJECT_ID(N'gold.FactSales', N'U')  IS NOT NULL DROP TABLE gold.FactSales;
IF OBJECT_ID(N'gold.DimCustomer', N'U') IS NOT NULL DROP TABLE gold.DimCustomer;
IF OBJECT_ID(N'gold.DimProduct', N'U')  IS NOT NULL DROP TABLE gold.DimProduct;
IF OBJECT_ID(N'gold.DimStore', N'U')    IS NOT NULL DROP TABLE gold.DimStore;
IF OBJECT_ID(N'gold.DimChannel', N'U')  IS NOT NULL DROP TABLE gold.DimChannel;
IF OBJECT_ID(N'gold.DimPayment', N'U')  IS NOT NULL DROP TABLE gold.DimPayment;
IF OBJECT_ID(N'gold.DimCampaign', N'U') IS NOT NULL DROP TABLE gold.DimCampaign;
IF OBJECT_ID(N'gold.DimDate', N'U')     IS NOT NULL DROP TABLE gold.DimDate;
IF OBJECT_ID(N'gold.LoadLog', N'U')     IS NOT NULL DROP TABLE gold.LoadLog;
GO

/* ---------- DimDate: anahtar akıllı (yyyymmdd) çünkü tarih sabit ve sıralanabilir ---------- */
CREATE TABLE gold.DimDate
(
    DateKey       INT          NOT NULL CONSTRAINT PK_gold_DimDate PRIMARY KEY,   -- 20230131
    FullDate      DATE         NOT NULL CONSTRAINT UQ_gold_DimDate_FullDate UNIQUE,
    [Year]        SMALLINT     NOT NULL,
    [Quarter]     TINYINT      NOT NULL,
    QuarterName   NVARCHAR(5)  NOT NULL,     -- Ç1 .. Ç4
    MonthNo       TINYINT      NOT NULL,
    MonthName     NVARCHAR(15) NOT NULL,     -- Ocak ...
    MonthShort    NVARCHAR(5)  NOT NULL,     -- Oca ...
    YearMonth     CHAR(7)      NOT NULL,     -- 2023-01
    YearMonthKey  INT          NOT NULL,     -- 202301
    WeekOfYear    TINYINT      NOT NULL,     -- ISO hafta (1 Ocak bazen önceki yılın 52. haftasıdır)
    [DayOfMonth]  TINYINT      NOT NULL,
    DayOfWeekNo   TINYINT      NOT NULL,     -- 1 = Pazartesi ... 7 = Pazar
    DayName       NVARCHAR(15) NOT NULL,
    IsWeekend     BIT          NOT NULL
);
GO

/* ---------- Boyutlar: yapay (surrogate) anahtar = IDENTITY; iş anahtarı UNIQUE; -1 = Bilinmiyor ---------- */
CREATE TABLE gold.DimCustomer
(
    CustomerKey    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_gold_DimCustomer PRIMARY KEY,
    CustomerID     VARCHAR(12)   NOT NULL CONSTRAINT UQ_gold_DimCustomer_ID UNIQUE,      -- iş anahtarı: M00227
    CustomerName   NVARCHAR(100) NOT NULL,
    Gender         NVARCHAR(10)  NOT NULL,
    City           NVARCHAR(50)  NOT NULL,
    Region         NVARCHAR(50)  NOT NULL,
    MembershipYear SMALLINT      NULL,
    LatestAge      TINYINT       NULL,                                                    -- son siparişteki (geçerli) yaş
    AgeGroup       NVARCHAR(20)  NOT NULL                                                  -- 18-24, 25-34, 35-44, 45-54, 55+
);

CREATE TABLE gold.DimProduct
(
    ProductKey   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_gold_DimProduct PRIMARY KEY,
    ProductID    VARCHAR(12)   NOT NULL CONSTRAINT UQ_gold_DimProduct_ID UNIQUE,
    ProductName  NVARCHAR(100) NOT NULL,
    Category     NVARCHAR(30)  NOT NULL,
    SubCategory  NVARCHAR(50)  NOT NULL,
    Brand        NVARCHAR(50)  NOT NULL
);

CREATE TABLE gold.DimStore
(
    StoreKey   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_gold_DimStore PRIMARY KEY,
    StoreID    VARCHAR(12)   NOT NULL CONSTRAINT UQ_gold_DimStore_ID UNIQUE,
    StoreName  NVARCHAR(100) NOT NULL,
    City       NVARCHAR(50)  NOT NULL,
    Region     NVARCHAR(50)  NOT NULL,
    StoreType  NVARCHAR(20)  NOT NULL            -- Fiziksel / Dijital
);

CREATE TABLE gold.DimChannel
(
    ChannelKey   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_gold_DimChannel PRIMARY KEY,
    ChannelName  NVARCHAR(20) NOT NULL CONSTRAINT UQ_gold_DimChannel_Name UNIQUE,   -- Mağaza / Web / Mobil
    ChannelGroup NVARCHAR(20) NOT NULL                                              -- Fiziksel / Dijital
);

CREATE TABLE gold.DimPayment
(
    PaymentKey   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_gold_DimPayment PRIMARY KEY,
    PaymentType  NVARCHAR(20) NOT NULL CONSTRAINT UQ_gold_DimPayment_Type UNIQUE,   -- Kredi Kartı / Nakit / Havale/EFT
    PaymentGroup NVARCHAR(20) NOT NULL                                              -- Kart / Nakit / Banka Transferi
);

CREATE TABLE gold.DimCampaign
(
    CampaignKey    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_gold_DimCampaign PRIMARY KEY,
    CampaignName   NVARCHAR(60) NOT NULL CONSTRAINT UQ_gold_DimCampaign_Name UNIQUE,
    CampaignType   NVARCHAR(40) NOT NULL,        -- Yılbaşı / Dini Bayram / Mevsimsel / Alışveriş Festivali / Yok
    CampaignSeason NVARCHAR(20) NOT NULL         -- Kış / İlkbahar / Yaz / Sonbahar / Tüm Yıl
);
GO

/* ---------- Bilinmiyor üyeleri (-1): yetim satır NULL anahtarla kalmasın, rapordan kaybolmasın ---------- */
SET IDENTITY_INSERT gold.DimCustomer ON;
INSERT INTO gold.DimCustomer (CustomerKey, CustomerID, CustomerName, Gender, City, Region, MembershipYear, LatestAge, AgeGroup)
VALUES (-1, 'BILINMIYOR', N'Bilinmiyor', N'Bilinmiyor', N'Bilinmiyor', N'Bilinmiyor', NULL, NULL, N'Bilinmiyor');
SET IDENTITY_INSERT gold.DimCustomer OFF;

SET IDENTITY_INSERT gold.DimProduct ON;
INSERT INTO gold.DimProduct (ProductKey, ProductID, ProductName, Category, SubCategory, Brand)
VALUES (-1, 'BILINMIYOR', N'Bilinmiyor', N'Bilinmiyor', N'Bilinmiyor', N'Bilinmiyor');
SET IDENTITY_INSERT gold.DimProduct OFF;

SET IDENTITY_INSERT gold.DimStore ON;
INSERT INTO gold.DimStore (StoreKey, StoreID, StoreName, City, Region, StoreType)
VALUES (-1, 'BILINMIYOR', N'Bilinmiyor', N'Bilinmiyor', N'Bilinmiyor', N'Bilinmiyor');
SET IDENTITY_INSERT gold.DimStore OFF;

SET IDENTITY_INSERT gold.DimChannel ON;
INSERT INTO gold.DimChannel (ChannelKey, ChannelName, ChannelGroup) VALUES (-1, N'Bilinmiyor', N'Bilinmiyor');
SET IDENTITY_INSERT gold.DimChannel OFF;

SET IDENTITY_INSERT gold.DimPayment ON;
INSERT INTO gold.DimPayment (PaymentKey, PaymentType, PaymentGroup) VALUES (-1, N'Bilinmiyor', N'Bilinmiyor');
SET IDENTITY_INSERT gold.DimPayment OFF;

SET IDENTITY_INSERT gold.DimCampaign ON;
INSERT INTO gold.DimCampaign (CampaignKey, CampaignName, CampaignType, CampaignSeason)
VALUES (-1, N'Bilinmiyor', N'Bilinmiyor', N'Bilinmiyor');
SET IDENTITY_INSERT gold.DimCampaign OFF;
GO

/* ---------- FactSales: grain = bir sipariş satırı ---------- */
CREATE TABLE gold.FactSales
(
    -- Boyut anahtarları (hepsi FK)
    DateKey      INT NOT NULL CONSTRAINT FK_FactSales_Date     FOREIGN KEY REFERENCES gold.DimDate (DateKey),
    CustomerKey  INT NOT NULL CONSTRAINT FK_FactSales_Customer FOREIGN KEY REFERENCES gold.DimCustomer (CustomerKey),
    ProductKey   INT NOT NULL CONSTRAINT FK_FactSales_Product  FOREIGN KEY REFERENCES gold.DimProduct (ProductKey),
    StoreKey     INT NOT NULL CONSTRAINT FK_FactSales_Store    FOREIGN KEY REFERENCES gold.DimStore (StoreKey),
    ChannelKey   INT NOT NULL CONSTRAINT FK_FactSales_Channel  FOREIGN KEY REFERENCES gold.DimChannel (ChannelKey),
    PaymentKey   INT NOT NULL CONSTRAINT FK_FactSales_Payment  FOREIGN KEY REFERENCES gold.DimPayment (PaymentKey),
    CampaignKey  INT NOT NULL CONSTRAINT FK_FactSales_Campaign FOREIGN KEY REFERENCES gold.DimCampaign (CampaignKey),

    -- Degenerate boyut: sipariş numarası (kendi boyut tablosu yok; grain'in parçası)
    OrderID      BIGINT NOT NULL,
    OrderLineID  INT    NOT NULL,

    -- Ölçüler
    Quantity        INT           NOT NULL,
    UnitPrice       DECIMAL(12,2) NOT NULL,
    UnitCost        DECIMAL(12,2) NOT NULL,
    DiscountRate    DECIMAL(4,2)  NOT NULL,
    GrossAmount     DECIMAL(14,2) NOT NULL,      -- Quantity x UnitPrice
    DiscountAmount  DECIMAL(14,2) NOT NULL,      -- GrossAmount x DiscountRate
    NetAmount       DECIMAL(14,2) NOT NULL,      -- GrossAmount - DiscountAmount
    CostAmount      DECIMAL(14,2) NOT NULL,      -- Quantity x UnitCost
    GrossProfit     DECIMAL(14,2) NOT NULL,      -- NetAmount - CostAmount

    -- Olay anına ait özellik (müşterinin o siparişteki yaşı) - regresyonda kullanılır
    CustomerAgeAtOrder TINYINT NULL,

    -- Lineage
    SourceFileName   NVARCHAR(260)    NOT NULL,
    BatchID          UNIQUEIDENTIFIER NOT NULL,
    GoldLoadDateTime DATETIME2(0)     NOT NULL,

    CONSTRAINT PK_gold_FactSales PRIMARY KEY (OrderID, OrderLineID)     -- grain'i veritabanı garanti eder
);

CREATE INDEX IX_FactSales_DateKey     ON gold.FactSales (DateKey);
CREATE INDEX IX_FactSales_CustomerKey ON gold.FactSales (CustomerKey);
CREATE INDEX IX_FactSales_ProductKey  ON gold.FactSales (ProductKey);
GO

/* ---------- gold.LoadLog: tablo bazlı yükleme kaydı ---------- */
CREATE TABLE gold.LoadLog
(
    LoadLogID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_gold_LoadLog PRIMARY KEY,
    RunDateTime   DATETIME2(0) NOT NULL,
    TableName     NVARCHAR(60) NOT NULL,
    LoadedRows    INT          NOT NULL,       -- tablodaki toplam satır (Bilinmiyor üyesi hariç)
    UnknownRows   INT          NOT NULL        -- (yalnızca FactSales) bir veya daha fazla boyut anahtarı -1 olan satır
);
GO

SELECT N'Gold tabloları hazır' AS Durum,
       (SELECT COUNT(*) FROM gold.DimCustomer) AS DimCustomer_Bilinmiyor_Dahil;
GO

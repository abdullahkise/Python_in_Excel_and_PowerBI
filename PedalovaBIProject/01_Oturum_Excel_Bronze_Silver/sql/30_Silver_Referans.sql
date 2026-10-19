/* =====================================================================
   30_Silver_Referans.sql
   Amaç      : Silver temizliğinde kullanılan ana veri (referans) tabloları ve DQ kural kataloğu.
   Bağımlılık: 10_Bronze_Kurulum.sql (şemalar). Bağımsız çalıştırılabilir, yeniden çalıştırılabilir (DROP + CREATE + seed).
   Not       : Gerçek hayatta bu tablolar MDM / kaynak sistemden gelir; burada eğitim için seed edilir.
               Değerler Proje_Sozlesmesi.md §4 ile birebir aynıdır.
   ===================================================================== */
USE BikeRetailDW;
GO

/* ---------- silver.RefProduct ---------- */
IF OBJECT_ID(N'silver.RefProduct', N'U') IS NOT NULL DROP TABLE silver.RefProduct;
CREATE TABLE silver.RefProduct
(
    ProductID   CHAR(4)       NOT NULL CONSTRAINT PK_silver_RefProduct PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Category    NVARCHAR(30)  NOT NULL,
    SubCategory NVARCHAR(50)  NOT NULL,
    Brand       NVARCHAR(50)  NOT NULL,
    BasePrice   DECIMAL(12,2) NOT NULL        -- 2023-01 liste fiyatı; DQ06 (aykırı fiyat) referansı
);

INSERT INTO silver.RefProduct (ProductID, ProductName, Category, SubCategory, Brand, BasePrice) VALUES
('P001', N'Zirvex Dağ Bisikleti 29',            N'Bisiklet', N'Dağ Bisikleti',       N'Zirvex',   18500),
('P002', N'Rotalux Yol Bisikleti Karbon',       N'Bisiklet', N'Yol Bisikleti',       N'Rotalux',  26000),
('P003', N'Urbanta Şehir Bisikleti',            N'Bisiklet', N'Şehir Bisikleti',     N'Urbanta',  12500),
('P004', N'Voltrik Elektrikli Şehir Bisikleti', N'Bisiklet', N'Elektrikli Bisiklet', N'Voltrik',  48000),
('P005', N'Urbanta Katlanır Bisiklet',          N'Bisiklet', N'Şehir Bisikleti',     N'Urbanta',  15500),
('P006', N'Voltrik Elektrikli Dağ Bisikleti',   N'Bisiklet', N'Elektrikli Bisiklet', N'Voltrik',  62000),
('P007', N'Torkpro Vites Seti 2x11',            N'Bileşen',  N'Vites',               N'Torkpro',   4200),
('P008', N'Torkpro Arka Aktarıcı',              N'Bileşen',  N'Vites',               N'Torkpro',   1900),
('P009', N'Frenix Disk Fren Seti',              N'Bileşen',  N'Fren',                N'Frenix',    2600),
('P010', N'Frenix Fren Balatası',               N'Bileşen',  N'Fren',                N'Frenix',     350),
('P011', N'Lastikor Dağ Lastiği',               N'Bileşen',  N'Lastik',              N'Lastikor',   900),
('P012', N'Lastikor Yol Lastiği',               N'Bileşen',  N'Lastik',              N'Lastikor',   800),
('P013', N'Lastikor İç Lastik',                 N'Bileşen',  N'Lastik',              N'Lastikor',   180),
('P014', N'Jantaş Alüminyum Jant Seti',         N'Bileşen',  N'Jant',                N'Jantaş',    5200),
('P015', N'Zincirli Bisiklet Zinciri',          N'Bileşen',  N'Zincir',              N'Zincirli',   450),
('P016', N'Konfora Jel Sele',                   N'Bileşen',  N'Sele',                N'Konfora',    700),
('P017', N'Gidonya Alüminyum Gidon',            N'Bileşen',  N'Gidon',               N'Gidonya',   1100),
('P018', N'Pedalis Platform Pedal',             N'Bileşen',  N'Pedal',               N'Pedalis',    650),
('P019', N'Kafatek Yol Kaskı',                  N'Aksesuar', N'Kask',                N'Kafatek',   1800),
('P020', N'Kafatek Dağ Kaskı',                  N'Aksesuar', N'Kask',                N'Kafatek',   2100),
('P021', N'Kilitrax U Kilit',                   N'Aksesuar', N'Kilit',               N'Kilitrax',   650),
('P022', N'Kilitrax Zincirli Kilit',            N'Aksesuar', N'Kilit',               N'Kilitrax',   480),
('P023', N'Pompaş Ayak Pompası',                N'Aksesuar', N'Pompa',               N'Pompaş',     420),
('P024', N'Aydınlık Ön Far',                    N'Aksesuar', N'Aydınlatma',          N'Aydınlık',   380),
('P025', N'Aydınlık Arka Stop',                 N'Aksesuar', N'Aydınlatma',          N'Aydınlık',   220),
('P026', N'Yudumlux Suluk',                     N'Aksesuar', N'Suluk',               N'Yudumlux',   150),
('P027', N'Sırtlan Bisiklet Çantası',           N'Aksesuar', N'Çanta',               N'Sırtlan',    900),
('P028', N'Sırtlan Bisiklet Eldiveni',          N'Aksesuar', N'Eldiven',             N'Sırtlan',    550);
GO

/* ---------- silver.RefStore ---------- */
IF OBJECT_ID(N'silver.RefStore', N'U') IS NOT NULL DROP TABLE silver.RefStore;
CREATE TABLE silver.RefStore
(
    StoreID   CHAR(4)       NOT NULL CONSTRAINT PK_silver_RefStore PRIMARY KEY,
    StoreName NVARCHAR(100) NOT NULL,
    City      NVARCHAR(50)  NOT NULL,
    Region    NVARCHAR(50)  NOT NULL,
    StoreType NVARCHAR(20)  NOT NULL
);

INSERT INTO silver.RefStore (StoreID, StoreName, City, Region, StoreType) VALUES
('S001', N'İstanbul Kadıköy Mağazası',   N'İstanbul',  N'Marmara',            N'Fiziksel'),
('S002', N'İstanbul Beşiktaş Mağazası',  N'İstanbul',  N'Marmara',            N'Fiziksel'),
('S003', N'İstanbul Esenyurt Mağazası',  N'İstanbul',  N'Marmara',            N'Fiziksel'),
('S004', N'Ankara Çankaya Mağazası',     N'Ankara',    N'İç Anadolu',         N'Fiziksel'),
('S005', N'Ankara Keçiören Mağazası',    N'Ankara',    N'İç Anadolu',         N'Fiziksel'),
('S006', N'İzmir Karşıyaka Mağazası',    N'İzmir',     N'Ege',                N'Fiziksel'),
('S007', N'İzmir Bornova Mağazası',      N'İzmir',     N'Ege',                N'Fiziksel'),
('S008', N'Bursa Nilüfer Mağazası',      N'Bursa',     N'Marmara',            N'Fiziksel'),
('S009', N'Antalya Muratpaşa Mağazası',  N'Antalya',   N'Akdeniz',            N'Fiziksel'),
('S010', N'Adana Seyhan Mağazası',       N'Adana',     N'Akdeniz',            N'Fiziksel'),
('S011', N'Konya Selçuklu Mağazası',     N'Konya',     N'İç Anadolu',         N'Fiziksel'),
('S012', N'Gaziantep Şahinbey Mağazası', N'Gaziantep', N'Güneydoğu Anadolu',  N'Fiziksel'),
('S013', N'Samsun İlkadım Mağazası',     N'Samsun',    N'Karadeniz',          N'Fiziksel'),
('S014', N'Trabzon Ortahisar Mağazası',  N'Trabzon',   N'Karadeniz',          N'Fiziksel'),
('S900', N'Dijital Kanal Deposu',        N'İstanbul',  N'Dijital',            N'Dijital');
GO

/* ---------- silver.RefCampaign (Gold DimCampaign'in kaynağı; O2'de kullanılır) ---------- */
IF OBJECT_ID(N'silver.RefCampaign', N'U') IS NOT NULL DROP TABLE silver.RefCampaign;
CREATE TABLE silver.RefCampaign
(
    CampaignName   NVARCHAR(60) NOT NULL CONSTRAINT PK_silver_RefCampaign PRIMARY KEY,
    CampaignType   NVARCHAR(40) NOT NULL,
    CampaignSeason NVARCHAR(20) NOT NULL
);

INSERT INTO silver.RefCampaign (CampaignName, CampaignType, CampaignSeason) VALUES
(N'Yılbaşı Kampanyası',         N'Yılbaşı',            N'Kış'),
(N'Ramazan Kampanyası',         N'Dini Bayram',        N'İlkbahar'),
(N'Kurban Bayramı Kampanyası',  N'Dini Bayram',        N'Yaz'),
(N'Yaz Kampanyası',             N'Mevsimsel',          N'Yaz'),
(N'Okula Dönüş Kampanyası',     N'Mevsimsel',          N'Sonbahar'),
(N'Kasım Kampanyası',           N'Alışveriş Festivali', N'Sonbahar'),
(N'Kampanya Yok',               N'Yok',                N'Tüm Yıl');
GO

/* ---------- silver.RefValueMap: yazım varyantı -> standart değer ----------
   SourceKey = silver.fn_FoldKey(ham değer) çıktısıdır (Türkçe karakter katlanmış, BÜYÜK harf, noktasız).
   Örn: 'İst.' -> 'IST' -> İstanbul ; 'kredi kartı' -> 'KREDI KARTI' -> Kredi Kartı */
IF OBJECT_ID(N'silver.RefValueMap', N'U') IS NOT NULL DROP TABLE silver.RefValueMap;
CREATE TABLE silver.RefValueMap
(
    MapType     VARCHAR(20)   NOT NULL,
    SourceKey   NVARCHAR(60)  NOT NULL,
    TargetValue NVARCHAR(60)  NOT NULL,
    CONSTRAINT PK_silver_RefValueMap PRIMARY KEY (MapType, SourceKey)
);

INSERT INTO silver.RefValueMap (MapType, SourceKey, TargetValue) VALUES
('City', N'ISTANBUL',  N'İstanbul'), ('City', N'IST',   N'İstanbul'),
('City', N'ANKARA',    N'Ankara'),   ('City', N'ANK',   N'Ankara'),
('City', N'IZMIR',     N'İzmir'),    ('City', N'IZM',   N'İzmir'),
('City', N'BURSA',     N'Bursa'),
('City', N'ANTALYA',   N'Antalya'),  ('City', N'ANT',   N'Antalya'),
('City', N'ADANA',     N'Adana'),
('City', N'KONYA',     N'Konya'),
('City', N'GAZIANTEP', N'Gaziantep'),('City', N'GANTEP', N'Gaziantep'), ('City', N'ANTEP', N'Gaziantep'),
('City', N'SAMSUN',    N'Samsun'),
('City', N'TRABZON',   N'Trabzon'),

('Gender', N'E',     N'Erkek'), ('Gender', N'ERKEK', N'Erkek'), ('Gender', N'M', N'Erkek'),
('Gender', N'K',     N'Kadın'), ('Gender', N'KADIN', N'Kadın'), ('Gender', N'F', N'Kadın'),

('Payment', N'KREDI KARTI', N'Kredi Kartı'), ('Payment', N'KK',    N'Kredi Kartı'), ('Payment', N'KART', N'Kredi Kartı'),
('Payment', N'NAKIT',       N'Nakit'),       ('Payment', N'PESIN', N'Nakit'),
('Payment', N'HAVALE/EFT',  N'Havale/EFT'),  ('Payment', N'HAVALE', N'Havale/EFT'), ('Payment', N'EFT', N'Havale/EFT');
GO

/* ---------- dq.RuleCatalog: DQ kural kataloğu ---------- */
IF OBJECT_ID(N'dq.RuleCatalog', N'U') IS NOT NULL DROP TABLE dq.RuleCatalog;
CREATE TABLE dq.RuleCatalog
(
    RuleCode        CHAR(4)       NOT NULL CONSTRAINT PK_dq_RuleCatalog PRIMARY KEY,
    Dimension       NVARCHAR(20)  NOT NULL,      -- Tamlık / Geçerlilik / Tutarlılık / Benzersizlik / Bütünlük
    RuleDescription NVARCHAR(200) NOT NULL,
    Action          NVARCHAR(20)  NOT NULL       -- Düzelt / NULL / Karantina / Tekrar Elendi
);

INSERT INTO dq.RuleCatalog (RuleCode, Dimension, RuleDescription, Action) VALUES
('DQ01', N'Tamlık',       N'MusteriAdi boş değil',                                          N'Düzelt'),
('DQ02', N'Tamlık',       N'UrunKategori boş değil',                                        N'Düzelt'),
('DQ03', N'Tamlık',       N'SiparisTarihi boş değil',                                       N'Karantina'),
('DQ04', N'Geçerlilik',   N'SiparisAdedi > 0',                                              N'Karantina'),
('DQ05', N'Geçerlilik',   N'MusteriYas 18-100 aralığında',                                  N'NULL'),
('DQ06', N'Geçerlilik',   N'BirimFiyat aykırı değil (<= 3 x ürün baz fiyatı)',              N'Karantina'),
('DQ07', N'Geçerlilik',   N'Tarih KaynakAy ile uyumlu ve bugünden ileri değil',             N'Karantina'),
('DQ08', N'Geçerlilik',   N'IndirimOrani 0-1 aralığında (yüzde tam sayı değil)',            N'Düzelt'),
('DQ09', N'Geçerlilik',   N'Sayısal alanlarda ondalık ayracı nokta',                        N'Düzelt'),
('DQ10', N'Geçerlilik',   N'Tarih biçimi ISO (YYYY-MM-DD)',                                 N'Düzelt'),
('DQ11', N'Tutarlılık',   N'Şehir standart yazımda',                                        N'Düzelt'),
('DQ12', N'Tutarlılık',   N'Metinlerde baş/son boşluk yok; harf büyüklüğü standart',        N'Düzelt'),
('DQ13', N'Tutarlılık',   N'Kategori yazımı RefProduct ile uyumlu',                         N'Düzelt'),
('DQ14', N'Tutarlılık',   N'Cinsiyet ve ödeme tipi tanımlı değer kümesinde',                N'Düzelt'),
('DQ15', N'Tutarlılık',   N'Müşteri adı "Ad Soyad" sırasında (müşterinin en sık adıyla uyumlu)', N'Düzelt'),
('DQ16', N'Tutarlılık',   N'MusteriID biçimi Mddddd',                                       N'Düzelt'),
('DQ17', N'Benzersizlik', N'(SiparisID, SiparisSatirID) tekrar etmez',                      N'Tekrar Elendi'),
('DQ18', N'Bütünlük',     N'UrunID RefProduct içinde var',                                  N'Karantina'),
('DQ19', N'Bütünlük',     N'MagazaID ile MagazaAdi RefStore ile uyumlu',                    N'Düzelt');
GO

SELECT N'Referans tablolar hazır' AS Durum,
       (SELECT COUNT(*) FROM silver.RefProduct)  AS Urun,
       (SELECT COUNT(*) FROM silver.RefStore)    AS Magaza,
       (SELECT COUNT(*) FROM silver.RefCampaign) AS Kampanya,
       (SELECT COUNT(*) FROM silver.RefValueMap) AS DegerEsleme,
       (SELECT COUNT(*) FROM dq.RuleCatalog)     AS Kural;
GO

/* =====================================================================
   31_Silver_Fonksiyonlar.sql
   Amaç      : Silver temizliğinde kullanılan, tablo erişimi OLMAYAN (saf) skaler fonksiyonlar.
               Saf + SCHEMABINDING olduğu için SQL Server 2019+ bunları satır içine açabilir (hızlı çalışır).
   Bağımlılık: Şema silver (10_Bronze_Kurulum.sql). Yeniden çalıştırılabilir (CREATE OR ALTER).
   Fonksiyonlar:
     silver.fn_FoldKey          Türkçe karakterleri ASCII'ye katla, BÜYÜK harf, noktaları at  -> eşleme anahtarı
     silver.fn_CleanText        Baş/son boşluğu at, boşsa NULL
     silver.fn_ParseDate        'YYYY-MM-DD' veya 'dd.MM.yyyy' -> DATE (olmazsa NULL)
     silver.fn_ParseDecimal     '720.42' / '720,42' -> DECIMAL(18,2) (olmazsa NULL)
     silver.fn_NormalizeCustomerID  'm00227' / 'M-00227' / 'M227' -> 'M00227'
   ===================================================================== */
USE BikeRetailDW;
GO

/* fn_FoldKey: 'İst.' -> 'IST', 'kredi kartı' -> 'KREDI KARTI', 'Peşin' -> 'PESIN'
   Neden TRANSLATE + UPPER? Türkçe collation'da UPPER('i') = 'İ' olduğu için önce i/ı/İ hepsini I'ya çeviriyoruz. */
CREATE OR ALTER FUNCTION silver.fn_FoldKey (@s NVARCHAR(200))
RETURNS NVARCHAR(200)
WITH SCHEMABINDING
AS
BEGIN
    RETURN LTRIM(RTRIM(REPLACE(UPPER(TRANSLATE(@s, N'İıiŞşĞğÜüÖöÇç', N'IIISSGGUUOOCC')), N'.', N'')));
END
GO

CREATE OR ALTER FUNCTION silver.fn_CleanText (@s NVARCHAR(200))
RETURNS NVARCHAR(200)
WITH SCHEMABINDING
AS
BEGIN
    RETURN NULLIF(LTRIM(RTRIM(@s)), N'');
END
GO

/* fn_ParseDate: ISO (23) ve Alman biçimi dd.MM.yyyy (104). Desen kontrolü, yanlış ayrıştırmayı önler. */
CREATE OR ALTER FUNCTION silver.fn_ParseDate (@s NVARCHAR(50))
RETURNS DATE
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE
        WHEN LTRIM(RTRIM(@s)) LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
            THEN TRY_CONVERT(DATE, LTRIM(RTRIM(@s)), 23)
        WHEN LTRIM(RTRIM(@s)) LIKE N'[0-3][0-9].[0-1][0-9].[0-9][0-9][0-9][0-9]'
            THEN TRY_CONVERT(DATE, LTRIM(RTRIM(@s)), 104)
        ELSE NULL
    END;
END
GO

/* fn_ParseDecimal: virgülü noktaya çevirip DECIMAL'e dönüştürür. Boş/bozuk -> NULL */
CREATE OR ALTER FUNCTION silver.fn_ParseDecimal (@s NVARCHAR(50))
RETURNS DECIMAL(18,2)
WITH SCHEMABINDING
AS
BEGIN
    RETURN TRY_CAST(REPLACE(NULLIF(LTRIM(RTRIM(@s)), N''), N',', N'.') AS DECIMAL(18,2));
END
GO

/* fn_NormalizeCustomerID: M/m ve '-' karakterlerini at, kalan yalnızca rakamsa 5 haneye tamamla. */
CREATE OR ALTER FUNCTION silver.fn_NormalizeCustomerID (@s NVARCHAR(50))
RETURNS CHAR(6)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @digits NVARCHAR(50) = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@s)), N'M', N''), N'm', N''), N'-', N'');
    RETURN CASE
        WHEN @digits <> N'' AND @digits NOT LIKE N'%[^0-9]%' AND LEN(@digits) <= 5
            THEN 'M' + RIGHT('00000' + @digits, 5)
        ELSE NULL
    END;
END
GO

/* ---------- Hızlı sınama (beklenen sonuç yanında) ---------- */
SELECT
    silver.fn_FoldKey(N'İst.')           AS FoldKey_Ist,        -- IST
    silver.fn_FoldKey(N'G.Antep')        AS FoldKey_GAntep,     -- GANTEP
    silver.fn_FoldKey(N'kredi kartı')    AS FoldKey_KK,         -- KREDI KARTI
    silver.fn_FoldKey(N'Peşin')          AS FoldKey_Pesin,      -- PESIN
    silver.fn_ParseDate(N'15.03.2023')   AS Tarih_Alman,        -- 2023-03-15
    silver.fn_ParseDate(N'2023-03-15')   AS Tarih_ISO,          -- 2023-03-15
    silver.fn_ParseDate(N'')             AS Tarih_Bos,          -- NULL
    silver.fn_ParseDecimal(N'720,42')    AS Ondalik_Virgul,     -- 720.42
    silver.fn_ParseDecimal(N'10385.0')   AS Ondalik_Nokta,      -- 10385.00
    silver.fn_NormalizeCustomerID(N'M-00227') AS Musteri_Tire,  -- M00227
    silver.fn_NormalizeCustomerID(N'm00227')  AS Musteri_Kucuk, -- M00227
    silver.fn_NormalizeCustomerID(N'M227')    AS Musteri_Kisa;  -- M00227
GO

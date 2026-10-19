/*
--https://learn.microsoft.com/en-us/sql/machine-learning/install/sql-machine-learning-services-windows-install-sql-2022?view=sql-server-ver17
--Python Script çalıştırma özelliğini aktif edelim.
EXEC sp_configure  'external scripts enabled', 1;
RECONFIGURE WITH OVERRIDE

--Kontrol edelim
EXEC sp_configure  'external scripts enabled';

--Örnek Python kodu
EXEC sp_execute_external_script @script=N'import sys;print(sys.version)',@language=N'Python'
GO


--Yerel dosyaya erişmek için (klasorde şunlara yetki ver)
Hesap Adı	                Amaç
-------------------------   --------------------------
NT Service\MSSQLLaunchpad	Launchpad hizmet hesabı
ALL APPLICATION PACKAGES	AppContainer yalıtım kapsayıcısının dosya erişim kimliği

--Dosya erişim testi
EXEC sp_execute_external_script
    @language = N'Python',
    @script = N'
import os
files = os.listdir(r"D:\KData")
print(f"Klasördeki dosya sayısı: {len(files)}")
';
*/

----------------------------
DECLARE @folder_path NVARCHAR(500) = N'C:\PedalovaBIProject\SalesRawData';

EXEC sp_execute_external_script
    @language = N'Python',
    @script = N'
import pandas as pd
import glob
import os

folder_path = folder_path_param
all_files = glob.glob(os.path.join(folder_path, "*.csv"))

if not all_files:
    print(f"Uyari: {folder_path} klasorunde CSV dosyasi bulunamadi")
    OutputDataSet = pd.DataFrame()
else:
    df_list = []
    for file in all_files:
        try:
            # dtype=str ile her sey metin olarak okunur, tip donusumu yapilmaz
            df = pd.read_csv(file, dtype=str, keep_default_na=False)
            df_list.append(df)
            print(f"Okundu: {os.path.basename(file)} ({len(df)} satir)")
        except Exception as e:
            print(f"Okuma hatasi {os.path.basename(file)}: {str(e)}")
    
    if df_list:
        OutputDataSet = pd.concat(df_list, ignore_index=True)
        print(f"Toplam birlestirilen: {len(OutputDataSet)} satir")
    else:
        OutputDataSet = pd.DataFrame()
',
    @input_data_1 = N'',
    @params = N'@folder_path_param NVARCHAR(500)',
    @folder_path_param = @folder_path
WITH RESULT SETS ((
    [KaynakAy] NVARCHAR(MAX),
    [SiparisID] NVARCHAR(MAX),
    [SiparisSatirID] NVARCHAR(MAX),
    [SiparisTarihi] NVARCHAR(MAX),
    [MusteriID] NVARCHAR(MAX),
    [MusteriAdi] NVARCHAR(MAX),
    [MusteriCinsiyet] NVARCHAR(MAX),
    [MusteriYas] NVARCHAR(MAX),
    [MusteriUyelikYili] NVARCHAR(MAX),
    [MusteriSehir] NVARCHAR(MAX),
    [MagazaID] NVARCHAR(MAX),
    [MagazaAdi] NVARCHAR(MAX),
    [MagazaBolge] NVARCHAR(MAX),
    [SatisKanali] NVARCHAR(MAX),
    [UrunID] NVARCHAR(MAX),
    [UrunAdi] NVARCHAR(MAX),
    [UrunKategori] NVARCHAR(MAX),
    [UrunAltKategori] NVARCHAR(MAX),
    [UrunMarka] NVARCHAR(MAX),
    [SiparisAdedi] NVARCHAR(MAX),
    [BirimFiyat] NVARCHAR(MAX),
    [UrunMaliyeti] NVARCHAR(MAX),
    [IndirimOrani] NVARCHAR(MAX),
    [KampanyaAdi] NVARCHAR(MAX),
    [OdemeTipi] NVARCHAR(MAX)
));
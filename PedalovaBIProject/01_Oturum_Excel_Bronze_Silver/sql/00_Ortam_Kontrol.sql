/* =====================================================================
   00_Ortam_Kontrol.sql
   Amac     : SQL Server'in Python calistirabildigini ve CSV klasorunu gorebildigini dogrula.
   Bagimlilik: Yok (master/herhangi bir DB'de calisir). Yeniden calistirilabilir.
   Not      : Bu dosya yalnizca okuma/kontrol yapar, nesne olusturmaz.
   ===================================================================== */

-- 1) Surum
SELECT @@VERSION AS SurumBilgisi;
GO

-- 2) External scripts etkin mi? (value_in_use = 1 olmali)
SELECT name, value, value_in_use
FROM sys.configurations
WHERE name = N'external scripts enabled';
-- Etkin degilse (bir kez):
--   EXEC sp_configure 'external scripts enabled', 1;  RECONFIGURE WITH OVERRIDE;
--   ardindan SQL Server servisini yeniden baslat.
GO

-- 3) Python + pandas calisiyor mu?
EXEC sp_execute_external_script
    @language = N'Python',
    @script = N'
import sys
import pandas as pd
print("Python:", sys.version.split()[0], "| pandas:", pd.__version__)
OutputDataSet = pd.DataFrame({"Durum": ["Python OK"]})
'
WITH RESULT SETS ((Durum NVARCHAR(50)));
GO

-- 4) CSV klasorunu gorebiliyor mu? (yolu kendi ortamina gore degistir; kalici yol 10_Bronze_Kurulum.sql'de tanimlanir)
DECLARE @FolderPath NVARCHAR(500) = N'C:\PedalovaBIProject\SalesRawData';

EXEC sp_execute_external_script
    @language = N'Python',
    @script = N'
import os
import pandas as pd
dosyalar = sorted(f for f in os.listdir(folder_path_param) if f.lower().endswith(".csv"))
print("Klasor:", folder_path_param, "| CSV sayisi:", len(dosyalar))
OutputDataSet = pd.DataFrame({"DosyaAdi": dosyalar})
',
    @params = N'@folder_path_param NVARCHAR(500)',
    @folder_path_param = @FolderPath
WITH RESULT SETS ((DosyaAdi NVARCHAR(260)));
-- Hata: "PermissionError / WinError 5" -> klasore SQLRUserGroup<instance> icin Read izni ver
--       (icacls "C:\PedalovaBIProject" /grant "SQLRUserGroup<instance>:(OI)(CI)RX"  ve "ALL APPLICATION PACKAGES").
GO

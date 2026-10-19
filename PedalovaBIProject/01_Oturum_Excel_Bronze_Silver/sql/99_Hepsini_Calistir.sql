/* =====================================================================
   99_Hepsini_Calistir.sql   (PLAN B - canlı demo çökerse)
   Amaç      : Bronze + Silver + DQ zincirinin TAMAMINI tek seferde, sırayla kurar ve yükler.
   Kullanım  : SSMS > Sorgu > SQLCMD Modu'nu AÇ (Query > SQLCMD Mode), aşağıdaki SqlKlasor değişkenini düzelt, F5.
   Süre      : ~1-2 dk (veri boyutuna bağlı)
   ===================================================================== */
:setvar SqlKlasor "C:\PedalovaBIProject\E2E_BI_Project\01_Oturum_Excel_Bronze_Silver\sql"
:on error exit

:r $(SqlKlasor)\10_Bronze_Kurulum.sql
:r $(SqlKlasor)\11_Bronze_Yukle.sql
:r $(SqlKlasor)\12_Bronze_Kontrol.sql
:r $(SqlKlasor)\20_Profiling.sql
:r $(SqlKlasor)\30_Silver_Referans.sql
:r $(SqlKlasor)\31_Silver_Fonksiyonlar.sql
:r $(SqlKlasor)\32_Silver_Tablolar.sql
:r $(SqlKlasor)\33_Silver_Views.sql
:r $(SqlKlasor)\34_Silver_Prosedur.sql
:r $(SqlKlasor)\35_DQ_Views.sql
:r $(SqlKlasor)\40_Silver_Dogrulama.sql

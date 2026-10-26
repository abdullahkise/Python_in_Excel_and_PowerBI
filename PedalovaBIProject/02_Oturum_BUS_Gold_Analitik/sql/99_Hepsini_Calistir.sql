/* =====================================================================
   99_Hepsini_Calistir.sql   (PLAN B - canlı demo çökerse)
   Amaç      : O2 Gold zincirinin TAMAMINI sırayla kurar ve yükler.
   Ön koşul  : O1 tamamlanmış (silver.Sales dolu). Yoksa önce O1\sql\99_Hepsini_Calistir.sql çalıştırılmalı.
   Kullanım  : SSMS > Sorgu > SQLCMD Modu'nu AÇ, SqlKlasor değişkenini düzelt, F5.
   ===================================================================== */
:setvar SqlKlasor "C:\PedalovaBIProject\E2E_BI_Project\02_Oturum_BUS_Gold_Analitik\sql"
:on error exit

:r $(SqlKlasor)\10_Gold_Tablolar.sql
:r $(SqlKlasor)\11_Gold_DimDate.sql
:r $(SqlKlasor)\12_Gold_Src_Views.sql
:r $(SqlKlasor)\13_Gold_Prosedurler.sql
:r $(SqlKlasor)\14_Gold_Dogrulama.sql
:r $(SqlKlasor)\15_Gold_Analitik_Views.sql

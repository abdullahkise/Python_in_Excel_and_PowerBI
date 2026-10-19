"""
11_Bronze_Yukle.sql icindeki Python bolumunu YEREL olarak test eder (SQL Server gerekmez).

Amac : SQL dosyasindaki @script metnini aynen cikarip, folder_path_param verip calistirir;
       OutputDataSet'in satir/kolon sayisini ve bozuk-karakter/BOM durumunu raporlar.
Kullanim: python bronze_csv_reader_test.py <SalesRawData klasoru> [sql dosyasi]
Bagimlilik: pandas
"""

import re
import sys
from pathlib import Path

klasor = sys.argv[1]
sql = Path(sys.argv[2] if len(sys.argv) > 2 else Path(__file__).parent.parent / "sql" / "11_Bronze_Yukle.sql")

metin = sql.read_text(encoding="utf-8-sig")
m = re.search(r"@script = N'(.*?)',\s*@params", metin, re.S)
if not m:
    sys.exit("Python script bolumu bulunamadi")
kod = m.group(1)
assert "'" not in kod, "Python kodunda tek tirnak var; T-SQL string'ini bozar"

ns = {"folder_path_param": klasor}
exec(kod, ns)
out = ns["OutputDataSet"]
print("Satir:", len(out), "| Kolon:", len(out.columns))
print("Kolonlar:", list(out.columns))
print("Dosya bazli:", out.groupby("SourceFileName").size().to_dict())
print("BOM'lu ilk kolon adi sorunu yok mu:", out.columns[0] == "KaynakAy")
print("Bos hucre (''), NULL degil:", int((out.MusteriAdi == "").sum()), "| NaN:", int(out.isna().sum().sum()))

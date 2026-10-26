"""
networkx_powerbi_gorsel.py'yi Power BI OLMADAN yerelde sınar.

Nasıl çalışır?
  - Power BI'ın Python görseline verdiği `dataset` DataFrame'ini taklit eder (alanlar: OrderID, OrderLineID, ProductName, Category)
    ve Power BI'ın "tekrar eden satırları kaldırma" davranışını uygular.
  - Betiği (başlık yorumları dahil aynen) çalıştırır; plt.show() yerine resmi PNG olarak kaydeder.
Bağımlılık: pandas, matplotlib, networkx
Kullanım  : python networkx_yerel_test.py <SalesRawData klasörü> [--png <çıktı.png>] [--kategori Aksesuar]
            (--kategori: Power BI'daki Kategori dilimleyicisi seçimini taklit eder)
"""

import argparse
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import o3_hesapla as o3  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ap = argparse.ArgumentParser()
ap.add_argument("klasor")
ap.add_argument("--png", default=str(Path(__file__).resolve().parent / "networkx_ornek.png"))
ap.add_argument("--kategori", default=None)
ap.add_argument("--yil", type=int, default=None, help="Power BI'daki Yıl dilimleyicisini taklit eder (satır sınırı için önerilir)")
a = ap.parse_args()

fact, _, _ = o3.fakt_olustur(a.klasor)
if a.kategori:
    fact = fact[fact.Category == a.kategori]
if a.yil:
    fact = fact[fact.OrderDate.dt.year == a.yil]
dataset = fact[["OrderID", "OrderLineID", "ProductName", "Category"]].drop_duplicates()
print("dataset:", dataset.shape, "| Power BI dedup sonrası aynı satır sayısı:", len(dataset) == len(fact),
      "| 150.000 satır sınırı aşıldı mı:", len(dataset) > 150000)

kaydedilen = []
plt.show = lambda *args, **kw: (plt.gcf().savefig(a.png, dpi=110), kaydedilen.append(a.png))

kod = (Path(__file__).parent / "networkx_powerbi_gorsel.py").read_text(encoding="utf-8")
ns = {"dataset": dataset}
exec(compile(kod, "networkx_powerbi_gorsel.py", "exec"), ns)

G = ns["G"]
print(f"Ağ: düğüm {G.number_of_nodes()}, kenar {G.number_of_edges()} | sipariş {ns['n_siparis']:,} | PNG: {kaydedilen}")
import networkx as nx  # noqa: E402
print("Bağlı bileşen:", nx.number_connected_components(G) if G.number_of_nodes() else 0)
if G.number_of_edges():
    top = sorted(G.edges(data=True), key=lambda e: -e[2]["lift"])[:5]
    print("En yüksek lift kenarları:")
    for u, v, w in top:
        print(f"  {u} — {v}: birlikte {w['birlikte']}, lift {w['lift']:.2f}")

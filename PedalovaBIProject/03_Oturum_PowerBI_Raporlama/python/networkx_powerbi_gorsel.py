# =====================================================================
# networkx_powerbi_gorsel.py  -  Power BI Python görseli: "Ürünler arasındaki görünmeyen ilişkiler"
#
# BONUS ANALYTICS. İş sorusu: "Peki ürünler arasındaki görünmeyen ilişkileri bulabilir miyiz?"
# Düğüm = ürün, kenar = AYNI SİPARİŞTE birlikte geçme.
#   Düğüm boyutu = ürünün geçtiği sipariş sayısı | Düğüm rengi = kategori
#   Kenar kalınlığı = LIFT (birliktelik, rastlantıdan kaç kat fazla?) | Kenar filtresi: en az MIN_BIRLIKTE sipariş ve MIN_LIFT
#
# KURULUM (Power BI Desktop):
#   1) Dosya > Seçenekler > Python betiği: yerel Python klasörü gösterilmiş olmalı (pandas, matplotlib, networkx kurulu).
#   2) Görselleştirme panelinden "Python görseli"ni ekle ve ŞU ALANLARI "Değerler"e sürükle:
#        DimProduct[ProductName], DimProduct[Category], FactSales[OrderID], FactSales[OrderLineID]
#      (Alan adları tabloda "ProductName" vb. olarak gelir; betik bu adlara göre çalışır.)
#   3) Python betik düzenleyicisine AŞAĞIDAKİ KODU (bu başlık hariç) yapıştır ve ▶ çalıştır.
#   4) Rapordaki dilimleyiciler (Kanal, Tarih, Segment...) görseli FİLTRELER: ağ seçime göre yeniden hesaplanır.
#   5) SATIR SINIRI: Python görseli en fazla 150.000 satır alır; 24 aylık veri 161.809 satırdır → görsel düzeyinde
#      Yıl = 2024 (veya 2023) filtresi uygula, aksi halde Power BI ilk 150.000 satırla çalışır ve uyarı gösterir.
#      Yerel prova: python networkx_yerel_test.py <SalesRawData> --yil 2024
#
# PYTHON GÖRSELİ KISITLARI: `dataset` = seçilen alanlardan oluşan DataFrame ve TEKRAR EDEN SATIRLAR KALDIRILIR
# (bu yüzden OrderLineID'yi de ekliyoruz); en çok 150.000 satır; çalışma ~5 sn; görsel etkileşimsizdir (resimdir).
# Çıktı: plt.show() ile oluşan resim. Power BI Service'te desteklenen paketler sınırlıdır: yayınlamadan ÖNCE
# networkx'in Service'te desteklendiğini doğrula (Desktop'ta yerel Python ile her zaman çalışır).
# =====================================================================

import textwrap
from collections import Counter
from itertools import combinations

import matplotlib.pyplot as plt
import networkx as nx
import pandas as pd

MIN_BIRLIKTE = 50     # kenar için en az ortak sipariş sayısı (gürültüyü eler)
MIN_LIFT = 1.5        # 1 = rastlantı; 1,5 = rastlantıdan %50 fazla birliktelik
SEED = 42

d = dataset[["OrderID", "ProductName", "Category"]].drop_duplicates()
kategori = d.drop_duplicates("ProductName").set_index("ProductName")["Category"].to_dict()
sepetler = d.groupby("OrderID")["ProductName"].apply(lambda s: sorted(set(s)))
n_siparis = len(sepetler)

urun_say, cift_say = Counter(), Counter()
for sepet in sepetler:
    urun_say.update(sepet)
    cift_say.update(combinations(sepet, 2))

G = nx.Graph()
for (a, b), c in cift_say.items():
    lift = (c / n_siparis) / ((urun_say[a] / n_siparis) * (urun_say[b] / n_siparis))
    if c >= MIN_BIRLIKTE and lift >= MIN_LIFT:
        G.add_edge(a, b, birlikte=c, lift=lift)

fig = plt.figure(figsize=(11, 7.5))
ax = fig.add_subplot(111)
ax.axis("off")

if G.number_of_edges() == 0:
    ax.text(0.5, 0.5, "Seçili filtrelerde eşiği geçen ürün çifti yok\n(MIN_BIRLIKTE=%d, MIN_LIFT=%.1f)" % (MIN_BIRLIKTE, MIN_LIFT),
            ha="center", va="center", fontsize=12)
else:
    renk = {"Bisiklet": "#C0504D", "Bileşen": "#4F81BD", "Aksesuar": "#9BBB59"}

    # Bağlantısız bileşenler birbirinden savrulmasın: her bileşeni ayrı yerleştir, ızgara üzerine diz
    bilesenler = sorted(nx.connected_components(G), key=len, reverse=True)
    merkezler = [(0.0, 0.0), (6.2, 0.8), (-6.2, 0.8), (0.0, -5.0), (6.2, -4.0), (-6.2, -4.0), (0.0, 5.0), (6.2, 4.6), (-6.2, 4.6)]
    pos = {}
    for i, b in enumerate(bilesenler):
        H = G.subgraph(b)
        yaricap = 1.6 * (len(b) ** 0.5) if i == 0 else 0.8 * (len(b) ** 0.5) + 0.4
        yerel = nx.kamada_kawai_layout(H, scale=yaricap) if len(b) > 2 else nx.spring_layout(H, seed=SEED, scale=yaricap)
        cx, cy = merkezler[i % len(merkezler)]
        for v, (x, y) in yerel.items():
            pos[v] = (x + cx, y + cy)

    en_cok = max(urun_say[v] for v in G.nodes)
    boyut = [120 + 700 * urun_say[v] / en_cok for v in G.nodes]
    nx.draw_networkx_edges(G, pos, ax=ax, alpha=0.40, edge_color="#7F7F7F",
                           width=[0.3 + 0.3 * G[u][v]["lift"] for u, v in G.edges])
    nx.draw_networkx_nodes(G, pos, ax=ax, node_size=boyut, edgecolors="white", linewidths=1.0,
                           node_color=[renk.get(kategori.get(v), "#BFBFBF") for v in G.nodes])
    etiket = {v: "\n".join(textwrap.wrap(v, 14)) for v in G.nodes}
    nx.draw_networkx_labels(G, pos, labels=etiket, ax=ax, font_size=6)
    for ad, r in renk.items():
        ax.scatter([], [], c=r, label=ad, s=60)
    ax.legend(loc="lower left", fontsize=8, frameon=False, title="Kategori")
    ax.set_title("Ürün birliktelik ağı  |  %d sipariş, %d ürün, %d ilişki  (kenar kalınlığı = lift)"
                 % (n_siparis, G.number_of_nodes(), G.number_of_edges()), fontsize=10)

plt.tight_layout()
plt.show()

# =====================================================================
# kmeans_python_in_excel.py  -  Python in Excel: müşteri segmentasyonu (K-Means)
#
# İş sorusu: "Tüm müşterilere aynı kampanyayı göndermek doğru mu?"
# Özellikler: TotalSpend (toplam harcama), OrderCount (sipariş sayısı), AvgBasket (ortalama sepet)
#
# KULLANIM (Excel, Microsoft 365):
#   1) Power Query ile gold.vw_Analytics_Customer'ı sayfaya yükle ve TABLO ADINI "Musteri_RFM" yap
#      (m\01_Gold_Baglanti.m, sorgu: Musteri_RFM).
#   2) Boş bir hücreye gel -> Formüller > Python Ekle (veya Ctrl+Alt+Shift+P) -> aşağıdaki HÜCRE bloklarını
#      HER BİRİNİ AYRI BİR HÜCREYE yapıştır. Hücreler yukarıdan aşağı, sol-üstten sağ-alta sırayla hesaplanır
#      (Python in Excel'de hücre sırası = satır satır, soldan sağa). Bu yüzden blokları AYNI sütunda alt alta koy.
#   3) Çıktı türü: tablo (DataFrame) bloklarında "Excel Değeri" seç (sayfaya yayılır);
#      grafik (fig) bloklarında "Python Nesnesi" bırak ya da görüntüyü hücre içinde göster.
#
# PYTHON IN EXCEL KISITLARI: Bulutta (Azure) çalışır; internet ve yerel dosya erişimi YOK; veriye yalnızca xl() ile
# erişilir. Çıktı = hücredeki SON ifade. pandas, numpy, matplotlib, scikit-learn Anaconda dağıtımıyla hazır gelir.
# Bu dosya yerelde SQL/Excel olmadan python\kmeans_yerel_test.py ile sınanır (xl() taklit edilir).
# =====================================================================


# %% HÜCRE 1  -  Veri ve özet istatistik  (çıktı: Excel Değeri)
import pandas as pd
df = xl("Musteri_RFM[#All]", headers=True)
ozellikler = ["TotalSpend", "OrderCount", "AvgBasket"]
df[ozellikler].describe().round(2)


# %% HÜCRE 2  -  Ölçekleme + k seçimi (elbow ve silhouette tablosu)  (çıktı: Excel Değeri)
# Neden ölçekleme? Harcama (yüz binler) ve sipariş sayısı (onlar) aynı ölçekte olmazsa K-Means yalnızca harcamaya bakar.
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score

X = StandardScaler().fit_transform(df[ozellikler])
sonuc = []
for k in range(2, 9):
    km = KMeans(n_clusters=k, n_init=10, random_state=42).fit(X)
    sonuc.append((k, round(km.inertia_, 2), round(silhouette_score(X, km.labels_), 4)))
k_tablo = pd.DataFrame(sonuc, columns=["k", "Inertia", "Silhouette"])
k_tablo


# %% HÜCRE 3  -  Elbow ve silhouette grafiği  (çıktı: grafik)
import matplotlib.pyplot as plt
fig, ax = plt.subplots(1, 2, figsize=(9, 3.2))
ax[0].plot(k_tablo["k"], k_tablo["Inertia"], marker="o")
ax[0].set_title("Elbow (Inertia)")
ax[0].set_xlabel("k")
ax[1].plot(k_tablo["k"], k_tablo["Silhouette"], marker="o", color="tab:green")
ax[1].set_title("Silhouette (yüksek = iyi)")
ax[1].set_xlabel("k")
plt.tight_layout()
fig


# %% HÜCRE 4  -  Son model (k) + segment profili + isim önerisi  (çıktı: Excel Değeri)
K = 4   # HÜCRE 2'deki en yüksek silhouette değerine göre seçildi (bu veri için k = 4)
km = KMeans(n_clusters=K, n_init=10, random_state=42).fit(X)
seg = df[["CustomerID"] + ozellikler].copy()
seg["Cluster"] = km.labels_

profil = seg.groupby("Cluster").agg(
    Musteri=("CustomerID", "size"),
    Harcama=("TotalSpend", "mean"),
    Siparis=("OrderCount", "mean"),
    Sepet=("AvgBasket", "mean"),
).round(1)


def isim_oner(p):
    """Küme numarası her çalıştırmada değişebilir; isim PROFİLDEN türetilir (eğitmen istediği gibi değiştirebilir)."""
    ad, kalan = {}, list(p.index)
    en_sepet = p["Sepet"].idxmax()
    ad[en_sepet] = "Nadir Büyük Sepet"
    kalan.remove(en_sepet)
    en_sik = p.loc[kalan, "Siparis"].idxmax()
    ad[en_sik] = "Sık Küçük Alıcı"
    kalan.remove(en_sik)
    kalan = sorted(kalan, key=lambda c: -p.loc[c, "Harcama"])
    for c, n in zip(kalan, ["Düzenli Orta", "Düşük Hacimli"] + ["Diğer %d" % i for i in range(1, 9)]):
        ad[c] = n
    return ad


isimler = isim_oner(profil)
seg["Segment"] = seg["Cluster"].map(isimler)
profil["Segment"] = profil.index.map(isimler)
profil.sort_values("Harcama", ascending=False)


# %% HÜCRE 5  -  Müşteri - segment tablosu (Power BI'a gidecek çıktı)  (çıktı: Excel Değeri)
# Bu tabloyu yeni bir sayfaya (Musteri_Segmentleri) DEĞER olarak yapıştır ve CSV olarak kaydet:
#   Dosya > Farklı Kaydet > CSV UTF-8 (Virgülle ayrılmış)  ->  Musteri_Segmentleri.csv
cikti = seg[["CustomerID", "Segment", "TotalSpend", "OrderCount", "AvgBasket"]].sort_values("CustomerID").reset_index(drop=True)
cikti


# %% HÜCRE 6  -  Segment görselleştirme  (çıktı: grafik)
fig, ax = plt.subplots(figsize=(6, 4))
for ad, g in seg.groupby("Segment"):
    ax.scatter(g["OrderCount"], g["AvgBasket"], label=ad, s=28)
ax.set_xlabel("Sipariş sayısı")
ax.set_ylabel("Ortalama sepet (TL)")
ax.set_title("Müşteri segmentleri")
ax.legend(fontsize=7)
plt.tight_layout()
fig

# Dynamic Island untuk macOS — Spesifikasi MVP

Tanggal: 25 Oktober 2026  
Status: disetujui pengguna pada 25 Oktober 2026 sebagai dasar implementasi, termasuk stack Swift + SwiftUI + AppKit.  
Review builder: selesai; tidak ada pertanyaan penting tambahan untuk menyusun rencana. Review ini tidak membuktikan kelayakan integrasi teknis.  
Nama aplikasi: belum diputuskan; “Dynamic Island” dipakai sebagai nama kerja.

## 1. Tujuan

Aplikasi untuk MacBook Pro M1 tanpa notch yang menyediakan panel di tengah atas layar. Pengguna dapat mengendalikan musik Spotify, menitipkan file saat memindahkannya ke tujuan, menjalankan terminal, serta mengetahui dan menjawab pertanyaan AI agent tanpa terus berpindah aplikasi.

Masalah utama: permintaan jawaban atau akses dari AI agent CLI sering terlewat ketika pengguna bekerja di tempat lain. Aplikasi harus menjaga konteks sesi dan project agar respons tidak terkirim ke agent yang salah.

Dokumen ini merangkum keputusan brainstorming. Kemampuan integrasi eksternal belum diuji; contoh pada mockup menggunakan data simulasi.

## 2. Platform dan batasan

- Target awal: MacBook Pro M1 tanpa notch milik pengguna.
- Panel menempel di tengah tepi atas layar. Area pemicu setinggi menu bar.
- Bahasa antarmuka: English dan Bahasa Indonesia; default English.
- Spotify merupakan sumber musik prioritas MVP.
- Tidak ada shortcut global khusus island pada MVP. Keyboard tetap digunakan untuk mengetik di terminal dan berinteraksi dengan kontrol yang memiliki fokus.
- Pengguna menerima pemberian izin macOS yang memang dibutuhkan, tetapi tidak menerima pemasangan plugin/hook, perubahan konfigurasi CLI, atau perubahan cara menjalankan agent sebagai syarat integrasi sesi eksternal.
- Belum ada keputusan distribusi melalui App Store, signing, harga, atau nama final.

## 3. Keputusan tampilan

### Bentuk dan ukuran

- Panel berbentuk persegi panjang horizontal dengan sudut membulat di bagian bawah.
- Saat membuka, panel melebar simetris ke kiri dan kanan dari tengah sekaligus memanjang ke bawah; sisi atas tetap menempel pada tepi layar.
- Tinggi mengikuti isi. Hindari tinggi minimum bersama yang menyisakan ruang kosong pada musik atau file.
- Ukuran boleh berbeda untuk Home, pertanyaan, area drop, daftar agent, dan terminal, tetapi tetap mengutamakan proporsi horizontal.
- Card tidak memakai border dekoratif. Gunakan perbedaan permukaan, jarak, dan tipografi untuk membedakan isi. Indikator fokus aksesibilitas dan batas area drop fungsional tetap boleh.
- Tetap menggunakan gaya desain sendiri; screenshot referensi adalah ilustrasi perilaku, bukan desain yang harus disalin.

### Home

- Home adalah tampilan ketika island dibuka melalui hover.
- Musik tetap menjadi bagian utama: cover, judul, artis, play/pause, previous/next, dan progres lagu.
- Ringkasan agent dan titipan file berukuran lebih kecil di samping musik. Klik ringkasan membuka fitur terkait.
- Navigasi menyediakan Home, Agent, Music, Files, Terminal, serta Settings.
- Pertanyaan agent dan drag file membuka tampilan khusus, bukan seluruh Home.

### Acuan visual

Mockup terakhir berada di luar source aplikasi:

`/Users/diazamantajati/.codex/visualizations/2026/10/25/01a17228-62b4-7de3-8486-b52b4bd9f8cf/island-concepts.html`

Mockup menyimpan alternatif Fokus dan Workspace. Pilihan terakhir yang terlihat adalah Workspace; ini menjadi acuan kerja yang diusulkan, bukan keputusan eksplisit untuk membuang alternatif Fokus. Builder boleh menetapkan detail layout daftar agent selama perilaku dan arah visual di dokumen ini terpenuhi.

## 4. Perilaku membuka dan menutup

| Keadaan | Perilaku |
| --- | --- |
| Diam | Panel sepenuhnya tersembunyi, meskipun musik atau sesi agent masih berjalan. |
| Hover tengah atas | Setelah delay membuka, tampilkan Home. |
| Kursor meninggalkan panel | Mulai delay menutup; kembali masuk membatalkan penutupan. |
| Drag file masuk | Segera tampilkan area drop khusus, tanpa daftar file titipan. |
| Pertanyaan agent masuk | Tampilkan pertanyaan yang mendapat giliran, dengan pengecualian terminal aktif dan full screen di bawah. |
| Pertanyaan belum dijawab dan panel menutup | Tampilkan indikator kecil jumlah permintaan yang masih menunggu. |
| Panel terminal disembunyikan | Sesi tetap berjalan. Menyembunyikan panel tidak mengakhiri proses. |

Delay membuka dan menutup hover dapat diatur secara terpisah. Builder harus membatalkan timer yang sudah tidak sesuai keadaan agar panel tidak menutup di tengah drag atau perpindahan antarbagian panel.

### Pertanyaan ketika terminal aktif

- Jika pengguna sedang mengetik di terminal island, pertanyaan baru muncul sebagai banner kecil di atas terminal.
- Jangan mencuri fokus atau mengganti terminal secara otomatis.
- Klik banner membuka pertanyaan; teks input yang belum dikirim dan sesi terminal tetap dipertahankan.
- Banner mengarahkan ke permintaan pertama dalam antrean, bukan otomatis ke permintaan terbaru.

### Full screen

- Perilaku pertanyaan agent saat aplikasi lain full screen tersedia di Settings.
- Default: hanya indikator kecil; pertanyaan dibuka atas interaksi pengguna.
- Pengguna bisa memilih agar pertanyaan tetap otomatis membuka panel ketika full screen.
- Hover dan drag tetap ditargetkan dapat digunakan saat full screen; perilaku aktual harus diuji pada macOS target.

## 5. Pertanyaan dan daftar AI agent

### Target

Agent: Codex CLI, Antigravity CLI, Claude Code, dan Oh My Pi.  
Aplikasi asal sesi eksternal: terminal VS Code, Orca, Terminal macOS, dan iTerm2.

Pengguna harus dapat menjalankan agent seperti biasa di aplikasi asal, tanpa konfigurasi tambahan pada CLI. Deteksi sesi eksternal masuk cakupan MVP, bukan hanya rencana versi berikutnya.

### Card list

- Tampilkan sesi yang dapat diidentifikasi sebagai card list.
- Tampilkan nama agent, project/folder, aplikasi asal, dan status yang benar-benar diketahui.
- Beberapa sesi dari agent atau project yang sama harus memiliki identitas berbeda.
- Status yang ditargetkan: bekerja, menunggu jawaban, selesai, serta tidak diketahui/tidak lagi tersedia bila diperlukan.
- Jangan menyimpulkan “menunggu jawaban” atau “selesai” hanya dari dugaan proses aktif/tidak aktif.
- Permintaan yang membutuhkan jawaban lebih diutamakan dalam daftar.
- Klik card membuka detail atau akses terminal yang sesuai kemampuan integrasinya.

### Tampilan pertanyaan

- Pembukaan otomatis hanya menampilkan pertanyaan, konteks agent/project yang singkat, dan kontrol jawaban yang relevan.
- Jangan menampilkan seluruh daftar agent, navigasi utama, atau fitur lain saat notifikasi pertanyaan membuka panel.
- Mendukung pilihan jawaban dan input teks ketika tipe permintaan agent memang mendukungnya.
- Pilihan jawaban harus berasal dari permintaan sebenarnya. Contoh “Allow once” pada mockup bukan izin untuk mengganti pilihan semua CLI dengan tombol universal.
- Jawaban hanya boleh dikirim ke sesi dan permintaan yang identitasnya telah dipastikan.
- Jika permintaan sudah dijawab dari terminal asal, dibatalkan, atau sesi berhenti, panel harus berhenti menawarkan jawaban usang.
- Tidak ada pemberian izin otomatis atau jawaban otomatis.

### Antrean

- Pertanyaan ditampilkan satu per satu sesuai urutan masuk.
- Tampilkan jumlah antrean tanpa memaksa seluruh daftar terbuka.
- Setelah pertanyaan terjawab, lanjutkan ke pertanyaan valid berikutnya.
- Jika pengguna membiarkan pertanyaan, panel boleh menutup setelah delay dan menyisakan indikator kecil.
- Menutup tampilan tidak berarti menolak atau menjawab permintaan.

## 6. Batas kelayakan integrasi yang wajib dibuktikan

Kebutuhan deteksi dan jawaban langsung lintas CLI/terminal belum terbukti. Izin macOS tidak dengan sendirinya menjamin seluruh sesi terminal dapat dibaca atau dikendalikan.

Sebelum membangun integrasi produksi, buat pembuktian lokal dan matriks untuk kombinasi yang dipakai pengguna. Catat secara terpisah:

1. Apakah sesi agent dapat ditemukan dan dipetakan ke aplikasi asal serta project.
2. Apakah status dan pertanyaan sebenarnya dapat dibaca, termasuk sesi di background.
3. Apakah opsi/input permintaan dapat direpresentasikan dengan benar.
4. Apakah jawaban dapat dikirim ke sesi yang tepat dan hasilnya dikonfirmasi.
5. Izin sistem yang diperlukan dan perilaku ketika izin ditolak/dicabut.

Identifikasi executable serta versi aktual agent dan terminal, termasuk makna “Antigravity CLI” dan “Oh My Pi” pada instalasi pengguna, melalui inspeksi sebelum menentukan adapter. Jangan menganggap dukungan dari kemiripan nama.

Jalur yang diusulkan untuk diuji: informasi proses/sesi yang sudah tersedia, kemampuan otomasi resmi terminal, dan Accessibility bila sesuai. Ini adalah kandidat pendekatan, bukan klaim bahwa semuanya tersedia.

Jika suatu kombinasi hanya mendukung deteksi, card harus menyatakan keterbatasannya dan bisa menawarkan akses ke terminal asal. Namun fallback tersebut **tidak dianggap memenuhi kebutuhan jawaban langsung**. Bila kebutuhan utama tidak dapat dipenuhi tanpa setup CLI, bawa hasil dan pilihan cakupan kembali kepada pengguna; jangan diam-diam memasang hook atau mengurangi janji MVP.

## 7. Terminal di dalam island

- MVP memiliki terminal interaktif milik aplikasi untuk membuka sesi dan mengetik perintah bebas, termasuk menjalankan agent.
- Mendukung beberapa sesi; menyembunyikan panel atau berpindah fitur tidak menghentikannya.
- Mengetik, scrolling output, serta kembali dari pertanyaan harus mempertahankan konteks sesi.
- Pemisahan tampilan dari pengelola sesi disiapkan agar sumber sesi internal dan eksternal dapat diwakili oleh model yang sama.
- Mengendalikan permintaan sesi eksternal dan menampilkan ulang terminal eksternal secara penuh adalah kemampuan berbeda. Pencerminan penuh terminal eksternal tidak otomatis dijanjikan oleh integrasi pertanyaan.
- Desain tidak mengharuskan launcher khusus tiap agent. Pengguna mengutamakan deteksi otomatis.

## 8. Titipan file

### Dua tampilan

1. **Saat drag masuk:** hanya area “Drop files here” atau “Taruh file di sini”, beserta ikon. Jangan tampilkan titipan yang sudah ada atau navigasi fitur lain.
2. **Saat dibuka biasa:** thumbnail/ikon file dan nama file, tersusun mendatar. Tidak ada area drop besar. File bisa dipilih, diseret keluar, atau dihapus dari titipan.

Nama panjang boleh diringkas secara visual, tetapi nama lengkap tetap dapat diperiksa. Thumbnail ilustrasi pada mockup bukan preview file nyata.

### Penyimpanan

- Settings menyediakan temporary copy dan original file reference.
- Default: aplikasi menyimpan salinan sementara miliknya.
- Mode referensi menghemat ruang tetapi bergantung pada keberadaan dan akses file asli; tampilkan keadaan tidak tersedia jika referensi rusak.
- Titipan dan metadata tetap tersedia setelah aplikasi ditutup atau Mac direstart.
- Penyimpanan harus berada di lokasi aplikasi yang persisten, bukan folder sementara sistem yang dapat dibersihkan sewaktu-waktu.
- Izin akses file dan referensi perlu bertahan sesuai model akses macOS yang dipilih builder.

### Sekali antar

- Setelah berhasil diserahkan ke tujuan, titipan dihapus dari island.
- Drag yang dibatalkan atau pengiriman yang gagal tidak menghapus titipan.
- Menghapus titipan tidak berarti menghapus file asli milik pengguna.
- Builder harus membuktikan sinyal keberhasilan serah-terima yang tersedia pada drag macOS. Jangan menganggap setiap drag-end atau diterimanya drop sebagai bukti penyalinan file sudah aman.
- Jika keberhasilan belum dapat dipastikan, pertahankan titipan dan jelaskan batasnya; jangan menghapus salinan terakhir berdasarkan dugaan.

## 9. Spotify

- Home menonjolkan cover, judul, artis, play/pause, previous/next, dan progres pemutaran.
- Tampilan Music menyediakan kontrol yang sama dalam panel ringkas.
- Musik di Home dan tab Music memakai state yang sama; status kontrol harus sinkron dengan Spotify sebenarnya.
- Ketiadaan Spotify atau tidak adanya lagu aktif ditangani dengan empty state ringkas, bukan data contoh seolah-olah sedang diputar.
- Kendali sumber musik lain tidak menjadi syarat MVP.

## 10. Settings dan bahasa

Settings MVP mencakup:

| Pengaturan | Keputusan |
| --- | --- |
| Language | English / Bahasa Indonesia; default English. |
| Open delay | Bisa diatur. |
| Close delay | Bisa diatur terpisah dari open delay. |
| Full-screen agent prompts | Default indikator kecil; opsi otomatis membuka pertanyaan. |
| File storage mode | Default temporary copy; opsi original file reference. |

Pilihan disimpan antar-peluncuran aplikasi. Pergantian bahasa langsung memperbarui label, status aplikasi, empty state, Settings, dan tombol umum. Nama file/project, command, output terminal, serta isi asli permintaan agent bukan teks antarmuka dan tidak diterjemahkan atau diubah otomatis.

## 11. Pilihan builder yang diusulkan, belum menjadi preferensi pengguna

- Aplikasi native macOS; Swift dengan AppKit/SwiftUI adalah rekomendasi awal untuk diuji. Library terminal, minimum macOS, dan teknik panel ditentukan setelah inspeksi mesin serta pembuktian teknis.
- Nilai awal delay: membuka 450 ms, menutup 1.000 ms, sesuai mockup. Rentang akhir ditentukan builder; timer terpisah untuk notifikasi belum menjadi kewajiban tersendiri.
- Satu layar aktif untuk MVP, dengan layar bawaan sebagai default bila tersedia. Multi-monitor otomatis dan konfigurasi per-monitor ditunda; jangan menyamakan keputusan ini dengan preferensi pengguna yang telah dikonfirmasi.
- Izin diminta ketika fiturnya membutuhkan, dengan penjelasan tujuan dan panduan membuka pengaturan sistem.
- Tidak ada bunyi pengingat tambahan secara default.
- App Quit berbeda dari menyembunyikan panel: peringatkan bila ada terminal milik aplikasi yang masih bekerja; menghentikan aplikasi tidak boleh mematikan sesi eksternal. Pemulihan proses terminal internal setelah restart tidak masuk MVP; pemulihan file tetap wajib.
- Tidak ada janji mengunggah atau mengirim isi terminal/file ke layanan lain untuk mendeteksi status. Pilih pemrosesan lokal untuk integrasi ini.

Builder boleh menentukan detail animasi, jarak, ukuran panel, navigasi internal, indikator error, dan detail teknis yang tidak mengubah keputusan produk di atas. Bila muncul benturan dengan kebutuhan inti, kembalikan sebagai keputusan produk, bukan perubahan diam-diam.

## 12. Di luar MVP

- Shortcut global, sumber musik selain Spotify, dan distribusi komersial.
- Pemasangan hook/plugin CLI atau modifikasi konfigurasi CLI demi memenuhi deteksi eksternal.
- Janji universal bahwa terminal eksternal apa pun dapat dicerminkan dan diketik sepenuhnya di island.
- Sinkronisasi file lintas perangkat, cloud storage, dan riwayat file setelah selesai diantar.
- Pemulihan proses terminal internal setelah aplikasi berhenti.

## 13. Kriteria penerimaan

1. Pada Mac tanpa notch, panel tersembunyi saat diam; hover membuka Home setelah delay yang tersimpan.
2. Panel horizontal, tidak menyisakan ruang kosong berlebihan, dan card tidak memiliki border dekoratif.
3. Home mengutamakan Spotify; ringkasan agent serta file berada di sampingnya.
4. Delay menutup dibatalkan ketika kursor kembali; drag atau input aktif tidak diputus oleh timer usang.
5. Drag masuk menampilkan area drop saja, bahkan ketika sudah ada titipan. Membatalkan drag tidak mengubah daftar titipan.
6. Membuka Files menampilkan thumbnail/ikon dan nama. Salinan titipan tetap dapat diakses setelah relaunch dan restart.
7. Pengiriman berhasil menghapus titipan; pengiriman batal/gagal mempertahankannya. File asli tidak ikut dihapus.
8. Sesi agent yang didukung muncul sebagai card dengan identitas yang tepat. Dukungan diuji pada kombinasi CLI/terminal sebenarnya, bukan hanya fixture.
9. Pertanyaan muncul sendiri, terurut satu per satu, dan indikator menampilkan antrean yang belum terjawab.
10. Jawaban mencapai sesi/permintaan yang tepat, termasuk ketika beberapa sesi identik berjalan. Permintaan usang tidak dapat dijawab lagi.
11. Saat mengetik di terminal island, permintaan baru muncul sebagai banner tanpa mengambil fokus; input tetap tersedia setelah kembali.
12. Saat aplikasi lain full screen, default hanya indikator kecil; perubahan setting mengubah perilakunya.
13. Terminal internal tetap berjalan ketika panel disembunyikan atau tab berganti.
14. UI dimulai dalam English; Bahasa Indonesia dapat dipilih dan pilihan tersimpan. Isi terminal serta file tidak diubah oleh pergantian bahasa.
15. Tidak ada setup CLI tersembunyi, izin sistem ditangani secara jelas, dan kombinasi yang belum didukung tidak diberi status sukses.

## 14. Urutan setelah dokumen disetujui

1. Susun rencana implementasi dari spesifikasi yang disetujui.
2. Awali rencana dengan pembuktian integrasi agent eksternal, akses full screen, dan sinyal keberhasilan drag file. Ketiganya memengaruhi janji produk.
3. Jika pembuktian mengungkap keterbatasan yang mengubah kebutuhan utama, ajukan hasil konkret dan keputusan cakupan kepada pengguna sebelum melanjutkan bagian terdampak.
4. Implementasikan aplikasi bertahap dan verifikasi pada Mac pengguna. Mockup bukan bukti bahwa fitur native sudah bekerja.

Pada saat persetujuan spesifikasi, belum ada source aplikasi, build native, pengujian integrasi agent, maupun deployment. Persetujuan desain tidak membuktikan kemampuan integrasi yang masih harus diuji.

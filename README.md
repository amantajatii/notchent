# Notchent

**Notch for Agent.**

Panel native di notch Mac untuk memantau coding agent, menerima notifikasi, dan melanjutkan percakapan yang didukung.

Aplikasi menu bar native untuk panel Home, Spotify, Files, dan terminal internal. Minimum macOS 14. **MVP belum lengkap:** membaca pertanyaan dan mengirim jawaban CLI nyata belum diimplementasikan. Bukti lengkap: [acceptance](docs/validation/mvp-acceptance.md).

## Build dan buka

Dari root repository, dengan Apple Command Line Tools aktif:

```sh
scripts/test.sh
scripts/build-app.sh
open .build/apps/Notchent.app
```

Nama produk: **Notchent**. Target Swift `IslandMac`, bundle ID, dan lokasi data lama dipertahankan agar integrasi dan data pengguna tetap kompatibel.

Artifact: `.build/apps/Notchent.app` (debug, ad-hoc signed, bundle ID `dev.nativeisland.app`). Belum dinotariskan atau diverifikasi untuk distribusi eksternal. Build mengikuti arsitektur mesin; baseline lokal arm64, macOS 27.0.1, Swift 6.4. SwiftTerm dipin tepat `1.99.1` melalui `Package.resolved`; compiler yang memahami manifest SwiftTerm (tools 6.2+) diperlukan.

Pada CLT 6.4 ini, `swift test` biasa gagal menemukan framework testing. `scripts/test.sh` memakai Swift Testing, `--disable-xctest`, framework search path/rpath CLT, dan native build engine. Warning deprecation native engine masih ada; belum dimigrasikan atau disembunyikan.

Untuk upgrade, pilih **Quit** pada instance lama terlebih dahulu, selesaikan konfirmasi sesi milik app, lalu build dan jalankan `open` di atas. Membuka bundle yang app-nya masih berjalan tidak memuat ulang binary baru. Build sendiri juga tidak me-restart app. Launch normal menyembunyikan panel saat idle; hover tengah atas membuka panel. Jangan gunakan `--show` untuk pemakaian normal karena mode inspeksi itu mempertahankan panel terbuka.

## Pemakaian dan izin

Home mengutamakan Music/Spotify dengan ringkasan Agents dan Files. Settings menyimpan Language (English default atau Bahasa Indonesia), Open delay, Close delay, Full screen, dan File storage. Teks terminal, nama file, serta isi permintaan agent tidak diterjemahkan.

Buka Spotify sendiri, lalu gunakan **Connect Spotify** ketika ingin memberikan izin Automation. macOS dapat meminta persetujuan; pengguna menentukan izinnya melalui dialog atau System Settings → Privacy & Security → Automation. Polling tidak meminta izin diam-diam dan tidak memulai Spotify/musik. Status consent/denied/unavailable berbeda. Metadata, artwork, serta tombol playback belum diverifikasi live pada bundle terbaru. Tidak perlu memberikan Accessibility atau Screen Recording untuk membuka panel; memberikan izin tambahan tidak mengaktifkan fitur jawaban agent yang belum ada.

Files menerima file reguler; direktori dan symlink ditolak. **Copy** menyimpan salinan milik app di `~/Library/Application Support/IslandMac/FileShelf`; **Reference** menyimpan bookmark ke file asli dan dapat menjadi unavailable ketika sumber hilang/tidak dapat diakses. Tidak ada batas kuota aplikasi yang dijanjikan; kapasitas disk dan izin tetap membatasi import. Hindari menganggap titipan sebagai backup.

Drag masuk menampilkan area drop. Penerimaan drop oleh AppKit terjadi sebelum import asinkron selesai; periksa item atau pesan gagal sebelum menganggap file tersimpan. Drag keluar memakai file promise: penghapusan titipan memerlukan hasil native `.copy` dan perbandingan byte tujuan yang berhasil. Cancel/gagal/hasil tidak pasti mempertahankan item; Remove hanya menghapus salinan milik app atau referensi, tidak menghapus file asli. Ini verifikasi sisi produsen, belum bukti bahwa semua aplikasi tujuan sudah mengonsumsi file. Finder drag dan restart Mac masih menunggu pengujian live.

Terminal: pilih folder untuk membuat sesi shell. **Hide** menyembunyikan panel dan mempertahankan PTY/draft; pindah tab juga mempertahankannya. **Close** meminta penghentian sesi milik app tersebut, secara asinkron. **Quit** meminta konfirmasi bila sesi milik app masih berjalan dan menunggu penghentiannya; sesi eksternal berada di luar store. GUI konfirmasi/fokus belum diverifikasi live pada build terbaru. Jangan Quit hanya untuk pengujian bila ada pekerjaan terminal yang ingin dipertahankan.

## Dukungan agent saat ini

| CLI | Nama executable yang dicari | Discovery | Baca pertanyaan / kirim jawaban |
| --- | --- | --- | --- |
| Codex CLI | `codex` | Metadata kandidat | Pertanyaan tunggal dengan jawaban teks lewat daemon lokal terbukti pada satu uji terkontrol; izin perintah dan kombinasi lain belum terbukti |
| Claude Code | `claude` | Metadata kandidat | Belum diimplementasikan |
| Antigravity CLI | `agy` | Metadata kandidat | Belum diimplementasikan |
| Oh My Pi | `omp` | Metadata kandidat | Belum diimplementasikan |

Semua baris memiliki batas yang sama: keturunan shell internal dipetakan memakai PID/birth time ke terminal milik app. Wrapper interpreter dapat terlewat. Host eksternal VS Code, Orca, Terminal, dan iTerm2 dikenali lewat ancestry; sesi Codex desktop dibaca melalui berkas rollout yang sedang dibuka proses (metadata, aktivitas, ringkasan selesai; baca-saja), tanpa scan riwayat atau perubahan hook/config; pane/proyek stabil belum diketahui, sehingga tidak ada pemetaan pane atau Open origin eksternal. Adapter Codex memakai identitas thread daemon, bukan identitas pane Terminal. Satu sesi uji Codex CLI melalui daemon bersama sudah membuktikan pertanyaan dan jawaban teks live; ini tidak memvalidasi seluruh 16 kombinasi CLI/host. Versi inventaris historis ada di [agent-capabilities](docs/validation/agent-capabilities.md), bukan janji kompatibilitas.

Adapter Codex kini terhubung ke WebSocket publik daemon lokal yang sudah berjalan, menampilkan permintaan dengan nama thread/proyek, dan hanya mengirim jawaban setelah klik pengguna. Semua jenis keputusan izin perintah yang ditawarkan protokol versi ini dipertahankan sesuai urutan: sekali jalan, selama sesi, aturan awalan perintah, aturan host jaringan, penolakan, atau pembatalan. Opsi sesi/aturan hanya tampil bila dikirim Codex dan cakupannya tertulis pada tombol. Pertanyaan nonrahasia tunggal atau sampai tiga pertanyaan sekaligus didukung; file-change/permissions dan MCP elicitation belum didukung lewat adapter daemon. Protokol framing/routing dan koneksi native initialize/loaded-list sudah diuji, dan replay izin perintah serta tampilannya di island sudah diamati untuk Codex/Terminal. Satu uji terkontrol sudah memverifikasi pengiriman jawaban teks melalui UI island dan hasil yang sama di CLI; jawaban izin perintah belum diverifikasi live. Tulisan terkirim bukan konfirmasi jawaban diterima; resolved dari server menghapus prompt, termasuk jika dijawab dari asalnya. Status aktivitas pada card proses tetap unknown. Pemindaian dasar tidak memasang hook/plugin atau mengubah konfigurasi CLI/shell. Popup desktop lokal dapat memakai hook opsional yang dipasang hanya setelah izin pengguna. Bila pengguna memilih opsi aturan permanen, Codex dapat menyimpan aturan melalui mekanismenya sendiri; app tidak memilih opsi itu otomatis.

Adapter mengamati thread yang masih loaded dan aktif melalui daemon milik pengguna yang sudah berjalan, tanpa mensyaratkan proses Codex ber-TTY. Sesi daemon terverifikasi ditampilkan sebagai card terpisah dari kandidat proses. Subscription memakai thread/resume tanpa config override, mengecek loaded sebelum/sesudah, lalu dilepas saat idle/keluar. Protokol tidak menyediakan join yang atomik terhadap unload; race tersebut belum terbukti aman live. Resume juga mengubah atribusi client daemon dan dapat memperpanjang masa loaded thread selama dipantau. Tidak membaca riwayat percakapan atau output terminal.

Di Agents, pilih sesi Codex lalu gunakan kolom chat untuk melanjutkan percakapan yang sama. Enter atau tombol panah mengantrekan teks melalui thread/queue/add dengan UUID sesi tersebut; tidak membuat atau me-resume percakapan pada server lain. Status queued berarti antrean diterima, bukan balasan sudah selesai. Draf disimpan per sesi. Jika hasil pengiriman tidak pasti, periksa percakapan asal sebelum membuka draf untuk mengirim lagi. Balasan selesai mengikuti pemantauan ringkasan lokal; streaming dan jawaban izin desktop belum tersedia. Pengiriman manusia sampai benar-benar diproses Codex belum diverifikasi end-to-end.


Hook pertanyaan Codex lokal sudah didukung. `scripts/build-app.sh` juga mengemas helper native IslandHook. Installer `python3 scripts/install-codex-hook.py --helper .build/apps/Notchent.app/Contents/MacOS/IslandHook` menambahkan handler PermissionRequest dan PreToolUse khusus pertanyaan ke `~/.codex/hooks.json`, menyimpan backup, dan mempertahankan handler lain. Setelah pemasangan, review dan trust definisi IslandMac lewat `/hooks` di Codex CLI. Installer tidak mengubah catatan trust atau mode keamanan. Permission menawarkan izinkan sekali, tolak, atau lanjutkan di Codex. Preferensi desktop hanya dipratinjau dan diteruskan ke UI asli; PreToolUse tidak dapat mengembalikan jawaban tool. Cloud-orchestrated Work tidak mendukung semua hook lokal ini.

Area drop sekarang terbuka saat file mulai diseret di mana pun pada layar, tanpa harus hover tepi atas. Area tetap terbuka selama drag dan menutup setelah file dilepas/dibatalkan. Data file lama di drag pasteboard dan drag teks tidak membuka island.

### Menjawab pertanyaan Codex melalui island

Jalankan sesi CLI pada daemon yang sama dengan Notchent:

```sh
codex app-server daemon start
codex --remote unix://
```

Saat Codex mengajukan pertanyaan, jawab pada panel prompt island. Jika hook opsional lebih dahulu menampilkan **Answer in Codex**, tekan tombol itu untuk melewatkan preview; pertanyaan resmi dari daemon kemudian menyediakan pilihan/kolom jawaban dan **Send** di island. Uji terkontrol 2026-10-29 membuktikan teks `ISLAND_TEXT_OK` dikirim dari island dan diterima CLI. Ini tidak menghubungkan dialog sesi desktop yang memakai server stdio terpisah.

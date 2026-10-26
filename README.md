# IslandMac

Aplikasi menu bar native untuk panel Home, Spotify, Files, dan terminal internal. Minimum macOS 14. **MVP belum lengkap:** membaca pertanyaan dan mengirim jawaban CLI nyata belum diimplementasikan. Bukti lengkap: [acceptance](docs/validation/mvp-acceptance.md).

## Build dan buka

Dari root repository, dengan Apple Command Line Tools aktif:

```sh
scripts/test.sh
scripts/build-app.sh
open .build/apps/IslandMac.app
```

Artifact: `.build/apps/IslandMac.app` (debug, ad-hoc signed, bundle ID `dev.nativeisland.app`). Belum dinotariskan atau diverifikasi untuk distribusi eksternal. Build mengikuti arsitektur mesin; baseline lokal arm64, macOS 27.0.1, Swift 6.4. SwiftTerm dipin tepat `1.99.1` melalui `Package.resolved`; compiler yang memahami manifest SwiftTerm (tools 6.2+) diperlukan.

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
| Codex CLI | `codex` | Metadata kandidat | Belum diimplementasikan; jalur app-server publik terkonfirmasi, runtime menunggu sesi uji terkendali |
| Claude Code | `claude` | Metadata kandidat | Belum diimplementasikan |
| Antigravity CLI | `agy` | Metadata kandidat | Belum diimplementasikan |
| Oh My Pi | `omp` | Metadata kandidat | Belum diimplementasikan |

Semua baris memiliki batas yang sama: keturunan shell internal dipetakan memakai PID/birth time ke terminal milik app. Wrapper interpreter dapat terlewat. Host eksternal VS Code, Orca, Terminal, dan iTerm2 hanya kandidat ancestry + TTY; pane/proyek stabil belum diketahui, sehingga tidak ada rute jawaban atau Open origin eksternal. Tidak ada satu pun dari 16 kombinasi CLI/host yang terbukti mendukung read/send live. Versi inventaris historis ada di [agent-capabilities](docs/validation/agent-capabilities.md), bukan janji kompatibilitas.

FIFO, revisi, penolakan rute usang, dan receipt diuji memakai adapter sintetis; itu bukan integrasi CLI nyata. Status aktivitas tetap unknown. Belum ada jawaban otomatis maupun jawaban langsung produksi. App tidak memasang hook/plugin, mengubah konfigurasi CLI/shell, atau mensyaratkan cara launch CLI khusus.

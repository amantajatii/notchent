# MVP acceptance — 2026-10-26

Baseline dokumentasi Task 3 ditambah perubahan lokal hover/UI/discovery dan adapter Codex eksperimental. **Full MVP: NOT MET.** Koneksi daemon Codex tersedia, tetapi prompt/reply live dan tiga CLI lain belum terbukti/tersedia. Build/test lokal tidak menggantikan acceptance native.

Status: **PASS** = seluruh klaim pada baris terbukti; **FAIL — not implemented** = kebutuhan belum tersedia; **UNVERIFIED** = implementasi ada tetapi bukti live yang diperlukan belum lengkap. Bukti parsial ditulis eksplisit, tidak dihitung sebagai PASS penuh.

| # | Kriteria spec §13 | Status | Bukti aktual / batas |
| --- | --- | --- | --- |
| 1 | Idle hidden, hover Home, delay tersimpan pada Mac tanpa notch | UNVERIFIED | Reducer/settings/geometry tests lulus. Root pernah mengamati Home awal; hover, notchless hardware, delay live build terbaru belum dibuktikan. |
| 2 | Panel horizontal, ruang ringkas, card tanpa border dekoratif | UNVERIFIED | Root mengamati tampilan awal Home/Settings; evaluasi compact/scaling build terbaru belum dilakukan. Lihat panel-behavior.md. |
| 3 | Spotify utama, ringkasan agent/file di samping | UNVERIFIED | Struktur Home dan tampilan awal diamati root; data Spotify live/permission belum terbukti. |
| 4 | Re-entry membatalkan close; drag/input tahan timer usang | UNVERIFIED | Regression reducer menguji generation/deadline/input/drag. Native pointer/focus live belum diuji. |
| 5 | Drag hanya drop area; cancel tidak mengubah shelf | UNVERIFIED | Reducer + storage/DeliveryGate tests lulus. Drag Finder/Escape native belum diamati. |
| 6 | Files thumbnail/nama; copy bertahan relaunch/restart | UNVERIFIED | FileShelf tests memakai filesystem nyata dan actor baru membuktikan copy/reload setelah sumber dihapus. Thumbnail/relaunch GUI belum diuji; restart Mac pending waktu pilihan pengguna. |
| 7 | Sukses menghapus shelf; batal/gagal retain; asli aman | UNVERIFIED | Gate membutuhkan `.copy` + byte comparison; cancellation/order/unsafe deletion tests lulus. Handoff Finder nyata belum diuji; bukan receipt konsumsi aplikasi tujuan. |
| 8 | Card agent beridentitas tepat pada kombinasi nyata | FAIL — not implemented | Metadata kandidat tersedia, stable pane eksternal tidak tersedia; tidak ada kombinasi CLI/host live yang terbukti. |
| 9 | Pertanyaan otomatis FIFO + pending indicator | FAIL — partial support | Adapter Codex eksperimental menerima request protocol dan queue updates langsung. Native WebSocket dan replay command-approval sekarang teramati; screenshot pengguna membuktikan prompt muncul di island. Adapter opsi terstruktur diperbaiki setelah screenshot menunjukkan pilihan aturan hilang. Tiga CLI lain belum didukung. |
| 10 | Jawaban tepat sesi/permintaan; stale ditolak | FAIL — partial support | Identitas koneksi/daemon/thread + raw JSON request ID dipertahankan; reply satu kali tanpa retry; scoped tests lulus. Pengiriman jawaban manusia dan hasil pada CLI belum diverifikasi. CLI lain unavailable. |
| 11 | Banner saat mengetik tanpa focus theft; draft kembali | UNVERIFIED | Banner/reducer/PTY diuji; adapter Codex dan publisher queue terpasang. Interaksi keyboard/fokus dengan prompt nyata di GUI belum diamati. |
| 12 | Full-screen default indikator; setting mengubah perilaku | UNVERIFIED | Reducer/classifier tests lulus, monitor konservatif terpasang. Full-screen/Spaces native belum diamati. |
| 13 | Terminal hidup saat Hide/pindah tab | UNVERIFIED | Real-PTY integration membuktikan view/session/draft retention serta controlled close/escalation/quit barrier. Hide/tab/resize GUI dan supported CLI di app belum diuji live. |
| 14 | English default; Indonesia persisten; isi asli tetap | UNVERIFIED | Settings persistence dan bundle en/id verified. Root pernah mengganti English → Indonesia → English di UI awal. Semua route compact, terminal/file dan relaunch locale build terbaru belum diamati. |
| 15 | Tanpa setup tersembunyi; izin jelas; unsupported tak sukses | UNVERIFIED | Inspeksi source: tanpa hook/config CLI, adapter unavailable, permission states eksplisit. Spotify preflight historis requires-consent; grant/denial/revocation bundle terbaru belum diuji. |

## Bukti lokal dan packaging

Host lokal: macOS 27.0.1 (26A434), arm64; Apple Swift 6.4. Minimum deployment macOS 14, bukan pengujian runtime pada macOS 14. Perintah canonical `scripts/test.sh` memakai Swift Testing CLT tanpa XCTest; warning native build engine deprecated sudah ada sebelumnya.

Final `scripts/test.sh` exit 0: 76 tests dalam 18 suites lulus (3.192 s); satu test Spotify live dilewati dengan “Requires opt-in”. `scripts/build-app.sh` exit 0, build product selesai (21.54 s). `codesign --verify --strict --verbose=2` menyatakan valid on disk dan satisfies its Designated Requirement; signature ad-hoc, arm64, tiga sealed resource files. `plutil -lint` lulus; `cmp` notice dengan lisensi dependency identik. `otool -L` hanya mencantumkan library/framework sistem, tanpa dylib dependency checkout. Log test `/tmp/island-task3-tests.log`, build `/tmp/island-task3-build.log`. Bundle lokal `.build/apps/IslandMac.app`; ID `dev.nativeisland.app`, versi 0.2.0 (2), development region en, deklarasi en/id. Tidak ada notarization/upload/publication. Proses app lama tidak di-restart sehingga keberadaan bundle terbaru tidak membuktikan UI sedang menjalankan binary ini.

SwiftTerm exact 1.99.1, revision `2f573f73af5e768d90847dce20c97fa9535d7164`; lockfile juga memuat h 1.0.1, swift-argument-parser 1.8.2, swift-png 4.5.2. Target library SwiftTerm tidak mendeklarasikan resource runtime; test fixtures tidak perlu dibundel. Notice MIT SwiftTerm kini disalin ke `Contents/Resources/ThirdPartyNotices/SwiftTerm-LICENSE.txt` sebelum signing. Localizations diekspor ke en.lproj/id.lproj.

## Native/live yang belum selesai

CUA inventory Task 3 merespons; IslandMac tidak tercantum, Spotify running, VS Code/Orca/Terminal not running menurut inventory tersebut. Tidak dilakukan launch/restart, unlock, grant izin, playback, manipulasi Terminal.app, kill sesi pengguna, atau instance `--show`. Inventory bukan bukti panel terlihat maupun semua proses benar-benar tidak ada. Terminal.app UI sebelumnya ditolak tool; tidak dicoba bypass. Percobaan UI dihentikan pada inventaris ini karena tidak ada own-app surface terlihat.

Masih perlu pengujian terkontrol: hover desktop/full screen/Spaces, cancel-close, menu bar clicks ketika hidden, kedua locale di semua route compact dan display scaling yang tersedia, Reduce Motion dan indikator keyboard focus; Spotify Connect/consent/revocation/metadata/artwork/control; Finder import/cancel/failure/promised copy; shelf GUI relaunch; terminal Hide/tab/resize/draft dan Quit confirm/cancel dengan sesi disposable milik app, sambil memastikan sesi eksternal tidak tersentuh. Restart Mac hanya pada waktu yang dipilih pengguna.

Kasus CLI versi tertentu, duplicate sessions, background tabs, answer-at-origin, FIFO live, permission loss dan receipt nyata belum dapat diselesaikan tanpa mekanisme read/send terbukti. Tidak tersedia fixture transcript nyata/redacted untuk ANSI redraw atau split UTF-8; tidak ada fixture yang dikarang. Jangan menyebut live cases ini lulus berdasarkan adapter sintetis.

Import drop AppKit mengembalikan accepted sebelum import async selesai. Kegagalan ditampilkan; hal ini bukan jaminan persistence pada saat callback synchronous kembali. Salinan tetap dipertahankan pada delivery canceled/failed/unknown. Batas retention-safe ini masih berlaku.

Referensi: [spec](../superpowers/specs/2026-10-25-dynamic-island-macos-design.md#13-kriteria-penerimaan), [Spotify](spotify.md), [agent inventory historis](agent-capabilities.md), [file probe historis](file-delivery.md), [panel](panel-behavior.md). File probe historis menjelaskan gate Phase 1; implementasi Phase 2 menambahkan DeliveryGate, tetapi belum meluluskan Finder live acceptance.

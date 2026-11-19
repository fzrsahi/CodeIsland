# Gemini & Antigravity Development Guidelines

> [!IMPORTANT]
> **Pedoman Kanonik Proyek:** Baca dan patuhi seluruh batasan arsitektur, zona terlarang, matriks RACI, serta SOP Git di [AGENTS.md](./AGENTS.md).

## 1. Permission & Safety Policy
Saat menjalankan perintah terminal dan menyunting berkas di repositori ini, patuhi batas keselamatan:

### Tindakan Terlarang (Strictly Prohibited)
Dilarang keras mengeksekusi perintah destruktif atau eskalasi hak akses:
- Penghapusan paksa rekursif: `rm -rf /`, `rm -rf ~`, `rm -rf *`, `rm -rf $HOME`
- Modifikasi atau pemformatan disk langsung: `mkfs`, `dd of=/dev/...`, `diskutil eraseDisk`, `fdisk`
- Eskalasi hak akses: `sudo`, `su -`, `doas`
- Perintah git destruktif yang menulis ulang remote history: `git push --force`, `git push -f`, `git reset --hard`
- Menulis langsung ke objek internal `.git/` atau berkas kredensial

### Tindakan Aman & Rutin (Auto-Allowed)
- Kompilasi dan pengujian kode: `swift build`, `swift test`, `cargo test`, `./scripts/ci/verify-local.sh`
- Inspeksi dan navigasi: `git status`, `git diff`, `git log`, `ls`, `grep`, `find`
- Membaca dan menyunting kode sumber di `Sources/`, `Tests/`, `crates/`, dan berkas konfigurasi proyek (kecuali zona terlarang DevOps di `AGENTS.md` §1).

# PaperDesk — ręczna instalacja USB/SSH

Aktualny kreator na Windows i Linux prowadzi przez pięć etapów:
zgodność, backup, przesłanie i weryfikację paczki, ręczną instalację oraz
sprawdzenie aplikacji. Każdy etap wymaga potwierdzenia wyniku przez użytkownika.
Kreator nie wykonuje poleceń na tablecie i nie sprawdza sam ich wyniku:
potwierdzenia są deklaracjami użytkownika.

Wymagane są OpenSSH (`ssh`, `scp`) i terminal. Na Windows używaj PowerShell,
na Linux powłoki POSIX. Wersja źródłowa wymaga Python 3.10+ i Tkinter;
EXE zawiera środowisko Python. Kreator nie pobiera zależności tabletu.
Nie ma płatności, aktywacji ani kluczy licencyjnych. Hasło SSH wpisuj wyłącznie
w terminalu. To hasło urządzenia, nie klucz licencyjny.

1. Podłącz reMarkable 2 kablem USB, włącz interfejs USB i zapisz pracę.
   Uruchom kreator, podaj adres (domyślnie `10.11.99.1`) i wybierz
   **Verify package and begin**.
2. Kreator sprawdza manifest SHA-256 i wersję paczki. Tworzy nowy lokalny
   katalog sesji w katalogu tymczasowym; wyświetla jego ścieżkę.
   Są tam archiwum paczki, skrypt kontroli zgodności i `MANUAL-STEPS.txt`.
   Zachowaj ten katalog na czas instalacji.
3. Wykonaj polecenie kontroli w terminalu. Porównaj odcisk klucza SSH
   z niezależnym, zaufanym źródłem. Zatrzymaj się przy zmianie tożsamości.
   Kontrola wymaga właściwego modelu, ARMv7, jednej z wersji firmware wyświetlonych przez kreator
   (odczyt `IMG_VERSION`, z rezerwowym `VERSION_ID`), zależności, narzędzi i miejsca na paczkę.
   Ostatnia linia musi brzmieć `PAPERDESK_COMPATIBILITY_OK`.
   Dla PaperDesk 4.2.0 sprawdzono także USB na firmware 3.29.0.153.
   Wersje XOVI/AppLoad sprawdź oddzielnie według listy kreatora:
   obecność pliku nie dowodzi zgodności jego wersji.
4. Najpierw zsynchronizuj lub wyeksportuj notatniki. Następnie wykonaj każde
   polecenie backupu oddzielnie: utwórz archiwum XOVI/AppLoad i istniejącego
   stanu PaperDesk, pobierz archiwum oraz sumę SHA-256 i porównaj je lokalnie.
   Backup nie obejmuje wszystkich danych tabletu. Skopiuj lokalny katalog
   sesji z backupem w trwałe miejsce, poza katalogiem tymczasowym.
5. Wykonaj osobno polecenia przesłania paczki i kontroli sum. Nowy katalog
   na tablecie ma unikalną nazwę. Jeśli już istnieje, zatrzymaj się;
   nie kasuj poprzedniej próby. Każda suma musi być poprawna.
6. Dopiero po poprawnej kontroli i backupie wykonaj ręcznie `sh ./install.sh`
   przez SSH. Zapisana na tablecie wersja musi odpowiadać wersji kreatora.
   Instalator produktu zachowuje swoje kopie zastępowanych aplikacji.
7. Opcjonalne uruchomienie `/home/root/xovi/start` wykonujesz osobno,
   ręcznie, po zapisaniu pracy. Sprawdź aplikacje oraz notatniki.
   Kreator nie włącza autostartu XOVI. Po restarcie tabletu start jest ręczny.

Przy dowolnym błędzie nie przechodź dalej. Zachowaj backupy i katalog roboczy.
Nie ma automatycznego przywracania ani czyszczenia wcześniejszych prób.
Backup nie gwarantuje odzyskania urządzenia. Dalsze informacje:
[product/MANUAL-INSTALL.md](product/MANUAL-INSTALL.md).

Uruchomienie ze źródeł:

- Windows: `python windows/installer.py` (zależności z `windows/requirements.txt`).
- Linux: `./PaperDesk-Installer.sh` (Python 3 z Tkinter, OpenSSH, sha256sum).
- Testy kreatora: `python -m unittest discover -s tests -p test_manual_wizard.py -v`.
- Testy wcześniejszej warstwy instalacji: `python -m unittest discover -s windows/tests -v`.
- Budowa Windows: `powershell -File scripts/build-windows-installer.ps1`.
- Budowa Linux: `sh scripts/build-linux-installer.sh`.
  Nazwy wyników korzystają z bieżącego `product/VERSION`.
  Skrypty budowania zapisują paczki w `dist/`; nie publikują ich.

Poniżej zachowano poprzednie instrukcje jako zapis historyczny.
Opisane tam automatyczne przyciski, Zenity i zbieranie hasła w GUI
nie dotyczą aktualnego kreatora.

<details>
<summary>Archiwalne instrukcje poprzedniego instalatora</summary>

# PaperDesk installer for Linux

Connect the reMarkable 2 over USB and enable its USB web interface.
Run `./PaperDesk-Installer.sh` from the unpacked installer folder.
Enter the tablet address (normally `10.11.99.1`) and the USB management
code from tablet settings. This is a device access code, not a licence key:
PaperDesk is free and open source.

The installer uses Zenity dialogs. It checks the package hashes and the
tablet's SSH fingerprint, verifies XOVI, AppLoad and the resource rebuilder,
then shows the app IDs already present. Click Install to continue. Matching
IDs are backed up and replaced; other AppLoad applications are untouched.
On a first PaperDesk install, the tablet keeps a separate copy of the
original app IDs and restores those originals on uninstall. Profiles and
settings remain on the tablet. Earlier PaperDesk installations may not
have that original snapshot, so preserve their existing backups.

The code stays in process memory. It is not copied to the tablet or stored
in the installer package. The old command-line installer in
`product/install-from-computer.sh` remains available. For every manual step,
see [the manual installation guide](product/MANUAL-INSTALL.md).

## Make the Linux bundle

Run `./scripts/build-linux-installer.sh` from the repository. It creates
`dist/paperdesk-linux-installer-3.0.0.1.tar.gz` and a SHA-256 file.
Extract the bundle, then launch `PaperDesk-Installer.sh`.
Zenity, OpenSSH, GNU coreutils and tar are required on the Linux computer.

The installer is checked for shell syntax and package integrity. It preserves
the original app snapshot, connection profiles, and PaperDesk backups.

</details>

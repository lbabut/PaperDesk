# PaperDesk — instalator Windows

Rozpakuj `paperdesk-windows-installer-3.0.0.1.zip` i uruchom
`PaperDesk-Installer.exe`. Nie wymaga Pythona ani praw administratora.
Przeznaczony dla Windows 10/11 x64 i reMarkable 2 z działającym XOVI,
AppLoad oraz qt-resource-rebuilder. Paczka zawiera PaperDesk 3.0.0.1.

1. Podłącz tablet przez USB, włącz interfejs USB i zapisz otwarte dokumenty.
2. Wpisz adres tabletu (domyślnie `10.11.99.1`) i kod zarządzania USB.
3. Przy pierwszym połączeniu porównaj odcisk klucza SSH z zaufanym źródłem.
4. Sprawdź listę istniejących aplikacji i zatwierdź instalację.
5. Po zakończeniu otwórz AppLoad i sprawdź aplikacje PaperDesk.

Instalator sprawdza SHA-256 lokalnej i przesłanej paczki, korzysta z instalatora
tabletu tworzącego kopie zapasowe, następnie uruchamia XOVI. Kod USB nie jest
zapisywany ani przekazywany w argumentach procesu. Klucze zaufanych tabletów
są zapisywane w `%LOCALAPPDATA%\PaperDesk\known_hosts`. Zmiana zapisanego
klucza blokuje połączenie; przed usunięciem wpisu wyjaśnij zmianę tożsamości.

Niepowodzenie instalacji może oznaczać częściową zmianę stanu tabletu.
Zachowaj `/home/root/.local/share/paperdesk` z kopiami zapasowymi; instrukcje
odinstalowania znajdują się w `product/MANUAL-INSTALL.md` w źródłach projektu.
Zwykły tryb Install PaperDesk nie instaluje XOVI ani jego rozszerzeń. Aplikacja nie jest podpisana
certyfikatem Authenticode, więc Windows może wyświetlić ostrzeżenie SmartScreen.

### Windows zatrzymał uruchomienie? SmartScreen

Jeśli widzisz „Windows protected your PC” („System Windows ochronił ten komputer”):

1. Sprawdź, czy plik pobrano z **paperdesk.lukaszbabut.info**.
2. Jeśli ufasz instalatorowi, kliknij **More info** („Więcej informacji”).
3. Kliknij **Run anyway** („Uruchom mimo to”). Instalator powinien się otworzyć.

Jeśli przycisku nie ma lub komputer firmowy blokuje uruchomienie, poproś dział IT
o sprawdzenie i dopuszczenie pliku. Nie wyłączaj ochrony Windows.


Przed instalacją sprawdza Windows 10/11 i środowisko 64-bitowe, dołączoną
obsługę kryptografii, miejsce na komputerze oraz możliwość zapisu ustawień.
Na tablecie sprawdza XOVI, backend AppLoad, LiTerm, qt-resource-rebuilder,
architekturę ARMv7, systemd, wymagane narzędzia, obsługę Ed25519, uprawnienia
zapisu i miejsce na paczkę oraz kopie zapasowe. Sprawdza też dostępność SFTP.
Brak wymagania zatrzymuje instalację przed utworzeniem katalogu na tablecie.

Budowanie ze źródeł:

```powershell
python -m pip install -r windows/requirements.txt
python -m unittest discover -s windows/tests -v
powershell -ExecutionPolicy Bypass -File scripts/build-windows-installer.ps1
```

Testy lokalne obejmują integralność paczki, zaufanie SSH i symulowany przebieg
instalacji. Test na fizycznym tablecie wymaga osobnego połączenia z urządzeniem.

## Automatyczne przygotowanie tabletu

Przycisk **Prepare tablet and install PaperDesk** instaluje przypięte wersje
XOVI 0.3.3 z qt-resource-rebuilder (wydanie v19-23052026), AppLoad 0.6.0
i backend LiTerm 0.1.7, a następnie PaperDesk. Obsługuje wyłącznie
reMarkable 2 z systemem 3.29.0.149. Komputer musi mieć dostęp do internetu;
pakiety są pobierane z oficjalnych wydań i weryfikowane przez SHA-256.

Przed uruchomieniem przeczytaj ostrzeżenie po angielsku i zaznacz zgodę.
Modyfikacja może powodować awarie, utratę danych, niesprawny interfejs lub
konieczność ręcznego odzyskiwania. Korzystasz na własne ryzyko. Autorzy
i współtwórcy PaperDesk nie ponoszą odpowiedzialności za problemy, utratę
danych ani uszkodzenia w zakresie dopuszczalnym przez obowiązujące prawo.
Najpierw wykonaj kopię lub synchronizację notatników i zapisz pracę.
Nie odłączaj USB; odblokuj tablet, jeśli poprosi o to podczas przygotowania.

Istniejące niezgodne zależności, dodatkowe aktywne rozszerzenia lub własne
skrypty XOVI zatrzymują przygotowanie. Użyj zwykłego Install PaperDesk
dla już przygotowanego tabletu albo poproś administratora o pomoc.
Przed zmianami powstaje kopia całego katalogu XOVI oraz skrypt przywracania
w `/home/root/.local/share/paperdesk-preparation/<identyfikator>/`.
Niezależny timer próbuje przywrócić standardowy interfejs po przerwaniu
przygotowania. To nie jest kopia notatników ani gwarancja odzyskania.
Nie zostaje włączony automatyczny start XOVI po restarcie.

Jeśli przygotowanie się udało, ale instalacja PaperDesk nie została
ukończona lub została anulowana, zależności pozostają na tablecie.
Ponów samą instalację przyciskiem Install PaperDesk.

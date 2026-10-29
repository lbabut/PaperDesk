# PaperDesk — lokalne paczki i test USB, 2026-10-29

Status: paczki Windows/Linux zbudowane jako niepublikowane kandydaty PaperDesk 3.0.3.
Kanoniczne źródła: [private-local-audit] na nostalgicznym.
Nie zmieniano publicznej wersji, kanałów aktualizacji, strony ani istniejących wydań.
Nie wykonywano stagingu ani commitów cudzych zmian.

## Weryfikacja rozbieżności

Porównano bieżące pliki z dist/paperdesk-3.0.3.zip. Wersje z tej paczki
odpowiadały starym wpisom manifestu. Obecne różnice są istniejącymi zmianami
anonimowych statystyk aktualizacji: opcja w PaperCare i nagłówki/persistowany
losowy identyfikator w agencie. Zmiany zachowano.

Skompilowany zasób PaperCare nie odpowiadał bieżącemu QML. Przebudowano
resources.rcc istniejącym kompilatorem Qt5 rcc i zaktualizowano dokładnie trzy
wpisy product/SHA256SUMS:

| Plik | SHA-256 po weryfikacji |
| --- | --- |
| payload/apps/papercare/ui/main.qml | 45a9b4238f31474e0434b1d48aa624b65bb67bfcd94f9c9ec27b7dd413aafc11 |
| payload/apps/papercare/resources.rcc | e96d0fb0eb563f5db5547896a6d9269fef18f20dcd5ebee6e228261e6d6f3c40 |
| payload/system/paperdesk-update-agent | ccf1123c6a5418f606e1b84b2962d4dc8542ab22f31273998f36576403d31d96 |

Cały manifest zweryfikowano ponownie. Poprzedni manifest i RCC zachowano w
build/installer-candidate-20261029-t63eo0iq. Archiwa wydanych wersji pozostały nietknięte.

## Poprawka kontroli zgodności

Rzeczywisty tablet używa IMG_VERSION=3.29.0.153, podczas gdy VERSION_ID=6.0.106
oznacza dystrybucję Codex Linux. Kreator odczytuje teraz IMG_VERSION, z rezerwowym
VERSION_ID. Dodano testy tego rozróżnienia.

Najpierw sprawdzono prawidłową odmowę instalacji na niezadeklarowanym firmware.
Po wyraźnej zgodzie użytkownika wykonano kontrolowaną instalację na 3.29.0.153.
Po jej zaliczeniu dodano ten firmware do dodatkowej listy zgodności wyłącznie dla
PaperDesk 3.0.3. Główne release.json/testedWith pozostaje bez zmian.
Końcowa kontrola zgodności na urządzeniu zakończyła się PAPERDESK_COMPATIBILITY_OK.

## Test rzeczywistego urządzenia

- reMarkable 2, ARMv7, firmware 3.29.0.153, USB do nostalgicznego.
- Zmieniony klucz SSH potwierdził użytkownik. Użyto oddzielnego przypiętego pliku
  known_hosts; nie usuwano poprzedniego wpisu i nie wyłączano kontroli tożsamości.
- Przed zmianami sprawdzono wymagania i cztery załadowane biblioteki XOVI.
- Wykonano archiwum XOVI, całego .config i .local/share (w tym notatników),
  konfiguracji usług oraz os-release. Pobrano je na nostalgicznego i sprawdzono SHA-256.
- Backup: 105927698 bajtów, SHA-256
  30b47de042334c84b75302c20d9d181e2ad4edff0375bdd1c948e88fb70310cf.
- Lokalizacja na tablecie: [private-tablet-audit]/tablet-before.tar.gz.
- Kopia na nostalgicznym:
  [private-local-audit].tar.gz.
- Przesłano i zweryfikowano paczkę, wykonano sh ./install.sh, sprawdzono wersję 3.0.3
  i oddzielnie uruchomiono /home/root/xovi/start.
- Instalator zachował własny dodatkowy backup poprzednich aplikacji:
  /home/root/.local/share/paperdesk/backups/20261029-130001-xB7g7a.
- Fizyczny test dotykowy PaperCare: sprawdzenie aktualizacji, otwarcie i anulowanie
  usuwania, zamknięcie aplikacji — wynik 0. Przywrócono konfigurację i fizyczne wejście.
- Końcowo xochitl jest aktywny, cztery biblioteki XOVI są załadowane, pomocnik testowy
  nie działa, pliki przejściowe przywracania wejścia nie pozostały.
- Stan autostartu XOVI jest identyczny przed i po próbie (brak usługi autostartu).
  Nie włączono startu XOVI przy uruchamianiu urządzenia.

Pierwsze porównanie całego katalogu notatników wykazało zmiany po restarcie
interfejsu. Zatrzymano interfejs i zweryfikowano je względem backupu:
22 usunięte pliki należały do trzech dokumentów już wcześniej oznaczonych
parent=trash; dodatkowo zniknął jeden plik metadanych QML OfflineStorage i zmienił
się plik .tree. Wszystkie 315 plików aktywnych dokumentów zachowało SHA-256 także
po teście dotykowym. Kopia sprzed testu zawiera również pliki z kosza.
Nie przywracano automatycznie usuniętych plików ani nie odwracano stanu kosza.

## Walidacja

- Końcowy zestaw Python projektu: 126 przypadków, 124 zaliczone, 2 Windows-only pominięte.
- QML: 165 zaliczonych, 0 błędów.
- Windows, dotychczasowa warstwa instalatora: 44 przypadki, 30 zaliczonych,
  14 POSIX-only pominiętych; w tym prawdziwy lokalny protokół SSH.
- Nowy zestaw kreatora: 13 przypadków; Linux 11 zaliczonych / 2 Windows-only
  pominięte; Windows 7 zaliczonych / 6 POSIX-only pominiętych.
- Symulacje błędów instalacji produktu: 5 zaliczonych.
- Końcowy zamrożony EXE: --self-test zakończony 0, osadzony produkt poprawny;
  --ui-smoke zakończony 0.
- Sprawdzono zgodność kodu kreatora pomiędzy paczkami i brak lokalnych konfiguracji,
  known_hosts oraz backupów urządzenia w archiwach.
- Kontrola składni i git diff --check zaliczone.

Test sprzętowy obejmował instalację, stan systemu i przebieg PaperCare. Pełne
fizyczne scenariusze pozostałych aplikacji nie były ponawiane. Linux GUI wymaga
Python 3.10+ z Tkinter; na nostalgicznym brak Tkinter, więc nie wykonano tam
wizualnego testu okna. Paczka Windows zawiera runtime Python. EXE nie jest
podpisany Authenticode.

## Paczki

Lokalny katalog odbioru:
[local-packages]

| Paczka | Bajty | SHA-256 |
| --- | ---: | --- |
| paperdesk-windows-installer-3.0.3.zip | 23389859 | c7f0e245d4dc02fe4c44866dff3b22d31d2e3b93a77d1ad81b1091f046d24825 |
| paperdesk-linux-installer-3.0.3.tar.gz | 2486529 | 2cfea69a1562a71e34587e0d4963139d87180c74a95d3e56ed6621ca581c012d |

Obok paczek zapisano pliki .sha256. Końcowa paczka Linux na nostalgicznym:
build/installer-candidate-20261029-t63eo0iq/final-source/dist/paperdesk-linux-installer-3.0.3.tar.gz.

Kopie robocze i wyniki kompilacji są odizolowane od istniejących wydań.
Windows zbudowano z kontrolowanej kopii bieżących źródeł; transfer kopii źródeł
do Windows zatwierdził użytkownik. Jednorazowy serwer transferu zamknięto po pobraniu.
Żadnej paczki nie opublikowano.

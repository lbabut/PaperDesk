# PaperDesk 1.1.4 (candidate)

PaperDesk zmienia reMarkable 2 w spokojne, monochromatyczne stanowisko sieciowe.
Pakiet dodaje piec aplikacji bezposrednio do listy AppLoad i zachowuje ich
ustawienia pomiedzy uruchomieniami. Redundantny hub oraz techniczny proces RDP
sa ukryte przed uzytkownikiem.

## Moduly

- **Terminal SSH** — natywna klawiatura, przewijanie, gest zmiany rozmiaru,
  skroty Ctrl i czytelny czarny tekst.
- **Czytnik WWW** — uproszczone strony bez skryptow, zapamietywane pokazywanie
  lub ukrywanie obrazkow, kompaktowe karty z tytulem nad grafika, gest
  powiekszania i e-inkowe przewijanie bez animacji.
- **Pulpit zdalny** — FreeRDP, dotyk, klawiatura, powiekszanie, przesuwanie
  obrazu i lokalnie zapisywany profil.
- **Czytnik RSS** — RSS/Atom, wlasne kanaly, ulubione, przeczytane artykuly,
  pelny tekst oraz cache offline.
- **PaperDesk Care** — wersja lokalna i dostepna, informacje o wydaniu oraz
  aktualizacja z podpisanego i zweryfikowanego pakietu.

PaperDesk nie odswieza niczego automatycznie w tle. Siec i ekran sa uzywane
tylko po poleceniu uzytkownika, co ogranicza miganie i zuzycie baterii.

Interfejs korzysta ze wspolnego, monochromatycznego systemu wizualnego:
redakcyjnej typografii, duzych pol dotykowych, cienkich ramek i spokojnego
rytmu bez animacji. Strony WWW sa dodatkowo normalizowane do czerni i bieli,
a dlugie artykuly pozostaja lekkie typograficznie zamiast stalego pogrubienia.

Pakiet zawiera zgodnosciowa poprawke AppLoad 0.6.0. Przy zamykaniu modulu
odlacza ona klawiature przed zniszczeniem okna, bezpiecznie obsluguje brak
zaladowanego frontendu i wysyla sygnal zamkniecia tylko raz. Zapobiega to
pozostawaniu niewidzialnej warstwy z przyciskiem „X”, ktora blokowala dotyk.
Obsluguje tez nowy sposob raportowania proporcji ekranu w AppLoad 0.6.0.

## Wymagania

- reMarkable 2 z reMarkable OS 3.29.x (przetestowano 3.29.0.149),
- XOVI 0.3.3,
- rm-xovi-extensions v19,
- AppLoad 0.6.0,
- LiTerm 0.1.7.

To jest konfiguracja przetestowana; inne wersje moga dzialac, ale nie sa czescia
tego wydania.

Po aktualizacji firmware XOVI musi miec przebudowana tablice symboli dla
dokladnej wersji systemu. Na testowanym urzadzeniu zrobiono to narzedziem
`/home/root/xovi/rebuild_hashtable` przed uruchomieniem PaperDesk.

## Instalacja z komputera

Graficzny instalator dla Linuxa jest opisany w
`../INSTALL-DESKTOP.md`. Wykrywa istniejące aplikacje przed instalacją i
prosi o potwierdzenie podmiany identycznych ID.


Podlacz tablet przez USB, rozpakuj paczke i uruchom:

```sh
cp paperdesk.conf.example paperdesk.local.conf
chmod 600 paperdesk.local.conf
```

W `paperdesk.local.conf` wpisz tylko kod zarzadzania USB z ustawien tabletu,
a nastepnie uruchom:

```sh
./install-from-computer.sh
```

Domyslny adres to `10.11.99.1`. Inny adres mozna podac jako argument:

```sh
./install-from-computer.sh 192.168.1.50
```

Instalator na tablecie tworzy kopie poprzednich wersji w
`/home/root/.local/share/paperdesk/backups`, zachowuje profile polaczen i nie
usuwa danych uzytkownika. Instalator komputerowy uruchamia XOVI ponownie, aby
AppLoad nie korzystal ze starej wersji zasobow. Instalacja wlacza tez usluge
`xovi-autostart`, dzieki ktorej XOVI i PaperDesk wracaja automatycznie po
pelnym restarcie urzadzenia.

## Instalacja bezposrednio na tablecie

Szczegolowa instrukcja reczna (Linux, USB, SSH, weryfikacja i deinstalacja)
jest w `MANUAL-INSTALL.md`. Skopiuj katalog na tablet i jako root uruchom `./install.sh`, a nastepnie
`/home/root/xovi/start`. Ponowne uruchomienie XOVI zamyka otwarte aplikacje,
wiec najpierw zakoncz prace nad dokumentami.

## Prywatnosc i bezpieczenstwo

- Terminal weryfikuje klucze hostow SSH i nie zapisuje hasel.
- PaperRDP zapisuje profil w katalogu roota z uprawnieniami `0600`.
- RSS przechowuje kanaly i artykuly lokalnie w ustawieniach xochitl.
- Po wlaczeniu obrazkow PaperWeb przekazuje ich publiczne adresy do
  `images.weserv.nl`, aby obejsc niezgodny TLS starych bibliotek tabletu,
  ograniczyc grafike do 760 px i usunac animacje. Nie wysyla tam cookies ani
  danych logowania.
- PaperDesk nie ma telemetrii ani zewnetrznego konta.
- PaperDesk Care przypina klucz publiczny wydan, weryfikuje podpis Ed25519,
  sume SHA-256 archiwum oraz wewnetrzne sumy plikow przed instalacja.
- Kod zarzadzania USB pozostaje w ignorowanym przez Git pliku
  `paperdesk.local.conf`; nie jest kopiowany na tablet ani przekazywany w
  argumentach procesu.

## Usuwanie

`./uninstall.sh` usuwa aplikacje, przywraca poprzednie zasoby AppLoad, jezeli
istnialy, i celowo zachowuje konfiguracje polaczen oraz kopie zapasowe. Po
operacji uruchom ponownie XOVI.

## Licencje skladnikow

Pakiet zawiera teksty licencji LiTerm, AppLoad/QTFB i FreeRDP w katalogu
`licenses`. Kod zrodlowy dolaczonego shima QTFB jest w `third_party_source`,
a kod warstwy PaperDesk, poprawki QML AppLoad i klienta PaperRDP znajduje sie
bezposrednio w paczce.

## Status wydania

Wydanie 1.1.3 zostalo przetestowane na fizycznym reMarkable 2 z systemem
3.29.0.149: uruchamianie wszystkich modulow, wszystkie bezpieczne akcje menu,
klawiatura systemowa, zachowanie ustawien, odswiezanie RSS, pobieranie pelnego
tekstu, czyszczenie okna AppLoad oraz fizyczne gesty przewijania i pinch.

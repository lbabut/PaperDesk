# Historia zmian

## 1.1.3 — 2026-09-28

- Terminal wymusza kilka ograniczonych odswiezen podczas startu, aby aktywne menu SSH nie pozostawalo pustym panelem e-ink,
- kazda zmiana bufora PTY uruchamia kontrolowane odrysowanie warstwy terminala,
- test sprzetowy wstrzykuje prawdziwy tekst do PTY i sprawdza odswiezenie, skroty, klawiature oraz zamkniecie,
- PaperWeb zapamietuje ostatni poprawnie otwarty adres HTTP lub HTTPS i przywraca go po ponownym uruchomieniu.

## 1.1.2 — 2026-09-27

- dodano bezpieczna deinstalacje calego PaperDesk bez otwierania terminala,
- akcja Uninstall wymaga osobnego, jednoznacznego potwierdzenia,
- dane polaczen, dane czytnika i kopie zapasowe pozostaja na tablecie,
- po usunieciu pakietu zasoby AppLoad sa automatycznie przeladowywane.
- proces wydawniczy zawsze przebudowuje osadzone zasoby QML, aby paczka nie mogla zawierac starszego interfejsu.

## 1.1.0 — 2026-09-27

- dodano PaperDesk Care: czytelny ekran wersji, dostepnosci aktualizacji i informacji o wydaniu,
- aktualizacje korzystaja z podpisanego manifestu Ed25519 i przypietego klucza publicznego,
- paczka ZIP jest weryfikowana przez SHA-256 przed rozpakowaniem, a jej pliki przez wewnetrzny manifest przed instalacja,
- instalator nadal wykonuje kopie poprzedniej wersji i zachowuje konfiguracje aplikacji,
- zadanie aktualizacji dziala poza interfejsem Xochitl, dzieki czemu moze bezpiecznie przeladowac XOVI po instalacji,
- konfiguracja instalacji przez USB wymaga tylko lokalnego kodu zarzadzania; sekret nie trafia do repozytorium ani argumentow procesu.

## 1.0.5 — 2026-09-27

- odswiezono caly system wizualny: redakcyjna typografia, lzejsze obramowania, wspolny rytm, promienie i stany dotyku,
- dopasowano centralny przycisk MENU/KEYBOARD AppLoad do nowego systemu wizualnego,
- pasek Terminala rezerwuje teraz czysta strefe dla centralnego MENU i nie naklada na nie przycisku skrotow ani pola klawiatury,
- przeprojektowano ekran startowy, formularz RDP, pasek Terminala, czytnik WWW oraz listy i formularze RSS,
- klawiatura PaperWeb pojawia sie tylko po dotknieciu pola adresu i znika po akcji, Enterze, dotknieciu strony lub rozpoczeciu przewijania,
- PaperWeb prosi serwery domyslnie o mobilna wersje dokumentu, co upraszcza menu i uklad przed konwersja do czytnika e-ink,
- mobilny tryb czytnika nie przywraca juz wielokolumnowego CSS serwisu; sekcje, siatki, tabele i kolumny sa skladane w jeden pionowy strumien,
- dodano zapamietywany przelacznik widoku Mobile/Computer; zmiana trybu przeladowuje biezaca strone odpowiednim profilem,
- mobilny czytnik ogolnie rozpoznaje powtarzalne naglowki oraz listy danych osadzone w JSON; strony skladane przez JavaScript nie koncza sie juz pustym ekranem,
- PaperWeb ma zapamietywany przelacznik Show/Hide Pictures; obrazki sa domyslnie ukryte, ograniczone do 12, skalowane do 760 px i zamieniane na statyczny JPEG przez zgodny z tabletem gateway TLS,
- karty czytnika maja teraz kompaktowy naglowek oraz tytul wpisu nad obrazem; przyciski jednoznacznie pokazuja aktualny tryb i akcje przelaczenia,
- lista AppLoad nie pokazuje juz redundantnego huba PaperDesk ani technicznego procesu PaperDesk RDP Engine; widoczne pozostaja cztery aplikacje uzytkowe,
- PaperWeb wymusza teraz spokojny czarno-bialy sklad stron ponad stylami serwisu, bez kolorow, cieni i animacji,
- tekst artykulow RSS ma naturalna wage zamiast stalego pogrubienia, co poprawia czytelnosc dlugich materialow,
- lista RSS uzywa teraz oddychajacych kart artykulow, spokojniejszego panelu zrodel i wygodniejszej szerokosci tekstu,
- dodano jednorazowy, nieinwazyjny starter naukowy: Physics World, Quanta Magazine, MIT Technology Review, ScienceDaily i Nature Physics,
- ograniczono pojedynczy kanal RSS do 12 najnowszych wpisow i 12 kB tresci na wpis, aby bardzo duze kanaly nie blokowaly watku interfejsu ani systemowego watchdoga,
- odswiezanie wybranego zrodla pobiera teraz tylko ten kanal, a odswiezanie wszystkich kanalow scala, sortuje, zapisuje i odrysowuje liste tylko raz na koncu,
- callbacki zakonczonych zapytan RSS nie dotykaja juz zniszczonego okna po zamknieciu aplikacji,
- dodano powtarzalny test zachowania uzytkownika na fizycznym tablecie dla huba, Terminala, WWW, RDP i RSS, z kontrola restartow, watchdoga oraz swiezego sladu po kazdej akcji,
- test RSS przetwarza na tablecie syntetyczny kanal o rozmiarze odpowiadajacym ciezkim zrodlom przed wykonaniem gestow i nawigacji,
- sprzetowa probka dlugiego artykulu dziala tylko w aktywnym tescie, jest calkowicie tylko do odczytu i nie moze zastapic normalnego cache RSS,
- potwierdzono zgodnosc na fizycznym reMarkable OS 3.29.0.149 z AppLoad 0.6.0 i LiTerm 0.1.7,
- obsluzono zerowa lub nieustawiona proporcje ekranu zwracana przez AppLoad 0.6.0,
- wycentrowano przycisk MENU/KEYBOARD AppLoad wzgledem calego ekranu,
- przebudowano caly interfejs jako spojny, kontrastowy produkt e-ink: jeden naglowek, duze pola dotykowe i prostsza hierarchia,
- usunieto zdublowane menu i techniczna stopke z ekranu startowego; cztery narzedzia maja teraz czytelne karty produktowe,
- ujednolicono naglowki, nazwy akcji, formularze i komunikaty Terminala, PaperWeb, PaperRDP oraz PaperRSS,
- wszystkie paski akcji maja teraz rowne przyciski o wspolnym czarno-bialym stylu, bez domyslnych kontrolek Qt wygladajacych jak prototyp,
- wszystkie bezpieczne akcje interfejsu otrzymaly stale cele testowe i sa sprawdzane automatycznie kliknieciami,
- test sprzetowy przechodzi przez cztery aplikacje w jednej sesji i wykonuje prawdziwe dotkniecia, przewijanie oraz gest dwoma palcami,
- Terminal nie wysuwa klawiatury przy starcie; klawiatura i skroty sa dostepne z duzych przyciskow,
- wlasne przyciski Terminala, RDP i huba uzywaja natywnych handlerow dotyku zamiast emulacji myszy,
- naprawiono przewijanie pelnego tekstu RSS przykrytego linkami i dodano test fizycznego gestu na tablecie,
- dodano automatyczny start XOVI po pelnym restarcie urzadzenia,
- naprawiono przesuniecie wspolrzednych linkow po przewinieciu PaperWeb,
- warstwa gestow jest teraz przypieta do nieruchomego obszaru ekranu,
- dotkniecie linku uwzglednia aktualne przewiniecie i powiekszenie strony,
- PaperRDP czysci ekran e-ink po przejsciu z logowania do zdalnego pulpitu,
- PaperRDP wykonuje tylko jedno opoznione pelne odswiezenie po polaczeniu, bez cyklicznego migania podczas pracy,
- usunieto druga, rysowana klawiature PaperRDP; aplikacja korzysta tylko z klawiatury systemowej,
- dodano widoczna instrukcje otwierania klawiatury systemowej gestem od gornej krawedzi,
- dodano menu skrotow RDP: Ctrl+C/V/X/A, Alt+Tab, Ctrl+Alt+Del, Win, Esc i Tab,
- wpisywanie z klawiatury systemowej odswieza tylko formularz zamiast calego ekranu, aby nie zapychac kolejki e-ink,
- ekran logowania wymusza jednorazowe czyszczenie pozostalosci poprzedniej klawiatury,
- Backspace obsluguje kody Qt Backspace, Delete, ASCII BS i DEL.
- dodano automatyczne testy klikniec wszystkich czterech przyciskow huba oraz test blokujacy globalne podmiany AppLoad.
- ekran logowania RDP jest teraz natywnym formularzem QML z systemowa klawiatura i prawidlowym Backspace,
- zapisany profil RDP jest wczytywany do natywnego formularza, a silnik FreeRDP uruchamia sie dopiero po nacisnieciu Connect.
- bezposrednie uruchomienie silnika RDP korzysta z zapisanego profilu i nie pokazuje juz starego formularza z rysowana klawiatura.
- aktualizacje RDP dostarczane pasami sa scalane w spojna klatke przed wyswietleniem na e-ink,
- ponownie przeslane, ale niezmienione piksele nie wywoluja juz zbednych odswiezen ekranu.
- hub PaperDesk pozostaje aktywny pod uruchomionym modulem, dzieki czemu po zamknieciu RDP nie zostaje osierocony przycisk X ani warstwa blokujaca dotyk.
- Enter z klawiatury systemowej RDP obsluguje teraz oba kody Qt: Return oraz Enter.
- Backspace i Enter w aktywnej sesji RDP normalizuja kody Qt, X11 oraz ASCII wysylane przez rozne wersje klawiatury AppLoad.
- znaki sterujace z kodowanej sciezki Unicode sa wysylane jako prawdziwe skany klawiszy RDP, a nie jako niewidoczne znaki tekstowe.
- gest przesuwania i powiekszania RDP publikuje jedna spojna klatke dopiero po puszczeniu palcow zamiast zalewac kolejke e-ink klatkami co 320 ms.
- duze zmiany pulpitu RDP sa ograniczone do tempa bezpiecznego dla sterownika e-ink; male aktualizacje kursora i tekstu pozostaja szybkie.
- natywny formularz RDP pozostaje wlascicielem okna podczas sesji; po zamknieciu RDP wraca formularz zamiast osieroconej warstwy AppLoad z przyciskiem X.
- naprawiono blad AppLoad 0.5.3 przy zamykaniu aplikacji: nie odwoluje sie juz do usunietego loadera, klawiatura jest odlaczana przed zniszczeniem okna, a sygnal zamkniecia jest obslugiwany tylko raz.
- w trybie pelnoekranowym przycisk AppLoad `KEYBOARD` bezposrednio wlacza i wylacza klawiature systemowa; nie wymaga juz krotkiego gestu i trafienia w znikajaca ikone.
- wewnetrzne okna AppLoad nie sa juz przedwczesnie oznaczane jako zamkniete przez nieaktywny kontroler QTFB; dzieki temu formularz RDP emituje prawdziwy sygnal zamkniecia i nie zostawia warstwy z `X`.

## 1.0.4 — 2026-09-26

- przetlumaczono interfejs PaperDesk, Terminala, PaperWeb, PaperRSS i PaperRDP na angielski,
- przetlumaczono menu profili SSH i komunikaty polaczenia,
- polaczono przewijanie i pinch PaperWeb w jeden kontroler wielodotykowy,
- dodano przyciski minus i plus jako pewne sterowanie powiekszeniem,
- zachowano otwieranie linkow krotkim dotknieciem.

## 1.0.3 — 2026-09-26

- naprawiono blokowanie przewijania PaperWeb przez obsluge gestu pinch,
- jeden palec przewija teraz strone bez animacji i bezwladnosci,
- dwa palce nadal zmieniaja powiekszenie,
- krotkie dotkniecie linku nadal otwiera wskazana strone,
- wlaczono szybki tryb odswiezania e-ink podczas pracy z dokumentem.

## 1.0.2 — 2026-09-26

- usunieto pozostajacy nad AppLoad przycisk „X” po wyjsciu z modulu,
- hub zamyka sie dopiero po bezpiecznym uruchomieniu wybranego modulu,
- po powiekszeniu RDP widok mozna przesuwac jednym palcem,
- przesuwanie widoku nie jest juz wysylane do zdalnego pulpitu jako klikniecie,
- odswiezanie podczas gestu zostalo ograniczone, aby zmniejszyc miganie e-ink.

## 1.0.1 — 2026-09-25

- usunieto zamykanie huba, ktore moglo pozostawic nieaktywne okno AppLoad,
- hub pozostaje ekranem glownym i przyjmuje powrot ze wszystkich modulow,
- wlaczono bezpieczne ponowne otwarcie huba po awaryjnym stanie AppLoad.

## 1.0.0 — 2026-09-25

- pierwszy wspolny ekran startowy PaperDesk,
- Terminal SSH, PaperWeb, PaperRDP i PaperRSS w jednej paczce,
- instalacja z kopia zapasowa i zachowaniem danych,
- spójny, kontrastowy interfejs bez animacji,
- paczka wydania z sumami kontrolnymi.

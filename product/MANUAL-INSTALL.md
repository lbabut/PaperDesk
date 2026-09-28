# PaperDesk Apps — instalacja ręczna na reMarkable 2

Ta instrukcja dotyczy ręcznej instalacji PaperDesk 1.1.4 z komputera
z Linuxem, przez USB i SSH. Nie wymaga graficznego instalatora.
Wersja 1.1.4 jest kandydatem do wydania; pełny test na czystym
tablecie nie został jeszcze przeprowadzony.

## 1. Przygotuj tablet i komputer

- Użyj reMarkable 2 z reMarkable OS 3.29.x. Testowany zestaw dla
  poprzedniego wydania: OS 3.29.0.149, XOVI 0.3.3,
  rm-xovi-extensions v19, AppLoad 0.6.0 i LiTerm 0.1.7.
- XOVI, AppLoad, LiTerm i rozszerzenie qt-resource-rebuilder muszą już
  działać. PaperDesk ich nie instaluje.
- Podłącz tablet przewodem USB. W ustawieniach tabletu włącz interfejs
  USB i odczytaj kod zarządzania USB. To hasło do SSH, nie licencja.
- Na komputerze potrzebne są: ssh, tar, gzip i sha256sum.
- Zamknij aplikacje na tablecie i zapisz otwarte dokumenty. Na końcu
  restart XOVI zamknie uruchomione aplikacje.

Domyślny adres tabletu to `10.11.99.1`. Jeżeli używasz innego
adresu, podstaw go we wszystkich poleceniach poniżej. Przy pierwszym
połączeniu SSH sprawdź odcisk klucza hosta przed jego zaakceptowaniem.
Jeżeli zapisany klucz hosta nagle się zmienił, przerwij instalację.

## 2. Rozpakuj i sprawdź paczkę

W katalogu, w którym pobrano archiwum:

```sh
sha256sum paperdesk-linux-installer-1.1.4.tar.gz
tar -xzf paperdesk-linux-installer-1.1.4.tar.gz
cd paperdesk-linux-installer-1.1.4/product
sha256sum -c SHA256SUMS
```

Porównaj SHA-256 całego archiwum z sumą opublikowaną obok paczki.
Ostatnie polecenie musi zgłosić `OK` przy wszystkich plikach.
Jeśli jakakolwiek suma się nie zgadza, nie kontynuuj.

## 3. Sprawdź wymagane składniki na tablecie

```sh
ssh root@10.11.99.1 'test -d /home/root/xovi &&
  test -d /home/root/xovi/exthome/appload &&
  test -f /home/root/xovi/extensions.d/qt-resource-rebuilder.so &&
  echo "XOVI, AppLoad i qt-resource-rebuilder: OK"'
```

SSH poprosi o kod zarządzania USB. Brak napisu `OK` oznacza,
że tablet nie jest gotowy. Po aktualizacji firmware XOVI może
wymagać przebudowania tablicy symboli dla dokładnej wersji systemu;
nie instaluj PaperDesk na niesprawnym XOVI.

Sprawdź, co już jest zainstalowane:

```sh
ssh root@10.11.99.1 'cat /home/root/.local/share/paperdesk/current-version 2>/dev/null || true
  for app in paperdesk literm paperweb paperrdp-login paperrdp paperrss papercare shims; do
    test -e "/home/root/xovi/exthome/appload/$app" && echo "$app"
  done
  true'
```

PaperDesk zastępuje tylko te identyfikatory AppLoad. Pozostałe aplikacje
zostają na tablecie. Przy pierwszej instalacji 1.1.4 kopia zastępowanych
katalogów trafia do `/home/root/.local/share/paperdesk/original`.
Jeśli aktualizujesz starszy PaperDesk, który nie ma
`original-recorded`, zachowaj jego wcześniejsze kopie: instalator
nie potrafi odtworzyć pierwotnego LiTerm z samego aktualnego katalogu.

## 4. Prześlij pliki

Będąc w katalogu `product` z punktu 2:

```sh
ssh root@10.11.99.1 'mkdir -p /home/root/paperdesk-install-manual'
tar --exclude='./paperdesk.local.conf' -cf - . |
  ssh root@10.11.99.1 'tar -xf - -C /home/root/paperdesk-install-manual'
```

Polecenie wyklucza lokalny plik z kodem USB. Nie dopisuj kodu do
polecenia ani nie kopiuj go na tablet. Sprawdź przesłane pliki:

```sh
ssh root@10.11.99.1 'cd /home/root/paperdesk-install-manual &&
  sha256sum -c SHA256SUMS'
```

## 5. Zainstaluj i przeładuj XOVI

```sh
ssh root@10.11.99.1 'cd /home/root/paperdesk-install-manual &&
  sh ./install.sh'
ssh root@10.11.99.1 '/home/root/xovi/start'
```

Pierwsze polecenie powinno zakończyć się komunikatem `Gotowe`.
Instalator zapisuje poprzedni stan przed podmianą modułów.
Po restarcie XOVI otwórz AppLoad na tablecie. Powinny pojawić się:
Terminal, Web, RDP, RSS i Care. Sprawdź, czy inne aplikacje nadal są
widoczne, oraz otwórz każdy z pięciu modułów.

Wersję i automatyczny start sprawdzisz poleceniami:

```sh
ssh root@10.11.99.1 'cat /home/root/.local/share/paperdesk/current-version;
  systemctl is-enabled xovi-autostart.service;
  systemctl is-enabled paperdesk-update.path'
```

Oczekiwana wersja to `1.1.4`, a obie usługi powinny zgłosić
`enabled`. Dane profili pozostają w katalogach użytkownika
na tablecie; ich instalator nie usuwa.

## Usunięcie i powrót do poprzedniego stanu

Najpierw zamknij aplikacje. Zachowaj katalog
`/home/root/.local/share/paperdesk` — zawiera kopie zapasowe.
Jeżeli pozostawiłeś katalog przesłany w punkcie 4:

```sh
ssh root@10.11.99.1 'sh /home/root/paperdesk-install-manual/uninstall.sh'
ssh root@10.11.99.1 '/home/root/xovi/start'
```

Deinstalator przywraca aplikacje, które istniały przed pierwszą
instalacją 1.1.4 i mają zapisany oryginał. Dane połączeń i kopie
zapasowe pozostają. Jeśli starsza instalacja PaperDesk nie ma
`original-recorded`, nie zakładaj, że deinstalator przywróci
oryginalny LiTerm: użyj wcześniej zachowanej kopii lub instalatora
odpowiedniej wersji LiTerm.

Jeżeli chcesz wrócić do wcześniejszego wydania PaperDesk zamiast
usuwać cały pakiet, zainstaluj ponownie jego kompletne, sprawdzone
archiwum. Nie kopiuj wybiórczo plików z `backups`, ponieważ
zmiany obejmują też zasoby AppLoad i usługi.

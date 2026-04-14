# Uwagi

1. Te testy sprawdzją działanie biblioteki tylko dla *poprawnych* danych. Obsługa błędów jest osobną kwestią, którą trzeba się zająć.
2. Nie gwarantuje, że fakt, że wasze rozwiązanie przechodzi 100% testów znaczy, że jest w 100% poprawne.
3. Te testy opierają się na mojej interpretacji zadania. Na forum Peczarski napisał że są przypadki gdzie funkcja może zwrócić 3 różne rzeczy, zatem to że testy nie przechodzą nie znaczy że Wasze rozwiązanie jest błędne 
4. Używacie testów na własną odpowiedzialność

# Instrukcja obsługi:

1. Wrzuć zawartość do folderu ze swoim projektem

Struktura folderu powinna wygladać następująco:

 - /projekt:
	- rstack.c
 	- rstack.h
 	- librstack.so
 	- makefile
 	- ...
 	- tests/
 	- test.sh

2. Skompiluj testy następującą komendą: `gcc tests/test*.c --std=gnu23 -L. -lrstack -o tester`

3. Ustaw LD_LIBRARY_PATH na folder w którym znajduję się projekt (jeżeli obecnie w nim jesteś, to w terminal wpisz `export LD_LIBRARY_PATH=$(pwd)`)

4. Uruchom testy:

`bash test.sh numer_testu/"all" (true/false - false wyłącza valgrind'a)`

i gotowe :D

---

kocham memory leak'i !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!111!!1!

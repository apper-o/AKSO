# Uwagi

1. Testy sprawdzają działanie biblioteki tylko dla poprawnych danych. Obsługa błędów jest osobną kwestią którą trzeba się zająć
2. Te testy opierają się na mojej interpretacji zadania. Na forum Peczarski napisał że są przypadki gdzie funkcja może zwrócić 3 różne rzeczy, zatem to że testy nie przechodzą nie znaczy że Wasze rozwiązanie jest błędne 
3. Jako punkt odniesienia, no moim rozwiązaniu wszystkie testy z valgrindem zajmują 5.4s na students'ie

# Instrukcja obsługi:

0. wrzuć zawartość do folderu ze swoim projektem (lub kopii folderu, bo trochę tu śmieci)

1. skompiluj testy następującą komendą: gcc-14 test*.c toster.c --std=gnu23 -L. -lrstack -o tester
2. uruchom testy: valgrind ./tester all
3. uruchom skrypt porównujący wyniki rstack_write: bash diff_all.sh

Kroki 1-3 polecam zautomatyzować wklejając regułkę do Makefile'a:

```
tester: toster.c
	gcc-14 test*.c toster.c --std=gnu23 -L. -lrstack -o tester

test: tester librstack.so
	valgrind ./tester all
	bash diff_all.sh
```

Można też uruchomić konkretny test podając numer testu jako argument (zamiast all) i używając diff.sh z tym samym argumentem

---

kocham memory leak'i !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!111!!1!

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#undef NDEBUG

int test1(void);
int test2(void);
int test3(void);
int test4(void);
int test5(void);
int test6(void);
int test7(void);
int test8(void);
int test9(void);
int test10(void);

int (*tests[10])(void) = { test1, test2, test3, test4, test5, test6, test7, test8, test9, test10 };

int do_test(int i) {
    int result = tests[i-1]();
    printf("Test %d: ", i);
    
    if (result != 0) {
        printf("Failed\n");
    } else {
        printf("Passed\n");
        return 1;
    }

    return 0;
}

int main(int argc, char *argv[]) {
    if (argc == 2) {
        if (strcmp(argv[1], "all") == 0) {
            for (int i = 1; i <= 10; i++) {
                do_test(i);
            }
        } else {
            do_test(atoi(argv[1]));
        }
    } else {
        printf("Podaj numer testu jako argument lub all aby uruchomić wszystkie testy\n");
    }
}


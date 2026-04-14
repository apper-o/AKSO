
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
int test11(void);
int test12(void);
int test13(void);
int test14(void);
int test15(void);
int test16(void);
int test17(void);
int test18(void);
int test19(void);
int test20(void);

int (*tests[20])(void) = { test1, test2, test3, test4, test5, test6, test7, test8, test9, test10, test11, test12, test13, test14, test15, test16, test17, test18, test19, test20 };

int do_test(int i) {
    int result = tests[i-1]();
    printf("===============================================\n");
    printf("Test %d\n", i);
    printf("-----------------------------------------------\n");
    
    if (result != 0) {
        printf("Assertions (rstack_front / rstack_empty) failed\n");
    } else {
        printf("Assertions (rstack_front / rstack_empty) passed\n");
    }

    return result;
}

int main(int argc, char *argv[]) {
    int code = 1;
    if (argc == 2) {
        code = do_test(atoi(argv[1]));
    } else {
        printf("Podaj numer testu jako argument\n");
    }

    return code;
}
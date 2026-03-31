#include <stdio.h>
#include <inttypes.h>


int dodaj(int a, int b);
int dodaj(long long a, long long b);

int dodaj()
{
    return a + b;
}

int main()
{
    long long a=2, b=1;
    printf("%d", dodaj(a,b));
    return 0;
}
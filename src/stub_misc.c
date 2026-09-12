#include <stdlib.h>
#include <stdio.h>
#include <calypsi/stubs.h>

static char *no_environ[] = { 0 };

char **_Stub_environ(void)
{
    return no_environ;
}

void _Stub_assert(const char *filename, int linenum)
{
    printf("Assertion failed: %s line %d\n", filename, linenum);
    exit(1);
}

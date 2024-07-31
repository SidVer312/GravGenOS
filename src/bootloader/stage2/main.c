#include "stdint.h"

void _cdecl cstart_(uint16_t bootDrive){
    puts("Hello World from C!\r\n");
    for (;;);
}
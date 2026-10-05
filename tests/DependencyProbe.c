#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach/machine.h>

// System libraries may live only in the dyld shared cache. Inspect the actual
// loaded headers from this native process, rather than treating otool -L as proof.
int main(int argc, char **argv) {
    int failed = 0;
    for (int n = 1; n < argc; n++) {
        if (!dlopen(argv[n], RTLD_LAZY | RTLD_LOCAL)) {
            fprintf(stderr, "FAIL load %s: %s\n", argv[n], dlerror());
            failed = 1;
            continue;
        }
        int found = 0;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            if (strcmp(_dyld_get_image_name(i), argv[n]) == 0) {
                const struct mach_header *header = _dyld_get_image_header(i);
                found = 1;
                printf("%s cputype=%d cpusubtype=%d %s\n", argv[n],
                    header->cputype, header->cpusubtype,
                    header->cputype == CPU_TYPE_ARM64 ? "PASS ARM64" : "FAIL");
                if (header->cputype != CPU_TYPE_ARM64) failed = 1;
            }
        }
        if (!found) {
            fprintf(stderr, "FAIL no exact loaded image match: %s\n", argv[n]);
            failed = 1;
        }
    }
    return failed;
}

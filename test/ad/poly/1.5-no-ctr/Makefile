# File     : Makefile
# Purpose  : makefile for poly 1.5-no-ctr subdir

# Rules

test :
	@./test.sh

build_ref :
	./gyre gyre.in; \
        for file in *.txt; do mv $$file ref/$$file; done

build_ref_arch :
	./gyre gyre.in; \
        for file in *.txt; do mv $$file ref/$$file.`uname -m`-`uname -s`; done

.PHONY: test build_ref build_ref_arch

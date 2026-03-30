.PHONY: all clean

ROCQ      := rocq compile
ROCQFLAGS := -Q . Boilerplate

SRC := Boilerplate.v

all: $(SRC:.v=.vo)

%.vo: %.v
	$(ROCQ) $(ROCQFLAGS) $<

clean:
	rm -f *.vo *.vos *.vok *.glob .*.aux boilerplate.scm

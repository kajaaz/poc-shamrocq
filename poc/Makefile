.PHONY: all clean

ROCQ     := rocq compile
ROCQFLAGS := -Q . Poc

SRC := Poc.v

all: $(SRC:.v=.vo)

%.vo: %.v
	$(ROCQ) $(ROCQFLAGS) $<

clean:
	rm -f *.vo *.vos *.vok *.glob .*.aux poc.scm

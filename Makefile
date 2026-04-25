.PHONY: clean test build release

clean:
	dzil clean

test:
	dzil test

build: clean
	dzil build
	mkdir -p releases
	mv -vf $$(ls -t *.tar.gz | head -n 1) releases/

release: build
	dzil clean
	git add releases/*.tar.gz
	git status
	@echo "tag and push ..."

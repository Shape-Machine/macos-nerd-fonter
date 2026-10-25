.PHONY: app run test clean

app:
	./scripts/build-app.sh

run: app
	open build/NerdFonter.app

test:
	swift test

clean:
	rm -rf .build build

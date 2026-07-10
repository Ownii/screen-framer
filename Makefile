APP := build/Screen Framer.app

.PHONY: build run stop restart test clean

# Baut das Release-Binary und verpackt es als "Screen Framer.app".
build:
	./scripts/build-app.sh

# Baut die App und startet sie.
run: build
	open "$(APP)"

# Beendet eine laufende Instanz (kein Fehler, wenn keine läuft).
stop:
	pkill -f "Screen Framer.app/Contents/MacOS/ScreenFramer" || true

# Stoppt, baut neu und startet.
restart: stop run

test:
	swift test

clean:
	swift package clean
	rm -rf build

.PHONY: app run clean

app:
	scripts/build-app.sh release

run: app
	open build/Wiggle.app

clean:
	rm -rf .build build

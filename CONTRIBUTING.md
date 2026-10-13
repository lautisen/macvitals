# Contributing

```bash
swift build
swift test
swift run macvitals sample                 # one live measurement as JSON
swift run macvitals demo-report --open     # render the report from synthetic data
```

Run the real daemon without installing anything or needing root:

```bash
mkdir -p /tmp/mv && cat > /tmp/mv/config.json <<'EOF'
{ "sampleIntervalSeconds": 30, "reportIntervalSeconds": 60,
  "webhook": { "url": "http://127.0.0.1:8787/hook", "secret": "dev" } }
EOF
MACVITALS_SECRET=dev python3 examples/receiver/receiver.py &   # local signed receiver
MACVITALS_HOME=/tmp/mv swift run macvitals daemon
```

`MACVITALS_HOME` relocates every file into that folder and disables self-removal.

## Guidelines

- Keep `MacVitalsCore` free of side effects where possible: parsers and analysis take plain
  values so they can be unit-tested (see `BatteryCollector.parse`, `ProcessCollector.parse`).
- No third-party dependencies.
- New insight rules need a test for the positive case and for a near-miss.
- Report HTML must stay self-contained (no external requests).

## Toolchain note

With only the Command Line Tools installed (no Xcode), `swift test` can fail to locate the
swift-testing macro plugin. Point to it explicitly:

```bash
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

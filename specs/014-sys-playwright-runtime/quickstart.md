# Quickstart: Validate the sys browser runtime

```bash
bash devcontainer.test/test-base-image-dockerfile.sh
sysBenches/base-image/build.sh --no-cache
```

Then resolve the image-owned Chromium executable, confirm `ldd` reports zero
`not found` libraries, and launch it headlessly in a disposable container. A
derived cloud image may be rebuilt for inheritance verification, but the
running `cloud-bench` container must remain untouched.

# Vendor/

Engine source lives here. It is **not** committed — clone it before building.

```sh
# libre: async I/O + protocol stacks (BSD-3-Clause). The old `librem` media
# library was merged into libre; there is no separate librem to clone.
git clone https://github.com/baresip/re.git Vendor/re

# baresip: modular SIP user agent (BSD-3-Clause).
git clone https://github.com/baresip/baresip.git Vendor/baresip
```

Pin specific tags once the PoC succeeds, and record the exact commits in
`docs/BARESIP-POC.md` for reproducibility.

Then:

```sh
Scripts/build-baresip-ios.sh      # builds per-slice static libs
Scripts/create-xcframework.sh     # -> Frameworks/Baresip.xcframework
```

## License note

Both libre and baresip are BSD-3-Clause. Keep the module set to royalty-free
codecs (Opus, G.711) for the PoC. Any non-free codec module (G.729, AMR, H.264)
carries separate patent obligations and must stay an explicit opt-in — do not
bundle it by default. Capture the full dependency license audit in
`docs/BARESIP-POC.md` §1 before distributing anything.

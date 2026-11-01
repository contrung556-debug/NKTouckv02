# NKTouch v0.2 build notes

This repository is a small patch/bootstrap layer rather than a vendored copy of the complete upstream project.

The workflow:
1. checks out this repository;
2. fetches the pinned upstream ZXTouch Rootless commit;
3. applies NKTouch v0.2 sources and branding;
4. builds the iOS app and rootless Theos package;
5. uploads the resulting `.deb`.

Pinned upstream SHA:
`a602da112ef1a688fb2601424443abb1ccc28c63`

Internal ZXTouch paths/bundle identifiers are deliberately retained where changing them could break IPC, runner services, settings, or script compatibility. Visible package/app branding is NKTouch.

# NFCPassportReader (vendored)

Source vendored from https://github.com/referendum-libre/NFCPassportReader
at commit `92018762f6103bf13a12b0bede9539f066de18a9`, itself a fork of
https://github.com/AndyQ/NFCPassportReader.

Fork changes at that commit: conditional `.pace` polling based on `skipPACE`.
Built on `69368850` (retains the `can:` param for CAN-PACE).
- `skipPACE=false` (CNIe) → `.pace` + `.iso14443` (Type A detected).
- `skipPACE=true` (passport/BAC) → `.iso14443` only (Type B detected).

Vendored (rather than pulled via CocoaPods `git:`/`commit:`) so the exact
source used by the app lives in this repo. Requires the `OpenSSL-Universal`
pod (declared in `EDocument.podspec`), matching the upstream package's own
dependency.

Distributed under the MIT license (see `LICENSE`), copyright Andy Qua.

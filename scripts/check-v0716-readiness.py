#!/usr/bin/env python3
"""Review the v0.7.16 dev release gate without starting an iOS build.

Source/host tests are not proof of accuracy on a physical iPhone. This audit
explicitly remains blocked until the user validates the 7 Test Lab groups
on-device and chooses to prepare a release candidate.
"""
from pathlib import Path
import json
import sys

ROOT=Path(__file__).resolve().parents[1]
GROUPS=("runtime","touch","input","color","vision","network","task")
REQUIRED=(
 "lua/nktestlab.lua", "lua/nkcoords.lua", "lua/nkstability.lua",
 "lua/nkregression.lua", "lua/nkcommand_contract.lua",
 "runtime/nkcore.c", "runtime/nkvision.m",
 "scripts/stage-v0716-testlab-dev.sh",
 "scripts/apply-v0716-cli-parser.py",
 "scripts/apply-v0716-command-contract.py",
 "scripts/apply-v0716-testlab-ui.py",
 "tests/test_v0716_native_preflight.py",
 "tests/test_v0716_reliability_report.py",
 "tests/test_v0716_color_accuracy.py",
 "tests/lua_v0716_coords_stability.lua",
 "tests/lua_v0716_regression.lua",
 "COMMAND_MATRIX_V0716.md",
)
missing=[name for name in REQUIRED if not (ROOT/name).is_file()]
new_release=list((ROOT/".github/workflows").glob("build-v0716*.yml"))
new_release+=list((ROOT/".github/workflows").glob("publish-v0716*.yml"))
new_release+=list((ROOT/"release").glob("v0716-build-ready.*")) if (ROOT/"release").exists() else []
evidence=ROOT/"release/v0716-iphone-verification.json"
device_pending=list(GROUPS)
if evidence.is_file():
    try:
        record=json.loads(evidence.read_text())
        if (record.get("device")=="iphone_rootless" and
            record.get("verified_by_user") is True):
            checks=record.get("groups",{})
            device_pending=[
                name for name in GROUPS
                if not isinstance(checks.get(name),dict) or
                   checks[name].get("result")!="PASS"
            ]
    except (ValueError,TypeError,AttributeError):
        pass

state="BLOCKED"
if missing or new_release:
    state="SOURCE_INCOMPLETE"
# No Sileo release/build is authorized by this diagnostic script, even when
# every on-device check is marked PASS. It requires a separate review step.
print(json.dumps({
 "version":"0.7.16-dev",
 "state":state,
 "source_missing":missing,
 "new_release_artifacts":[str(x.relative_to(ROOT)) for x in new_release],
 "iphone_groups_still_needing_evidence":device_pending,
 "manual_release_review_required":True,
 "build_started":False,
 "sileo_published":False,
},ensure_ascii=False,indent=2))
if missing or new_release:
    sys.exit(1)

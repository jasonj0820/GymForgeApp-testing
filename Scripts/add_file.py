#!/usr/bin/env python3
"""Adds a new Swift file to GymForge.xcodeproj without Xcode or XcodeGen.

    python3 Scripts/add_file.py iOS/Views/NewView.swift iOS/Views/TodayView.swift

The new file joins the same folder group and the same targets as the second file (a file that
already sits next to it), so nothing about targets has to be spelled out. Safe to run twice.
"""
import hashlib, os, re, sys

PROJECT = os.path.join(os.path.dirname(__file__), "..", "GymForge.xcodeproj", "project.pbxproj")


def new_id(seed, text):
    n = 0
    while True:
        candidate = hashlib.md5(f"{seed}:{n}".encode()).hexdigest()[:24].upper()
        if candidate not in text:
            return candidate
        n += 1


def add(new_path, sibling_path):
    name, sibling = os.path.basename(new_path), os.path.basename(sibling_path)
    if os.path.dirname(new_path) != os.path.dirname(sibling_path):
        sys.exit(f"{new_path} and {sibling_path} must be in the same folder")
    text = open(PROJECT).read()
    if f"/* {name} */ = {{isa = PBXFileReference" in text:
        print(f"= {name} already in the project")
        return
    ref = re.search(r"\t\t([0-9A-F]{24}) /\* %s \*/ = \{isa = PBXFileReference[^\n]*\n" % re.escape(sibling), text)
    if not ref:
        sys.exit(f"{sibling} isn't in the project")
    sibling_ref = ref.group(1)
    file_ref = new_id("ref:" + new_path, text)

    # 1. the file itself
    text = text.replace(ref.group(0), ref.group(0) +
        f"\t\t{file_ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};\n", 1)

    # 2. its folder group: the group listing whose children include the sibling
    child = f"\t\t\t\t{sibling_ref} /* {sibling} */,\n"
    start = text.index("/* Begin PBXGroup section */")
    at = text.index(child, start)
    text = text[:at] + child + f"\t\t\t\t{file_ref} /* {name} */,\n" + text[at + len(child):]

    # 3. one build file per target the sibling is compiled into
    builds = re.findall(r"\t\t([0-9A-F]{24}) /\* %s in Sources \*/ = \{isa = PBXBuildFile; fileRef = %s /\* %s \*/; \};\n"
                        % (re.escape(sibling), sibling_ref, re.escape(sibling)), text)
    if not builds:
        sys.exit(f"{sibling} isn't compiled into any target")
    for index, sibling_build in enumerate(builds):
        build = new_id(f"build:{new_path}:{index}", text)
        decl = f"\t\t{sibling_build} /* {sibling} in Sources */ = {{isa = PBXBuildFile; fileRef = {sibling_ref} /* {sibling} */; }};\n"
        text = text.replace(decl, decl +
            f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {name} */; }};\n", 1)
        phase = f"\t\t\t\t{sibling_build} /* {sibling} in Sources */,\n"
        text = text.replace(phase, phase + f"\t\t\t\t{build} /* {name} in Sources */,\n", 1)
    open(PROJECT, "w").write(text)
    print(f"+ {new_path} ({len(builds)} target{'s' if len(builds) != 1 else ''})")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    add(sys.argv[1], sys.argv[2])

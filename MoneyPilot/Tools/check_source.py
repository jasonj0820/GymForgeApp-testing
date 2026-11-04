"""Source integrity checks. NOT a Swift compiler or substitute for XCTest."""
from pathlib import Path
import re, plistlib, xml.etree.ElementTree as ET
root = Path(__file__).resolve().parent.parent
from tree_sitter import Language, Parser
import tree_sitter_swift
parser = Parser(Language(tree_sitter_swift.language()))
files = sorted(root.rglob('*.swift'))
for path in files:
    tree = parser.parse(path.read_bytes())
    def walk(node):
        assert node.type != 'ERROR' and not node.is_missing, (path.name, node.start_point, node.type)
        for child in node.children: walk(child)
    walk(tree.root_node)
    print(f'Swift syntax: {path.name} OK')
project = (root/'MoneyPilot.xcodeproj/project.pbxproj').read_text()
objects = set(re.findall(r'"([A-F0-9]{24})" = \{', project))
refs = set(re.findall(r'"([A-F0-9]{24})"', project))
assert refs <= objects, refs - objects
for path in files:
    assert f'"{path.name}"' in project, f'Missing source: {path.name}'
ET.parse(root/'MoneyPilot.xcodeproj/xcshareddata/xcschemes/MoneyPilot.xcscheme')
plistlib.loads((root/'MoneyPilot/PrivacyInfo.xcprivacy').read_bytes())
assert len(re.findall(r'func test\w+\(', (root/'MoneyPilotTests/EngineTests.swift').read_text())) == 74
print(f'Project integrity: {len(objects)} IDs, {len(files)} Swift files, shared scheme and privacy manifest OK')
print('74 XCTest cases present; NOT executed. Xcode build and on-device QA still required.')

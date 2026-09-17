#!/usr/bin/env python3
"""Execute the same XCTest test methods with plain Swift when XCTest is absent."""
from pathlib import Path
import re, subprocess, tempfile
root=Path(__file__).resolve().parent.parent
source=(root/'Tests/TrainingCoreTests/TrainingCoreTests.swift').read_text()
source=source.replace('import XCTest','import Foundation').replace('@testable import TrainingCore','')
stubs='''
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "Expected \\(a) == \\(b)", file: file, line: line) }
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) { precondition(abs(a-b) <= accuracy, "Expected \\(a) ~= \\(b)", file: file, line: line) }
func XCTAssertTrue(_ a: Bool, file: StaticString = #file, line: UInt = #line) { precondition(a, "Expected true", file: file, line: line) }
func XCTAssertFalse(_ a: Bool, file: StaticString = #file, line: UInt = #line) { precondition(!a, "Expected false", file: file, line: line) }
func XCTAssertNil<T>(_ a: T?, file: StaticString = #file, line: UInt = #line) { precondition(a == nil, "Expected nil", file: file, line: line) }
'''
names=re.findall(r'func (test\w+)\(\)',source)
with tempfile.TemporaryDirectory(prefix='healthlens-tests-') as temp:
 p=Path(temp)
 (p/'main.swift').write_text(stubs+source+'\nlet tests = TrainingCoreTests()\n'+'\n'.join(f'tests.{name}(); print("PASS {name}")' for name in names)+f'\nprint("{len(names)} core test cases passed")\n')
 subprocess.run(['swiftc','-module-cache-path',str(p/'cache'),str(root/'Sources/TrainingCore/TrainingCore.swift'),str(p/'main.swift'),'-o',str(p/'tests')],check=True)
 subprocess.run([str(p/'tests')],check=True)

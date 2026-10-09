"""Extracts every ```swift block of README.md and docs/ into examples/doc-snippets, so CI
compiles them. Blocks of declarations stay at file scope; other blocks become function bodies."""

import pathlib
import re
import shutil

root = pathlib.Path(__file__).resolve().parent.parent
out = root / "examples" / "doc-snippets"
shutil.rmtree(out, ignore_errors=True)
out.mkdir(parents=True)

declaration = re.compile(r"^(@|final class |class |struct |enum |actor |extension |protocol )")
features = (root / "Tests" / "Golden" / "SampleFeatures.swift.txt").read_text()
features = features[features.index("/// The features"):]

(out / "Prelude.swift").write_text(
    "import Entitler\nimport Foundation\n\n" + features + """
let key = "sk_test"
let server = try! EntitlerServer(key: key)
let customer = try! server.customer("user_123")
let client = try! EntitlerClient(token: "token")
let api = AppAPI()
let signIn = SignIn()
let service = try! EntitlerService()
let bundledKeys: [JSONWebKey] = []
let customerID = "user_123"
let environmentID = "env_1"
let userID = "user_123"
let visitorID = newVisitorID()
let visitorCookie: String? = nil
let jobID = "1"
let document = ""
let name = "Ada"
let email = "ada@example.com"

struct AppAPI {
  func entitlerToken() async throws -> String { "" }
}

struct SignIn {
  func currentIDToken() async throws -> String { "" }
}

func summarise(_ text: String) async throws -> (summary: String, tokens: Int64) { ("", 0) }

func exportPDF() async throws {}
""")

count = 0
for path in [root / "README.md", *sorted((root / "docs").glob("*.md"))]:
    blocks = re.findall(r"^```swift\n(.*?)^```", path.read_text(), flags=re.S | re.M)
    for index, block in enumerate(blocks):
        count += 1
        name = re.sub(r"\W", "_", path.stem) + f"_{index}"
        block = "".join(line for line in block.splitlines(True) if not line.startswith("import "))
        if declaration.match(block.lstrip()):
            body = block
        else:
            body = f"func snippet_{name}() async throws {{\n{block}}}\n"
        imports = "import Entitler\nimport Foundation\n"
        if ": View" in block or "ObservableObject" in block:
            body = f"#if canImport(SwiftUI)\nimport SwiftUI\n\n{body}#endif\n"
        (out / f"{name}.swift").write_text(imports + "\n" + body)
print(f"Extracted {count} snippets.")

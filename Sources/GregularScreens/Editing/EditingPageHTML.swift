/// The editing page, one self-contained file: no outside scripts, styles,
/// fonts or images, so the browser fetches nothing but this Apple TV. Every
/// name from the library is put on the page as text (`textContent`), never
/// as HTML, since names come from the server and are untrusted.
///
/// Its parts are plain files in `Page/`, compiled in: the web version
/// serves the same files as its channel editor (scripts/build-web.sh), so
/// both are one page.
enum EditingPageHTML {
    static let page = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="referrer" content="no-referrer">
    <title>Gregular TV channels</title>
    <style>
    \(text(PackageResources.editor_css))</style>
    </head>
    <body>
    \(text(PackageResources.editor_body_html))<script>
    \(text(PackageResources.editor_js))</script>
    </body>
    </html>

    """

    private static func text(_ bytes: [UInt8]) -> String {
        String(decoding: bytes, as: UTF8.self)
    }
}

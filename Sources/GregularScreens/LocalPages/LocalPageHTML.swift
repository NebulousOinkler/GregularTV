/// A page the Apple TV serves on the home network (`LocalPage`), as one
/// self-contained file: no outside scripts, styles, fonts or images, so the
/// browser fetches nothing but this Apple TV. Its parts are plain files,
/// compiled in, with `local-page.js` (what every such page shares) before
/// its own script.
enum LocalPageHTML {
    static func page(title: String, css: [UInt8], body: [UInt8], script: [UInt8]) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="no-referrer">
        <title>\(title)</title>
        <style>
        \(text(css))</style>
        </head>
        <body>
        \(text(body))<script>
        \(text(PackageResources.local_page_js))
        \(text(script))</script>
        </body>
        </html>

        """
    }

    private static func text(_ bytes: [UInt8]) -> String {
        String(decoding: bytes, as: UTF8.self)
    }
}

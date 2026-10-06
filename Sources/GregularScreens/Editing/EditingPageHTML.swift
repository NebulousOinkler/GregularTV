/// The editing page (`LocalPage.editing`). Its parts are plain files in
/// `Page/`: the web version serves the same files as its channel editor
/// (scripts/build-web.sh), so both are one page.
enum EditingPageHTML {
    static let page = LocalPageHTML.page(title: "Gregular TV channels", css: PackageResources.editor_css,
                                         body: PackageResources.editor_body_html, script: PackageResources.editor_js)
}

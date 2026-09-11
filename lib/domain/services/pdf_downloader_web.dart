// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:typed_data';
import 'dart:html' as html;

/// Web implementation: the ONLY reliable way to trigger a file download in
/// a browser is a Blob Object URL + an anchor with the `download`
/// attribute, clicked programmatically. `window.open()` and data: URIs are
/// both blocked by pop-up blockers or silently size-capped — see Defect
/// 14.4 in the rebuild blueprint for the five iterations that led here.
Future<bool> downloadOrPrintPdfBytes(
  Uint8List bytes,
  String filename, {
  String? htmlContent,
}) async {
  try {
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    Future.delayed(const Duration(seconds: 5), () => html.Url.revokeObjectUrl(url));
    return true;
  } catch (_) {
    return false;
  }
}

import '../../../core/constants/app_constants.dart';

/// The title and description of a session planned from an Inbox idea.
///
/// The title is the first non-empty line of the idea, trimmed and clipped to
/// [AppConstants.maxTaskTitleLength] UTF-16 units without splitting a
/// surrogate pair. The description is the remaining lines, trimmed, or null.
({String title, String? description}) inboxSessionText(String ideaText) {
  final lines = ideaText.split('\n');
  var index = 0;
  while (index < lines.length && lines[index].trim().isEmpty) {
    index++;
  }
  if (index >= lines.length) return (title: '', description: null);
  final title = clipUtf16(lines[index].trim(), AppConstants.maxTaskTitleLength);
  final rest = lines.sublist(index + 1).join('\n').trim();
  return (title: title, description: rest.isEmpty ? null : rest);
}

/// Clips [text] to at most [maxUnits] UTF-16 code units, never leaving half of
/// a surrogate pair at the end.
String clipUtf16(String text, int maxUnits) {
  if (text.length <= maxUnits) return text;
  var end = maxUnits;
  final last = text.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return text.substring(0, end);
}

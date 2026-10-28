// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'on_load_resource_batch_filter.dart';

// **************************************************************************
// ExchangeableObjectGenerator
// **************************************************************************

///Class that represents a filter that the batched implementation of the [PlatformWebViewCreationParams.onLoadResource] event
///(enabled with [InAppWebViewSettings.useBatchedOnLoadResource]) can apply directly inside the page,
///before the resource entries are buffered and sent to Dart, further reducing the number of messages.
///
///A `null` field means "don't filter on this criterion"; an empty list matches nothing.
///
///**NOTE**: this filter is used only if [InAppWebViewSettings.useOnLoadResource] and
///[InAppWebViewSettings.useBatchedOnLoadResource] are both `true`.
///
///**Officially Supported Platforms/Implementations**:
///- Android WebView
///- iOS WKWebView
///- macOS WKWebView
class OnLoadResourceBatchFilter {
  ///If non-`null`, only resource entries whose URL hostname is contained in this list are kept and batched.
  ///
  ///The comparison is case-insensitive and made against the `hostname` part of the resource URL
  ///(`"www.example.com"` does not match `"example.com"`; use both values if you want to keep both).
  ///Entries with an opaque or unparsable URL (such as `data:` or `blob:` URLs, whose hostname is empty)
  ///are dropped when a host filter is set.
  List<String>? hosts;

  ///If non-`null`, only resource entries whose `initiatorType` is contained in this list are kept and batched.
  ///
  ///Typical values are the ones returned by the JavaScript `PerformanceResourceTiming.initiatorType`,
  ///such as `"css"`, `"fetch"`, `"img"`, `"link"`, `"script"`, `"xmlhttprequest"`, `"video"`, `"audio"`, `"other"`.
  List<String>? initiatorTypes;

  ///
  ///**Officially Supported Platforms/Implementations**:
  ///- Android WebView
  ///- iOS WKWebView
  ///- macOS WKWebView
  OnLoadResourceBatchFilter({this.hosts, this.initiatorTypes});

  ///Gets a possible [OnLoadResourceBatchFilter] instance from a [Map] value.
  static OnLoadResourceBatchFilter? fromMap(
    Map<String, dynamic>? map, {
    EnumMethod? enumMethod,
  }) {
    if (map == null) {
      return null;
    }
    final instance = OnLoadResourceBatchFilter(
      hosts: map['hosts'] != null
          ? List<String>.from(map['hosts']!.cast<String>())
          : null,
      initiatorTypes: map['initiatorTypes'] != null
          ? List<String>.from(map['initiatorTypes']!.cast<String>())
          : null,
    );
    return instance;
  }

  ///Converts instance to a map.
  Map<String, dynamic> toMap({EnumMethod? enumMethod}) {
    return {"hosts": hosts, "initiatorTypes": initiatorTypes};
  }

  ///Converts instance to a map.
  Map<String, dynamic> toJson() {
    return toMap();
  }

  @override
  String toString() {
    return 'OnLoadResourceBatchFilter{hosts: $hosts, initiatorTypes: $initiatorTypes}';
  }
}

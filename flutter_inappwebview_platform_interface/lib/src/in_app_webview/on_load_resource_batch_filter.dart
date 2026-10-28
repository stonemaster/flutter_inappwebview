import 'package:flutter_inappwebview_internal_annotations/flutter_inappwebview_internal_annotations.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

part 'on_load_resource_batch_filter.g.dart';

///Class that represents a filter that the batched implementation of the [PlatformWebViewCreationParams.onLoadResource] event
///(enabled with [InAppWebViewSettings.useBatchedOnLoadResource]) can apply directly inside the page,
///before the resource entries are buffered and sent to Dart, further reducing the number of messages.
///
///A `null` field means "don't filter on this criterion"; an empty list matches nothing.
///
///**NOTE**: this filter is used only if [InAppWebViewSettings.useOnLoadResource] and
///[InAppWebViewSettings.useBatchedOnLoadResource] are both `true`.
@SupportedPlatforms(platforms: [
  AndroidPlatform(),
  IOSPlatform(),
  MacOSPlatform(),
])
@ExchangeableObject()
class OnLoadResourceBatchFilter_ {
  ///If non-`null`, only resource entries whose `initiatorType` is contained in this list are kept and batched.
  ///
  ///Typical values are the ones returned by the JavaScript `PerformanceResourceTiming.initiatorType`,
  ///such as `"css"`, `"fetch"`, `"img"`, `"link"`, `"script"`, `"xmlhttprequest"`, `"video"`, `"audio"`, `"other"`.
  List<String>? initiatorTypes;

  ///If non-`null`, only resource entries whose URL hostname is contained in this list are kept and batched.
  ///
  ///The comparison is case-insensitive and made against the `hostname` part of the resource URL
  ///(`"www.example.com"` does not match `"example.com"`; use both values if you want to keep both).
  ///Entries with an opaque or unparsable URL (such as `data:` or `blob:` URLs, whose hostname is empty)
  ///are dropped when a host filter is set.
  List<String>? hosts;

  OnLoadResourceBatchFilter_({this.initiatorTypes, this.hosts});
}

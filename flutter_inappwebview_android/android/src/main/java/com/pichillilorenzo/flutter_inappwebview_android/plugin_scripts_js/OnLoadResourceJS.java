package com.pichillilorenzo.flutter_inappwebview_android.plugin_scripts_js;

import androidx.annotation.Nullable;

import com.pichillilorenzo.flutter_inappwebview_android.types.PluginScript;
import com.pichillilorenzo.flutter_inappwebview_android.types.UserScriptInjectionTime;

import org.json.JSONObject;

import java.util.Map;
import java.util.Set;

public class OnLoadResourceJS {
  public static final String ON_LOAD_RESOURCE_JS_PLUGIN_SCRIPT_GROUP_NAME = "IN_APP_WEBVIEW_ON_LOAD_RESOURCE_JS_PLUGIN_SCRIPT";
  public static final String ON_LOAD_RESOURCE_BATCH_JS_PLUGIN_SCRIPT_GROUP_NAME = "IN_APP_WEBVIEW_ON_LOAD_RESOURCE_BATCH_JS_PLUGIN_SCRIPT";
  public static final String ON_LOAD_RESOURCE_BATCH_JS_MESSAGE_HANDLER_NAME = "onLoadResourceBatched";
  public static final String VAR_ON_LOAD_RESOURCE_BATCH_FILTER = "$IN_APP_WEBVIEW_ON_LOAD_RESOURCE_BATCH_FILTER";
  public static String FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_JS_SOURCE() {
    return
            JavaScriptBridgeJS.get_JAVASCRIPT_BRIDGE_NAME() + "._useOnLoadResource";
  }
  /**
   * Flag variable used to distinguish between the legacy per-event script and the batched one
   * when both could be present in the same page (e.g. runtime setting swap).
   */
  public static String FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_MODE_JS_SOURCE() {
    return
            JavaScriptBridgeJS.get_JAVASCRIPT_BRIDGE_NAME() + "._onLoadResourceMode";
  }
  /**
   * Flag variable containing the resource filter (as a JS object or {@code null})
   * applied by the batched script before buffering entries, set by {@code InAppWebViewSettings.onLoadResourceBatchFilter}.
   */
  public static String FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_BATCH_FILTER_JS_SOURCE() {
    return
            JavaScriptBridgeJS.get_JAVASCRIPT_BRIDGE_NAME() + "._onLoadResourceBatchFilter";
  }
  public static PluginScript ON_LOAD_RESOURCE_JS_PLUGIN_SCRIPT(@Nullable Set<String> allowedOriginRules,
                                                               boolean forMainFrameOnly) {
    return
            new PluginScript(
                    OnLoadResourceJS.ON_LOAD_RESOURCE_JS_PLUGIN_SCRIPT_GROUP_NAME,
                    OnLoadResourceJS.ON_LOAD_RESOURCE_JS_SOURCE(),
                    UserScriptInjectionTime.AT_DOCUMENT_START,
                    null,
                    false,
                    allowedOriginRules,
                    forMainFrameOnly
            );
  }

  /**
   * Batched version of the {@code onLoadResource} plugin script:
   * instead of doing a full generic JS-bridge round trip (Promise + JSON.stringify + bridge call +
   * method-channel reply via evaluateJavascript) for every PerformanceObserver entry,
   * entries are buffered and flushed in batches.
   * On WKWebView-based platforms the batch is sent through a dedicated message handler
   * ({@code onLoadResourceBatched}) with no Promise and no per-event reply;
   * on Android there are no dedicated message handlers, so it falls back to a single
   * {@code callHandler('onLoadResourceBatched', batch)} generic bridge call per batch
   * instead of one per resource.
   * An optional {@code filter} (the {@code InAppWebViewSettings.onLoadResourceBatchFilter} representation as a map)
   * drops unwanted entries directly inside the page before they are even buffered.
   */
  public static PluginScript ON_LOAD_RESOURCE_BATCH_JS_PLUGIN_SCRIPT(@Nullable Set<String> allowedOriginRules,
                                                                     boolean forMainFrameOnly,
                                                                     @Nullable Map<String, Object> filter) {
    return
            new PluginScript(
                    OnLoadResourceJS.ON_LOAD_RESOURCE_BATCH_JS_PLUGIN_SCRIPT_GROUP_NAME,
                    OnLoadResourceJS.ON_LOAD_RESOURCE_BATCH_JS_SOURCE(filter),
                    UserScriptInjectionTime.AT_DOCUMENT_START,
                    null,
                    false,
                    allowedOriginRules,
                    forMainFrameOnly
            );
  }

  /**
   * Returns the plugin script to use for the {@code useOnLoadResource} setting,
   * choosing between the batched implementation (default) and the legacy per-event one.
   */
  public static PluginScript onLoadResourcePluginScript(boolean useBatchedOnLoadResource,
                                                        @Nullable Map<String, Object> filter,
                                                        @Nullable Set<String> allowedOriginRules,
                                                        boolean forMainFrameOnly) {
    if (useBatchedOnLoadResource) {
      return ON_LOAD_RESOURCE_BATCH_JS_PLUGIN_SCRIPT(allowedOriginRules, forMainFrameOnly, filter);
    }
    return ON_LOAD_RESOURCE_JS_PLUGIN_SCRIPT(allowedOriginRules, forMainFrameOnly);
  }

  /**
   * Serializes the {@code onLoadResourceBatchFilter} setting as a JS object literal (or {@code null} when no filter is set).
   */
  public static String ON_LOAD_RESOURCE_BATCH_FILTER_JSON_SOURCE(@Nullable Map<String, Object> filter) {
    if (filter == null || filter.isEmpty()) {
      return "null";
    }
    try {
      return new JSONObject(filter).toString();
    } catch (Exception e) {
      return "null";
    }
  }

  public static String ON_LOAD_RESOURCE_JS_SOURCE() {
    String FLAG = "window." + FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_JS_SOURCE();
    String MODE = "window." + FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_MODE_JS_SOURCE();
    return
            FLAG + " = true;" +
                    MODE + " = 'legacy';" +
                    "(function() {" +
                    "   if (window.__flutterInAppWebviewOnLoadResourceLegacyInstalled) return;" +
                    "   window.__flutterInAppWebviewOnLoadResourceLegacyInstalled = true;" +
                    "   var observer = new PerformanceObserver(function(list) {" +
                    "       list.getEntries().forEach(function(entry) {" +
                    "         if ((" + FLAG + " == null || " + FLAG + " == true) && " + MODE + " != 'batched') {" +
                    "           var resource = {" +
                    "             'url': entry.name," +
                    "             'initiatorType': entry.initiatorType," +
                    "             'startTime': entry.startTime," +
                    "             'duration': entry.duration" +
                    "           };" +
                    "           window." + JavaScriptBridgeJS.get_JAVASCRIPT_BRIDGE_NAME() + ".callHandler('onLoadResource', resource);" +
                    "         }" +
                    "       });" +
                    "   });" +
                    "   observer.observe({entryTypes: ['resource']});" +
                    "})();";
  }

  public static String ON_LOAD_RESOURCE_BATCH_JS_SOURCE(@Nullable Map<String, Object> filter) {
    String FLAG = "window." + FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_JS_SOURCE();
    String MODE = "window." + FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_MODE_JS_SOURCE();
    String FILTER = "window." + FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_BATCH_FILTER_JS_SOURCE();
    String BRIDGE = JavaScriptBridgeJS.get_JAVASCRIPT_BRIDGE_NAME();
    String source =
            FLAG + " = true;" +
                    MODE + " = 'batched';" +
                    FILTER + " = " + VAR_ON_LOAD_RESOURCE_BATCH_FILTER + ";" +
                    "(function() {" +
                    "   if (window.__flutterInAppWebviewOnLoadResourceBatchInstalled) return;" +
                    "   window.__flutterInAppWebviewOnLoadResourceBatchInstalled = true;" +
                    "   var bridgeName = '" + BRIDGE + "';" +
                    "   var FLUSH_INTERVAL_MS = 150;" +
                    "   var MAX_BATCH_SIZE = 50;" +
                    "   var batch = [];" +
                    "   var flushTimer = null;" +
                    "   function isEnabled() {" +
                    "     var mode = " + MODE + ";" +
                    "     return mode == null || mode == undefined || mode == 'batched';" +
                    "   }" +
                    "   function matchesFilter(url, initiatorType) {" +
                    "     var filter = " + FILTER + ";" +
                    "     if (filter == null || typeof filter !== 'object') return true;" +
                    "     if (filter.initiatorTypes != null && filter.initiatorTypes.indexOf(initiatorType) < 0) return false;" +
                    "     if (filter.hosts != null) {" +
                    "       var host = null;" +
                    "       try { host = new URL(url).hostname; } catch (_) {}" +
                    "       if (host == null || host === '') return false;" +
                    "       host = ('' + host).toLowerCase();" +
                    "       for (var i = 0; i < filter.hosts.length; i++) {" +
                    "         var filterHost = ('' + filter.hosts[i]).toLowerCase();" +
                    "         if (host === filterHost || host.endsWith('.' + filterHost)) return true;" +
                    "       }" +
                    "       return false;" +
                    "     }" +
                    "     return true;" +
                    "   }" +
                    "   function sendBatch() {" +
                    "     if (flushTimer != null) {" +
                    "       clearTimeout(flushTimer);" +
                    "       flushTimer = null;" +
                    "     }" +
                    "     if (batch.length === 0) return;" +
                    "     if (" + FLAG + " == false || !isEnabled()) {" +
                    "       batch = [];" +
                    "       return;" +
                    "     }" +
                    "     var payload = batch;" +
                    "     batch = [];" +
                    "     var handler = null;" +
                    "     try {" +
                    "       handler = window.webkit.messageHandlers['" + ON_LOAD_RESOURCE_BATCH_JS_MESSAGE_HANDLER_NAME + "'];" +
                    "     } catch (_) {}" +
                    "     if (handler != null && handler.postMessage) {" +
                    "       var message = { batch: payload };" +
                    "       var windowId = window._" + BRIDGE + "_windowId;" +
                    "       if (windowId != null && windowId != undefined) {" +
                    "         message._windowId = windowId;" +
                    "       }" +
                    "       handler.postMessage(message);" +
                    "     } else if (window[bridgeName] != null && window[bridgeName].callHandler) {" +
                    "       window[bridgeName].callHandler('" + ON_LOAD_RESOURCE_BATCH_JS_MESSAGE_HANDLER_NAME + "', payload);" +
                    "     }" +
                    "   }" +
                    "   function scheduleFlush() {" +
                    "     if (flushTimer == null) {" +
                    "       flushTimer = setTimeout(sendBatch, FLUSH_INTERVAL_MS);" +
                    "     }" +
                    "   }" +
                    "   var observer = new PerformanceObserver(function(list) {" +
                    "     var entries = list.getEntries();" +
                    "     if (entries.length === 0) return;" +
                    "     if (" + FLAG + " == false || !isEnabled()) return;" +
                    "     for (var i = 0; i < entries.length; i++) {" +
                    "       var entry = entries[i];" +
                    "       if (!matchesFilter(entry.name, entry.initiatorType)) continue;" +
                    "       batch.push({" +
                    "         'url': entry.name," +
                    "         'initiatorType': entry.initiatorType," +
                    "         'startTime': entry.startTime," +
                    "         'duration': entry.duration" +
                    "       });" +
                    "     }" +
                    "     if (batch.length >= MAX_BATCH_SIZE) {" +
                    "       sendBatch();" +
                    "     } else if (batch.length > 0) {" +
                    "       scheduleFlush();" +
                    "     }" +
                    "   });" +
                    "   observer.observe({entryTypes: ['resource']});" +
                    "   document.addEventListener('pagehide', function() { sendBatch(); });" +
                    "})();";
    return source.replace(VAR_ON_LOAD_RESOURCE_BATCH_FILTER, ON_LOAD_RESOURCE_BATCH_FILTER_JSON_SOURCE(filter));
  }
}

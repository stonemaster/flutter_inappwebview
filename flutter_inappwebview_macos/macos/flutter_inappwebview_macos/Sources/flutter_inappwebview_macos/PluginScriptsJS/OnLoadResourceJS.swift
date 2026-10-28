//
//  resourceObserverJS.swift
//  flutter_inappwebview
//
//  Created by Lorenzo Pichilli on 16/02/21.
//

import Foundation

public class OnLoadResourceJS {
    
    public static let ON_LOAD_RESOURCE_JS_PLUGIN_SCRIPT_GROUP_NAME = "IN_APP_WEBVIEW_ON_LOAD_RESOURCE_JS_PLUGIN_SCRIPT"
    public static let ON_LOAD_RESOURCE_BATCH_JS_PLUGIN_SCRIPT_GROUP_NAME = "IN_APP_WEBVIEW_ON_LOAD_RESOURCE_BATCH_JS_PLUGIN_SCRIPT"
    public static let ON_LOAD_RESOURCE_BATCH_JS_MESSAGE_HANDLER_NAME = "onLoadResourceBatched"
    
    public static let VAR_ON_LOAD_RESOURCE_BATCH_FILTER = "$IN_APP_WEBVIEW_ON_LOAD_RESOURCE_BATCH_FILTER"
    
    public static func FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_JS_SOURCE() -> String {
        return "window.\(JavaScriptBridgeJS.get_JAVASCRIPT_BRIDGE_NAME())._useOnLoadResource"
    }
    
    /// Flag variable used to distinguish between the legacy per-event script and the batched one
    /// when both could be present in the same page (e.g. runtime setting swap).
    public static func FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_MODE_JS_SOURCE() -> String {
        return "window.\(JavaScriptBridgeJS.get_JAVASCRIPT_BRIDGE_NAME())._onLoadResourceMode"
    }
    
    /// Flag variable containing the resource filter (as a JS object or `null`)
    /// applied by the batched script before buffering entries, set by `InAppWebViewSettings.onLoadResourceBatchFilter`.
    public static func FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_BATCH_FILTER_JS_SOURCE() -> String {
        return "window.\(JavaScriptBridgeJS.get_JAVASCRIPT_BRIDGE_NAME())._onLoadResourceBatchFilter"
    }
    
    public static func ON_LOAD_RESOURCE_JS_PLUGIN_SCRIPT(allowedOriginRules: [String]?, forMainFrameOnly: Bool) -> PluginScript {
        return PluginScript(
            groupName: ON_LOAD_RESOURCE_JS_PLUGIN_SCRIPT_GROUP_NAME,
            source: ON_LOAD_RESOURCE_JS_SOURCE(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: forMainFrameOnly,
            allowedOriginRules: allowedOriginRules,
            requiredInAllContentWorlds: false,
            messageHandlerNames: [])
    }
    
    /// Batched version of the `onLoadResource` plugin script:
    /// instead of doing a full generic JS-bridge round trip (Promise + JSON.stringify + postMessage +
    /// method-channel reply via evaluateJavaScript) for every PerformanceObserver entry,
    /// entries are buffered and flushed in batches through a dedicated WKScriptMessageHandler
    /// (`onLoadResourceBatched`), with no Promise and no per-event reply.
    /// If the dedicated handler is not available (e.g. Android WebView or when the message handler
    /// registration is missing), it falls back to a single generic bridge call per batch
    /// (`callHandler('onLoadResourceBatched', batch)`), which is still one round trip per batch
    /// instead of one per resource.
    /// An optional `filter` (`InAppWebViewSettings.onLoadResourceBatchFilter` representation as a dictionary)
    /// drops unwanted entries directly inside the page before they are even buffered.
    public static func ON_LOAD_RESOURCE_BATCH_JS_PLUGIN_SCRIPT(allowedOriginRules: [String]?, forMainFrameOnly: Bool, filter: [String: Any?]? = nil) -> PluginScript {
        return PluginScript(
            groupName: ON_LOAD_RESOURCE_BATCH_JS_PLUGIN_SCRIPT_GROUP_NAME,
            source: ON_LOAD_RESOURCE_BATCH_JS_SOURCE(filter: filter),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: forMainFrameOnly,
            allowedOriginRules: allowedOriginRules,
            requiredInAllContentWorlds: false,
            messageHandlerNames: [ON_LOAD_RESOURCE_BATCH_JS_MESSAGE_HANDLER_NAME])
    }
    
    /// Returns the plugin script to use for the `useOnLoadResource` setting,
    /// choosing between the batched implementation (default) and the legacy per-event one.
    public static func onLoadResourcePluginScript(settings: InAppWebViewSettings, allowedOriginRules: [String]?, forMainFrameOnly: Bool) -> PluginScript {
        if settings.useBatchedOnLoadResource {
            return ON_LOAD_RESOURCE_BATCH_JS_PLUGIN_SCRIPT(allowedOriginRules: allowedOriginRules, forMainFrameOnly: forMainFrameOnly, filter: settings.onLoadResourceBatchFilter)
        }
        return ON_LOAD_RESOURCE_JS_PLUGIN_SCRIPT(allowedOriginRules: allowedOriginRules, forMainFrameOnly: forMainFrameOnly)
    }
    
    /// Serializes the `onLoadResourceBatchFilter` setting as a JS object literal (or `null` when no filter is set).
    public static func ON_LOAD_RESOURCE_BATCH_FILTER_JSON_SOURCE(filter: [String: Any?]?) -> String {
        guard let filter = filter, !filter.isEmpty else {
            return "null"
        }
        var sanitized: [String: Any] = [:]
        for (key, value) in filter {
            sanitized[key] = value ?? NSNull()
        }
        guard JSONSerialization.isValidJSONObject(sanitized),
              let data = try? JSONSerialization.data(withJSONObject: sanitized),
              let json = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return json
    }
    
    public static func ON_LOAD_RESOURCE_JS_SOURCE() -> String {
        return """
        \(FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_JS_SOURCE()) = true;
        \(FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_MODE_JS_SOURCE()) = 'legacy';
        (function() {
            if (window.__flutterInAppWebviewOnLoadResourceLegacyInstalled) return;
            window.__flutterInAppWebviewOnLoadResourceLegacyInstalled = true;
            var observer = new PerformanceObserver(function(list) {
                list.getEntries().forEach(function(entry) {
                    if ((\(FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_JS_SOURCE()) == null || \(FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_JS_SOURCE()) == true) && \(FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_MODE_JS_SOURCE()) != 'batched') {
                        var resource = {
                            "url": entry.name,
                            "initiatorType": entry.initiatorType,
                            "startTime": entry.startTime,
                            "duration": entry.duration
                        };
                        window.\(JavaScriptBridgeJS.get_JAVASCRIPT_BRIDGE_NAME()).callHandler("onLoadResource", resource);
                    }
                });
            });
            observer.observe({entryTypes: ['resource']});
        })();
        """
    }
    
    public static func ON_LOAD_RESOURCE_BATCH_JS_SOURCE(filter: [String: Any?]? = nil) -> String {
        let source = """
        \(FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_JS_SOURCE()) = true;
        \(FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_MODE_JS_SOURCE()) = 'batched';
        \(FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_BATCH_FILTER_JS_SOURCE()) = \(VAR_ON_LOAD_RESOURCE_BATCH_FILTER);
        (function() {
            if (window.__flutterInAppWebviewOnLoadResourceBatchInstalled) return;
            window.__flutterInAppWebviewOnLoadResourceBatchInstalled = true;
            var bridgeName = "\(JavaScriptBridgeJS.get_JAVASCRIPT_BRIDGE_NAME())";
            var FLUSH_INTERVAL_MS = 150;
            var MAX_BATCH_SIZE = 50;
            var batch = [];
            var flushTimer = null;
            function isEnabled() {
                var mode = \(FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_MODE_JS_SOURCE());
                return mode == null || mode == undefined || mode == 'batched';
            }
            function matchesFilter(url, initiatorType) {
                var filter = \(FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_BATCH_FILTER_JS_SOURCE());
                if (filter == null || typeof filter !== 'object') return true;
                if (filter.initiatorTypes != null && filter.initiatorTypes.indexOf(initiatorType) < 0) return false;
                if (filter.hosts != null) {
                    var host = null;
                    try { host = new URL(url).hostname; } catch (_) {}
                    if (host == null || host === '') return false;
                    host = ('' + host).toLowerCase();
                    for (var i = 0; i < filter.hosts.length; i++) {
                        var filterHost = ('' + filter.hosts[i]).toLowerCase();
                        if (host === filterHost || host.endsWith('.' + filterHost)) return true;
                    }
                    return false;
                }
                return true;
            }
            function sendBatch() {
                if (flushTimer != null) {
                    clearTimeout(flushTimer);
                    flushTimer = null;
                }
                if (batch.length === 0) return;
                if (\(FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_JS_SOURCE()) == false || !isEnabled()) {
                    batch = [];
                    return;
                }
                var payload = batch;
                batch = [];
                var handler = null;
                try {
                    handler = window.webkit.messageHandlers['\(ON_LOAD_RESOURCE_BATCH_JS_MESSAGE_HANDLER_NAME)'];
                } catch (_) {}
                if (handler != null && handler.postMessage) {
                    var message = { batch: payload };
                    var windowId = \(WindowIdJS.WINDOW_ID_VARIABLE_JS_SOURCE());
                    if (windowId != null && windowId != undefined) {
                        message._windowId = windowId;
                    }
                    handler.postMessage(message);
                } else if (window[bridgeName] != null && window[bridgeName].callHandler) {
                    window[bridgeName].callHandler('\(ON_LOAD_RESOURCE_BATCH_JS_MESSAGE_HANDLER_NAME)', payload);
                }
            }
            function scheduleFlush() {
                if (flushTimer == null) {
                    flushTimer = setTimeout(sendBatch, FLUSH_INTERVAL_MS);
                }
            }
            var observer = new PerformanceObserver(function(list) {
                var entries = list.getEntries();
                if (entries.length === 0) return;
                if (\(FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_JS_SOURCE()) == false || !isEnabled()) return;
                for (var i = 0; i < entries.length; i++) {
                    var entry = entries[i];
                    if (!matchesFilter(entry.name, entry.initiatorType)) continue;
                    batch.push({
                        "url": entry.name,
                        "initiatorType": entry.initiatorType,
                        "startTime": entry.startTime,
                        "duration": entry.duration
                    });
                }
                if (batch.length >= MAX_BATCH_SIZE) {
                    sendBatch();
                } else if (batch.length > 0) {
                    scheduleFlush();
                }
            });
            observer.observe({entryTypes: ['resource']});
            document.addEventListener('pagehide', function() { sendBatch(); });
        })();
        """
        return source.replacingOccurrences(of: VAR_ON_LOAD_RESOURCE_BATCH_FILTER,
                                           with: ON_LOAD_RESOURCE_BATCH_FILTER_JSON_SOURCE(filter: filter))
    }
}

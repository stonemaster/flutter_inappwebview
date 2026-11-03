//
//  ProxyManager.swift
//  flutter_inappwebview
//

import Foundation
import WebKit
import FlutterMacOS

@available(macOS 14.0, *)
public class ProxyManager: ChannelDelegate {
    static let METHOD_CHANNEL_NAME = "com.pichillilorenzo/flutter_inappwebview_proxycontroller"

    /// Inert oblivious-HTTP config appended to every proxy stack, making
    /// WebKit drop its existing sessions and connection pools on the
    /// change — see https://bugs.webkit.org/show_bug.cgi?id=316948 (and
    /// comment on `applyProxyConfigurations`).
    ///
    /// WebKit only recreates sessions when some stack entry requires HTTP
    /// protocols (`nw_proxy_config_stack_requires_http_protocols`), and
    /// only `nw_proxy_config_create_oblivious_http` entries satisfy that.
    /// Routing is unaffected: relay host and match domain are both
    /// unresolvable `.invalid` names.
    static let sessionRecreateTrigger: ProxyConfiguration = {
        let relay = ProxyConfiguration.RelayHop(
            http2RelayEndpoint: .url(URL(string: "https://unused-relay.invalid/")!)
        )
        let trigger = ProxyConfiguration(
            obliviousHTTPRelay: relay,
            relayResourcePath: "/gateway",
            gatewayKeyConfig: Data(count: 8),
            matchDomains: ["unused-match.invalid"]
        )
        return trigger
    }()

    private var plugin: InAppWebViewFlutterPlugin?

    init(plugin: InAppWebViewFlutterPlugin) {
        super.init(channel: FlutterMethodChannel(name: ProxyManager.METHOD_CHANNEL_NAME, binaryMessenger: plugin.registrar.messenger))
        self.plugin = plugin
    }

    public override func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any]
        switch call.method {
        case "setProxyOverride":
            if let args = arguments?["settings"] as? [String:Any?],
               let settings = ProxySettings.fromMap(map: args) {
                setProxyOverride(settings)
                result(true)
            } else {
                result(false)
            }
            break
        case "clearProxyOverride":
            clearProxyOverride()
            result(true)
            break
        default:
            result(FlutterMethodNotImplemented)
            break
        }
    }
    
    public func setProxyOverride(_ settings: ProxySettings) {
        applyProxyConfigurations(settings.toProxyConfigurations())
    }

    public func clearProxyOverride() {
        applyProxyConfigurations([])
    }

    /// Assigns `proxyConfigurations` on the stores shared by all webviews of
    /// the app, always appending an inert session-recreate trigger entry.
    ///
    /// WebKit bug 316948: assigning `proxyConfigurations` on a data store
    /// that is already in use does not tear down the network sessions and
    /// per-host connection pools already kept for that store — pools are
    /// keyed to the data store, not the web view, so they survive webview
    /// teardown too. That bites this embedder's use case of toggling a Tor
    /// proxy on localhost: after tunnel shutdown the cleared configuration
    /// leaves stale pooled connections through the (now dead)
    /// 127.0.0.1:<port> endpoint behind, and the webview can get stuck in a
    /// state where navigation keeps failing (CANNOT_CONNECT_TO_HOST) even
    /// though a fresh load would have picked up the cleared (direct)
    /// configuration. The same holds in the opposite direction: hosts with
    /// pooled direct connections bypass a newly set proxy.
    ///
    /// WebKit only discards existing sessions and connection pools when the
    /// assigned proxy stack contains an oblivious-HTTP entry, so — like
    /// Firefox iOS — every transition always appends the inert
    /// `sessionRecreateTrigger` below to force a clean release of stale
    /// pool state before the fresh configuration takes over.
    ///
    /// Caveat: with webviews alive this can cancel loads in flight while
    /// their old session is discarded; the embedder surfaces those as
    /// ordinary (retriable) navigation errors.
    private func applyProxyConfigurations(_ configurations: [ProxyConfiguration]) {
        var stack = configurations
        stack.append(ProxyManager.sessionRecreateTrigger)
        WKWebsiteDataStore.default().proxyConfigurations = stack
        WKWebsiteDataStore.nonPersistent().proxyConfigurations = stack
    }

    public override func dispose() {
        super.dispose()
        plugin = nil
    }

    deinit {
        debugPrint("ProxyManager - dealloc")
        dispose()
    }
}

@available(macOS 14.0, *)
public class ProxySettings {
    var proxyRules: [ProxyRule]

    init(
        proxyRules: [ProxyRule]
    ) {
        self.proxyRules = proxyRules
    }

    public static func fromMap(map: [String:Any?]?) -> ProxySettings? {
        guard let map = map else {
            return nil
        }
        return ProxySettings(
            proxyRules: (map["proxyRules"] as! [[String:Any?]]).map { ProxyRule.fromMap(map: $0)! }
        )
    }
    
    public func toProxyConfigurations() -> [ProxyConfiguration] {
        var proxyConfigurations: [ProxyConfiguration] = []
        for rule in proxyRules {
            if let proxyConfiguration = rule.toProxyConfiguration() {
                proxyConfigurations.append(proxyConfiguration)
            }
        }
        return proxyConfigurations
    }
}

@available(macOS 14.0, *)
public class ProxyRule {
    var url: String
    var allowFailover: Bool?
    var excludedDomains: [String]?
    var matchDomains: [String]?
    var username: String?
    var password: String?
    var relayHop1: ProxyRelayHop?
    var relayHop2: ProxyRelayHop?

    init(
        url: String,
        allowFailover: Bool?,
        excludedDomains: [String]?,
        matchDomains: [String]?,
        username: String?,
        password: String?,
        relayHop1: ProxyRelayHop?,
        relayHop2: ProxyRelayHop?
    ) {
        self.url = url
        self.allowFailover = allowFailover
        self.excludedDomains = excludedDomains
        self.matchDomains = matchDomains
        self.username = username
        self.password = password
        self.relayHop1 = relayHop1
        self.relayHop2 = relayHop2
    }

    public static func fromMap(map: [String:Any?]?) -> ProxyRule? {
        guard let map = map else {
            return nil
        }
        return ProxyRule(
            url: map["url"] as! String,
            allowFailover: map["allowFailover"] as? Bool,
            excludedDomains: map["excludedDomains"] as? [String],
            matchDomains: map["matchDomains"] as? [String],
            username: map["username"] as? String,
            password: map["password"] as? String,
            relayHop1: ProxyRelayHop.fromMap(map: map["relayHop1"] as? [String:Any?]),
            relayHop2: ProxyRelayHop.fromMap(map: map["relayHop2"] as? [String:Any?])
        )
    }
    
    public func toProxyConfiguration() -> ProxyConfiguration? {
        guard let endpointUrl = URL(string: url.contains("://") ? url : "http://" + url),
              let port: NWEndpoint.Port = .init(rawValue: UInt16(endpointUrl.port ?? 80)),
              let host = endpointUrl.host else {
            return nil
        }
        
        var endpointHost = NWEndpoint.Host(host)
        if let ipv4 = IPv4Address(host) {
            endpointHost = .ipv4(ipv4)
        } else if let ipv6 = IPv6Address(host) {
            endpointHost = .ipv6(ipv6)
        }
        let endpoint = NWEndpoint.hostPort(host: endpointHost, port: port)
        var proxyConfiguration: ProxyConfiguration
        let proxyRelayHops: [ProxyRelayHop] = [relayHop1, relayHop2].filter({ $0 != nil }).map({ $0! })
        if !proxyRelayHops.isEmpty {
            proxyConfiguration = ProxyConfiguration(relayHops: proxyRelayHops.compactMap({ $0.toRelayHop() }))
        } else {
            proxyConfiguration = endpointUrl.scheme?.lowercased() == "socks5" ?
            ProxyConfiguration(socksv5Proxy: endpoint) :
            ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: endpointUrl.scheme?.lowercased() == "https" ? .init() : nil)
        }

        if let allowFailover = allowFailover {
            proxyConfiguration.allowFailover = allowFailover
        }
        if let excludedDomains = excludedDomains {
            proxyConfiguration.excludedDomains = excludedDomains
        }
        if let matchDomains = matchDomains {
            proxyConfiguration.matchDomains = matchDomains
        }
        if let username = username, let password = password {
            proxyConfiguration.applyCredential(username: username, password: password)
        }
        return proxyConfiguration
    }
}

@available(macOS 14.0, *)
public class ProxyRelayHop {
    var http3RelayEndpoint: String?
    var http2RelayEndpoint: String?
    var additionalHTTPHeaders: [String:String]?
    
    init(
        http3RelayEndpoint: String,
        http2RelayEndpoint: String?,
        additionalHTTPHeaders: [String:String]?
    ) {
        self.http3RelayEndpoint = http3RelayEndpoint
        self.http2RelayEndpoint = http2RelayEndpoint
        self.additionalHTTPHeaders = additionalHTTPHeaders
    }
    
    init(
        http2RelayEndpoint: String,
        additionalHTTPHeaders: [String:String]?
    ) {
        self.http2RelayEndpoint = http2RelayEndpoint
        self.additionalHTTPHeaders = additionalHTTPHeaders
    }
    
    public static func fromMap(map: [String:Any?]?) -> ProxyRelayHop? {
        guard let map = map else {
            return nil
        }
        let http3RelayEndpoint = map["http3RelayEndpoint"] as? String
        let http2RelayEndpoint = map["http2RelayEndpoint"] as? String
        let additionalHTTPHeaders = map["additionalHTTPHeaders"] as? [String:String]
        if http3RelayEndpoint == nil, http2RelayEndpoint == nil {
            return nil
        }
        if http3RelayEndpoint != nil {
            return ProxyRelayHop(
                http3RelayEndpoint: http3RelayEndpoint!,
                http2RelayEndpoint: http2RelayEndpoint,
                additionalHTTPHeaders: additionalHTTPHeaders
            )
        }
        return ProxyRelayHop(
            http2RelayEndpoint: http2RelayEndpoint!,
            additionalHTTPHeaders: additionalHTTPHeaders
        )
    }
    
    public func toRelayHop() -> ProxyConfiguration.RelayHop? {
        if let http3RelayEndpoint = http3RelayEndpoint,
           let url = URL(string: http3RelayEndpoint) {
            var http2Endpoint: NWEndpoint? = nil
            if let http2RelayEndpoint = http2RelayEndpoint,
               let url2 = URL(string: http2RelayEndpoint) {
                http2Endpoint = NWEndpoint.url(url2)
            }
            return ProxyConfiguration.RelayHop(http3RelayEndpoint: NWEndpoint.url(url),
                                               http2RelayEndpoint: http2Endpoint,
                                               additionalHTTPHeaderFields: additionalHTTPHeaders ?? [:])
        }
        if let http2RelayEndpoint = http2RelayEndpoint,
           let url = URL(string: http2RelayEndpoint) {
            return ProxyConfiguration.RelayHop(http2RelayEndpoint: NWEndpoint.url(url),
                                               additionalHTTPHeaderFields: additionalHTTPHeaders ?? [:])
        }
        return nil
    }
}

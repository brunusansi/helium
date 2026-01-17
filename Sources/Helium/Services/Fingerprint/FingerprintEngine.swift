import Foundation
import WebKit

/// Engine for applying fingerprint spoofing to WebKit views
final class FingerprintEngine {
    static let shared = FingerprintEngine()
    
    private init() {}
    
    /// Generate JavaScript injection code for fingerprint spoofing
    func generateInjectionScript(config: FingerprintConfig) -> String {
        """
        (function() {
            'use strict';
            
            // ========================================
            // Navigator Overrides
            // ========================================
            
            const navigatorOverrides = {
                hardwareConcurrency: \(config.hardwareConcurrency),
                deviceMemory: \(config.deviceMemory),
                platform: '\(config.platform.navigator)',
                vendor: '\(config.vendor)',
                language: '\(config.languages.first ?? "en-US")',
                languages: \(config.languages.map { "'\($0)'" }.joined(separator: ", ").wrapped(in: "[")),
            };
            
            for (const [key, value] of Object.entries(navigatorOverrides)) {
                Object.defineProperty(Navigator.prototype, key, {
                    get: () => value,
                    configurable: true
                });
            }
            
            // ========================================
            // Screen Overrides
            // ========================================
            
            const screenOverrides = {
                width: \(config.screenWidth),
                height: \(config.screenHeight),
                availWidth: \(config.screenWidth),
                availHeight: \(config.screenHeight - 25),
                colorDepth: \(config.colorDepth),
                pixelDepth: \(config.colorDepth),
            };
            
            for (const [key, value] of Object.entries(screenOverrides)) {
                Object.defineProperty(Screen.prototype, key, {
                    get: () => value,
                    configurable: true
                });
            }
            
            Object.defineProperty(window, 'devicePixelRatio', {
                get: () => \(config.pixelRatio),
                configurable: true
            });
            
            // ========================================
            // WebGL Fingerprint Protection
            // ========================================
            
            const webglVendor = '\(config.webglVendor)';
            const webglRenderer = '\(config.webglRenderer)';
            const unmaskedVendor = '\(config.webglUnmaskedVendor)';
            const unmaskedRenderer = '\(config.webglUnmaskedRenderer)';
            
            const getParameterOriginal = WebGLRenderingContext.prototype.getParameter;
            WebGLRenderingContext.prototype.getParameter = function(parameter) {
                const UNMASKED_VENDOR_WEBGL = 0x9245;
                const UNMASKED_RENDERER_WEBGL = 0x9246;
                
                if (parameter === UNMASKED_VENDOR_WEBGL) return unmaskedVendor;
                if (parameter === UNMASKED_RENDERER_WEBGL) return unmaskedRenderer;
                if (parameter === this.VENDOR) return webglVendor;
                if (parameter === this.RENDERER) return webglRenderer;
                
                return getParameterOriginal.call(this, parameter);
            };
            
            // WebGL2
            if (window.WebGL2RenderingContext) {
                const getParameter2Original = WebGL2RenderingContext.prototype.getParameter;
                WebGL2RenderingContext.prototype.getParameter = function(parameter) {
                    const UNMASKED_VENDOR_WEBGL = 0x9245;
                    const UNMASKED_RENDERER_WEBGL = 0x9246;
                    
                    if (parameter === UNMASKED_VENDOR_WEBGL) return unmaskedVendor;
                    if (parameter === UNMASKED_RENDERER_WEBGL) return unmaskedRenderer;
                    if (parameter === this.VENDOR) return webglVendor;
                    if (parameter === this.RENDERER) return webglRenderer;
                    
                    return getParameter2Original.call(this, parameter);
                };
            }
            
            // ========================================
            // Canvas Fingerprint Protection
            // ========================================
            
            const canvasNoise = \(config.canvasNoise);
            
            const originalToDataURL = HTMLCanvasElement.prototype.toDataURL;
            HTMLCanvasElement.prototype.toDataURL = function(type, quality) {
                const ctx = this.getContext('2d');
                if (ctx && canvasNoise > 0) {
                    const imageData = ctx.getImageData(0, 0, this.width, this.height);
                    const data = imageData.data;
                    for (let i = 0; i < data.length; i += 4) {
                        data[i] = Math.max(0, Math.min(255, data[i] + (Math.random() - 0.5) * canvasNoise * 255));
                        data[i+1] = Math.max(0, Math.min(255, data[i+1] + (Math.random() - 0.5) * canvasNoise * 255));
                        data[i+2] = Math.max(0, Math.min(255, data[i+2] + (Math.random() - 0.5) * canvasNoise * 255));
                    }
                    ctx.putImageData(imageData, 0, 0);
                }
                return originalToDataURL.call(this, type, quality);
            };
            
            const originalGetImageData = CanvasRenderingContext2D.prototype.getImageData;
            CanvasRenderingContext2D.prototype.getImageData = function(sx, sy, sw, sh) {
                const imageData = originalGetImageData.call(this, sx, sy, sw, sh);
                if (canvasNoise > 0) {
                    const data = imageData.data;
                    for (let i = 0; i < data.length; i += 4) {
                        data[i] = Math.max(0, Math.min(255, data[i] + (Math.random() - 0.5) * canvasNoise * 255));
                        data[i+1] = Math.max(0, Math.min(255, data[i+1] + (Math.random() - 0.5) * canvasNoise * 255));
                        data[i+2] = Math.max(0, Math.min(255, data[i+2] + (Math.random() - 0.5) * canvasNoise * 255));
                    }
                }
                return imageData;
            };
            
            // ========================================
            // Audio Fingerprint Protection
            // ========================================
            
            const audioNoise = \(config.audioNoise);
            
            if (window.AudioContext || window.webkitAudioContext) {
                const AudioCtx = window.AudioContext || window.webkitAudioContext;
                const originalCreateAnalyser = AudioCtx.prototype.createAnalyser;
                
                AudioCtx.prototype.createAnalyser = function() {
                    const analyser = originalCreateAnalyser.call(this);
                    const originalGetFloatFrequencyData = analyser.getFloatFrequencyData.bind(analyser);
                    
                    analyser.getFloatFrequencyData = function(array) {
                        originalGetFloatFrequencyData(array);
                        if (audioNoise > 0) {
                            for (let i = 0; i < array.length; i++) {
                                array[i] += (Math.random() - 0.5) * audioNoise * 100;
                            }
                        }
                    };
                    
                    return analyser;
                };
            }
            
            // ========================================
            // WebRTC Protection
            // ========================================
            
            \(generateWebRTCProtection(policy: config.webrtcPolicy))
            
            // ========================================
            // Media Devices Spoofing
            // ========================================
            
            const mediaDevices = {
                audioInputs: \(config.mediaDevices.audioInputs),
                audioOutputs: \(config.mediaDevices.audioOutputs),
                videoInputs: \(config.mediaDevices.videoInputs)
            };
            
            if (navigator.mediaDevices && navigator.mediaDevices.enumerateDevices) {
                const originalEnumerateDevices = navigator.mediaDevices.enumerateDevices.bind(navigator.mediaDevices);
                
                navigator.mediaDevices.enumerateDevices = async function() {
                    const devices = [];
                    
                    for (let i = 0; i < mediaDevices.audioInputs; i++) {
                        devices.push({
                            deviceId: 'audio-input-' + i,
                            groupId: 'audio-group-' + i,
                            kind: 'audioinput',
                            label: i === 0 ? 'Built-in Microphone' : 'Microphone ' + (i + 1)
                        });
                    }
                    
                    for (let i = 0; i < mediaDevices.audioOutputs; i++) {
                        devices.push({
                            deviceId: 'audio-output-' + i,
                            groupId: 'audio-group-' + i,
                            kind: 'audiooutput',
                            label: i === 0 ? 'Built-in Speakers' : 'Speakers ' + (i + 1)
                        });
                    }
                    
                    for (let i = 0; i < mediaDevices.videoInputs; i++) {
                        devices.push({
                            deviceId: 'video-input-' + i,
                            groupId: 'video-group-' + i,
                            kind: 'videoinput',
                            label: i === 0 ? 'FaceTime HD Camera' : 'Camera ' + (i + 1)
                        });
                    }
                    
                    return devices;
                };
            }
            
            // ========================================
            // Timezone Spoofing
            // ========================================
            
            \(generateTimezoneOverride(config: config.timezone))
            
            // ========================================
            // Geolocation Spoofing
            // ========================================
            
            \(generateGeolocationOverride(config: config.geolocation))
            
            // ========================================
            // Plugin/MIME Type Spoofing (Safari typical)
            // ========================================
            
            Object.defineProperty(Navigator.prototype, 'plugins', {
                get: () => {
                    return {
                        length: 0,
                        item: () => null,
                        namedItem: () => null,
                        refresh: () => {}
                    };
                },
                configurable: true
            });
            
            Object.defineProperty(Navigator.prototype, 'mimeTypes', {
                get: () => {
                    return {
                        length: 0,
                        item: () => null,
                        namedItem: () => null
                    };
                },
                configurable: true
            });
            
            console.log('[Helium] Fingerprint protection active');
        })();
        """
    }
    
    private func generateWebRTCProtection(policy: WebRTCPolicy) -> String {
        switch policy {
        case .disableNonProxiedUdp:
            return """
            if (window.RTCPeerConnection) {
                const OriginalRTCPeerConnection = window.RTCPeerConnection;
                
                window.RTCPeerConnection = function(config, constraints) {
                    if (config && config.iceServers) {
                        config.iceServers = [];
                    }
                    config = config || {};
                    config.iceTransportPolicy = 'relay';
                    
                    return new OriginalRTCPeerConnection(config, constraints);
                };
                
                window.RTCPeerConnection.prototype = OriginalRTCPeerConnection.prototype;
            }
            """
        case .defaultPublicInterfaceOnly:
            return """
            if (window.RTCPeerConnection) {
                const OriginalRTCPeerConnection = window.RTCPeerConnection;
                
                window.RTCPeerConnection = function(config, constraints) {
                    if (config && config.iceServers) {
                        config.iceServers = config.iceServers.filter(s => !s.urls.includes('stun:'));
                    }
                    return new OriginalRTCPeerConnection(config, constraints);
                };
                
                window.RTCPeerConnection.prototype = OriginalRTCPeerConnection.prototype;
            }
            """
        default:
            return "// WebRTC: Using default policy"
        }
    }
    
    private func generateTimezoneOverride(config: TimezoneConfig) -> String {
        switch config {
        case .auto:
            return "// Timezone: Using system timezone"
        case .matchProxy:
            return "// Timezone: Will be set dynamically based on proxy location"
        case .custom(let timezone, let offset):
            return """
            const targetTimezone = '\(timezone)';
            const targetOffset = \(offset);
            
            const OriginalDate = Date;
            const offsetDiff = (new OriginalDate().getTimezoneOffset() - targetOffset) * 60 * 1000;
            
            window.Date = function(...args) {
                if (args.length === 0) {
                    const d = new OriginalDate();
                    d.setTime(d.getTime() + offsetDiff);
                    return d;
                }
                return new OriginalDate(...args);
            };
            
            window.Date.prototype = OriginalDate.prototype;
            window.Date.now = () => OriginalDate.now() + offsetDiff;
            window.Date.parse = OriginalDate.parse;
            window.Date.UTC = OriginalDate.UTC;
            
            const originalResolvedOptions = Intl.DateTimeFormat.prototype.resolvedOptions;
            Intl.DateTimeFormat.prototype.resolvedOptions = function() {
                const result = originalResolvedOptions.call(this);
                result.timeZone = targetTimezone;
                return result;
            };
            """
        }
    }
    
    private func generateGeolocationOverride(config: GeolocationConfig) -> String {
        switch config {
        case .auto:
            return "// Geolocation: Using real location"
        case .disabled:
            return """
            navigator.geolocation.getCurrentPosition = function(success, error, options) {
                if (error) {
                    error({ code: 1, message: 'User denied Geolocation' });
                }
            };
            navigator.geolocation.watchPosition = function(success, error, options) {
                if (error) {
                    error({ code: 1, message: 'User denied Geolocation' });
                }
                return 0;
            };
            """
        case .matchProxy:
            return "// Geolocation: Will be set dynamically based on proxy location"
        case .custom(let lat, let lon, let accuracy):
            return """
            const spoofedPosition = {
                coords: {
                    latitude: \(lat),
                    longitude: \(lon),
                    accuracy: \(accuracy),
                    altitude: null,
                    altitudeAccuracy: null,
                    heading: null,
                    speed: null
                },
                timestamp: Date.now()
            };
            
            navigator.geolocation.getCurrentPosition = function(success, error, options) {
                success(spoofedPosition);
            };
            
            navigator.geolocation.watchPosition = function(success, error, options) {
                success(spoofedPosition);
                return 1;
            };
            """
        }
    }
    
    /// Create a WKUserScript for injection
    func createUserScript(config: FingerprintConfig) -> WKUserScript {
        let source = generateInjectionScript(config: config)
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }
}

// MARK: - String Extension

private extension String {
    func wrapped(in wrapper: String) -> String {
        let close = wrapper == "[" ? "]" : (wrapper == "{" ? "}" : wrapper)
        return "\(wrapper)\(self)\(close)"
    }
}

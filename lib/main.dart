import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chromecast_dlna_finder/chromecast_dlna_finder.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io' show Platform;

// --- AdMob Configuration ---
// TODO: IMPORTANT! Replace with your real AdMob App ID in AndroidManifest.xml and Info.plist
// Test IDs are used here for development purposes.
final String adUnitIdBanner = Platform.isAndroid
    ? 'ca-app-pub-3940256099942544/6300978111' // Test ID
    : 'ca-app-pub-3940256099942544/2934735716'; // Test ID
final String adUnitIdInterstitial = Platform.isAndroid
    ? 'ca-app-pub-3940256099942544/1033173712' // Test ID
    : 'ca-app-pub-3940256099942544/4411468910'; // Test ID
final String adUnitIdAppOpen = Platform.isAndroid
    ? 'ca-app-pub-3940256099942544/9257395921' // Test ID
    : 'ca-app-pub-3940256099942544/5575463023'; // Test ID

// --- Global Variables & Constants ---
const String appTitle = 'Cast to TV Screen';
const Duration maxAdCacheDuration = Duration(hours: 4);
const String platformChannelName = 'com.example.casttotvscreen/casting';

// --- Main Entry Point ---
void main() {
  // Ensure Flutter bindings are initialized for plugin use before runApp
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Google Mobile Ads SDK
  MobileAds.instance.initialize();
  runApp(const MyApp());
}

// --- Root Application Widget ---
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  AppOpenAd? _appOpenAd;
  bool _isShowingAppOpenAd = false;
  DateTime? _appOpenLoadTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAppOpenAd();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appOpenAd?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Try to show App Open Ad when the app resumes from background
    if (state == AppLifecycleState.resumed) {
      _showAppOpenAd();
    }
  }

  /// Load an AppOpenAd.
  void _loadAppOpenAd() {
    AppOpenAd.load(
      adUnitId: adUnitIdAppOpen,
      orientation: AppOpenAd.orientationPortrait,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          print('[AdMob] AppOpenAd loaded.');
          _appOpenLoadTime = DateTime.now();
          _appOpenAd = ad;
          // Do not show immediately, wait for app resume
        },
        onAdFailedToLoad: (error) {
          print('[AdMob] AppOpenAd failed to load: $error');
        },
      ),
    );
  }

  /// Shows an AppOpenAd if available and not already showing.
  void _showAppOpenAd() {
    if (_appOpenAd == null) {
      print('[AdMob] Warning: AppOpenAd is null, attempting to load.');
      _loadAppOpenAd();
      return;
    }
    if (_isShowingAppOpenAd) {
      print('[AdMob] Warning: Tried to show AppOpenAd while already showing.');
      return;
    }
    if (DateTime.now().difference(_appOpenLoadTime ?? DateTime.now()) > maxAdCacheDuration) {
      print('[AdMob] AppOpenAd expired, loading new one.');
      _appOpenAd!.dispose();
      _appOpenAd = null;
      _loadAppOpenAd();
      return;
    }

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _isShowingAppOpenAd = true;
        print('[AdMob] AppOpenAd showed.');
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        print('[AdMob] AppOpenAd failed to show: $error');
        _isShowingAppOpenAd = false;
        ad.dispose();
        _appOpenAd = null;
        _loadAppOpenAd(); // Try loading again
      },
      onAdDismissedFullScreenContent: (ad) {
        print('[AdMob] AppOpenAd dismissed.');
        _isShowingAppOpenAd = false;
        ad.dispose();
        _appOpenAd = null;
        _loadAppOpenAd(); // Load the next ad
      },
    );

    _appOpenAd!.show();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        )
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false, // Hide debug banner
    );
  }
}

// --- Home Page Widget ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Platform Channel
  static const platform = MethodChannel(platformChannelName);

  // State Variables
  String _connectionStatus = 'Initializing...';
  List<CastDevice> _discoveredDevices = [];
  bool _isDiscovering = false;
  bool _isConnecting = false;
  bool _isCasting = false;
  CastDevice? _selectedDevice;
  StreamSubscription? _discoverySubscription;
  final ChromeCastDiscovery _discoveryService = ChromeCastDiscovery();
  bool _permissionsGranted = false;

  // AdMob Ads
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  InterstitialAd? _interstitialAd;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndInitializeApp();
  }

  @override
  void dispose() {
    _stopDiscovery(); // Ensure discovery stops
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    // Attempt to stop casting if the widget is disposed while casting
    if (_isCasting) {
      _stopCastingNative(showStatusUpdate: false); // Don't update UI on dispose
    }
    super.dispose();
  }

  // --- Permission Handling ---
  Future<void> _requestPermissionsAndInitializeApp() async {
    setState(() { _connectionStatus = 'Requesting Permissions...'; });

    // Request location permission (often needed for network discovery)
    var locationStatus = await Permission.locationWhenInUse.request();

    if (locationStatus.isGranted) {
       if (mounted) {
           setState(() {
             _permissionsGranted = true;
             _connectionStatus = 'Permissions Granted. Initializing...';
           });
           // Proceed with app initialization
           _initializeAds();
           _startDiscovery();
       }
    } else {
        if (mounted) {
            setState(() {
              _permissionsGranted = false;
              _connectionStatus = 'Location Permission Denied.';
            });
            _showPermissionDeniedDialog('Location permission is required to discover devices on your network.');
        }
    }
    // Note: Screen Capture permission is requested natively via MediaProjectionManager
  }

  void _showPermissionDeniedDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text('Open Settings'),
            onPressed: () {
              openAppSettings();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  // --- AdMob Integration ---
  void _initializeAds() {
    if (!_permissionsGranted) return;
    _loadBannerAd();
    _loadInterstitialAd();
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: adUnitIdBanner,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          print('[AdMob] BannerAd loaded.');
          if (mounted) setState(() => _isBannerAdLoaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          print('[AdMob] BannerAd failed to load: $err');
          ad.dispose();
          if (mounted) setState(() => _isBannerAdLoaded = false);
        },
        onAdClicked: (ad) => print('[AdMob] BannerAd clicked.'),
        onAdImpression: (ad) => print('[AdMob] BannerAd impression.'),
      ),
    )..load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: adUnitIdInterstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          print('[AdMob] InterstitialAd loaded.');
          _interstitialAd = ad;
          _setupInterstitialAdCallbacks();
        },
        onAdFailedToLoad: (err) {
          print('[AdMob] InterstitialAd failed to load: $err');
          _interstitialAd = null; // Ensure it's null on failure
        },
      ),
    );
  }

  void _setupInterstitialAdCallbacks() {
      _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (ad) => print('[AdMob] InterstitialAd showed.'),
        onAdDismissedFullScreenContent: (ad) {
          print('[AdMob] InterstitialAd dismissed.');
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitialAd(); // Preload the next one
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          print('[AdMob] InterstitialAd failed to show: $error');
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitialAd(); // Try loading again
        },
        onAdImpression: (ad) => print('[AdMob] InterstitialAd impression.'),
        onAdClicked: (ad) => print('[AdMob] InterstitialAd clicked.'),
      );
  }

  void _showInterstitialAd() {
    if (_interstitialAd == null) {
      print('[AdMob] Warning: InterstitialAd not ready, attempting to load.');
      _loadInterstitialAd(); // Try to load if not available
      return; // Don't proceed to show
    }
    _interstitialAd!.show();
    // Ad object will be replaced in the dismiss callback
  }

  // --- Device Discovery ---
  void _startDiscovery() {
    if (_isDiscovering || !_permissionsGranted) return;
    print('Starting device discovery...');
    if (mounted) {
        setState(() {
          _isDiscovering = true;
          _discoveredDevices = [];
          _connectionStatus = 'Discovering Devices...';
          _selectedDevice = null;
          _isCasting = false;
        });
    }

    // Cancel previous subscription if any
    _discoverySubscription?.cancel();

    _discoverySubscription = _discoveryService.discoverDevices().handleError((error) {
        print('Discovery Error: $error');
        if (mounted) {
            setState(() {
              _connectionStatus = 'Discovery Error. Check Network/Permissions.';
              _isDiscovering = false;
            });
        }
    }).listen((device) {
        print('Device Found: ${device.name} at ${device.host}');
        if (mounted && !_discoveredDevices.any((d) => d.id == device.id)) {
            setState(() {
              _discoveredDevices.add(device);
              // Update status if it was previously 'No devices found'
              if (_connectionStatus == 'No devices found') {
                  _connectionStatus = 'Select a device';
              }
            });
        }
    }, onDone: () {
        print('Discovery finished.');
        if (mounted) {
            setState(() {
              _isDiscovering = false;
              if (_discoveredDevices.isEmpty) {
                _connectionStatus = 'No devices found. Tap refresh.';
              } else if (!_isCasting && _selectedDevice == null) {
                 _connectionStatus = 'Select a device';
              }
            });
        }
    });

    // Add a timeout for discovery
    Future.delayed(const Duration(seconds: 15), () {
        if (_isDiscovering && mounted) {
            print('Discovery timed out.');
            _stopDiscovery();
             if (_discoveredDevices.isEmpty) {
                setState(() => _connectionStatus = 'Discovery Timeout. No devices found.');
             } else {
                 setState(() => _connectionStatus = 'Select a device');
             }
        }
    });
  }

  void _stopDiscovery() {
    if (!_isDiscovering) return;
    print('Stopping device discovery...');
    _discoverySubscription?.cancel();
    _discoverySubscription = null;
    if (mounted) {
      setState(() {
        _isDiscovering = false;
        // Avoid overwriting meaningful status like 'Connected' or 'Error'
        if (_connectionStatus.startsWith('Discovering')) {
          _connectionStatus = 'Discovery Stopped.';
        }
      });
    }
  }

  // --- Casting Logic (via Platform Channel) ---
  Future<void> _connectAndCast(CastDevice device) async {
    if (!_permissionsGranted) {
      _showPermissionDeniedDialog('Permissions are required to cast.');
      return;
    }
    if (_isConnecting || _isCasting) {
        print('Already connecting or casting.');
        return;
    }

    print('Attempting to cast to ${device.name}');
    if (mounted) {
        setState(() {
          _selectedDevice = device;
          _isConnecting = true;
          _connectionStatus = 'Connecting to ${device.name}...
(Requires Screen Capture Permission)';
        });
    }

    // Show interstitial ad before starting the cast process
    _showInterstitialAd();

    try {
      // Call native method - this might trigger native permission dialogs (e.g., screen capture)
      final bool? result = await platform.invokeMethod<bool>('startScreenMirroring', {
        'deviceId': device.id, // Pass necessary info
        'deviceName': device.name,
        'deviceHost': device.host,
        'devicePort': device.port,
      });

      if (mounted) {
        setState(() {
          _isConnecting = false;
          if (result == true) {
            _isCasting = true;
            _connectionStatus = 'Casting to ${device.name}';
            print('Successfully started casting to ${device.name}');
          } else {
            // Handle failure: Could be permission denial, network issue, or native error
            _isCasting = false;
            _selectedDevice = null;
            _connectionStatus = 'Failed to start casting. (Permission denied or error)';
            print('Failed to start casting. Result: $result');
            // Optionally show a more specific error dialog
          }
        });
      }
    } on PlatformException catch (e) {
      print('PlatformException during casting: ${e.message}');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isCasting = false;
          _selectedDevice = null;
          _connectionStatus = "Failed to cast: ${e.message ?? 'Unknown platform error'}";
        });
      }
    } catch (e) {
        print('Unexpected error during casting: $e');
         if (mounted) {
            setState(() {
              _isConnecting = false;
              _isCasting = false;
              _selectedDevice = null;
              _connectionStatus = "Failed to cast: Unexpected error.";
            });
         }
    }
  }

  Future<void> _stopCastingNative({bool showStatusUpdate = true}) async {
    if (!_isCasting && _selectedDevice == null) {
        print('Not casting, nothing to stop.');
        return; // Nothing to stop
    }

    String stoppingDeviceName = _selectedDevice?.name ?? 'the device';
    print('Attempting to stop casting on $stoppingDeviceName');
    if (mounted && showStatusUpdate) {
      setState(() {
        // Keep _selectedDevice for context, but mark as not casting immediately
        _isCasting = false;
        _isConnecting = false; // Ensure connecting is false
        _connectionStatus = 'Stopping cast on $stoppingDeviceName...';
      });
    }

    try {
      // Call native method to stop casting
      await platform.invokeMethod('stopCasting');
      print('Successfully stopped casting.');
      if (mounted && showStatusUpdate) {
        setState(() {
          _connectionStatus = 'Disconnected';
          _selectedDevice = null;
          _isCasting = false;
          _isConnecting = false;
          // Restart discovery to find devices again
          _startDiscovery();
        });
      }
    } on PlatformException catch (e) {
      print('PlatformException during stop casting: ${e.message}');
      if (mounted && showStatusUpdate) {
        setState(() {
          // Even on failure, reset state to disconnected
          _connectionStatus = "Failed to stop cast cleanly: ${e.message ?? 'Unknown error'}. Resetting...";
          _selectedDevice = null;
          _isCasting = false;
          _isConnecting = false;
          _startDiscovery(); // Try discovering again
        });
      }
    } catch (e) {
        print('Unexpected error during stop casting: $e');
         if (mounted && showStatusUpdate) {
            setState(() {
              _connectionStatus = "Failed to stop cast: Unexpected error. Resetting...";
              _selectedDevice = null;
              _isCasting = false;
              _isConnecting = false;
              _startDiscovery();
            });
         }
    }
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(appTitle),
        actions: [
          // Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh),
            // Disable refresh if discovering, connecting, or permissions not granted
            onPressed: _isDiscovering || _isConnecting || !_permissionsGranted ? null : _startDiscovery,
            tooltip: 'Refresh Devices',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // --- Cast/Disconnect Button ---
            ElevatedButton.icon(
              // Enable disconnect only if currently casting.
              // Disable connect/disconnect if connecting or permissions missing.
              onPressed: _isConnecting || !_permissionsGranted ? null : (_isCasting ? _stopCastingNative : null),
              icon: _isConnecting
                  ? Container(
                      width: 24, height: 24,
                      padding: const EdgeInsets.all(2.0),
                      child: const CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                    )
                  : Icon(_isCasting ? Icons.cast_connected : Icons.cast, size: 30),
              label: Text(
                  _isConnecting ? 'Connecting...' :
                  (_isCasting ? 'Disconnect' :
                  (_permissionsGranted ? 'Select a Device Below' : 'Permissions Required')),
                  style: const TextStyle(fontSize: 18)
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: _isCasting ? Colors.redAccent : (_permissionsGranted ? Colors.deepPurple : Colors.grey),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),

            // --- Status Display ---
            Text(
              'Status: $_connectionStatus',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // --- Device List Section ---
            Text(
              'Available Devices:',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _buildDeviceList(),
            ),
            const SizedBox(height: 8),

            // --- Ad Banner ---
            _buildBannerAdWidget(),
          ],
        ),
      ),
    );
  }

  // --- Helper Widgets ---
  Widget _buildDeviceList() {
    if (!_permissionsGranted) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.perm_device_information, size: 50, color: Colors.orange),
            const SizedBox(height: 16),
            const Text('Location permission needed for discovery.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _requestPermissionsAndInitializeApp, child: const Text('Grant Permission')),
            TextButton(onPressed: openAppSettings, child: const Text('Open App Settings')),
          ],
        ),
      );
    }

    if (_isDiscovering && _discoveredDevices.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isDiscovering && _discoveredDevices.isEmpty) {
      return Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                  const Icon(Icons.tv_off, size: 50, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(_connectionStatus, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),
                  if (!_isDiscovering) // Show refresh button only when not discovering
                    ElevatedButton.icon(
                        onPressed: _startDiscovery,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Search Again')
                    )
              ]
          )
      );
    }

    // Display the list of found devices
    return ListView.builder(
      itemCount: _discoveredDevices.length,
      itemBuilder: (context, index) {
        final device = _discoveredDevices[index];
        bool isSelected = _selectedDevice?.id == device.id;
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: Icon(Icons.tv, color: isSelected ? Theme.of(context).primaryColor : Colors.grey[700], size: 30),
            title: Text(device.name ?? 'Unknown Device', style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('${device.host}:${device.port} (${device.type})'),
            selected: isSelected,
            selectedTileColor: Colors.deepPurple.withOpacity(0.1),
            // Allow selection only if not connecting or already casting
            onTap: _isConnecting || _isCasting ? null : () => _connectAndCast(device),
            trailing: isSelected && (_isConnecting || _isCasting)
                ? (_isConnecting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle, color: Colors.green))
                : null,
          ),
        );
      },
    );
  }

  Widget _buildBannerAdWidget() {
    if (_bannerAd != null && _isBannerAdLoaded) {
      return Container(
        alignment: Alignment.center,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    } else {
      // Placeholder while ad is loading or if permissions are denied
      return Container(
        height: 50, // Standard banner height
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: Text(
            _permissionsGranted ? 'Ad Banner Loading...' : 'Ads disabled (permissions needed)',
            style: TextStyle(color: Colors.grey[600])
        ),
      );
    }
  }
}


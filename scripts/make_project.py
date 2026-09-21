"""Rebuild a dependency-free Xcode project. No network, signing or user data."""
from pathlib import Path
import hashlib, json, plistlib
root=Path(__file__).resolve().parent.parent
objects={}
def oid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def obj(name,body):
 key=oid(name);objects[key]=body;return key
def q(s): return json.dumps(s,ensure_ascii=False)
refs=[];builds=[]
for path in ['App/HealthLensApp.swift','App/ContentView.swift','App/AppModel.swift','App/HealthService.swift','Sources/TrainingCore/TrainingCore.swift']:
 f=obj(path,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = "<group>";')
 refs.append(f);builds.append(obj('build'+path,f'isa = PBXBuildFile; fileRef = {f};'))
resources=[]
for path,kind in [('App/Assets.xcassets','folder.assetcatalog'),('App/PrivacyInfo.xcprivacy','text.xml')]:
 f=obj(path,f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(path)}; sourceTree = "<group>";')
 refs.append(f);resources.append(obj('build'+path,f'isa = PBXBuildFile; fileRef = {f};'))
for path in ['App/Info.plist','App/HealthLens.entitlements','README.md','ALGORITHMS.md']:
 refs.append(obj(path,f'isa = PBXFileReference; lastKnownFileType = text; path = {q(path)}; sourceTree = "<group>";'))
product=obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = HealthLens.app; sourceTree = BUILT_PRODUCTS_DIR;')
products=obj('products',f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
main=obj('main',f'isa = PBXGroup; children = ({",".join(refs+[products])},); sourceTree = "<group>";')
sources=obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
res=obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resources)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks=obj('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
projectconfigs=[];targetconfigs=[]
for name in ['Debug','Release']:
 common={'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if name=='Debug' else 'dwarf-with-dsym'}
 if name=='Debug': common.update({'ENABLE_TESTABILITY':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG'})
 app={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'com.matrixchen.healthlens','CODE_SIGN_STYLE':'Automatic','CODE_SIGN_ENTITLEMENTS':'App/HealthLens.entitlements','INFOPLIST_FILE':'App/Info.plist','GENERATE_INFOPLIST_FILE':'NO','TARGETED_DEVICE_FAMILY':'1','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CURRENT_PROJECT_VERSION':'3','MARKETING_VERSION':'1.1.1','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks'}
 def settings(d):return ' '.join(k+' = '+q(v)+';' for k,v in d.items())
 projectconfigs.append(obj('project'+name,f'isa = XCBuildConfiguration; buildSettings = {{ {settings(common)} }}; name = {name};'))
 targetconfigs.append(obj('target'+name,f'isa = XCBuildConfiguration; buildSettings = {{ {settings(app)} }}; name = {name};'))
pc=obj('projectconfigs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(projectconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tc=obj('targetconfigs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(targetconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = ({sources},{frameworks},{res},); buildRules = (); dependencies = (); name = HealthLens; productName = HealthLens; productReference = {product}; productType = "com.apple.product-type.application";')
project=obj('project',f'isa = PBXProject; attributes = {{ LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.0; SystemCapabilities = {{ com.apple.HealthKit = {{ enabled = 1; }}; }}; }}; }}; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = ("zh-Hans",en,Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
pbx='// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(k+' = { '+v+' };\n' for k,v in objects.items())+'}; rootObject = '+project+'; }\n'
(root/'HealthLens.xcodeproj/project.pbxproj').write_text(pbx)
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="HealthLens.app" BlueprintName="HealthLens" ReferencedContainer="container:HealthLens.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="HealthLens.app" BlueprintName="HealthLens" ReferencedContainer="container:HealthLens.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
(root/'HealthLens.xcodeproj/xcshareddata/xcschemes/HealthLens.xcscheme').write_text(scheme)
info={'CFBundleDisplayName':'HappyBody','CFBundleName':'$(PRODUCT_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSRequiresIPhoneOS':True,'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],'NSHealthShareUsageDescription':'读取你的运动、睡眠、心率、步数、活动能量、呼吸、血氧、手腕温度及体成分记录，在本机展示趋势并结合自评提供训练休息参考。数据不会上传。'}
privacy={'NSPrivacyTracking':False,'NSPrivacyTrackingDomains':[],'NSPrivacyCollectedDataTypes':[],'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategoryUserDefaults','NSPrivacyAccessedAPITypeReasons':['CA92.1']}]}
for path,data in [('App/Info.plist',info),('App/HealthLens.entitlements',{'com.apple.developer.healthkit':True}),('App/PrivacyInfo.xcprivacy',privacy)]:
 (root/path).write_bytes(plistlib.dumps(data,sort_keys=False))
(root/'App/Assets.xcassets/Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
(root/'App/Assets.xcassets/AppIcon.appiconset/Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}}))
print('Created HealthLens.xcodeproj, shared scheme, HealthKit entitlement and privacy manifest')

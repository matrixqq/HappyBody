"""Create an isolated iOS test runner for the actual app model and HealthKit service."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parent.parent
objects={}
def oid(s):return hashlib.sha256(('sync-tests:'+s).encode()).hexdigest()[:24].upper()
def add(s,body):
 k=oid(s);objects[k]=body;return k
def q(s):return json.dumps(s)
refs=[];builds=[]
for path in ['App/AppModel.swift','App/HealthService.swift','Sources/TrainingCore/TrainingCore.swift','Tests/AppSyncTests.swift']:
 f=add(path,f'isa=PBXFileReference;lastKnownFileType=sourcecode.swift;path={q(path)};sourceTree="<group>";')
 refs.append(f);builds.append(add('build'+path,f'isa=PBXBuildFile;fileRef={f};'))
product=add('product','isa=PBXFileReference;explicitFileType=wrapper.cfbundle;path=HappyBodySyncTests.xctest;sourceTree=BUILT_PRODUCTS_DIR;')
products=add('products',f'isa=PBXGroup;children=({product},);name=Products;sourceTree="<group>";')
main=add('main',f'isa=PBXGroup;children=({",".join(refs+[products])},);sourceTree="<group>";')
source=add('sources',f'isa=PBXSourcesBuildPhase;buildActionMask=2147483647;files=({",".join(builds)},);runOnlyForDeploymentPostprocessing=0;')
frameworks=add('frameworks','isa=PBXFrameworksBuildPhase;buildActionMask=2147483647;files=();runOnlyForDeploymentPostprocessing=0;')
pc=[];tc=[]
for name in ['Debug','Release']:
 pc.append(add('project'+name,f'isa=XCBuildConfiguration;name={name};buildSettings={{SWIFT_VERSION=5.0;IPHONEOS_DEPLOYMENT_TARGET=17.0;SDKROOT=iphoneos;CLANG_ENABLE_MODULES=YES;SWIFT_OPTIMIZATION_LEVEL="-Onone";}};'))
 tc.append(add('target'+name,f'isa=XCBuildConfiguration;name={name};buildSettings={{PRODUCT_NAME="$(TARGET_NAME)";PRODUCT_BUNDLE_IDENTIFIER=com.matrixchen.happybody.synctests;GENERATE_INFOPLIST_FILE=YES;TARGETED_DEVICE_FAMILY=1;SUPPORTED_PLATFORMS="iphoneos iphonesimulator";CODE_SIGNING_ALLOWED=NO;LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/Frameworks @loader_path/Frameworks";}};'))
pconf=add('pconf',f'isa=XCConfigurationList;buildConfigurations=({",".join(pc)},);defaultConfigurationName=Debug;defaultConfigurationIsVisible=0;')
tconf=add('tconf',f'isa=XCConfigurationList;buildConfigurations=({",".join(tc)},);defaultConfigurationName=Debug;defaultConfigurationIsVisible=0;')
target=add('target',f'isa=PBXNativeTarget;name=HappyBodySyncTests;productName=HappyBodySyncTests;productType="com.apple.product-type.bundle.unit-test";productReference={product};buildConfigurationList={tconf};buildPhases=({source},{frameworks},);buildRules=();dependencies=();')
proj=add('project',f'isa=PBXProject;buildConfigurationList={pconf};compatibilityVersion="Xcode 14.0";developmentRegion=en;knownRegions=(en,Base,);mainGroup={main};productRefGroup={products};projectDirPath="";projectRoot="";targets=({target},);')
folder=root/'HappyBodySyncTests.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion=1;classes={};objectVersion=56;objects={'+''.join(k+'={'+v+'};' for k,v in objects.items())+'};rootObject='+proj+';}')
scheme=folder/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="HappyBodySyncTests.xctest" BlueprintName="HappyBodySyncTests" ReferencedContainer="container:HappyBodySyncTests.xcodeproj"/>'
(scheme/'HappyBodySyncTests.xcscheme').write_text(f'<?xml version="1.0" encoding="UTF-8"?><Scheme version="1.3"><BuildAction><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref}</TestableReference></Testables></TestAction></Scheme>')

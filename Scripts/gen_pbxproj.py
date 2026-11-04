# One-off generator for Ductile.xcodeproj (Xcode 16 format, synced folders). Kept for reference.
import hashlib, sys
def I(name): return hashlib.md5(name.encode()).hexdigest()[:24].upper()
TEAM = "H9GTGM97FP"
o = {}  # id -> body text
def add(name, body): o[I(name)] = body; return I(name)

app_sync = add("sync.App", 'isa = PBXFileSystemSynchronizedRootGroup; path = App; sourceTree = "<group>";')
shared_sync = add("sync.Shared", 'isa = PBXFileSystemSynchronizedRootGroup; path = Shared; sourceTree = "<group>";')
widget_sync = add("sync.Widget", 'isa = PBXFileSystemSynchronizedRootGroup; path = Widget; sourceTree = "<group>";')
cfg = [add("ref."+f, f'isa = PBXFileReference; lastKnownFileType = {t}; path = {f}; sourceTree = "<group>";')
       for f, t in [("App-Info.plist","text.plist.xml"),("Widget-Info.plist","text.plist.xml"),
                    ("App.entitlements","text.plist.entitlements"),("Widget.entitlements","text.plist.entitlements")]]
cfg_group = add("group.Config", f'isa = PBXGroup; children = ({", ".join(cfg)}, ); path = Config; sourceTree = "<group>";')
app_prod = add("prod.app", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Ductile.app; sourceTree = BUILT_PRODUCTS_DIR;')
wid_prod = add("prod.widget", 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = DuctileWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("group.Products", f'isa = PBXGroup; children = ({app_prod}, {wid_prod}, ); name = Products; sourceTree = "<group>";')
main = add("group.main", f'isa = PBXGroup; children = ({app_sync}, {shared_sync}, {widget_sync}, {cfg_group}, {products}, ); sourceTree = "<group>";')

def phases(t):
    return [add(f"{t}.sources", 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0;'),
            add(f"{t}.frameworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0;'),
            add(f"{t}.resources", 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0;')]

embed_file = add("build.embedWidget", f'isa = PBXBuildFile; fileRef = {wid_prod}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }};')
embed = add("app.embed", f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({embed_file}, ); name = "Embed Foundation Extensions"; runOnlyForDeploymentPostprocessing = 0;')

def cfg_list(name, debug, release):
    d = add(f"{name}.Debug", f'isa = XCBuildConfiguration; buildSettings = {{ {debug} }}; name = Debug;')
    r = add(f"{name}.Release", f'isa = XCBuildConfiguration; buildSettings = {{ {release} }}; name = Release;')
    return add(f"{name}.list", f'isa = XCConfigurationList; buildConfigurations = ({d}, {r}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

def s(**kw): return " ".join(f'{k} = {v};' for k, v in kw.items())
common = dict(ALWAYS_SEARCH_USER_PATHS="NO", CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES",
              ENABLE_STRICT_OBJC_MSGSEND="YES", ENABLE_USER_SCRIPT_SANDBOXING="YES", GCC_C_LANGUAGE_STANDARD="gnu17",
              IPHONEOS_DEPLOYMENT_TARGET="17.0", SDKROOT="iphoneos", SWIFT_VERSION="5.0", MTL_FAST_MATH="YES")
proj_list = cfg_list("project",
    s(**common, DEBUG_INFORMATION_FORMAT="dwarf", ENABLE_TESTABILITY="YES", GCC_OPTIMIZATION_LEVEL="0",
      ONLY_ACTIVE_ARCH="YES", SWIFT_ACTIVE_COMPILATION_CONDITIONS='"DEBUG $(inherited)"', SWIFT_OPTIMIZATION_LEVEL='"-Onone"'),
    s(**common, DEBUG_INFORMATION_FORMAT='"dwarf-with-dsym"', SWIFT_COMPILATION_MODE="wholemodule", VALIDATE_PRODUCT="YES"))

def target_settings(bundle, plist, ents, extra):
    return s(CODE_SIGN_ENTITLEMENTS=ents, CODE_SIGN_STYLE="Automatic", CURRENT_PROJECT_VERSION="1",
             DEVELOPMENT_TEAM=TEAM, GENERATE_INFOPLIST_FILE="NO", INFOPLIST_FILE=plist, MARKETING_VERSION="1.2",
             PRODUCT_BUNDLE_IDENTIFIER=bundle, PRODUCT_NAME='"$(TARGET_NAME)"', SWIFT_EMIT_LOC_STRINGS="YES",
             TARGETED_DEVICE_FAMILY="1", **extra)
app_set = target_settings("com.jason.ductile", "Config/App-Info.plist", "Config/App.entitlements",
    dict(ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon", LD_RUNPATH_SEARCH_PATHS='"$(inherited) @executable_path/Frameworks"'))
wid_set = target_settings("com.jason.ductile.widgets", "Config/Widget-Info.plist", "Config/Widget.entitlements",
    dict(APPLICATION_EXTENSION_API_ONLY="YES", SKIP_INSTALL="YES",
         LD_RUNPATH_SEARCH_PATHS='"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"'))
app_list, wid_list = cfg_list("app", app_set, app_set), cfg_list("widget", wid_set, wid_set)

wid_target = add("target.widget", f'isa = PBXNativeTarget; buildConfigurationList = {wid_list}; buildPhases = ({", ".join(phases("widget"))}, ); buildRules = ( ); dependencies = ( ); fileSystemSynchronizedGroups = ({widget_sync}, {shared_sync}, ); name = DuctileWidgets; productName = DuctileWidgets; productReference = {wid_prod}; productType = "com.apple.product-type.app-extension";')
project_id = I("project")
proxy = add("proxy.widget", f'isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {wid_target}; remoteInfo = DuctileWidgets;')
dep = add("dep.widget", f'isa = PBXTargetDependency; target = {wid_target}; targetProxy = {proxy};')
app_target = add("target.app", f'isa = PBXNativeTarget; buildConfigurationList = {app_list}; buildPhases = ({", ".join(phases("app"))}, {embed}, ); buildRules = ( ); dependencies = ({dep}, ); fileSystemSynchronizedGroups = ({app_sync}, {shared_sync}, ); name = Ductile; productName = Ductile; productReference = {app_prod}; productType = "com.apple.product-type.application";')
o[project_id] = (f'isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; '
    f'TargetAttributes = {{{app_target} = {{CreatedOnToolsVersion = 16.0; }}; {wid_target} = {{CreatedOnToolsVersion = 16.0; }}; }}; }}; '
    f'buildConfigurationList = {proj_list}; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base, ); '
    f'mainGroup = {main}; minimizedProjectReferenceProxies = 1; preferredProjectObjectVersion = 77; productRefGroup = {products}; '
    f'projectDirPath = ""; projectRoot = ""; targets = ({app_target}, {wid_target}, );')

body = "\n".join(f"\t\t{k} = {{{v}}};" for k, v in sorted(o.items()))
open(sys.argv[1], "w").write(f"// !$*UTF8*$!\n{{\n\tarchiveVersion = 1;\n\tclasses = {{\n\t}};\n\tobjectVersion = 77;\n\tobjects = {{\n{body}\n\t}};\n\trootObject = {project_id};\n}}\n")
print(app_target, wid_target)

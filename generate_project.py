import os
import hashlib

PROJECT_NAME = "VoiceMemo"
BUNDLE_ID = "cn.mistbit.voicememo"
SOURCES_DIR = "Sources/VoiceMemo"
ENTITLEMENTS_PATH = "VoiceMemo.entitlements"
INFO_PLIST_PATH = "Sources/VoiceMemo/Info.plist"
RESOURCES_DIR = "Sources/VoiceMemo/Resources"

DEPENDENCIES = [
    ("https://github.com/aliyun/alibabacloud-oss-swift-sdk-v2.git", "0.1.0-beta", "AlibabaCloudOSS"),
    ("https://github.com/stephencelis/SQLite.swift.git", "0.14.1", "SQLite"),
    ("https://github.com/vapor/mysql-kit.git", "4.0.0", "MySQLKit")
]

def gen_id(key):
    return hashlib.sha1(key.encode("utf-8")).hexdigest().upper()[:24]

PBX_PROJECT_ID = gen_id("project")
MAIN_GROUP_ID = gen_id("group:main")
SOURCES_GROUP_ID = gen_id("group:sources")
RESOURCES_GROUP_ID = gen_id("group:resources")
PRODUCTS_GROUP_ID = gen_id("group:products")
PRODUCT_REF_ID = gen_id("product:app")
TARGET_ID = gen_id("target:app")
CONFIG_LIST_ID = gen_id("configlist:project")
DEBUG_CONFIG_ID = gen_id("config:project:debug")
RELEASE_CONFIG_ID = gen_id("config:project:release")
NATIVE_TARGET_CONFIG_LIST_ID = gen_id("configlist:target")
TARGET_DEBUG_CONFIG_ID = gen_id("config:target:debug")
TARGET_RELEASE_CONFIG_ID = gen_id("config:target:release")
SOURCES_BUILD_PHASE_ID = gen_id("phase:sources")
RESOURCES_BUILD_PHASE_ID = gen_id("phase:resources")
FRAMEWORKS_BUILD_PHASE_ID = gen_id("phase:frameworks")

pkg_refs = []
pkg_deps = []

for url, version, product in DEPENDENCIES:
    ref_id = gen_id(f"pkgref:{url}")
    dep_id = gen_id(f"pkgdep:{product}")
    pkg_refs.append((ref_id, url, version))
    pkg_deps.append((dep_id, ref_id, product))

source_files = []
resource_files = []

for root, dirs, files in os.walk(SOURCES_DIR):
    for file in files:
        if file.endswith(".swift"):
            path = os.path.join(root, file)
            file_id = gen_id(f"file:{path}")
            build_file_id = gen_id(f"build:{path}")
            path = os.path.join(root, file)
            source_files.append((file_id, build_file_id, file, path))

if os.path.isdir(RESOURCES_DIR):
    for root, dirs, files in os.walk(RESOURCES_DIR):
        for file in files:
            path = os.path.join(root, file)
            file_id = gen_id(f"resource:{path}")
            build_file_id = gen_id(f"resourcebuild:{path}")
            resource_files.append((file_id, build_file_id, file, path))

info_plist_id = gen_id(f"file:{INFO_PLIST_PATH}")
entitlements_id = gen_id(f"file:{ENTITLEMENTS_PATH}")

def resource_file_type(path):
    _, ext = os.path.splitext(path.lower())
    if ext == ".icns":
        return "image.icns"
    if ext == ".png":
        return "image.png"
    if ext in [".jpg", ".jpeg"]:
        return "image.jpeg"
    return "file"

frameworks_files = ""
resources_files = "\n".join(
    f'\t\t\t\t{b_id} /* {name} in Resources */,'
    for f_id, b_id, name, path in resource_files
)
resources_children = "\n".join(
    f'\t\t\t\t{f_id} /* {name} */,'
    for f_id, b_id, name, path in resource_files
)

# Construct PBXProject
content = """// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 54;
	objects = {

/* Begin PBXBuildFile section */
"""

for f_id, b_id, name, path in source_files:
    content += f'\t\t{b_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {f_id} /* {name} */; }};\n'

for f_id, b_id, name, path in resource_files:
    content += f'\t\t{b_id} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {f_id} /* {name} */; }};\n'

content += """/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\t{PRODUCT_REF_ID} /* {PROJECT_NAME}.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; };
\t\t{ENTITLEMENTS_ID} /* {ENTITLEMENTS_PATH} */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = {ENTITLEMENTS_PATH}; sourceTree = "<group>"; };
\t\t{INFO_PLIST_ID} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {INFO_PLIST_PATH}; sourceTree = "<group>"; };
"""

for f_id, b_id, name, path in source_files:
    content += f'\t\t{f_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {path}; sourceTree = "<group>"; }};\n'

for f_id, b_id, name, path in resource_files:
    file_type = resource_file_type(path)
    content += f'\t\t{f_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {path}; sourceTree = "<group>"; }};\n'

content += """/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{FRAMEWORKS_BUILD_PHASE_ID} /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{FRAMEWORKS_FILES}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{MAIN_GROUP_ID} = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{SOURCES_GROUP_ID} /* Sources */,
\t\t\t\t{RESOURCES_GROUP_ID} /* Resources */,
\t\t\t\t{PRODUCTS_GROUP_ID} /* Products */,
\t\t\t\t{ENTITLEMENTS_ID} /* {ENTITLEMENTS_PATH} */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t};
\t\t{SOURCES_GROUP_ID} /* Sources */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{INFO_PLIST_ID} /* Info.plist */,
"""

for f_id, b_id, name, path in source_files:
    content += f'\t\t\t\t{f_id} /* {name} */,\n'

content += """\t\t\t);
\t\t\tname = Sources;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t{RESOURCES_GROUP_ID} /* Resources */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{RESOURCES_CHILDREN}
\t\t\t);
\t\t\tname = Resources;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t{PRODUCTS_GROUP_ID} /* Products */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{PRODUCT_REF_ID} /* {PROJECT_NAME}.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{TARGET_ID} /* {PROJECT_NAME} */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {NATIVE_TARGET_CONFIG_LIST_ID} /* Build configuration list for PBXNativeTarget "{PROJECT_NAME}" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES_BUILD_PHASE_ID} /* Sources */,
\t\t\t\t{FRAMEWORKS_BUILD_PHASE_ID} /* Frameworks */,
\t\t\t\t{RESOURCES_BUILD_PHASE_ID} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = {PROJECT_NAME};
\t\t\tpackageProductDependencies = (
"""

for dep_id, ref_id, product in pkg_deps:
    content += f'\t\t\t\t{dep_id} /* {product} */,\n'

content += """\t\t\t);
\t\t\tproductName = {PROJECT_NAME};
\t\t\tproductReference = {PRODUCT_REF_ID} /* {PROJECT_NAME}.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{PBX_PROJECT_ID} /* Project object */ = {
\t\t\tisa = PBXProject;
\t\t\tattributes = {
\t\t\t\tLastSwiftUpdateCheck = 1420;
\t\t\t\tLastUpgradeCheck = 1420;
\t\t\t\tTargetAttributes = {
\t\t\t\t\t{TARGET_ID} = {
\t\t\t\t\t\tCreatedOnToolsVersion = 14.2;
\t\t\t\t\t\tLastSwiftMigration = 1420;
\t\t\t\t\t};
\t\t\t\t};
\t\t\t};
\t\t\tbuildConfigurationList = {CONFIG_LIST_ID} /* Build configuration list for PBXProject "{PROJECT_NAME}" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {MAIN_GROUP_ID};
\t\t\tpackageReferences = (
"""

for ref_id, url, version in pkg_refs:
    content += f'\t\t\t\t{ref_id} /* XCRemoteSwiftPackageReference "{url}" */,\n'

content += """\t\t\t);
\t\t\tproductRefGroup = {PRODUCTS_GROUP_ID};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{TARGET_ID} /* {PROJECT_NAME} */,
\t\t\t);
\t\t};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{RESOURCES_BUILD_PHASE_ID} /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{RESOURCES_FILES}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{SOURCES_BUILD_PHASE_ID} /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
"""

for f_id, b_id, name, path in source_files:
    content += f'\t\t\t\t{b_id} /* {name} in Sources */,\n'

content += """\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{DEBUG_CONFIG_ID} /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t{RELEASE_CONFIG_ID} /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf-with-dsym;
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t};
\t\t\tname = Release;
\t\t};
\t\t{TARGET_DEBUG_CONFIG_ID} /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "{ENTITLEMENTS_PATH}";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = "{INFO_PLIST_PATH}";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t{TARGET_RELEASE_CONFIG_ID} /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "{ENTITLEMENTS_PATH}";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = "{INFO_PLIST_PATH}";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t};
\t\t\tname = Release;
\t\t};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{CONFIG_LIST_ID} /* Build configuration list for PBXProject "{PROJECT_NAME}" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{DEBUG_CONFIG_ID} /* Debug */,
\t\t\t\t{RELEASE_CONFIG_ID} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
\t\t{NATIVE_TARGET_CONFIG_LIST_ID} /* Build configuration list for PBXNativeTarget "{PROJECT_NAME}" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{TARGET_DEBUG_CONFIG_ID} /* Debug */,
\t\t\t\t{TARGET_RELEASE_CONFIG_ID} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
/* End XCConfigurationList section */

/* Begin XCRemoteSwiftPackageReference section */
"""

for ref_id, url, version in pkg_refs:
    content += f"""\t\t{ref_id} /* XCRemoteSwiftPackageReference "{url}" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "{url}";
\t\t\trequirement = {{
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = "{version}";
\t\t\t}};
\t\t}};\n"""

content += """/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
"""

for dep_id, ref_id, product in pkg_deps:
    content += f"""\t\t{dep_id} /* {product} */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {ref_id} /* XCRemoteSwiftPackageReference */;
\t\t\tproductName = {product};
\t\t}};\n"""

content += """/* End XCSwiftPackageProductDependency section */
	};
	rootObject = {PBX_PROJECT_ID} /* Project object */;
}
"""

# Write to file
project_dir = f"{PROJECT_NAME}.xcodeproj"
os.makedirs(project_dir, exist_ok=True)
content = (
    content
    .replace("{PROJECT_NAME}", PROJECT_NAME)
    .replace("{BUNDLE_ID}", BUNDLE_ID)
    .replace("{ENTITLEMENTS_PATH}", ENTITLEMENTS_PATH)
    .replace("{INFO_PLIST_PATH}", INFO_PLIST_PATH)
    .replace("{PBX_PROJECT_ID}", PBX_PROJECT_ID)
    .replace("{MAIN_GROUP_ID}", MAIN_GROUP_ID)
    .replace("{SOURCES_GROUP_ID}", SOURCES_GROUP_ID)
    .replace("{PRODUCT_REF_ID}", PRODUCT_REF_ID)
    .replace("{ENTITLEMENTS_ID}", entitlements_id)
    .replace("{INFO_PLIST_ID}", info_plist_id)
    .replace("{TARGET_ID}", TARGET_ID)
    .replace("{CONFIG_LIST_ID}", CONFIG_LIST_ID)
    .replace("{DEBUG_CONFIG_ID}", DEBUG_CONFIG_ID)
    .replace("{RELEASE_CONFIG_ID}", RELEASE_CONFIG_ID)
    .replace("{NATIVE_TARGET_CONFIG_LIST_ID}", NATIVE_TARGET_CONFIG_LIST_ID)
    .replace("{TARGET_DEBUG_CONFIG_ID}", TARGET_DEBUG_CONFIG_ID)
    .replace("{TARGET_RELEASE_CONFIG_ID}", TARGET_RELEASE_CONFIG_ID)
    .replace("{SOURCES_BUILD_PHASE_ID}", SOURCES_BUILD_PHASE_ID)
    .replace("{RESOURCES_BUILD_PHASE_ID}", RESOURCES_BUILD_PHASE_ID)
    .replace("{FRAMEWORKS_BUILD_PHASE_ID}", FRAMEWORKS_BUILD_PHASE_ID)
    .replace("{RESOURCES_GROUP_ID}", RESOURCES_GROUP_ID)
    .replace("{PRODUCTS_GROUP_ID}", PRODUCTS_GROUP_ID)
    .replace("{FRAMEWORKS_FILES}", frameworks_files)
    .replace("{RESOURCES_FILES}", resources_files)
    .replace("{RESOURCES_CHILDREN}", resources_children)
)

with open(os.path.join(project_dir, "project.pbxproj"), "w") as f:
    f.write(content)

print(f"Generated {project_dir} successfully!")

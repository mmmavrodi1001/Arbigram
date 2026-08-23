load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "ArbigramSettings",
    module_name = "ArbigramSettings",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    # Above TelegramCore, which is the point: editing this module rebuilds a
    # handful of modules rather than the whole project. What the engine itself
    # has to read lives in ArbigramCore instead.
    deps = [
        "//submodules/ArbigramCore:ArbigramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The fork's own tests, and the reason they can exist at all: both settings
# modules depend on nothing, so this target builds two small libraries rather
# than the three hundred modules an app-level test would drag in. Seconds, not
# the twenty minutes a full build costs.
swift_library(
    name = "ArbigramSettingsTestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        ":ArbigramSettings",
    ],
)

# Pinned to a device and an OS that exist on the runner. The default runner
# picks an invalid device and the test process exits 15 with nothing useful said.
ios_test_runner(
    name = "ArbigramSettingsTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "ArbigramSettingsTests",
    minimum_os_version = "13.0",
    runner = ":ArbigramSettingsTestRunner",
    deps = [
        ":ArbigramSettingsTestsLib",
    ],
    visibility = [
        "//visibility:public",
    ],
)

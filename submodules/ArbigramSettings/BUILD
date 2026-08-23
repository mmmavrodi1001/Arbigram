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

# The device is named because the default picks an invalid one and the test
# process exits 15 with nothing useful said. The OS version is deliberately not:
# the runner accepts only what the selected Xcode ships, which is not the newest
# runtime installed on the machine. Pinning 26.5 was refused by an Xcode offering
# 26.2, on a machine that had both. Left open it takes the newest it can actually
# run, and survives the next image bump.
ios_test_runner(
    name = "ArbigramSettingsTestRunner",
    device_type = "iPhone 17",
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

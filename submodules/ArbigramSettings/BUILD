load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

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

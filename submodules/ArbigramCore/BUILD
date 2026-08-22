load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ArbigramCore",
    module_name = "ArbigramCore",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    # Deliberately empty, and deliberately small. TelegramCore depends on this
    # module, so every edit here rebuilds TelegramCore and the three hundred
    # modules above it. Anything that does not have to be read from inside
    # TelegramCore belongs in ArbigramSettings, which sits above it.
    deps = [
    ],
    visibility = [
        "//visibility:public",
    ],
)

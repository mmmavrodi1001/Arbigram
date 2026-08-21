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
    # Deliberately empty. TelegramCore depends on this module, so anything this
    # one pulls in would end up underneath TelegramCore too.
    deps = [
    ],
    visibility = [
        "//visibility:public",
    ],
)

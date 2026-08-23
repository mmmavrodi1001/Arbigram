import Foundation
import Display
import TelegramPresentationData
import AccountContext
import PromptUI
import ArbigramSettings

/// Asks for the hidden-accounts phrase before doing something irreversible.
///
/// Logging out is the only action in the fork that cannot be undone from
/// inside the app — the session is gone and getting back in needs the phone
/// and a code. With thirty accounts, one mistaken tap is expensive.
///
/// Deleting an account is deliberately not gated: that path has its own
/// confirmations, and it is not what this guards against.
///
/// With no phrase set the action proceeds as before, so this never becomes a
/// wall in front of someone who never asked for one.
public func arbigramRequireSecretPhrase(
    context: AccountContext,
    present: @escaping (ViewController) -> Void,
    proceed: @escaping () -> Void
) {
    if ArbigramSettings.shared.secretPhrase.isEmpty {
        proceed()
        return
    }

    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")

    present(promptController(
        context: context,
        text: isRussian ? "Введи свою фразу" : "Enter your phrase",
        titleFont: .bold,
        subtitle: isRussian
            ? "Выход из аккаунта необратим. Чтобы подтвердить, введи фразу, заданную для скрытых аккаунтов."
            : "Logging out cannot be undone. Type the phrase you set for hidden accounts to confirm.",
        value: "",
        apply: { value in
            guard let value, ArbigramSettings.shared.matchesSecretPhrase(value) else {
                return
            }
            proceed()
        }
    ))
}

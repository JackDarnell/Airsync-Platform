import SwiftUI

struct ReceiverFlowView: View {
    let receiver: Receiver
    @ObservedObject var store: PairedReceiverStore

    var body: some View {
        if store.isPaired(receiver) {
            CalibrationView(session: .liveReceiverSession(baseURL: receiver.baseURL))
        } else {
            PairingView(receiver: receiver, store: store)
        }
    }
}

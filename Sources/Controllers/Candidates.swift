//
//  AvroKeyboard
//
//  Swift port of Candidates.m (original by Rifat Nabi, OmicronLab, 2012).
//

import Cocoa
import InputMethodKit

/// The shared candidate window, created once at startup with the IMK server.
@objc(Candidates)
public final class Candidates: IMKCandidates {

    // nonisolated(unsafe): created once in main() before the run loop starts,
    // then only touched from the main thread, matching the original code.
    nonisolated(unsafe) private static var shared: Candidates?

    @objc(allocateSharedInstanceWithServer:)
    public class func allocateSharedInstance(server: IMKServer) {
        if shared == nil {
            let instance = Candidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
            instance?.setAttributes([IMKCandidatesSendServerKeyEventFirst: true])
            instance?.setDismissesAutomatically(false)
            shared = instance
        }
    }

    @objc(deallocateSharedInstance)
    public class func deallocateSharedInstance() {
        shared = nil
    }

    @objc(sharedInstance)
    public class func sharedInstance() -> Candidates? {
        return shared
    }
}

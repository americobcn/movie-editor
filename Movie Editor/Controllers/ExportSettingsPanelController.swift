//
//  ExportSettingsPanelController.swift
//  Movie Editor
//
//  Created by Américo Cot Toloza on 01/05/2020.
//  Copyright © 2020 Américo Cot Toloza. All rights reserved.
//

protocol ExportSettingsPanelControllerDelegate: class {
    func exportPresetDidChange(_ preset: String)
}

class ExportSettingsPanelController: NSViewController {
    
    enum VideoCodec: String, CaseIterable {
        case H264
        case H265
        case ProRes
        
        var codecDescription: String? {
            switch self {
            case .H264:
                return "AVAssetExportPresetHighestQuality"
            case .H265:
                return "AVAssetExportPresetHEVCHighestQuality"
            case .ProRes:
                return "AVAssetExportPresetAppleProRes422LPCM"
            }
        }
    }
    
    @IBOutlet weak var codecExportPopup: NSPopUpButton!
    var delegate: ExportSettingsPanelControllerDelegate?
    
    //MARK: Overrides
    override func viewDidLoad() {
        super.viewDidLoad()
        let exportCodecs = VideoCodec.allCases.map(\.rawValue)
        codecExportPopup.addItems(withTitles: exportCodecs)
    }
    
    
    //MARK: @IBActions
    @IBAction func codecSetAction(_ sender: NSPopUpButton) {
        let selectedCodec: VideoCodec = .allCases.first(where: { $0.rawValue == sender.title })!
        let localPreset = selectedCodec.codecDescription ?? ""
        print("Selected Codec: \(localPreset)")
        delegate?.exportPresetDidChange(localPreset)
                
    }
    
    
    @IBAction func Close(_ sender: NSButton) {
        view.window?.orderOut(sender)
    }
    
    @IBAction func loadExportPanel(_ sender: NSMenuItem) {
        view.window?.makeKeyAndOrderFront(sender)
    }

}


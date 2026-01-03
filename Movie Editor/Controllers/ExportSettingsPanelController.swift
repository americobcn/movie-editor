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
    
    var delegate: ExportSettingsPanelControllerDelegate?
    
    //MARK: Outlets Export Seetings Window
    @IBOutlet weak var codecExportPopup: NSPopUpButton!
    // @IBOutlet weak var sizeExportPopup: NSPopUpButton!
    // @IBOutlet weak var setExportSettingsButton: NSButton!
    // @IBOutlet weak var cancelExportSettingsButton: NSButton!
    
    //MARK: Variables Export Seetings Window
    // var exportSizeWidth: String = ""
    // var exportSizeHeigh: String = ""
    // var localPreset: String = ""
    
    let exportCodecs = VideoCodec.allCases.map(\.rawValue)
    
    
    //MARK: Overrides
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        codecExportPopup.addItems(withTitles: exportCodecs)

    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        // updateExportSettings()
        
    }
    
    //MARK: @IBActions
    
    @IBAction func codecSetAction(_ sender: NSPopUpButton) {
        let selectedCodec: VideoCodec = .allCases.first(where: { $0.rawValue == sender.title })!
        let localPreset = selectedCodec.codecDescription ?? ""
        print("Selected Codec: \(localPreset)")
        delegate?.exportPresetDidChange(localPreset)
                
    }
    
    // @IBAction func sizeSetAction(_ sender: NSPopUpButton) {
    //     updateSizes()
    // }
    
    @IBAction func Close(_ sender: NSButton) {
        view.window?.orderOut(sender)
    }
    
    @IBAction func loadExportPanel(_ sender: NSMenuItem) {
        view.window?.makeKeyAndOrderFront(sender)
    }
    
    
    //MARK: Functions
    // func updateExportSettings() {
    //     //Setting up export settings
    //     let codec = codecExportPopup.selectedItem?.title
    //     switch codec {
    //     case "H.264":
    //         sizeExportPopup.removeAllItems()
    //         // sizeExportPopup.addItems(withTitles: h264SizesPopUp)
    //         break
    //     case "HEVC (H.265)":
    //         sizeExportPopup.removeAllItems()
    //         // sizeExportPopup.addItems(withTitles: hvecSizesPopUp)
    //         break
    //
    //     default:
    //         sizeExportPopup.removeAllItems()
    //     }
    //     updateExportPreset()
    //
    // }

    // func updateSizes () {
    //     let exportSize = sizeExportPopup.title.components(separatedBy: "x")
    //     // exportSizeWidth = exportSize[0]
    //     // exportSizeHeigh = exportSize[1]
    //     // updateExportPreset()
    // }
        
    // func updateExportPreset () {
    //     var exportPresetCodec = ""
    //     var exportPresetSize = ""
    //     switch codecExportPopup.title {
    //     case "H.264":
    //         exportPresetCodec = "AVAssetExportPreset"
    //         break
    //     case "HEVC (H.265)":
    //         exportPresetCodec = "AVAssetExportPresetHEVC"
    //         break
    //     case "ProRes":
    //         exportPresetCodec = "AVAssetExportPresetAppleProRes422LPCM"
    //         break
    //     default:
    //         break
    //     }
    //
    //     exportPresetSize = sizeExportPopup.title
    //     //localPreset = exportPresetCodec + exportPresetSize
    //     // delegate?.exportPresetDidChange(localPreset)
    // }

}


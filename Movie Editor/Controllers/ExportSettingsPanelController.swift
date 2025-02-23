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
    
    var delegate: ExportSettingsPanelControllerDelegate?
    
    //MARK: Outlets Export Seetings Window
    @IBOutlet weak var codecExportPopup: NSPopUpButton!
    @IBOutlet weak var sizeExportPopup: NSPopUpButton!
    @IBOutlet weak var setExportSettingsButton: NSButton!
    @IBOutlet weak var cancelExportSettingsButton: NSButton!
    
    //MARK: Variables Export Seetings Window
    var exportSizeWidth: String = ""
    var exportSizeHeigh: String = ""
    var localPreset: String = ""
    
    let exportCodecsPopUp = ["H.264", "HEVC (H.265)"]
    let h264SizesPopUp = ["960x540", "1280x720", "1920x1080", "3840x2160"]
    let hvecSizesPopUp = ["1920x1080", "3840x2160"]
    let exportH264QualityPopUp = ["Low", "Medium", "High"]
    
    //MARK: Overrides
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        codecExportPopup.addItems(withTitles: exportCodecsPopUp)
//        print("DELEGATE in ESPC: \(String(describing: delegate))")
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        updateExportSettings()
        
    }
    
    //MARK: @IBActions
    
    @IBAction func codecSetAction(_ sender: NSPopUpButton) {
        updateExportSettings()
    }
    
    @IBAction func sizeSetAction(_ sender: NSPopUpButton) {
        updateSizes()
    }
    
    @IBAction func Close(_ sender: NSButton) {
        view.window?.orderOut(sender)
    }
    
    @IBAction func loadExportPanel(_ sender: NSMenuItem) {
        view.window?.makeKeyAndOrderFront(sender)
    }
    
    
    //MARK: Functions
    func updateExportSettings() {
        //Setting up export settings
        let codec = codecExportPopup.selectedItem?.title
        switch codec {
        case "H.264":
            sizeExportPopup.removeAllItems()
            sizeExportPopup.addItems(withTitles: h264SizesPopUp)
            break
        case "HEVC (H.265)":
            sizeExportPopup.removeAllItems()
            sizeExportPopup.addItems(withTitles: hvecSizesPopUp)
            break
        default:
            sizeExportPopup.removeAllItems()
        }
        updateExportPreset()
        
    }

    func updateSizes () {
        exportSizeWidth = sizeExportPopup.title.components(separatedBy: "x")[0]
        exportSizeHeigh = sizeExportPopup.title.components(separatedBy: "x")[1]
        updateExportPreset()
        
    }
        
    func updateExportPreset () {
        var exportPresetCodec = ""
        var exportPresetSize = ""
        switch codecExportPopup.title {
        case "H.264":
            exportPresetCodec = "AVAssetExportPreset"
            break
        case "HEVC (H.265)":
            exportPresetCodec = "AVAssetExportPresetHEVC"
            break
        default:
            break
        }
        
        exportPresetSize = sizeExportPopup.title
        localPreset = exportPresetCodec + exportPresetSize
//        print("EXPORT PRESET: \(String(describing: localPreset)), sending to delegate")
        delegate?.exportPresetDidChange(localPreset)
    }

}


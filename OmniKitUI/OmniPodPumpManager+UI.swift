//
//  OmniPodPumpManager+UI.swift
//  OmniKitUI
//
//  Created by Pete Schwamb on 8/4/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

import UIKit
import LoopKit
import LoopKitUI
import OmniKit


internal class OmnipodHUDProvider: HUDProvider, PodStateObserver {
    var managerIdentifier: String {
        return OmnipodPumpManager.managerIdentifier
    }

    public weak var delegate: HUDProviderDelegate?
    
    private var podState: PodState {
        didSet {
            if oldValue.lastInsulinMeasurements?.reservoirVolume == nil && podState.lastInsulinMeasurements?.reservoirVolume != nil {
                reservoirView = OmnipodReservoirView.instantiate()
                delegate?.newHUDViewsAvailable([reservoirView!])
            }
            
            if oldValue.lastInsulinMeasurements != podState.lastInsulinMeasurements {
                updateReservoirView()
            }
        }
    }
    
    private let pumpManager: OmnipodPumpManager
    
    private var reservoirView: OmnipodReservoirView?
    
    private var podLifeView: PodLifeHUDView?
    
    public init(pumpManager: OmnipodPumpManager) {
        self.pumpManager = pumpManager
        self.podState = pumpManager.state.podState
    }
    
    private func updateReservoirView() {
        if let lastInsulinMeasurements = podState.lastInsulinMeasurements,
            let reservoirVolume = lastInsulinMeasurements.reservoirVolume,
            let reservoirView = reservoirView
        {
            let reservoirLevel = min(1, max(0, reservoirVolume / pumpManager.pumpReservoirCapacity))
            reservoirView.reservoirLevel = reservoirLevel
            let reservoirAlertState: ReservoirAlertState = podState.alarms.contains(.lowReservoir) ? .lowReservoir : .ok
            
            reservoirView.updateReservoir(volume: reservoirVolume, at: lastInsulinMeasurements.validTime, level: reservoirLevel, reservoirAlertState: reservoirAlertState)
        }
    }
    
    private func updatePodLifeView() {
        if let podLifeView = podLifeView {
            let lifetime = podState.expiresAt.timeIntervalSince(podState.activatedAt)
            podLifeView.setPodLifeCycle(startTime: podState.activatedAt, lifetime: lifetime)
        }
    }
    
    public func createHUDViews() -> [BaseHUDView] {
        if podState.lastInsulinMeasurements?.reservoirVolume != nil {
            self.reservoirView = OmnipodReservoirView.instantiate()
            self.updateReservoirView()
            self.delegate?.newHUDViewsAvailable([self.reservoirView!])
        }
        
        podLifeView = PodLifeHUDView.instantiate()
        updatePodLifeView()
        
        return [reservoirView, podLifeView].compactMap { $0 }
    }
    
    public func didTapOnHudView(_ view: BaseHUDView) -> HUDTapAction? {
        if let _ = view as? PodLifeHUDView {
            return HUDTapAction.showViewController(pumpManager.settingsViewController())
        }
        return nil
    }
    
    public var hudViewsRawState: HUDProvider.HUDViewsRawState {
        var rawValue: HUDProvider.HUDViewsRawState = [
            "pumpReservoirCapacity": pumpManager.pumpReservoirCapacity,
            "podActivatedAt": podState.activatedAt,
            "lifetime": podState.expiresAt.timeIntervalSince(podState.activatedAt),
            "alarms": podState.alarms.rawValue
        ]
        
        if let lastInsulinMeasurements = podState.lastInsulinMeasurements {
            rawValue["reservoirVolume"] = lastInsulinMeasurements.reservoirVolume
            rawValue["reservoirVolumeValidTime"] = lastInsulinMeasurements.validTime
        }
        
        return rawValue
    }
    
    public static func createHUDViews(rawValue: HUDProvider.HUDViewsRawState) -> [BaseHUDView] {
        guard let pumpReservoirCapacity = rawValue["pumpReservoirCapacity"] as? Double,
            let podActivatedAt = rawValue["podActivatedAt"] as? Date,
            let lifetime = rawValue["lifetime"] as? Double,
            let rawAlarms = rawValue["alarms"] as? UInt8 else
        {
            return []
        }
        
        let alarms = PodAlarmState(rawValue: rawAlarms)
        let reservoirVolume = rawValue["reservoirVolume"] as? Double
        let reservoirVolumeValidTime = rawValue["reservoirVolumeValidTime"] as? Date
        
        
        let reservoirView = OmnipodReservoirView.instantiate()
        if let reservoirVolume = reservoirVolume,
            let reservoirVolumeValidTime = reservoirVolumeValidTime
        {
            let reservoirLevel = min(1, max(0, reservoirVolume / pumpReservoirCapacity))
            reservoirView.reservoirLevel = reservoirLevel
            let reservoirAlertState: ReservoirAlertState = alarms.contains(.lowReservoir) ? .lowReservoir : .ok
            reservoirView.updateReservoir(volume: reservoirVolume, at: reservoirVolumeValidTime, level: reservoirLevel, reservoirAlertState: reservoirAlertState)
        }
        
        let podLifeHUDView = PodLifeHUDView.instantiate()
        podLifeHUDView.setPodLifeCycle(startTime: podActivatedAt, lifetime: lifetime)
        
        return [reservoirView, podLifeHUDView]
    }
    
    func didUpdatePodState(_ podState: PodState) {
        DispatchQueue.main.async {
            self.podState = podState
        }
    }
}

extension OmnipodPumpManager: PumpManagerUI {
    
    static public func setupViewController() -> (UIViewController & PumpManagerSetupViewController) {
        return OmnipodPumpManagerSetupViewController.instantiateFromStoryboard()
    }
    
    public func settingsViewController() -> UIViewController {
        return OmnipodSettingsViewController(pumpManager: self)
    }
    
    public var smallImage: UIImage? {
        return UIImage(named: "Pod", in: Bundle(for: OmnipodSettingsViewController.self), compatibleWith: nil)!
    }
    
    public func hudProvider() -> HUDProvider? {
        return OmnipodHUDProvider(pumpManager: self)
    }
    
    public static func createHUDViews(rawValue: HUDProvider.HUDViewsRawState) -> [BaseHUDView] {
        return OmnipodHUDProvider.createHUDViews(rawValue: rawValue)
    }
}

// MARK: - DeliveryLimitSettingsTableViewControllerSyncSource
extension OmnipodPumpManager {
    public func syncDeliveryLimitSettings(for viewController: DeliveryLimitSettingsTableViewController, completion: @escaping (DeliveryLimitSettingsResult) -> Void) {
        guard let maxBasalRate = viewController.maximumBasalRatePerHour,
            let maxBolus = viewController.maximumBolus else
        {
            completion(.failure(PodCommsError.invalidData))
            return
        }
        
        completion(.success(maximumBasalRatePerHour: maxBasalRate, maximumBolus: maxBolus))
    }
    
    public func syncButtonTitle(for viewController: DeliveryLimitSettingsTableViewController) -> String {
        return NSLocalizedString("Save", comment: "Title of button to save delivery limit settings")    }
    
    public func syncButtonDetailText(for viewController: DeliveryLimitSettingsTableViewController) -> String? {
        return nil
    }
    
    public func deliveryLimitSettingsTableViewControllerIsReadOnly(_ viewController: DeliveryLimitSettingsTableViewController) -> Bool {
        return false
    }
}

// MARK: - SingleValueScheduleTableViewControllerSyncSource
extension OmnipodPumpManager {
    public func syncScheduleValues(for viewController: SingleValueScheduleTableViewController, completion: @escaping (RepeatingScheduleValueResult<Double>) -> Void) {
        let timeZone = state.podState.timeZone
        podComms.runSession(withName: "Save Basal Profile", using: rileyLinkDeviceProvider.firstConnectedDevice) { (result) in
            do {
                switch result {
                case .success(let session):
                    let scheduleOffset = timeZone.scheduleOffset(forDate: Date())
                    let newSchedule = BasalSchedule(repeatingScheduleValues: viewController.scheduleItems)
                    let _ = try session.cancelDelivery(deliveryType: .all, beepType: .noBeep)
                    let _ = try session.setBasalSchedule(schedule: newSchedule, scheduleOffset: scheduleOffset, confidenceReminder: false, programReminderInterval: 0)
                    completion(.success(scheduleItems: viewController.scheduleItems, timeZone: timeZone))
                case .failure(let error):
                    throw error
                }
            } catch let error {
                self.log.error("Save basal profile failed: %{public}@", String(describing: error))
                completion(.failure(error))
            }
        }
    }
    
    public func syncButtonTitle(for viewController: SingleValueScheduleTableViewController) -> String {
        return NSLocalizedString("Sync With Pod", comment: "Title of button to sync basal profile from pod")
    }
    
    public func syncButtonDetailText(for viewController: SingleValueScheduleTableViewController) -> String? {
        return nil
    }
    
    public func singleValueScheduleTableViewControllerIsReadOnly(_ viewController: SingleValueScheduleTableViewController) -> Bool {
        return false
    }
}

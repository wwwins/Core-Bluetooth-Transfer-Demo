//
//  SecondViewController.swift
//  Bluetooth
//
//  Created by Mick on 12/20/14.
//  Copyright (c) 2014 MacCDevTeam LLC. All rights reserved.
//

import UIKit
import CoreBluetooth

class BTLECentralViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @IBOutlet private weak var textView: UITextView!
    
    private var centralManager: CBCentralManager?
    private var discoveredPeripheral: CBPeripheral?
    
    // And somewhere to store the incoming data
    private let data = NSMutableData()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // 第一步: 設定 CBCentralManager 及 delegate
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        
        print("Stopping scan")
        centralManager?.stopScan()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    /** centralManagerDidUpdateState is a required protocol method.
    *  Usually, you'd check for other states to make sure the current device supports LE, is powered on, etc.
    *  In this instance, we're just using it to wait for CBCentralManagerStatePoweredOn, which indicates
    *  the Central is ready to be used.
    */
    func centralManagerDidUpdateState(central: CBCentralManager) {
        print("\(__LINE__) \(__FUNCTION__)")

        if central.state != .PoweredOn {
            // In a real app, you'd deal with all the states correctly
            return
        }
        
        // The state must be CBCentralManagerStatePoweredOn...
        
        // ... so start scanning
        scan()
    }
    
    /** Scan for peripherals - specifically for our service's 128bit CBUUID
    */
    func scan() {

//        centralManager?.scanForPeripheralsWithServices(
//            [transferServiceUUID], options: [
//                CBCentralManagerScanOptionAllowDuplicatesKey : NSNumber(bool: true)
//            ]
//        )
//        // 第二步: 掃描裝置(可指定或不指定特定裝置)
        centralManager?.scanForPeripheralsWithServices(nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey:1])

        print("Scanning started")
    }

    /** 第三步: 發現裝置，進行連線
    *  This callback comes whenever a peripheral that is advertising the TRANSFER_SERVICE_UUID is discovered.
    *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
    *  we start the connection process
    */
    func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        
        // Reject any where the value is above reasonable range
        // Reject if the signal strength is too low to be close enough (Close is around -22dB)

//        if  RSSI.integerValue < -15 && RSSI.integerValue > -35 {
//            println("Device not at correct range")
//            return
//        }

        print("Discovered \(peripheral.name) at \(RSSI)")

        // Ok, it's in range - have we already seen it?
        
        if discoveredPeripheral != peripheral {
            // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it
            discoveredPeripheral = peripheral
            
            // And connect
            print("Connecting to peripheral \(peripheral)")
            
            centralManager?.connectPeripheral(peripheral, options: nil)
        }
    }
  

    // 處理連線失敗
    /** If the connection fails for whatever reason, we need to deal with it.
    */
    func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        print("Failed to connect to \(peripheral). (\(error!.localizedDescription))")
        
        cleanup()
    }

    /** 第四步: 成功連線裝置
    *  We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
    */
    func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        print("Peripheral Connected")
        
        // Stop scanning
        centralManager?.stopScan()
        print("Scanning stopped")
        
        // Clear the data that we may already have
        data.length = 0

        // 第五步: 設定連線裝置 delegate
        // Make sure we get the discovery callbacks
        peripheral.delegate = self

        // 第六步: 掃描此連線裝置有哪些服務
        // Search only for services that match our UUID
        peripheral.discoverServices([transferServiceUUID])
//        peripheral.discoverServices(nil)

        // 讀取 RSSI 值
        peripheral.readRSSI()
    }

    // 第七步: 成功發現服務(裝置可能會有多個服務)
    /** The Transfer Service was discovered
    */
    func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        // Discover the characteristic we want...

        // 第八步: 找出特定的服務
        // Loop through the newly filled peripheral.services array, just in case there's more than one.
        for service in peripheral.services as [CBService]! {
            peripheral.discoverCharacteristics([transferCharacteristicUUID], forService: service)
//          peripheral.discoverCharacteristics(nil, forService: service)
        }
    }

    // 第九步: 訂閱此特定的服務
    /** The Transfer characteristic was discovered.
    *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
    */
    func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        // Deal with errors (if any)
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            cleanup()
            return
        }

        // Again, we loop through the array, just in case.
        for characteristic in service.characteristics as [CBCharacteristic]! {
            // And check if it's the right one
            if characteristic.UUID.isEqual(transferCharacteristicUUID) {
                // 第十步: 回應需要訂閱
                // If it is, subscribe to it
                peripheral.setNotifyValue(true, forCharacteristic: characteristic)
            }
        }
        // Once this is complete, we just need to wait for the data to come in.
    }

    // 第十一步: 處理訂閱後傳回來的資料
    /** This callback lets us know more data has arrived via notification on the characteristic
    */
    func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        // Have we got everything we need?
        if let stringFromData = NSString(data: characteristic.value!, encoding: NSUTF8StringEncoding) {
            if stringFromData.isEqualToString("EOM") {
                // We have, so show the data,
                textView.text = NSString(data: (data.copy() as! NSData) as NSData, encoding: NSUTF8StringEncoding) as! String
                
                // Cancel our subscription to the characteristic
                peripheral.setNotifyValue(false, forCharacteristic: characteristic)

                // and disconnect from the peripehral
                centralManager?.cancelPeripheralConnection(peripheral)
            }
        
            // Otherwise, just add the data on to what we already have
            data.appendData(characteristic.value!)
            
            // Log it
            print("Received: \(stringFromData)")
        } else {
            print("Invalid data")
        }
    }

    // 處理裝置訂閱狀態改變
    /** The peripheral letting us know whether our subscribe/unsubscribe happened or not
    */
    func peripheral(peripheral: CBPeripheral, didUpdateNotificationStateForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        print("Error changing notification state: \(error?.localizedDescription)")
        
        // Exit if it's not the transfer characteristic
        if !characteristic.UUID.isEqual(transferCharacteristicUUID) {
            return
        }
        
        // Notification has started
        if (characteristic.isNotifying) {
            print("Notification began on \(characteristic)")
        } else { // Notification has stopped
            print("Notification stopped on (\(characteristic))  Disconnecting")
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }

    func peripheral(peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: NSError?) {
      print(">>> \(peripheral.name!) RSSI: \(RSSI)")
    }

    // 處理置裝斷線
    /** Once the disconnection happens, we need to clean up our local copy of the peripheral
    */
    func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        print("Peripheral Disconnected")
        discoveredPeripheral = nil
        
        // We're disconnected, so start scanning again
        scan()
    }

    // 取消訂閱
    /** Call this when things either go wrong, or you're done with the connection.
    *  This cancels any subscriptions if there are any, or straight disconnects if not.
    *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
    */
    private func cleanup() {
        // Don't do anything if we're not connected
        // self.discoveredPeripheral.isConnected is deprecated
        if discoveredPeripheral?.state != CBPeripheralState.Connected { // explicit enum required to compile here?
            return
        }
        
        // See if we are subscribed to a characteristic on the peripheral
        if let services = discoveredPeripheral?.services as [CBService]? {
            for service in services {
                if let characteristics = service.characteristics as [CBCharacteristic]? {
                    for characteristic in characteristics {
                        if characteristic.UUID.isEqual(transferCharacteristicUUID) && characteristic.isNotifying {
                            discoveredPeripheral?.setNotifyValue(false, forCharacteristic: characteristic)
                            // And we're done.
                            return
                        }
                    }
                }
            }
        }
        
        // If we've got this far, we're connected, but we're not subscribed, so we just disconnect
        centralManager?.cancelPeripheralConnection(discoveredPeripheral!)
    }
}


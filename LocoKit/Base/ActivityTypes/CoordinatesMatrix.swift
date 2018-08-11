//
//  Matrix.swift
//  LearnerCoacher
//
//  Created by Matt Greenfield on 7/05/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import os.log
import CoreLocation

class CoordinatesMatrix {
    
    static let minimumProbability = 0.001
    
    static let pseudoCount: UInt16 = 1
 
    var bins: [[UInt16]] // [lat][long]
    var lngBinWidth: Double
    var latBinWidth: Double
    var lngRange: (min: Double, max: Double)
    var latRange: (min: Double, max: Double)
   
    // used for loading from serialised strings
    convenience init?(string: String) {
        let lines = string.components(separatedBy: ";")
        
        guard lines.count > 3 else {
            return nil
        }

        let sizeLine = lines[0].components(separatedBy: ",")
        guard let latBinCount = Int(sizeLine[0]), let lngBinCount = Int(sizeLine[1]) else {
            os_log("BIN COUNTS FAIL")
            return nil
        }
        
        let latRangeLine = lines[1].components(separatedBy: ",")
        guard let latMin = Double(latRangeLine[0]), let latMax = Double(latRangeLine[1]) else {
            os_log("LAT RANGE FAIL")
            return nil
        }
        
        let lngRangeLine = lines[2].components(separatedBy: ",")
        guard let lngMin = Double(lngRangeLine[0]), let lngMax = Double(lngRangeLine[1]) else {
            os_log("LNG RANGE FAIL")
            return nil
        }
        
        let latRange = (min: latMin, max: latMax)
        let lngRange = (min: lngMin, max: lngMax)
        let lngBinWidth = (lngRange.max - lngRange.min) / Double(lngBinCount)
        let latBinWidth = (latRange.max - latRange.min) / Double(latBinCount)
        
        var bins = Array(repeating: Array<UInt16>(repeating: CoordinatesMatrix.pseudoCount, count: lngBinCount),
                         count: latBinCount)
        
        let binLines = lines.suffix(from: 3)
        for binLine in binLines {
            let bits = binLine.components(separatedBy: ",")
            guard bits.count == 3 else {
                continue
            }
            
            guard let latBin = Int(bits[0]), let lngBin = Int(bits[1]), var value = Int(bits[2]) else {
                os_log("CoordinatesMatrix bin fail: %@", bits)
                return nil
            }
           
            // fix overflows
            if value > Int(UInt16.max) {
                value = Int(UInt16.max)
            }
            
            bins[latBin][lngBin] = UInt16(value)
        }
        
        self.init(bins: bins, latBinWidth: latBinWidth, lngBinWidth: lngBinWidth, latRange: latRange, lngRange: lngRange)
    }
    
    // everything pre determined except which bins the coordinates go in. ActivityType uses this directly
    convenience init(coordinates: [CLLocationCoordinate2D], latBinCount: Int, lngBinCount: Int,
                     latRange: (min: Double, max: Double), lngRange: (min: Double, max: Double)) {
        let latBinWidth = (latRange.max - latRange.min) / Double(latBinCount)
        let lngBinWidth = (lngRange.max - lngRange.min) / Double(lngBinCount)
        
        // pre fill the bins with pseudo count
        var bins = Array(repeating: Array<UInt16>(repeating: CoordinatesMatrix.pseudoCount, count: lngBinCount),
                         count: latBinCount)
        
        // proper fill the bins
        for coordinate in coordinates {
            let lngBin = Int((coordinate.longitude - lngRange.min) / lngBinWidth)
            let latBin = Int((coordinate.latitude - latRange.min) / latBinWidth)
            
            guard latBin >= 0 && latBin < latBinCount && lngBin >= 0 && lngBin < lngBinCount else {
                continue
            }
            
            let existingValue = bins[latBin][lngBin]
            if existingValue < UInt16.max {
                bins[latBin][lngBin] = existingValue + 1
            }
        }
        
        self.init(bins: bins, latBinWidth: latBinWidth, lngBinWidth: lngBinWidth, latRange: latRange, lngRange: lngRange)
    }
    
    init(bins: [[UInt16]], latBinWidth: Double, lngBinWidth: Double, latRange: (min: Double, max: Double),
         lngRange: (min: Double, max: Double)) {
        self.bins = bins
        self.lngRange = lngRange
        self.latRange = latRange
        self.lngBinWidth = lngBinWidth
        self.latBinWidth = latBinWidth
    }
}

extension CoordinatesMatrix {
    
    func probabilityFor(_ coordinate: CLLocationCoordinate2D, maxThreshold: Int? = nil) -> Double {
        guard latBinWidth > 0 && lngBinWidth > 0 else {
            return 0
        }
        
        var matrixMax: UInt16 = 0
        for bin in bins {
            if let rowMax = bin.max() {
                matrixMax = max(rowMax, UInt16(matrixMax))
            }
        }
        
        guard matrixMax > 0 else {
            return 0
        }
       
        if var maxThreshold = maxThreshold {
            
            // fix overflows
            if maxThreshold > Int(UInt16.max) {
                maxThreshold = Int(UInt16.max)
            }
            
            matrixMax.clamp(min: 0, max: UInt16(maxThreshold))
        }
        
        let latBin = Int((coordinate.latitude - latRange.min) / latBinWidth)
        let lngBin = Int((coordinate.longitude - lngRange.min) / lngBinWidth)
        
        guard latBin >= 0 && latBin < bins.count else {
            return (Double(CoordinatesMatrix.pseudoCount) / Double(matrixMax)).clamped(min: 0, max: 1)
        }
        guard lngBin >= 0 && lngBin < bins[0].count else {
            return (Double(CoordinatesMatrix.pseudoCount) / Double(matrixMax)).clamped(min: 0, max: 1)
        }
        
        let binCount = bins[latBin][lngBin]
        
        return (Double(binCount) / Double(matrixMax)).clamped(min: 0, max: 1)
    }
    
}

extension CoordinatesMatrix {
   
    // xCount,yCount,pseudoCount;
    // xMin,xMax;
    // yMin,yMax;
    // x,y,value; ...
    
    var serialised: String {
        var result = "\(bins.count),\(bins[0].count),\(CoordinatesMatrix.pseudoCount);"
        result += "\(latRange.min),\(latRange.max);"
        result += "\(lngRange.min),\(lngRange.max);"
        
        for (x, bin) in bins.enumerated() {
            for (y, value) in bin.enumerated() {
                if value > CoordinatesMatrix.pseudoCount {
                    result += "\(x),\(y),\(value);"
                }
            }
        }
        
        return result
    }
    
}

extension CoordinatesMatrix: CustomStringConvertible {
    
    var description: String {
        var result = ""
        
        result += "lngRange: \(lngRange)\n"
        result += "latRange: \(latRange)\n"
        
        var matrixMax: UInt16 = 0
        for lngBins in bins {
            if let maxBin = lngBins.max(), maxBin > matrixMax {
                matrixMax = maxBin
            }
        }
       
        // TODO: this doesn't take into account the maxThreshold (eg 10 events per D2 bin)
        for lngBins in bins.reversed() {
            var yString = ""
            for value in lngBins {
                let pctOfMax = Double(value) / Double(matrixMax)
                if value <= CoordinatesMatrix.pseudoCount {
                    yString += "-"
                } else if pctOfMax >= 1 {
                    yString += "X"
                } else {
                    yString += String(format: "%1.0f", pctOfMax * 10)
                }
            }
            
            result += yString + "\n"
            
        }
        
        return result
    }
}

//
//  SliderScales.swift
//  SliderScales
//
//  Created by Michael Forrest on 16/08/2021.
//

import Foundation

protocol SliderScale{
    var tickValues: [Float] { get }
    func isMajorTick(value: Float)->Bool
    func position(of value: Float)->CGFloat
    func value(at position: CGFloat)->Float
    func format(_ value: Float)->String
    // Should the wheel snap to a particular value?
    var isDiscrete: Bool { get }
}

struct LinearScale: SliderScale{
    var minValue: Float
    var maxValue: Float
    var majorTicks: Float = 3.0
    var minorTicks: Float = 1.0
    
    func format(_ value: Float)->String{
        maxValue > 100 ? String(format: "%0.0f", value) :  maxValue <= 1.0 ? String(format: "%0.2f", value) :  String(format: "%0.1f", value)
    }
    
    var tickValues: [Float]{
        stride(from: minValue, through: maxValue, by: minorTicks).map{$0}
    }
    func isMajorTick(value: Float) -> Bool {
        (value - minValue).truncatingRemainder(dividingBy: majorTicks) == 0
    }
    
    func position(of value: Float)->CGFloat{
        CGFloat((value - minValue) / (maxValue - minValue))
    }
    func value(at position: CGFloat)->Float{
        max(min((Float(position) * (maxValue - minValue)) + minValue, maxValue), minValue)
    }
    
    var isDiscrete = false
}

protocol DiscreteScaleProvider{
    var tickValues: [Float] { get set }
    
}

extension DiscreteScaleProvider{
    func halfwayBetween(_ value: Float, _ nextValue: Float )-> Float {
//        value + 0.5 * (nextValue - value)
        // geometric mean:
        (value * nextValue).squareRoot()
    }
    
    func nearestTickValue(to position: CGFloat)->Float{
         let positionIndex = Int(round(position * CGFloat(tickValues.count)))
         return tickValues[max(0,min(tickValues.count - 1,positionIndex))]
     }
     
     private func nearestTickIndex(to value: Float)->Int{
         for (index,tickValue) in tickValues.enumerated(){
             let previousTick = index > 0 ? tickValues[index - 1] : nil
             let nextTick = index < tickValues.count - 1 ? tickValues[index + 1] : nil
             let lowerBound = previousTick == nil ? -.greatestFiniteMagnitude : halfwayBetween(previousTick!,tickValue)
             let upperBound = nextTick == nil ? .greatestFiniteMagnitude : halfwayBetween(tickValue,nextTick!)
             if lowerBound < value && value <= upperBound {
                 return index
             }
         }
         // should never get here.
         print("SHOULDN'T GET HERE")
         return 0
     }
     
     func isMajorTick(value: Float) -> Bool {
         false
     }
     // used to lay out ticks and move control into position
     func position(of value: Float)->CGFloat{
         CGFloat(nearestTickIndex(to: value)) / CGFloat(tickValues.count)
     }
     // used to calculate domain value to be sent back to camera or whatever
     func value(at position: CGFloat)->Float{
         nearestTickValue(to: position)
     }
}

struct DiscreteScale: SliderScale, DiscreteScaleProvider{
    var tickValues: [Float]
    var isDiscrete = true
    
    func format(_ value: Float) -> String {
        "\(Int(round(value)))"
//        "\(Int(round(1/value)))"
    }
    
    var minValue: Float
    var maxValue: Float

    
    init(values: [Float]){
        self.tickValues = values
        minValue = values.min()!
        maxValue = values.max()!
    }
    
  
}

struct DiscreteScaleInverted: SliderScale, DiscreteScaleProvider{

    var tickValues: [Float]
    var isDiscrete = true
    
    func format(_ value: Float) -> String {
        value.isNaN || value == 0 ? ""  : "\(Int(round(1/value)))"
    }
    
    var minValue: Float
    var maxValue: Float

    init(values: [Float]){
        self.tickValues = values.map{ 1 / $0 }.reversed()
        minValue = values.min()!
        maxValue = values.max()!
    }
    
}

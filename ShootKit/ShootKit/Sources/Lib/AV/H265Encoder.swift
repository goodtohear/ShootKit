//
//  H265Encoder.swift
//  TPVideoCall
//
//  Created by Truc Pham on 25/05/2022.
//

import Foundation
import VideoToolbox

protocol H265EncoderDelegate:AnyObject, ConnectionLogger {
    func videoEncoderDidYieldVideoData(_ encoder : H265Encoder, compressedVideo : Data)
    func videoEncoderDidExtractParameterSet(_ encoder : H265Encoder, parameterSet: [Data])
    func videoEncoderDidEncodeSampleBuffer(_ encoder: H265Encoder, sampleBuffer: CMSampleBuffer)
    func videoEncoderDidFail(_ encoder: H265Encoder, error: OSStatus)
}

class H265Encoder {
    weak var delegate : H265EncoderDelegate?
    private var frameID:Int64 = 0
    var parameterSet: [Data]?
    var width: Int32 = 1920
    var height:Int32 = 1080
    var bitRate : Int32 = 0 // specified below
    var fps : Int32 = 0 // specified below
    
    @Published var totalBytesEncoded: Int = 0
    
    func addToTotal(bytes: Int){
        DispatchQueue.main.async { [weak self] in
            self?.totalBytesEncoded += bytes
        }
    }
    
    private var encodeQueue = DispatchQueue(label: "encode")
    private var callBackQueue = DispatchQueue(label: "callBack")
    
    var encodeSession:VTCompressionSession?
    var encodeCallBack:VTCompressionOutputCallback?
    var codecType: CMVideoCodecType
    
    init(codecType: CMVideoCodecType = kCMVideoCodecType_HEVC, width:Int32, height:Int32, bitRate : Int32?, fps: Int32?) {
        self.codecType = codecType
        self.width = width
        self.height = height
        self.bitRate = bitRate != nil ? bitRate! : height * 3 * 4
        self.fps = (fps != nil) ? fps! : 30
        delegate?.log(message:"Encoder configuration size: \(self.width)x\(self.height) bitRate: \(self.bitRate) fps: \(self.fps)", color: .systemGreen)
        setCallBack()
        initVideoToolBox()
    }
    
    private func initVideoToolBox() {
        let hevcSupported = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        if !hevcSupported {
            delegate?.log(message: "HEVC hardware encoding not supported on this device", color: .systemRed)
            return
        }
        //create VTCompressionSession
        let state = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width, height: height, codecType: codecType,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encodeCallBack ,
            refcon:
//                unsafeBitCast(self, to: UnsafeMutableRawPointer.self),
                 UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
            compressionSessionOut: &self.encodeSession)
        
        if state != noErr {
            delegate?.log(message: "create VTCompressionSession failed", color: .systemRed)
            return
        }
        
        guard let encodeSession = encodeSession else { return }
        
        //Set real-time encoding output
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        //Set encoding method
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        //Set whether to generate B frames (because B frames are not necessary when decoding, B frames can be discarded)
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        //Set key frame interval
        var frameInterval = 10
        let number = CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &frameInterval)
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: number)
        
        //Set the desired frame rate, not the actual frame rate
        let fpscf = CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &fps)
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fpscf)
        
        //Set the average bit rate, the unit is bps. If the bit rate is higher, it will be very clear, but at the same time the file will be larger. If the bit rate is small, the image will sometimes be blurred, but it can barely be seen
        //Code rate calculation formula reference notes
        //        var bitrate = width * height * 3 * 4
        let bitrateAverage = CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &bitRate)
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrateAverage)
        
        //Bit rate limit
        let bitRatesLimit :CFArray = [bitRate * 2,1] as CFArray
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_DataRateLimits, value: bitRatesLimit)
        
        VTSessionSetProperty(encodeSession, key: kVTVideoEncoderList_IsHardwareAccelerated, value: hevcSupported ? kCFBooleanTrue : kCFBooleanFalse)
        
        if #available(iOS 14.5,macOS 11.3, *) {
            VTSessionSetProperty(encodeSession, key: kVTVideoEncoderSpecification_EnableLowLatencyRateControl, value: kCFBooleanTrue)
      
        }
//        VTSessionSetProperty(encodeSession, key: kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder, value: kCFBooleanTrue)
        
    }
    
    private func setCallBack()  {
        //Coding complete callback
        encodeCallBack = {(outputCallbackRefCon, sourceFrameRefCon, status, flag, sampleBuffer)  in
            guard let outputCallbackRefCon = outputCallbackRefCon else {return}
            let encoder : H265Encoder =
//                unsafeBitCast(outputCallbackRefCon, to: H265Encoder.self)
                 Unmanaged<H265Encoder>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
            let callBackQueue = encoder.callBackQueue // cos we were hitting EXC_BAD_ACCESS?
            
            guard let sampleBuffer = sampleBuffer else {
                return
            }
            
           
            /// 0. Raw byte data 8 bytes
            let buffer : [UInt8] = [0x00,0x00,0x00,0x01]
            /// 1. [UInt8] -> UnsafeBufferPointer<UInt8>

            
            let attachArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)

            let strkey = unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self)
            let cfDic = unsafeBitCast(CFArrayGetValueAtIndex(attachArray, 0), to: CFDictionary.self)
            let keyFrame = !CFDictionaryContainsKey(cfDic, strkey)//Without this key, it means synchronization, which is a key frame
            
            //  Obtain sps pps
            if keyFrame && encoder.parameterSet == nil{
                let parameterSet = getParameterSet(sampleBuffer)
                if parameterSet.count > 0 {
                    DispatchQueue.main.async { [weak encoder] in
                        encoder?.parameterSet = parameterSet
                        encoder?.delegate?.log(message: "Encoding parameters extracted from sampleBuffer: \(parameterSet)", color: .green)
                    }
                    callBackQueue.async {
                        encoder.delegate?.videoEncoderDidExtractParameterSet(encoder, parameterSet: parameterSet)
                    }
                }
            }
            // --------- data input ----------
            
            guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
            //                let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            //                let timeAgo = CMTimeSubtract(timeStamp, CMClockGetTime(CMClockGetHostTimeClock()))
            //                encoder.delegate?.log(message: "Encoded buffer with timestamp \(timeStamp.seconds) \(timeAgo.seconds)")
            //var arr = [Int8]()
            //let pointer = arr.withUnsafeMutableBufferPointer({$0})
            var dataPointer: UnsafeMutablePointer<Int8>?  = nil
            var totalLength :Int = 0
            let blockState = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
            if blockState != noErr{
                encoder.delegate?.log(message: "Failed to get data\(blockState)", color: .red)
                return
            }
            // now dataPointer has our blockBuffer
            
            var data = Data(capacity: totalLength)
            let p = unsafeBitCast(dataPointer, to: UnsafePointer<UInt8>.self)
            data.append(p, count: totalLength)
            let byteCount = data.count
            
            callBackQueue.async { [weak encoder] in
                if let encoder = encoder{
                    encoder.delegate?.videoEncoderDidYieldVideoData(encoder, compressedVideo: data)
                    encoder.addToTotal(bytes: byteCount)
                }
            }
        }
    }
    

    
    //Start coding
    func encode(_ sampleBuffer:CMSampleBuffer){
        guard VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) else { return }
        if self.encodeSession == nil {
            initVideoToolBox()
        }
        encodeQueue.async {[weak self] in
            guard let self = self, var imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), let encodeSession = self.encodeSession else { return }
            imageBuffer = Unmanaged<CVImageBuffer>.passRetained(imageBuffer).takeRetainedValue()
//        encodeQueue.async {
//            guard var imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), let encodeSession = self.encodeSession else { return }
//            imageBuffer = Unmanaged<CVImageBuffer>.passUnretained(imageBuffer).takeRetainedValue()
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let duration = CMSampleBufferGetDuration(sampleBuffer)
//            let time = CMTime(value: self.frameID, timescale: 100)
            var flags: VTEncodeInfoFlags = VTEncodeInfoFlags()
            let state = VTCompressionSessionEncodeFrame(encodeSession, imageBuffer: imageBuffer, presentationTimeStamp: time, duration: duration, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
            if state != noErr{
                self.delegate?.log(message: "encode failure \(OSErrorCodeDescription(state))", color: .red)
                self.delegate?.videoEncoderDidFail(self, error: state)
            }
        }
        
    }
    
    deinit {
        if let encodeSession = encodeSession {
            VTCompressionSessionCompleteFrames(encodeSession, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(encodeSession);
//            self.encodeSession = nil;
        }
    }
}

private func getParameterSet(_ sampleBuffer: CMSampleBuffer) -> [Data] {
    var result = [Data]()
    let codecStartCode =  [UInt8](arrayLiteral: 0x00, 0x00, 0x00, 0x01)
//    parameterSet.append(contentsOf: codecStartCode)
    guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return []}
    
    var numParams = 0
    CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(description, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &numParams, nalUnitHeaderLengthOut: nil)
    // in H264 Stream, index 0 == sps, 1 == pps
    // in HEVC Stream, index 0 == vps, 1 == sps, 2 == pps
    for index in 0 ..< numParams {
        var parameterSetPointer: UnsafePointer<UInt8>?
        var parameterSetLength = 0
        CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(description, parameterSetIndex: index, parameterSetPointerOut: &parameterSetPointer, parameterSetSizeOut: &parameterSetLength, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
        
        if let parameterSetPointer = parameterSetPointer{
            var data = Data()
            
            data.append(contentsOf: codecStartCode)
            data.append(parameterSetPointer, count: parameterSetLength)
            
            result.append(data)
        }
    }
    
    return result
}

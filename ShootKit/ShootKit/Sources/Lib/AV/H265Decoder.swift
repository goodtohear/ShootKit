//
//  H265Decoder.swift
//  TPVideoCall
//
//  Created by Truc Pham on 25/05/2022.
//

import Foundation
import VideoToolbox
import OSLog

protocol H265DecoderDelegate:AnyObject, ConnectionLogger{
    func videoDecoder(_ decoder: H265Decoder, failedWith error: OSStatus)
    func videoDecoderDidDecodePixelBuffer(_ decoder: H265Decoder, pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, presentationDuration: CMTime)
}

class H265Decoder {
    weak var delegate : H265DecoderDelegate?
    var expectsNalu: Bool = true
    var width: Int32
    var height:Int32
    
    var decodeQueue = DispatchQueue(label: "decode") // both serial queues
    var callBackQueue:DispatchQueue
    var decodeDesc : CMVideoFormatDescription?
    
    var parameterSet: [Data]?{
        didSet{
            DispatchQueue.main.async {
                self.parameterSetView = self.parameterSet
            }
        }
    }
    @Published var parameterSetView: [Data]?

    @Published var totalBytesDecoded: Int = 0
    
    var decompressionSession : VTDecompressionSession?

    /// Converts the sender's timestamps to this Mac's host clock.
    let remoteClockMap = RemoteClockMap()
    private let jsonDecoder = JSONDecoder()
    var callback : VTDecompressionOutputCallback?
    
    var pixelBufferPool: CVPixelBufferPool?
    private var outputBufferAuxAttributes: NSDictionary?

    
    
    public init( width: Int32, height: Int32, callbackQueue: DispatchQueue) {
        self.width = width
        self.height = height
        self.callBackQueue = callbackQueue
    }
    
    func initDecoder() -> Bool {
        
        if decompressionSession != nil {
            return true
        }
        guard let parameterSet = parameterSet else {
            return false
        }
        //var frameData = Data(capacity: Int(size))
        //frameData.append(length, count: 4)
        //let point :UnsafePointer<UInt8> = [UInt8](data).withUnsafeBufferPointer({$0}).baseAddress!
        //frameData.append(point + UnsafePointer<UInt8>.Stride(4), count: Int(naluSize))
        //Processing sps/pps
        
        let parameterValues = parameterSet.map { data in
            var result = [UInt8]()
            [UInt8](data).suffix(from: 4).forEach { (value) in
                result.append(value)
            }
            return result
        }

        
        let parameterSetPointers = parameterValues.compactMap { $0.withUnsafeBufferPointer{$0}.baseAddress}
        
        let sizes = parameterValues.map{$0.count}
        
        /**
         Set decoding parameters according to sps pps
         param kCFAllocatorDefault allocator
         param 2 Number of parameters
         param parameterSetPointers parameter set pointers
         param parameterSetSizes parameter set size
         length of param naluHeaderLen nalu nalu start code 4
         param _decodeDesc Decoder description
         return status
         */
        let descriptionState = CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: parameterSetPointers.count, parameterSetPointers: parameterSetPointers, parameterSetSizes: sizes, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &decodeDesc)
        if descriptionState != noErr {
            // error reference (I'm getting 12714) https://www.osstatus.com/search/results?platform=all&framework=all
            // -12714 = kCMFormatDescriptionBridgeError_InvalidSerializedSampleDescription
            delegate?.log(message: "Description creation failed with error \(ErrorCodeLookup[descriptionState] ?? "\(descriptionState)") for , sizes: \(sizes)", color: .red )
            return false
        }
        guard let decodeDesc = decodeDesc else { return false}
        //Decoding callback setting
        /*
         VTDecompressionOutputCallbackRecord is a simple structure with a pointer (decompressionOutputCallback) to the callback method after the frame is decompressed. You need to provide an instance (decompressionOutputRefCon) where this callback method can be found. The VTDecompressionOutputCallback callback method includes seven parameters:
         Parameter 1: Reference of the callback
         Parameter 2: Reference of the frame
         Parameter 3: A status identifier (contains undefined codes)
         Parameter 4: Indicate synchronous/asynchronous decoding, or whether the decoder intends to drop frames
         Parameter 5: Buffer of the actual image
         Parameter 6: Timestamp of occurrence
         Parameter 7: Duration of appearance
         */
        setCallBack()
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: callback,
            decompressionOutputRefCon:
                // unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        /*
         Decoding parameters:
         * kCVPixelBufferPixelFormatTypeKey: the output data format of the camera
         kCVPixelBufferPixelFormatTypeKey, the measured available value is
         kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, which is 420v
         kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, which is 420f
         kCVPixelFormatType_32BGRA, iOS converts YUV to BGRA format internally
         YUV420 is generally used for standard-definition video, and YUV422 is used for high-definition video. The limitation here is surprising. However, under the same conditions, the calculation time and transmission pressure of YUV420 are smaller than those of YUV422.
         
         * kCVPixelBufferWidthKey/kCVPixelBufferHeightKey: the resolution of the video source width*height
         * kCVPixelBufferOpenGLCompatibilityKey: It allows the decoded image to be drawn directly in the context of OpenGL instead of copying data between the bus and the CPU. This is sometimes called a zero-copy channel, because the undecoded image is copied during the drawing process.
         
         */
        let imageBufferAttributes = [
//            kCVPixelBufferPixelFormatTypeKey:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA, // FORCE A CONVERSION COS I'M USING IT ELSEWHERE?
//            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_422YpCbCr8, // this comes through correctly in the pixel buffer
            kCVPixelBufferWidthKey:width,
            kCVPixelBufferHeightKey:height,
            kCVPixelBufferMetalCompatibilityKey: true,
            //            kCVPixelBufferOpenGLCompatibilityKey:true
        ] as [CFString : Any]
        
        if pixelBufferPool == nil {
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, imageBufferAttributes as NSDictionary, &pixelBufferPool)
            outputBufferAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: 5] // not used anywherez
        }
//
        //Create session
        
        /*!
         @function VTDecompressionSessionCreate
         @abstract creates a session for decompressing video frames.
         @discussion The decompressed frame will be sent out by calling OutputCallback
         @param allocator memory session. By using the default kCFAllocatorDefault allocator.
         @param videoFormatDescription describes the source video frame
         @param videoDecoderSpecification specifies the specific video decoder that must be used. NULL
         @param destinationImageBufferAttributes describes the requirements of the source pixel buffer NULL
         @param outputCallback Callback called using the decompressed frame
         @param decompressionSessionOut points to a variable to receive a new decompression session
         */
        let state = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: decodeDesc, decoderSpecification: nil, imageBufferAttributes: imageBufferAttributes as CFDictionary, outputCallback: &callbackRecord, decompressionSessionOut: &decompressionSession)
        
        if state != noErr {
            delegate?.log(message: "Failed to create decodeSession \(OSErrorCodeDescription(state))", color: .red)
            return false
        }
        guard let decompressionSession = decompressionSession else { return false }
        VTSessionSetProperty(decompressionSession, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(self.decompressionSession!, key: kVTDecompressionPropertyKey_PixelBufferPool, value: pixelBufferPool!)
        
        delegate?.log(message: "Created decompression session with parameter set \(parameterSet)", color: .systemOrange)
        
        return true
        
    }
        
    //Successfully decoded back
    private func setCallBack()  {

       //(UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, OSStatus, VTDecodeInfoFlags, CVImageBuffer?, CMTime, CMTime) -> Void
        callback = { decompressionOutputRefCon, sourceFrameRefCon, status, inforFlags, imageBuffer, presentationTimeStamp, presentationDuration in
            guard let outputCallbackRefCon = decompressionOutputRefCon else { return }
            let decoder : H265Decoder =
                //unsafeBitCast(decompressionOutputRefCon, to: H265Decoder.self)
             Unmanaged<H265Decoder>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()

            if let delegate = decoder.delegate  {

                if inforFlags.contains(.frameDropped){
                    delegate.log(message: "Dropped frame", color: .red)
                }
                guard let imageBuffer = imageBuffer else {
                    delegate.log(message: "Decoding error: Image buffer creation failed - \(ErrorCodeLookup[status] ?? "\(status)")", color: .red)
                    decoder.callBackQueue.async {[weak delegate, weak decoder] in
                        guard let decoder else { return }
                        delegate?.videoDecoder(decoder, failedWith: status)
                    }
                    return
                }
                decoder.callBackQueue.async { [weak delegate, weak decoder] in
                    guard let delegate, let decoder else { return }
                    delegate.videoDecoderDidDecodePixelBuffer(decoder, pixelBuffer: imageBuffer, presentationTimeStamp: presentationTimeStamp, presentationDuration: presentationDuration)
                }
            }
        }
    }
    func decode(_ data: Data) {
        decodeQueue.async {[weak self] in
            guard let self = self else { return }
            let length:UInt32 =  UInt32(data.count)
//            self.delegate?.log(message: "will decode \(data)")
            self.decodeByte(data: data, size: length)
        }
    }
    /// Decodes a videoFrameWithHeader message. The timestamp handed to the delegate is the time
    /// on this Mac's host clock at which the frame should be displayed.
    func decodeFrameWithHeader(_ payload: Data) {
        let headerLengthSize = MemoryLayout<UInt32>.size
        guard payload.count > headerLengthSize else { return }
        let headerLength = Int(payload.prefix(headerLengthSize).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) })
        guard payload.count >= headerLengthSize + headerLength else { return }
        let headerData = payload.subdata(in: headerLengthSize ..< headerLengthSize + headerLength)
        guard let header = try? jsonDecoder.decode(VideoFrameHeader.self, from: headerData) else {
            delegate?.log(message: "Invalid video frame header \(headerData)", color: .red)
            return
        }
        let compressedFrame = payload.subdata(in: (headerLengthSize + headerLength) ..< payload.count)
        // Consult the clock map here, on arrival, not later on the decode queue where the frame may have waited.
        let displayTime = remoteClockMap.displayHostTime(forSenderPresentationTimeStamp: header.presentationTimeStamp)
        decodeQueue.async { [weak self] in
            self?.decodeByte(data: compressedFrame, size: UInt32(compressedFrame.count), displayTime: displayTime, duration: header.duration ?? .invalid)
        }
    }

    private func decodeByte(data:Data,size:UInt32, displayTime: CMTime = .invalid, duration: CMTime = .invalid) {
        if parameterSet == nil {
            return
        }
        if initDecoder(){
            decode(frame: [UInt8](data), size: size, displayTime: displayTime, duration: duration)
        }
    }
    
    private func decode(frame:[UInt8],size:UInt32, displayTime: CMTime, duration: CMTime) {
        //
        var blockBuffer: CMBlockBuffer?
        //        var memoryBlock = frame1.withUnsafeMutableBytes({$0}).baseAddress
        //        var ddd = Data(bytes: frame, count: Int(size))
        //Create blockBuffer
        /*!
         Parameter 1: structureAllocator kCFAllocatorDefault
         Parameter 2: memoryBlock frame
         Parameter 3: frame size
         Parameter 4: blockAllocator: Pass NULL
         Parameter 5: customBlockSource Pass NULL
         Parameter 6: offsetToData data offset
         Parameter 7: dataLength data length
         Parameter 8: flags function and control flags
         Parameter 9: newBBufOut blockBuffer address, cannot be empty
         */
        let blockState = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                            memoryBlock: nil,
                                                            blockLength: Int(size),
                                                            blockAllocator: kCFAllocatorDefault,
                                                            customBlockSource: nil,
                                                            offsetToData:0,
                                                            dataLength: Int(size),
                                                            flags: kCMBlockBufferAssureMemoryNowFlag,
                                                            blockBufferOut: &blockBuffer)
        if blockState != noErr {
            self.delegate?.log(message: "Failed to create blockBuffer \(OSErrorCodeDescription(blockState))", color: .red)
            return
        }
        // Copy the bytes into memory the block buffer owns, so they stay valid for as long as the decoder needs them.
        let copyState = CMBlockBufferReplaceDataBytes(with: frame, blockBuffer: blockBuffer!, offsetIntoDestination: 0, dataLength: Int(size))
        if copyState != noErr {
            self.delegate?.log(message: "Failed to copy frame into blockBuffer \(OSErrorCodeDescription(copyState))", color: .red)
            return
        }
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: displayTime, decodeTimeStamp: .invalid)
        var sampleSizeArray :[Int] = [Int(size)]
        var sampleBuffer :CMSampleBuffer?
        //Create sampleBuffer
        /*
         Parameter 1: allocator allocator, use the default memory allocation, kCFAllocatorDefault
         Parameter 2: blockBuffer. The data blockBuffer that needs to be encoded. Cannot be NULL
         Parameter 3: formatDescription, video output format
         Parameter 4: numSamples.CMSampleBuffer number.
         Parameter 5: numSampleTimingEntries must be 0,1,numSamples
         Parameter 6: sampleTimingArray. Array. Empty
         Parameter 7: numSampleSizeEntries defaults to 1
         Parameter 8: sampleSizeArray
         Parameter 9: sampleBuffer object
         */
        let readyState = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
                                                   dataBuffer: blockBuffer,
                                                   formatDescription: decodeDesc,
                                                   sampleCount: CMItemCount(1),
                                                   sampleTimingEntryCount: CMItemCount(1),
                                                   sampleTimingArray: &timing,
                                                   sampleSizeEntryCount: CMItemCount(1),
                                                   sampleSizeArray: &sampleSizeArray,
                                                   sampleBufferOut: &sampleBuffer)
        if readyState != noErr {
            self.delegate?.log(message: "Sample Buffer Create Ready failed \(OSErrorCodeDescription(readyState))", color: .red)
            return
        }
        
        guard let decompressionSession = self.decompressionSession, let sampleBuffer = sampleBuffer else { return }
        //Decode data
        /*
         Parameter 1: Decoding session
         Parameter 2: Source data CMsampleBuffer containing one or more video frames
         Parameter 3: Decoding flag
         Parameter 4: decoded data outputPixelBuffer
         Parameter 5: Synchronous/asynchronous decoding identification
         */
        let sourceFrame:UnsafeMutableRawPointer? = nil
        var inforFalg = VTDecodeInfoFlags.asynchronous
        let decodeState = VTDecompressionSessionDecodeFrame(
            decompressionSession,
            sampleBuffer: sampleBuffer,
            flags: VTDecodeFrameFlags._EnableAsynchronousDecompression,
            frameRefcon: sourceFrame,
            infoFlagsOut: &inforFalg
        )
        if decodeState != noErr {
            delegate?.log(message: "Decoding failed for \(decompressionSession) \(OSErrorCodeDescription(decodeState))", color: .red)
        }
//        let numberOfFramesBeingDecoded = kVTDecompressionPropertyKey_NumberOfFramesBeingDecoded
        DispatchQueue.main.async {
            self.totalBytesDecoded += Int(size)
//            self.numberOfFramesBeingDecoded = numberOfFramesBeingDecoded
        }
    }
    
    deinit {
        if let decompressionSession = self.decompressionSession {
            VTDecompressionSessionInvalidate(decompressionSession)
            self.decompressionSession = nil
        }
        
    }
}

//
//  OSErrorCodeLookup.swift
//  TelestratorApp
//
//  Created by Michael Forrest on 03/02/2023.
//

import Foundation
import VideoToolbox
// https://www.osstatus.com/search/results?platform=all&framework=all
let ErrorCodeLookup = [
    kCMFormatDescriptionBridgeError_InvalidSerializedSampleDescription: "kCMFormatDescriptionBridgeError_InvalidSerializedSampleDescription",
    kCMFormatDescriptionError_InvalidParameter: "kCMFormatDescriptionError_InvalidParameter",
    kCMBlockBufferBadLengthParameterErr: "kCMBlockBufferBadLengthParameterErr",
    kCMFormatDescriptionBridgeError_InvalidSlice: "kCMFormatDescriptionBridgeError_InvalidSlice",
    kVTVideoDecoderBadDataErr: "kVTVideoDecoderBadDataErr",
    kVTVideoDecoderReferenceMissingErr: "kVTVideoDecoderReferenceMissingErr",
    kVTInvalidSessionErr: "kVTInvalidSessionErr",
]
func OSErrorCodeDescription(_ code: OSStatus)->String{
    "\(ErrorCodeLookup[code] ?? "\(code))")"
}

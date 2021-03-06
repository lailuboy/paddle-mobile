/* Copyright (c) 2018 PaddlePaddle Authors. All Rights Reserved.
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License. */

import Foundation

class FetchKernel<P: PrecisionProtocol>: Kernel, Computable {
    var expectedTranspose: [Int]?
    var device: MTLDevice?
    var initContext: InitContext?
    
    required init(device: MTLDevice, param: FetchParam<P>, initContext: InitContext) throws {
        param.output.initBuffer(device: device)
        if GlobalConfig.shared.computePrecision == .Float16 {
            if param.input.transpose == [0, 2, 3, 1] {
                super.init(device: device, inFunctionName: "fetch_half", initContext: initContext)
            } else if param.input.transpose == [0, 1, 2, 3] {
                switch param.input.tensorDim.cout() {
                case 1, 2:
                    super.init(device: device, inFunctionName: "fetch_1or2_half", initContext: initContext)
                case 4:
                    expectedTranspose = [0, 2, 3, 1]
                    super.init(device: device, inFunctionName: "fetch_half", initContext: initContext)
                default:
                    fatalError(" not support ")
                }
            } else {
                fatalError(" not support ")
            }
        } else if GlobalConfig.shared.computePrecision == .Float32 {
            if param.input.transpose == [0, 2, 3, 1] {
                super.init(device: device, inFunctionName: "fetch_float", initContext: initContext)
            } else if param.input.transpose == [0, 1, 2, 3] {
                switch param.input.tensorDim.cout() {
                case 1, 2:
                    super.init(device: device, inFunctionName: "fetch_1or2_float", initContext: initContext)
                case 4:
                    expectedTranspose = [0, 2, 3, 1]
                    super.init(device: device, inFunctionName: "fetch_float", initContext: initContext)
                default:
                    fatalError(" not support ")
                }
            } else {
                fatalError(" not support ")
            }
        } else {
            fatalError(" not support ")
        }
        self.device = device
        self.initContext = initContext
    }
    
    func compute(commandBuffer: MTLCommandBuffer, param: FetchParam<P>) throws {
        var input = param.input
        if let expectedTranspose = expectedTranspose {
            if param.input.transpose != expectedTranspose {
                if let device = device, let initContext = initContext, let transposedInput = encodeTransposeInput(input: param.input, toTranspose: expectedTranspose, commandBuffer: commandBuffer, device: device, initContext: initContext) {
                    input = transposedInput
                } else {
                    print("input transpose failed in slice kernel")
                }
            }
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw PaddleMobileError.predictError(message: " encode is nil")
        }
        encoder.setTexture(input.metalTexture, index: 0)
        encoder.setBuffer(param.output.resultBuffer!, offset: 0, index: 0)
        encoder.dispatch(computePipline: pipline, outTexture: param.input.metalTexture)
        encoder.endEncoding()
    }
}

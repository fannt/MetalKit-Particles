//
//  ParticleLab.swift
//  MetalParticles
//
//  Created by Simon Gladman on 04/04/2015.
//  Copyright (c) 2015 Simon Gladman. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.

//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>

import Metal
import MetalKit
import GameplayKit

class ParticleLab: MTKView
{
    let imageWidth: UInt
    let imageHeight: UInt
    
    fileprivate var imageWidthFloatBuffer: MTLBuffer!
    fileprivate var imageHeightFloatBuffer: MTLBuffer!
    
    let bytesPerRow: Int
    let region: MTLRegion
    let blankBitmapRawData : [UInt8]
    
    fileprivate var kernelFunction: MTLFunction!
    fileprivate var pipelineState: MTLComputePipelineState!
    fileprivate var defaultLibrary: MTLLibrary! = nil
    fileprivate var commandQueue: MTLCommandQueue! = nil
    
    fileprivate var errorFlag:Bool = false
    
    fileprivate var threadsPerThreadgroup:MTLSize!
    fileprivate var threadgroupsPerGrid:MTLSize!
    
    let particleCount: Int
    let alignment:Int = 0x4000
    let particlesMemoryByteSize:Int
    
    fileprivate var particlesMemory:UnsafeMutableRawPointer? = nil
    fileprivate var particlesVoidPtr: OpaquePointer!
    fileprivate var particlesParticlePtr: UnsafeMutablePointer<Particle>!
    fileprivate var particlesParticleBufferPtr: UnsafeMutableBufferPointer<Particle>!
    
    fileprivate var gravityWellParticle = Particle(A: Vector4(x: 0, y: 0, z: 0, w: 0),
        B: Vector4(x: 0, y: 0, z: 0, w: 0),
        C: Vector4(x: 0, y: 0, z: 0, w: 0),
        D: Vector4(x: 0, y: 0, z: 0, w: 0))
    
    let particleSize = MemoryLayout<Particle>.size
    let particleColorSize = MemoryLayout<ParticleColor>.size
    let boolSize = MemoryLayout<Bool>.size
    let floatSize = MemoryLayout<Float>.size
    
    weak var particleLabDelegate: ParticleLabDelegate?
    
    var particleColor = ParticleColor(R: 1, G: 0.5, B: 0.2, A: 1)
    var dragFactor: Float = 0.97
    var respawnOutOfBoundsParticles = true
    var clearOnStep = true
    
    fileprivate var frameStartTime: CFAbsoluteTime!
    fileprivate var frameNumber = 0
    
    var particlesBufferNoCopy: MTLBuffer!
    
    init(width: UInt, height: UInt, numParticles: ParticleCount)
    {
        particleCount = numParticles.rawValue
        
        imageWidth = width
        imageHeight = height
        
        bytesPerRow = Int(4 * imageWidth)
        
        region = MTLRegionMake2D(0, 0, Int(imageWidth), Int(imageHeight))
        blankBitmapRawData = [UInt8](repeating: 0, count: Int(imageWidth * imageHeight * 4))
        particlesMemoryByteSize = particleCount * MemoryLayout<Particle>.size
        
        super.init(frame: CGRect(x: 0, y: 0, width: Int(width), height: Int(height)), device:  MTLCreateSystemDefaultDevice())
        
        framebufferOnly = false
        colorPixelFormat = MTLPixelFormat.bgra8Unorm
        sampleCount = 1
        preferredFramesPerSecond = 60
        
        drawableSize = CGSize(width: CGFloat(imageWidth), height: CGFloat(imageHeight));
       
        setUpParticles()
        
        setUpMetal()
        
        particlesBufferNoCopy = device!.makeBuffer(bytesNoCopy: particlesMemory!, length: Int(particlesMemoryByteSize), options: MTLResourceOptions(), deallocator: nil)
    }
    
    required init(coder aDecoder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit
    {
        free(particlesMemory)
    }
    
    fileprivate func setUpParticles()
    {
        posix_memalign(&particlesMemory, alignment, particlesMemoryByteSize)
        
        particlesVoidPtr = OpaquePointer(particlesMemory)
        particlesParticlePtr = UnsafeMutablePointer<Particle>(particlesVoidPtr)
        particlesParticleBufferPtr = UnsafeMutableBufferPointer(start: particlesParticlePtr, count: particleCount)
        
        resetParticles()
        resetGravityWells()
    }
    
    func resetGravityWells()
    {
        setGravityWellProperties(gravityWell: .one, normalisedPositionX: 0.25, normalisedPositionY: 0.75, mass: 10, spin: 0.2)
        setGravityWellProperties(gravityWell: .two, normalisedPositionX: 0.25, normalisedPositionY: 0.25, mass: 10, spin: -0.2)
        setGravityWellProperties(gravityWell: .three, normalisedPositionX: 0.75, normalisedPositionY: 0.25, mass: 10, spin: 0.2)
        setGravityWellProperties(gravityWell: .four, normalisedPositionX: 0.75, normalisedPositionY: 0.75, mass: 10, spin: -0.2)
    }
    
    func resetParticles(_ edgesOnly: Bool = false, distribution: Distribution = Distribution.gaussian)
    {
        func rand() -> Float32
        {
            return Float(drand48() - 0.5) * 0.005
        }
        
        let imageWidthDouble = Double(imageWidth)
        let imageHeightDouble = Double(imageHeight)
        
        let randomSource = GKRandomSource()
        
        let randomWidth: GKRandomDistribution
        let randomHeight: GKRandomDistribution
        
        switch distribution
        {
        case .gaussian:
            randomWidth = GKGaussianDistribution(randomSource: randomSource, lowestValue: 0, highestValue: Int(imageWidthDouble))
            randomHeight = GKGaussianDistribution(randomSource: randomSource, lowestValue: 0, highestValue: Int(imageHeightDouble))
            
        case .uniform:
            randomWidth = GKShuffledDistribution(randomSource: randomSource, lowestValue: 0, highestValue: Int(imageWidthDouble))
            randomHeight = GKShuffledDistribution(randomSource: randomSource, lowestValue: 0, highestValue: Int(imageHeightDouble))
        }
        
        for index in particlesParticleBufferPtr.startIndex ..< particlesParticleBufferPtr.endIndex
        {
            var positionAX = Float(randomWidth.nextInt())
            var positionAY = Float(randomHeight.nextInt())
            
            var positionBX = Float(randomWidth.nextInt())
            var positionBY = Float(randomHeight.nextInt())
            
            var positionCX = Float(randomWidth.nextInt())
            var positionCY = Float(randomHeight.nextInt())
            
            var positionDX = Float(randomWidth.nextInt())
            var positionDY = Float(randomHeight.nextInt())
            
            if edgesOnly
            {
                let positionRule = Int(arc4random() % 4)
                
                if positionRule == 0
                {
                    positionAX = 0
                    positionBX = 0
                    positionCX = 0
                    positionDX = 0
                }
                else if positionRule == 1
                {
                    positionAX = Float(imageWidth)
                    positionBX = Float(imageWidth)
                    positionCX = Float(imageWidth)
                    positionDX = Float(imageWidth)
                }
                else if positionRule == 2
                {
                    positionAY = 0
                    positionBY = 0
                    positionCY = 0
                    positionDY = 0
                }
                else
                {
                    positionAY = Float(imageHeight)
                    positionBY = Float(imageHeight)
                    positionCY = Float(imageHeight)
                    positionDY = Float(imageHeight)
                }
            }
            
            let particle = Particle(A: Vector4(x: positionAX, y: positionAY, z: rand(), w: rand()),
                B: Vector4(x: positionBX, y: positionBY, z: rand(), w: rand()),
                C: Vector4(x: positionCX, y: positionCY, z: rand(), w: rand()),
                D: Vector4(x: positionDX, y: positionDY, z: rand(), w: rand()))
            
            particlesParticleBufferPtr[index] = particle
        }
    }
    

    override func draw(_ dirtyRect: CGRect)
    {
        step()
    }
    
    fileprivate func setUpMetal()
    {
        guard let device = MTLCreateSystemDefaultDevice() else
        {
            errorFlag = true
            
            particleLabDelegate?.particleLabMetalUnavailable()
            
            return
        }
  
        defaultLibrary = device.newDefaultLibrary()
        commandQueue = device.makeCommandQueue()
        
        kernelFunction = defaultLibrary.makeFunction(name: "particleRendererShader")
        
        do
        {
            try pipelineState = device.makeComputePipelineState(function: kernelFunction!)
        }
        catch
        {
            fatalError("newComputePipelineStateWithFunction failed ")
        }
        
        let threadExecutionWidth = pipelineState.threadExecutionWidth
        
        threadsPerThreadgroup = MTLSize(width:threadExecutionWidth,height:1,depth:1)
        threadgroupsPerGrid = MTLSize(width:particleCount / threadExecutionWidth, height:1, depth:1)
        
        var imageWidthFloat = Float(imageWidth)
        var imageHeightFloat = Float(imageHeight)
        
        imageWidthFloatBuffer =  device.makeBuffer(bytes: &imageWidthFloat, length: MemoryLayout<Float>.size, options: MTLResourceOptions())
        
        imageHeightFloatBuffer = device.makeBuffer(bytes: &imageHeightFloat, length: MemoryLayout<Float>.size, options: MTLResourceOptions())
        
        frameStartTime = CFAbsoluteTimeGetCurrent()
    }
    
    final fileprivate func step()
    {
        frameNumber += 1
        
        if frameNumber == 100
        {
            let frametime = (CFAbsoluteTimeGetCurrent() - frameStartTime) / 100

            let description = "\(Int(self.particleCount * 4)) particles at \(Int(1 / frametime)) fps"
            
            particleLabDelegate?.particleLabStatisticsDidUpdate(fps: Int(1 / frametime), description: description)
            
            frameStartTime = CFAbsoluteTimeGetCurrent()
            
            frameNumber = 0
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()
        
        commandEncoder.setComputePipelineState(pipelineState)

        commandEncoder.setBuffer(particlesBufferNoCopy, offset: 0, at: 0)
        commandEncoder.setBuffer(particlesBufferNoCopy, offset: 0, at: 1)
        
        commandEncoder.setBytes(&gravityWellParticle, length: particleSize, at: 2)
        commandEncoder.setBytes(&particleColor, length: particleColorSize, at: 3)
        
        commandEncoder.setBuffer(imageWidthFloatBuffer, offset: 0, at: 4)
        commandEncoder.setBuffer(imageHeightFloatBuffer, offset: 0, at: 5)
        
        commandEncoder.setBytes(&dragFactor, length: floatSize, at: 6)
        commandEncoder.setBytes(&respawnOutOfBoundsParticles, length: boolSize, at: 7)
        
        guard let drawable = currentDrawable else
        {
            Swift.print("currentDrawable returned nil")
            
            return
        }
        
        if clearOnStep
        {
            drawable.texture.replace(region: self.region, mipmapLevel: 0, withBytes: blankBitmapRawData, bytesPerRow: bytesPerRow)
        }
        
        commandEncoder.setTexture(drawable.texture, at: 0)
        
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        commandEncoder.endEncoding()

        commandBuffer.present(drawable)
        
        commandBuffer.commit()
        
        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.background).async
        {
            self.particleLabDelegate?.particleLabDidUpdate()
        }
    }
    

    
    final func getGravityWellNormalisedPosition(gravityWell: GravityWell) -> (x: Float, y: Float)
    {
        let returnPoint: (x: Float, y: Float)
        
        let imageWidthFloat = Float(imageWidth)
        let imageHeightFloat = Float(imageHeight)
        
        switch gravityWell
        {
        case .one:
            returnPoint = (x: gravityWellParticle.A.x / imageWidthFloat, y: gravityWellParticle.A.y / imageHeightFloat)
            
        case .two:
            returnPoint = (x: gravityWellParticle.B.x / imageWidthFloat, y: gravityWellParticle.B.y / imageHeightFloat)
            
        case .three:
            returnPoint = (x: gravityWellParticle.C.x / imageWidthFloat, y: gravityWellParticle.C.y / imageHeightFloat)
            
        case .four:
            returnPoint = (x: gravityWellParticle.D.x / imageWidthFloat, y: gravityWellParticle.D.y / imageHeightFloat)
        }
        
        return returnPoint
    }
    
    final func setGravityWellProperties(gravityWellIndex: Int, normalisedPositionX: Float, normalisedPositionY: Float, mass: Float, spin: Float)
    {
        switch gravityWellIndex
        {
        case 1:
            setGravityWellProperties(gravityWell: .two, normalisedPositionX: normalisedPositionX, normalisedPositionY: normalisedPositionY, mass: mass, spin: spin)
            
        case 2:
            setGravityWellProperties(gravityWell: .three, normalisedPositionX: normalisedPositionX, normalisedPositionY: normalisedPositionY, mass: mass, spin: spin)
            
        case 3:
            setGravityWellProperties(gravityWell: .four, normalisedPositionX: normalisedPositionX, normalisedPositionY: normalisedPositionY, mass: mass, spin: spin)
            
        default:
            setGravityWellProperties(gravityWell: .one, normalisedPositionX: normalisedPositionX, normalisedPositionY: normalisedPositionY, mass: mass, spin: spin)
        }
    }
    
    final func setGravityWellProperties(gravityWell: GravityWell, normalisedPositionX: Float, normalisedPositionY: Float, mass: Float, spin: Float)
    {
        let imageWidthFloat = Float(imageWidth)
        let imageHeightFloat = Float(imageHeight)
        
        switch gravityWell
        {
        case .one:
            gravityWellParticle.A.x = imageWidthFloat * normalisedPositionX
            gravityWellParticle.A.y = imageHeightFloat * normalisedPositionY
            gravityWellParticle.A.z = mass
            gravityWellParticle.A.w = spin
            
        case .two:
            gravityWellParticle.B.x = imageWidthFloat * normalisedPositionX
            gravityWellParticle.B.y = imageHeightFloat * normalisedPositionY
            gravityWellParticle.B.z = mass
            gravityWellParticle.B.w = spin
            
        case .three:
            gravityWellParticle.C.x = imageWidthFloat * normalisedPositionX
            gravityWellParticle.C.y = imageHeightFloat * normalisedPositionY
            gravityWellParticle.C.z = mass
            gravityWellParticle.C.w = spin
            
        case .four:
            gravityWellParticle.D.x = imageWidthFloat * normalisedPositionX
            gravityWellParticle.D.y = imageHeightFloat * normalisedPositionY
            gravityWellParticle.D.z = mass
            gravityWellParticle.D.w = spin
        }
    }
}

protocol ParticleLabDelegate: NSObjectProtocol
{
    func particleLabDidUpdate()
    func particleLabMetalUnavailable()
    
    func particleLabStatisticsDidUpdate(fps: Int, description: String)
}

enum Distribution
{
    case gaussian
    case uniform
}

enum GravityWell
{
    case one
    case two
    case three
    case four
}

//  Since each Particle instance defines four particles, the visible particle count
//  in the API is four times the number we need to create.
enum ParticleCount: Int
{
    case halfMillion = 131072
    case oneMillion =  262144
    case twoMillion =  524288
    case fourMillion = 1048576
    case eightMillion = 2097152
    case sixteenMillion = 4194304
}

//  Paticles are split into three classes. The supplied particle color defines one
//  third of the rendererd particles, the other two thirds use the supplied particle
//  color components but shifted to BRG and GBR
struct ParticleColor
{
    var R: Float32 = 0
    var G: Float32 = 0
    var B: Float32 = 0
    var A: Float32 = 1
}

struct Particle // Matrix4x4
{
    var A: Vector4 = Vector4(x: 0, y: 0, z: 0, w: 0)
    var B: Vector4 = Vector4(x: 0, y: 0, z: 0, w: 0)
    var C: Vector4 = Vector4(x: 0, y: 0, z: 0, w: 0)
    var D: Vector4 = Vector4(x: 0, y: 0, z: 0, w: 0)
}

// Regular particles use x and y for position and z and w for velocity
// gravity wells use x and y for position and z for mass and w for spin
struct Vector4
{
    var x: Float32 = 0
    var y: Float32 = 0
    var z: Float32 = 0
    var w: Float32 = 0
}


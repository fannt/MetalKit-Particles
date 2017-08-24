//
//  GameViewController.swift
//  OSXMetalParticles
//
//  Created by Simon Gladman on 12/06/2015.
//  Copyright (c) 2015 Simon Gladman. All rights reserved.
//

import Cocoa


class GameViewController : NSViewController, ParticleLabDelegate
{
    var gravityWellAngle: Float = 0
    var particleLab: ParticleLab!
    let floatPi = Float(Double.pi)
    
    let fpsLabel = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
    
    override func viewDidLoad()
    {        
        super.viewDidLoad()
        
        particleLab = ParticleLab(width: 1024, height: 768, numParticles: ParticleCount.fourMillion)
        
        particleLab.dragFactor = 0.85
        particleLab.respawnOutOfBoundsParticles = true
        particleLab.particleLabDelegate = self
        particleLab.clearOnStep = true
        
        view.addSubview(particleLab)
        
        fpsLabel.textColor = NSColor.white
        fpsLabel.isEditable = false
        fpsLabel.drawsBackground = false
        view.addSubview(fpsLabel)
    }

    func particleLabMetalUnavailable()
    {
        // handle metal unavailable here
    }
    
    func particleLabStatisticsDidUpdate(fps: Int, description: String)
    {
        DispatchQueue.main.async
        {
            self.fpsLabel.string = description
        }
    }
    
    func particleLabDidUpdate()
    {
        /*
        dispatch_async(dispatch_get_main_queue())
        {
            self.fpsLabel.string = self.particleLab.status
        }
        */
        cloudChamberStep()
    }
    
    func cloudChamberStep()
    {
        gravityWellAngle = gravityWellAngle + 0.02
        
        particleLab.setGravityWellProperties(gravityWell: .one,
            normalisedPositionX: 0.5 + 0.1 * sin(gravityWellAngle + floatPi * 0.5),
            normalisedPositionY: 0.5 + 0.1 * cos(gravityWellAngle + floatPi * 0.5),
            mass: 11 * sin(gravityWellAngle / 1.9),
            spin: 23 * cos(gravityWellAngle / 2.1))
        
        particleLab.setGravityWellProperties(gravityWell: .four,
            normalisedPositionX: 0.5 + 0.1 * sin(gravityWellAngle + floatPi * 1.5),
            normalisedPositionY: 0.5 + 0.1 * cos(gravityWellAngle + floatPi * 1.5),
            mass: 11 * sin(gravityWellAngle / 1.9),
            spin: 23 * cos(gravityWellAngle / 2.1))
        
        particleLab.setGravityWellProperties(gravityWell: .two,
            normalisedPositionX: 0.5 + (0.35 + sin(gravityWellAngle * 2.7)) * cos(gravityWellAngle / 1.3),
            normalisedPositionY: 0.5 + (0.35 + sin(gravityWellAngle * 2.7)) * sin(gravityWellAngle / 1.3),
            mass: 26 * cos(gravityWellAngle / 1.5),
            spin: -19 * sin(gravityWellAngle * 1.5))
        
        particleLab.setGravityWellProperties(gravityWell: .three,
            normalisedPositionX: 0.5 + (0.35 + sin(gravityWellAngle * 2.7)) * cos(gravityWellAngle / 1.3 + floatPi),
            normalisedPositionY: 0.5 + (0.35 + sin(gravityWellAngle * 2.7)) * sin(gravityWellAngle / 1.3 + floatPi),
            mass: 26 * cos(gravityWellAngle / 1.5),
            spin: -19 * sin(gravityWellAngle * 1.5))
    }
    
    
    
}

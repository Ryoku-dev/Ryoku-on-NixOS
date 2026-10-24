#pragma once

#include <QString>

struct SandyPass {
    QString keyA;   // outgoing image
    QString keyB;   // incoming image
    QString keyB2;  // previous incoming, cross-faded under keyB
    QString keyB3;  // one further back, faded in by bcut

    float center[2] = {0, 0};      // hero centre, item pixels
    float hero[2] = {0, 0};        // hero half extents, item pixels
    float resolution[2] = {0, 0};  // scene size, item pixels
    float grid[2] = {0, 0};        // particle grid columns, rows

    float progress = 0;  // morph 0..1
    float time = 0;      // seconds, for the turbulence and ring motion
    float dir = 1;       // +1 forward, -1 backward
    float seed = 0;
    float carry = 0;     // progress bias when a storm is re-armed mid-flight

    float bcut = 1;   // cross-fade cut between B2 and B3
    float bmix = 1;   // cross-fade between the incoming layers
    float swirl = 0;  // ring transition amount
    float wave = 0;   // 1 while a swap-loop wave is arched

    float videoIn = 0;   // live-video mix on the incoming layer
    float videoOut = 0;  // live-video mix on the outgoing layer
    float resScale = 1;  // < 1 renders offscreen then blits up

    float ringSpin = 1;
    float ringWave = 1;
    float ringSoft = 1;
    float ringSize = 1;

    float strands = 22;
    float twist = 1;
    float orbit = 1;
    float turbulence = 1;
    float waist = 1;
    float front = 0.65f;
    float fan = 0.6f;
    float arc = 1;
    float swapLoop = 0;
    float swapStyle = 1;  // shader index (1,2,3,6,7,8,10,11,13,16,17)
};

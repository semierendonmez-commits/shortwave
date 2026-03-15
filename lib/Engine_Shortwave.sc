// lib/Engine_Shortwave.sc
// Shortwave radio simulator
// 6 generative "stations" + atmospheric noise + tuner
// Single SynthDef, all stations run simultaneously
// Tuner position controls which stations are audible

Engine_Shortwave : CroneEngine {
  var <synth;
  var tuneBus, sigBus;

  *new { |context, doneCallback| ^super.new(context, doneCallback) }

  alloc {
    tuneBus = Bus.control(context.server, 1);
    sigBus  = Bus.control(context.server, 1);

    SynthDef(\shortwave, {
      arg tuner=50, // 0-100 "MHz" dial position
          bandwidth=3, // station reception width
          noise_floor=0.15, // background static level
          drift_rate=0.02, // how fast stations wander
          drift_amt=1.5, // how far they drift
          interference=0.3, // heterodyne interference amount
          crackle_rate=5, // atmospheric crackle density
          crackle_level=0.1,
          // station volumes (individual control)
          vol_1=0.8, vol_2=0.8, vol_3=0.8,
          vol_4=0.8, vol_5=0.8, vol_6=0.8,
          // global
          amp=0.7, quality=0.8, // quality: 0=degraded, 1=clear
          // buses
          tune_bus=0, sig_bus=0;

      // ── vars ─────────────────────────────────────────
      var station_freqs, station_drifts, station_sigs;
      var prox, sig_strength, nearest_dist;
      var stn1, stn2, stn3, stn4, stn5, stn6;
      var static_noise, crackle, heterodyne;
      var atmo, mix_l, mix_r, out_l, out_r;
      var t, drift_lfo;

      // ── station center frequencies (MHz) ─────────────
      // drift: each station slowly wanders
      drift_lfo = Array.fill(6, { |i|
        LFNoise1.kr(drift_rate * (1 + (i * 0.1))) * drift_amt
      });

      station_freqs = [15, 28, 42, 58, 72, 88] + drift_lfo;

      // ── proximity envelopes (gaussian fade) ──────────
      // how "close" the tuner is to each station
      prox = station_freqs.collect({ |freq|
        var dist = (tuner - freq).abs;
        var env = (dist.neg.squared / (bandwidth * bandwidth * 2)).exp;
        // add slight noise to signal for realism
        env = env * (1 + (LFNoise2.kr(0.5) * (1 - quality) * 0.3));
        env.clip(0, 1)
      });

      // signal strength: strongest nearby station
      sig_strength = prox.reduce(\max);
      Out.kr(sig_bus, sig_strength);
      Out.kr(tune_bus, tuner);

      // nearest station distance (for heterodyne)
      nearest_dist = station_freqs.collect({ |freq| (tuner - freq).abs }).reduce(\min);

      // ══════════════════════════════════════════════════
      // STATION 1: DRONE (15 MHz)
      // slowly evolving filtered noise pad
      // ══════════════════════════════════════════════════
      stn1 = {
        var n, f1, f2;
        n = PinkNoise.ar(0.5) + (SinOsc.ar(
          LFNoise1.kr(0.05).range(40, 120)) * 0.3);
        f1 = BPF.ar(n, LFNoise1.kr(0.08).range(200, 800), 0.3) * 2;
        f2 = BPF.ar(n, LFNoise1.kr(0.06).range(400, 1600), 0.2) * 1.5;
        (f1 + f2) * 0.4
      }.value;

      // ══════════════════════════════════════════════════
      // STATION 2: NUMBERS (28 MHz)
      // eerie sine tone beeps in repeating patterns
      // like a real numbers station broadcast
      // ══════════════════════════════════════════════════
      stn2 = {
        var tone, pattern, env, freq_seq;
        // pseudo-random repeating pattern
        pattern = LFPulse.kr(
          Demand.kr(Impulse.kr(3), 0,
            Dseq([3, 3, 3, 6, 3, 3, 12, 3, 3, 3, 3, 6], inf)),
          0, 0.3);
        // stepped frequency (5 tones repeating)
        freq_seq = Demand.kr(Impulse.kr(3), 0,
          Dseq([800, 1000, 800, 600, 1200, 800, 1000, 600], inf));
        tone = SinOsc.ar(Lag.kr(freq_seq, 0.01)) * pattern;
        tone = tone + (SinOsc.ar(Lag.kr(freq_seq, 0.01) * 2.01) * pattern * 0.15);
        tone * 0.5
      }.value;

      // ══════════════════════════════════════════════════
      // STATION 3: PULSE (42 MHz)
      // rhythmic shortwave pulses, like a radar or time signal
      // ══════════════════════════════════════════════════
      stn3 = {
        var imp, filt, rate;
        rate = LFNoise0.kr(0.2).range(2, 8).round(1);
        imp = Impulse.ar(rate) * 0.8;
        imp = imp + (Impulse.ar(rate * 2) * 0.2 * LFPulse.kr(0.5));
        filt = RLPF.ar(imp, LFNoise1.kr(0.3).range(1000, 4000), 0.3);
        filt + (BPF.ar(imp, 2400, 0.1) * 0.6)
      }.value;

      // ══════════════════════════════════════════════════
      // STATION 4: VOICE (58 MHz)
      // formant synthesis - vowel-like textures from noise
      // ghostly shortwave voices
      // ══════════════════════════════════════════════════
      stn4 = {
        var src, formants, vowel_idx, f1f, f2f, f3f;
        src = BrownNoise.ar(0.6) + (Impulse.ar(
          LFNoise0.kr(0.3).range(80, 160)) * 0.3);
        // 3 formant frequencies, slowly morphing between vowels
        vowel_idx = LFNoise1.kr(0.15).range(0, 1);
        f1f = LinLin.kr(vowel_idx, 0, 1, 270, 730); // a→e→i
        f2f = LinLin.kr(vowel_idx, 0, 1, 2300, 1090);
        f3f = LinLin.kr(vowel_idx, 0, 1, 3000, 2440);
        formants = BPF.ar(src, f1f, 0.08) * 3
                 + (BPF.ar(src, f2f, 0.06) * 2)
                 + (BPF.ar(src, f3f, 0.05) * 1);
        // add gentle pitch to give it a "speaking" quality
        formants = formants * LFPulse.kr(
          LFNoise0.kr(0.4).range(3, 7), 0,
          LFNoise1.kr(0.2).range(0.3, 0.7));
        formants * 0.35
      }.value;

      // ══════════════════════════════════════════════════
      // STATION 5: MORSE (72 MHz)
      // keyed sine wave, pseudo-random morse patterns
      // ══════════════════════════════════════════════════
      stn5 = {
        var tone, morse_env, dot_rate;
        dot_rate = LFNoise0.kr(0.1).range(6, 14);
        // random dots and dashes
        morse_env = LFPulse.kr(dot_rate, 0,
          Demand.kr(Impulse.kr(dot_rate), 0,
            Drand([0.15, 0.15, 0.15, 0.4, 0.4, 0.05], inf)));
        tone = SinOsc.ar(
          LFNoise0.kr(0.05).range(600, 1200).round(100)
        ) * morse_env;
        tone * 0.5
      }.value;

      // ══════════════════════════════════════════════════
      // STATION 6: MUSIC (88 MHz)
      // detuned harmonic series, fragmented melody
      // like catching a distant broadcast
      // ══════════════════════════════════════════════════
      stn6 = {
        var fund, harmonics, melody, env;
        fund = Demand.kr(Impulse.kr(LFNoise0.kr(0.2).range(1, 4)), 0,
          Drand([55, 65.4, 73.4, 82.4, 98, 110, 130.8, 146.8], inf));
        fund = Lag.kr(fund, 0.05);
        harmonics = SinOsc.ar(fund) * 0.3
          + (SinOsc.ar(fund * 2.01) * 0.2)   // slight detune
          + (SinOsc.ar(fund * 3.003) * 0.12)
          + (SinOsc.ar(fund * 4.998) * 0.08)
          + (SinOsc.ar(fund * 6.01) * 0.05);
        // intermittent envelope (signal cuts in and out)
        env = LFNoise1.kr(0.5).range(0.2, 1) *
              LFPulse.kr(LFNoise0.kr(0.15).range(0.3, 2), 0, 0.7);
        harmonics * env * 0.5
      }.value;

      // ══════════════════════════════════════════════════
      // ATMOSPHERE (always present)
      // ══════════════════════════════════════════════════

      // broadband static (louder between stations)
      static_noise = (WhiteNoise.ar(0.3) + (PinkNoise.ar(0.2)))
        * (1 - sig_strength) * noise_floor;

      // crackle (random pops)
      crackle = Dust.ar(crackle_rate) * crackle_level
        * LFNoise1.kr(2).range(0.3, 1);

      // heterodyne: beat frequency between tuner and nearest station
      // the classic shortwave whistle/squeal
      heterodyne = SinOsc.ar(
        nearest_dist.max(0.01) * LFNoise1.kr(0.3).range(30, 120)
      ) * interference * (1 - sig_strength).max(0) * 0.15;

      // ── MIX ──────────────────────────────────────────
      mix_l = (stn1 * prox[0] * vol_1)
            + (stn2 * prox[1] * vol_2)
            + (stn3 * prox[2] * vol_3)
            + (stn4 * prox[3] * vol_4)
            + (stn5 * prox[4] * vol_5)
            + (stn6 * prox[5] * vol_6);

      // stereo: each station slightly panned
      mix_r = (stn1 * prox[0] * vol_1 * 0.8)
            + (stn2 * prox[1] * vol_2 * 1.1)
            + (stn3 * prox[2] * vol_3 * 0.9)
            + (stn4 * prox[3] * vol_4 * 1.05)
            + (stn5 * prox[4] * vol_5 * 0.85)
            + (stn6 * prox[5] * vol_6 * 1.15);

      // quality degradation: add noise proportional to signal
      mix_l = mix_l + (WhiteNoise.ar(0.1) * sig_strength * (1 - quality));
      mix_r = mix_r + (WhiteNoise.ar(0.1) * sig_strength * (1 - quality));

      // add atmosphere
      out_l = mix_l + static_noise + crackle + heterodyne;
      out_r = mix_r + static_noise + (crackle * 0.7) + (heterodyne * -0.8);

      out_l = HPF.ar(out_l, 100); // radio doesn't go below ~100Hz
      out_r = HPF.ar(out_r, 100);

      // slight saturation (radio speaker character)
      out_l = (out_l * 2).tanh * 0.7;
      out_r = (out_r * 2).tanh * 0.7;

      Out.ar(0, [out_l, out_r] * amp);
    }).add;

    context.server.sync;

    synth = Synth.new(\shortwave, [
      \tune_bus, tuneBus.index,
      \sig_bus, sigBus.index,
    ], target: context.xg);

    // ── commands ────────────────────────────────────────
    [\tuner, \bandwidth, \noise_floor, \drift_rate, \drift_amt,
     \interference, \crackle_rate, \crackle_level,
     \vol_1, \vol_2, \vol_3, \vol_4, \vol_5, \vol_6,
     \amp, \quality
    ].do({ |key|
      this.addCommand(key, "f", { |msg| synth.set(key, msg[1]) });
    });

    // ── polls ──────────────────────────────────────────
    this.addPoll(\poll_tune, { tuneBus.getSynchronous });
    this.addPoll(\poll_sig,  { sigBus.getSynchronous });
  }

  free {
    if (synth.notNil)   { synth.free };
    if (tuneBus.notNil) { tuneBus.free };
    if (sigBus.notNil)  { sigBus.free };
  }
}

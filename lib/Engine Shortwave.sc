// lib/Engine_Shortwave.sc v3
// All-sample shortwave radio
// 8 granular station slots + cross-mod noise oscillators
// Sharp tuning, ring mod interference, signal degradation

Engine_Shortwave : CroneEngine {
  var <synth;
  var tuneBus, sigBus;
  var bufs; // array of 8 buffers

  *new { |context, doneCallback| ^super.new(context, doneCallback) }

  alloc {
    tuneBus = Bus.control(context.server, 1);
    sigBus  = Bus.control(context.server, 1);

    // 8 stereo sample buffers (30s each)
    bufs = Array.fill(8, { Buffer.alloc(context.server, 48000*30, 2) });

    SynthDef(\shortwave, {
      arg tuner=50, bw=1.0,
          // station center frequencies (set from Lua)
          sf1=10,sf2=22,sf3=34,sf4=46,sf5=58,sf6=70,sf7=82,sf8=94,
          // station volumes
          sv1=0.8,sv2=0.8,sv3=0.8,sv4=0.8,sv5=0.8,sv6=0.8,sv7=0.8,sv8=0.8,
          // station lengths
          sl1=1,sl2=1,sl3=1,sl4=1,sl5=1,sl6=1,sl7=1,sl8=1,
          // buffers
          b1=0,b2=0,b3=0,b4=0,b5=0,b6=0,b7=0,b8=0,
          // granular global
          grain_rate=0.7,  // overall grain density multiplier
          grain_size=0.15, // overall grain size multiplier
          // cross-mod noise oscillators
          noise_osc_a=80, noise_osc_b=3,
          noise_xmod=0.5,
          // atmosphere
          noise_floor=0.2, interf=0.5,
          crackle_dens=8, crackle_amp=0.12,
          drift_rate=0.03, drift_amt=2,
          quality=0.7,
          // output
          amp=0.7,
          tune_bus=0, sig_bus=0;

      // ── vars ─────────────────────────────────────────
      var dfs, proxs, sigs;
      var sig_max, noise_gate;
      var xmod_a, xmod_b, noise_sig;
      var static_n, crackle, hetero, nearest_d;
      var ring_sum, mix_mono;
      var out_l, out_r;
      var i_proxs; // intermediate for ring mod

      // ── drifting frequencies ──────────────────────────
      dfs = [
        sf1 + (LFNoise1.kr(drift_rate*1.0)*drift_amt),
        sf2 + (LFNoise1.kr(drift_rate*0.8)*drift_amt),
        sf3 + (LFNoise1.kr(drift_rate*1.2)*drift_amt),
        sf4 + (LFNoise1.kr(drift_rate*0.7)*drift_amt),
        sf5 + (LFNoise1.kr(drift_rate*1.1)*drift_amt),
        sf6 + (LFNoise1.kr(drift_rate*0.9)*drift_amt),
        sf7 + (LFNoise1.kr(drift_rate*1.3)*drift_amt),
        sf8 + (LFNoise1.kr(drift_rate*0.6)*drift_amt),
      ];

      // ── sharp gaussian proximity ─────────────────────
      proxs = dfs.collect({ |df|
        ((tuner - df).squared.neg / (bw * bw * 2)).exp
      });

      sig_max = proxs.reduce(\max);
      noise_gate = (1 - sig_max).max(0);
      Out.kr(sig_bus, sig_max);
      Out.kr(tune_bus, tuner);

      // ══════════════════════════════════════════════════
      // 8 GRANULAR SAMPLE STATIONS
      // each has unique granular character
      // ══════════════════════════════════════════════════
      sigs = [b1,b2,b3,b4,b5,b6,b7,b8].collect({ |buf, idx|
        var len, sv, prox, rate_var, pos_var, dens, gs;
        var trig_rate, trig, rd, env, sig_out;
        var pitch_wobble;

        len  = [sl1,sl2,sl3,sl4,sl5,sl6,sl7,sl8][idx];
        sv   = [sv1,sv2,sv3,sv4,sv5,sv6,sv7,sv8][idx];
        prox = proxs[idx];

        // each station has slightly different grain character
        // using idx to seed variation
        rate_var = LFNoise1.kr(0.05 + (idx*0.01)).range(0.3, 1.8)
          * grain_rate;
        pos_var = LFNoise1.kr(0.03 + (idx*0.007)).range(0, 0.9);
        dens = LFNoise1.kr(0.08 + (idx*0.015)).range(3, 25) * grain_rate;
        gs = LFNoise1.kr(0.04 + (idx*0.01)).range(0.03, 0.4) * grain_size;

        // grain trigger
        trig = Dust.ar(dens);

        // read with jitter
        rd = PlayBuf.ar(2, buf,
          rate_var * BufRateScale.kr(buf)
            * LFNoise1.kr(0.2 + (idx*0.05)).range(0.7, 1.3), // rate jitter
          trig,
          (pos_var + (LFNoise1.kr(0.1 + (idx*0.02)) * 0.15)).wrap(0,1)
            * BufFrames.kr(buf),
          1);

        // grain envelope
        env = EnvGen.ar(
          Env.linen(gs*0.3, gs, gs*0.5, 1, \sin), trig);

        // ionospheric flutter (slight pitch wobble when signal is weak)
        pitch_wobble = 1 + (LFNoise2.kr(3 + idx) * (1-prox) * 0.02);

        // mono mix of stereo
        sig_out = ((rd[0] + rd[1]) * 0.5) * env * sv * pitch_wobble;

        // occasional signal dropout (realistic fading)
        sig_out = sig_out * LFNoise1.kr(
          LFNoise0.kr(0.1).range(0.2, 2)).range(0.5, 1);

        sig_out
      });

      // ══════════════════════════════════════════════════
      // CROSS-MODULATING NOISE OSCILLATORS
      // character changes based on tuner position
      // louder between stations, muffled near stations
      // ══════════════════════════════════════════════════
      xmod_a = SinOsc.ar(
        noise_osc_a * (1 + (noise_gate * 2))
        + (SinOsc.ar(noise_osc_b * (1 + noise_gate)) * noise_xmod * noise_osc_a * 0.5)
      );
      xmod_b = LFTri.ar(
        noise_osc_b * (1 + (noise_gate * 3))
        + (xmod_a * noise_xmod * noise_osc_b * 0.3)
      );

      // noise character: between stations = harsh, near = muffled
      noise_sig = (xmod_a * 0.3 + xmod_b * 0.2)
        * noise_gate * noise_floor;
      // filter: muffled when somewhat near, harsher when far
      noise_sig = RLPF.ar(noise_sig,
        LinLin.kr(noise_gate, 0, 1, 300, 6000), 0.3);
      // add some crunch
      noise_sig = (noise_sig * (1 + (noise_gate * 4))).tanh * 0.4 * noise_floor;

      // ══════════════════════════════════════════════════
      // ATMOSPHERE
      // ══════════════════════════════════════════════════

      // broadband static
      static_n = (WhiteNoise.ar(0.12) + PinkNoise.ar(0.08))
        * noise_floor * (noise_gate + 0.05);

      // crackle
      crackle = Dust.ar(crackle_dens * (noise_gate + 0.2))
        * crackle_amp * LFNoise1.kr(4).range(0.2, 1);

      // heterodyne whistle
      nearest_d = dfs.collect({ |df| (tuner-df).abs }).reduce(\min);
      hetero = SinOsc.ar(
        nearest_d.max(0.01) * LFNoise1.kr(0.4).range(30, 180)
      ) * interf * noise_gate.squared * 0.2;

      // ══════════════════════════════════════════════════
      // MIX + INTERFERENCE
      // ══════════════════════════════════════════════════

      // weighted sum of all stations
      mix_mono = 0;
      i_proxs = Array.new(8);
      8.do({ |idx|
        mix_mono = mix_mono + (sigs[idx] * proxs[idx]);
        i_proxs = i_proxs.add(sigs[idx] * proxs[idx]);
      });

      // ring mod when stations overlap
      ring_sum = 0;
      4.do({ |idx|
        ring_sum = ring_sum + (
          i_proxs[idx*2] * i_proxs[(idx*2+1).min(7)]
        );
      });
      ring_sum = ring_sum * interf * 3;

      // quality degradation
      mix_mono = (mix_mono * quality)
        + (mix_mono * BrownNoise.ar(0.25) * (1-quality));

      // stereo spread (each station slightly different placement)
      out_l = mix_mono + ring_sum + noise_sig + static_n + crackle + hetero;
      out_r = mix_mono + (ring_sum * -0.7)
        + (noise_sig * LFNoise1.kr(2).range(0.5, 1))
        + (static_n * 0.85)
        + (crackle * LFNoise1.kr(5).range(0.3, 1))
        + (hetero * -0.6);

      // subtle per-station stereo
      4.do({ |idx|
        out_l = out_l + (i_proxs[idx*2] * 0.15);
        out_r = out_r + (i_proxs[(idx*2+1).min(7)] * 0.15);
      });

      // radio character: HPF + soft saturation
      out_l = HPF.ar(out_l, 120);
      out_r = HPF.ar(out_r, 120);
      out_l = (out_l * 2).tanh * 0.55;
      out_r = (out_r * 2).tanh * 0.55;

      Out.ar(0, [out_l, out_r] * amp);
    }).add;

    context.server.sync;

    synth = Synth.new(\shortwave, [
      \tune_bus, tuneBus.index, \sig_bus, sigBus.index,
      \b1, bufs[0].bufnum, \b2, bufs[1].bufnum,
      \b3, bufs[2].bufnum, \b4, bufs[3].bufnum,
      \b5, bufs[4].bufnum, \b6, bufs[5].bufnum,
      \b7, bufs[6].bufnum, \b8, bufs[7].bufnum,
    ], target: context.xg);

    // ── load sample into slot ──────────────────────────
    8.do({ |idx|
      var cmd = ("load_" ++ (idx+1)).asSymbol;
      this.addCommand(cmd, "s", { |msg|
        bufs[idx].free;
        bufs[idx] = Buffer.read(context.server, msg[1].asString, action: { |b|
          synth.set(
            [\b1,\b2,\b3,\b4,\b5,\b6,\b7,\b8][idx], b.bufnum,
            [\sl1,\sl2,\sl3,\sl4,\sl5,\sl6,\sl7,\sl8][idx], b.numFrames / b.sampleRate
          );
        });
      });
    });

    // ── float commands ─────────────────────────────────
    [\tuner, \bw, \noise_floor, \drift_rate, \drift_amt,
     \interf, \crackle_dens, \crackle_amp, \quality,
     \grain_rate, \grain_size,
     \noise_osc_a, \noise_osc_b, \noise_xmod,
     \sf1,\sf2,\sf3,\sf4,\sf5,\sf6,\sf7,\sf8,
     \sv1,\sv2,\sv3,\sv4,\sv5,\sv6,\sv7,\sv8,
     \sl1,\sl2,\sl3,\sl4,\sl5,\sl6,\sl7,\sl8,
     \amp
    ].do({ |key|
      this.addCommand(key, "f", { |msg| synth.set(key, msg[1]) });
    });

    this.addPoll(\poll_tune, { tuneBus.getSynchronous });
    this.addPoll(\poll_sig,  { sigBus.getSynchronous });
  }

  free {
    if(synth.notNil){synth.free};
    bufs.do({ |b| if(b.notNil){b.free} });
    if(tuneBus.notNil){tuneBus.free};
    if(sigBus.notNil){sigBus.free};
  }
}

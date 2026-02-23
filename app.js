/* =========================================
   BAVA — Live Caption App
   Main Application Logic
   ========================================= */

(function () {
  'use strict';

  // ==========================================
  // CONSTANTS & CONFIG
  // ==========================================
  const LANG = 'nl-NL';
  const STORAGE_KEY = 'bava_transcripts';
  const SETTINGS_KEY = 'bava_settings';
  const MAX_HISTORY = 50;
  const AUTO_RESTART_DELAY = 300;
  const SILENCE_TIMEOUT = 60000; // 1 minute of silence before auto-stop
  const SPEAKER_CHANGE_THRESHOLD = 1500; // 1.5s silence = potential speaker change
  const VOICE_MATCH_THRESHOLD = 0.65;     // similarity score to match existing speaker
  const VOICE_SAMPLE_INTERVAL = 80;       // ms between voice feature samples
  const VOICE_PROFILE_MIN_SAMPLES = 3;    // minimum samples before profile is reliable

  // Accessible color palette — distinguishable for colorblind users
  // Uses Wong's colorblind-safe palette + extras
  const SPEAKER_COLORS = [
    { name: 'Blauw',    hex: '#4a9eff', border: '#2b7de9' },
    { name: 'Oranje',   hex: '#e69f00', border: '#c98a00' },
    { name: 'Groen',    hex: '#009e73', border: '#007a59' },
    { name: 'Roze',     hex: '#cc79a7', border: '#b05e8c' },
    { name: 'Geel',     hex: '#f0e442', border: '#d4c830' },
    { name: 'Cyaan',    hex: '#56b4e9', border: '#3a9ad4' },
    { name: 'Rood',     hex: '#d55e00', border: '#b34d00' },
    { name: 'Paars',    hex: '#a855f7', border: '#8b3de0' },
  ];

  // ==========================================
  // STATE
  // ==========================================
  const state = {
    isListening: false,
    currentMode: 'conversation', // 'conversation' | 'tv' | 'history'
    recognition: null,
    audioContext: null,
    analyser: null,
    mediaStream: null,
    currentTranscript: '',
    sessionParagraphs: [],
    sessionStartTime: null,
    silenceTimer: null,
    restartTimer: null,
    volumeAnimFrame: null,
    // Speaker tracking
    currentSpeakerId: 0,
    speakerColorMap: {},      // speakerId -> colorIndex
    nextColorIndex: 0,
    lastSpeechTime: null,     // timestamp of last speech event
    speakerCount: 0,
    // Voice fingerprinting
    speakerProfiles: {},      // speakerId -> { pitchAvg, pitchVar, centroidAvg, centroidVar, sampleCount }
    voiceSampleBuffer: [],    // recent voice feature samples for current segment
    voiceSampleTimer: null,   // interval for collecting voice samples
    pitchAnalyser: null,      // dedicated analyser for pitch (larger fftSize)
    settings: {
      theme: 'dark',
      fontSize: 24,
      autoSave: true,
      haptic: true,
    },
  };

  // ==========================================
  // DOM ELEMENTS
  // ==========================================
  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => document.querySelectorAll(sel);

  const els = {
    splash: $('#splash'),
    app: $('#app'),
    btnStart: $('#btn-start'),
    btnMenu: $('#btn-menu'),
    btnCloseMenu: $('#btn-close-menu'),
    menuOverlay: $('#menu-overlay'),
    modeLabel: $('#mode-label'),
    statusDot: $('#status-dot'),
    tabs: $$('.tab'),
    views: {
      conversation: $('#view-conversation'),
      tv: $('#view-tv'),
      history: $('#view-history'),
    },
    // Conversation
    captionsList: $('#captions-list'),
    captionLive: $('#caption-live'),
    liveText: $('#live-text'),
    emptyState: $('#empty-state'),
    btnMic: $('#btn-mic'),
    micRing: $('#mic-ring'),
    micIcon: $('#mic-icon'),
    micIconOff: $('#mic-icon-off'),
    volumeMeter: $('#volume-meter'),
    volumeBar: $('#volume-bar'),
    // TV
    tvCaptions: $('#tv-captions'),
    tvCaptionLine1: $('#tv-caption-line-1'),
    tvCaptionLine2: $('#tv-caption-line-2'),
    tvEmptyState: $('#tv-empty-state'),
    btnTvMic: $('#btn-tv-mic'),
    tvMicRing: $('#tv-mic-ring'),
    // History
    historyList: $('#history-list'),
    historyEmpty: $('#history-empty'),
    btnClearHistory: $('#btn-clear-history'),
    // Settings
    fontSlider: $('#font-slider'),
    fontSizeValue: $('#font-size-value'),
    toggleAutosave: $('#toggle-autosave'),
    toggleHaptic: $('#toggle-haptic'),
    themeChips: $$('[data-theme]'),
    // Speaker legend
    speakerLegend: $('#speaker-legend'),
    speakerLegendList: $('#speaker-legend-list'),
    // Toast
    toast: $('#toast'),
  };

  // ==========================================
  // INITIALIZATION
  // ==========================================
  function init() {
    loadSettings();
    applySettings();
    setupEventListeners();
    checkSpeechSupport();
  }

  function checkSpeechSupport() {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) {
      showToast('⚠️ Spraakherkenning niet ondersteund in deze browser');
      els.btnMic.disabled = true;
      els.btnTvMic.disabled = true;
    }
  }

  // ==========================================
  // EVENT LISTENERS
  // ==========================================
  function setupEventListeners() {
    // Splash
    els.btnStart.addEventListener('click', () => {
      els.splash.classList.add('hidden');
      els.app.classList.remove('hidden');
    });

    // Menu
    els.btnMenu.addEventListener('click', openMenu);
    els.btnCloseMenu.addEventListener('click', closeMenu);
    els.menuOverlay.addEventListener('click', (e) => {
      if (e.target === els.menuOverlay) closeMenu();
    });

    // Tabs
    els.tabs.forEach((tab) => {
      tab.addEventListener('click', () => switchMode(tab.dataset.mode));
    });

    // Mic buttons
    els.btnMic.addEventListener('click', toggleListening);
    els.btnTvMic.addEventListener('click', toggleListening);

    // Settings
    els.fontSlider.addEventListener('input', (e) => {
      state.settings.fontSize = parseInt(e.target.value);
      els.fontSizeValue.textContent = e.target.value;
      applyFontSize();
      saveSettings();
    });

    els.themeChips.forEach((chip) => {
      chip.addEventListener('click', () => {
        els.themeChips.forEach((c) => {
          c.classList.remove('active');
          c.setAttribute('aria-checked', 'false');
        });
        chip.classList.add('active');
        chip.setAttribute('aria-checked', 'true');
        state.settings.theme = chip.dataset.theme;
        applyTheme();
        saveSettings();
      });
    });

    els.toggleAutosave.addEventListener('change', (e) => {
      state.settings.autoSave = e.target.checked;
      saveSettings();
    });

    els.toggleHaptic.addEventListener('change', (e) => {
      state.settings.haptic = e.target.checked;
      saveSettings();
    });

    // History
    els.btnClearHistory.addEventListener('click', clearHistory);

    // Prevent screen from sleeping using Wake Lock API
    requestWakeLock();
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible' && state.isListening) {
        requestWakeLock();
      }
    });
  }

  // ==========================================
  // SPEECH RECOGNITION ENGINE
  // ==========================================
  function createRecognition() {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) return null;

    const recognition = new SpeechRecognition();
    recognition.lang = LANG;
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.maxAlternatives = 1;

    recognition.onstart = () => {
      state.isListening = true;
      updateMicUI(true);
      resetSilenceTimer();
      if (!state.sessionStartTime) {
        state.sessionStartTime = new Date();
      }
    };

    recognition.onresult = (event) => {
      resetSilenceTimer();
      handleResults(event);
      hapticFeedback();
    };

    recognition.onerror = (event) => {
      console.warn('Speech error:', event.error);
      
      if (event.error === 'not-allowed') {
        showToast('🎙️ Microfoon toegang geweigerd — controleer je instellingen');
        stopListening();
        return;
      }

      if (event.error === 'no-speech') {
        // Silence — just restart
        return;
      }

      if (event.error === 'network') {
        showToast('📶 Geen internetverbinding');
      }

      if (event.error === 'aborted') {
        return; // Normal abort, don't restart
      }

      // For other errors, try to restart
      if (state.isListening) {
        scheduleRestart();
      }
    };

    recognition.onend = () => {
      // Auto-restart if we're still supposed to be listening
      if (state.isListening) {
        scheduleRestart();
      } else {
        updateMicUI(false);
        finalizeSession();
      }
    };

    return recognition;
  }

  // ==========================================
  // SPEAKER DETECTION — Voice Fingerprinting
  // ==========================================

  /**
   * Estimate fundamental frequency (pitch) via autocorrelation.
   * Returns pitch in Hz, or 0 if no clear pitch detected.
   */
  function estimatePitch() {
    if (!state.pitchAnalyser || !state.audioContext) return 0;

    const bufferLength = state.pitchAnalyser.fftSize;
    const buffer = new Float32Array(bufferLength);
    state.pitchAnalyser.getFloatTimeDomainData(buffer);

    // Check if there's enough signal (not silence)
    let rms = 0;
    for (let i = 0; i < bufferLength; i++) {
      rms += buffer[i] * buffer[i];
    }
    rms = Math.sqrt(rms / bufferLength);
    if (rms < 0.01) return 0; // too quiet

    // Autocorrelation-based pitch detection
    const sampleRate = state.audioContext.sampleRate;
    const minPeriod = Math.floor(sampleRate / 500); // max 500 Hz
    const maxPeriod = Math.floor(sampleRate / 60);   // min 60 Hz

    let bestCorrelation = 0;
    let bestPeriod = 0;

    for (let period = minPeriod; period <= maxPeriod && period < bufferLength / 2; period++) {
      let correlation = 0;
      let norm1 = 0;
      let norm2 = 0;
      const len = bufferLength - period;

      for (let i = 0; i < len; i++) {
        correlation += buffer[i] * buffer[i + period];
        norm1 += buffer[i] * buffer[i];
        norm2 += buffer[i + period] * buffer[i + period];
      }

      // Normalized cross-correlation
      const normFactor = Math.sqrt(norm1 * norm2);
      if (normFactor > 0) {
        correlation /= normFactor;
      }

      if (correlation > bestCorrelation && correlation > 0.5) {
        bestCorrelation = correlation;
        bestPeriod = period;
      }
    }

    return bestPeriod > 0 ? sampleRate / bestPeriod : 0;
  }

  /**
   * Calculate spectral centroid — the "brightness" of the voice.
   * Returns centroid frequency in Hz.
   */
  function calculateSpectralCentroid() {
    if (!state.analyser || !state.audioContext) return 0;

    const freqData = new Uint8Array(state.analyser.frequencyBinCount);
    state.analyser.getByteFrequencyData(freqData);

    let weightedSum = 0;
    let totalWeight = 0;
    const nyquist = state.audioContext.sampleRate / 2;
    const binWidth = nyquist / freqData.length;

    for (let i = 0; i < freqData.length; i++) {
      const magnitude = freqData[i];
      const frequency = i * binWidth;
      weightedSum += magnitude * frequency;
      totalWeight += magnitude;
    }

    return totalWeight > 0 ? weightedSum / totalWeight : 0;
  }

  /**
   * Collect a single voice feature sample (pitch + spectral centroid).
   * Called at regular intervals during speech.
   */
  function collectVoiceSample() {
    const pitch = estimatePitch();
    const centroid = calculateSpectralCentroid();

    // Only store if there's meaningful audio
    if (pitch > 0 && centroid > 0) {
      state.voiceSampleBuffer.push({ pitch, centroid });
    }
  }

  /**
   * Start collecting voice samples at regular intervals.
   */
  function startVoiceSampling() {
    stopVoiceSampling();
    state.voiceSampleBuffer = [];
    state.voiceSampleTimer = setInterval(collectVoiceSample, VOICE_SAMPLE_INTERVAL);
  }

  /**
   * Stop collecting voice samples.
   */
  function stopVoiceSampling() {
    if (state.voiceSampleTimer) {
      clearInterval(state.voiceSampleTimer);
      state.voiceSampleTimer = null;
    }
  }

  /**
   * Build a voice fingerprint from collected samples.
   * Returns { pitchAvg, pitchVar, centroidAvg, centroidVar } or null if not enough data.
   */
  function buildFingerprint(samples) {
    if (!samples || samples.length < VOICE_PROFILE_MIN_SAMPLES) return null;

    const pitches = samples.map(s => s.pitch);
    const centroids = samples.map(s => s.centroid);

    const pitchAvg = pitches.reduce((a, b) => a + b, 0) / pitches.length;
    const centroidAvg = centroids.reduce((a, b) => a + b, 0) / centroids.length;

    const pitchVar = pitches.reduce((sum, p) => sum + (p - pitchAvg) ** 2, 0) / pitches.length;
    const centroidVar = centroids.reduce((sum, c) => sum + (c - centroidAvg) ** 2, 0) / centroids.length;

    return { pitchAvg, pitchVar, centroidAvg, centroidVar };
  }

  /**
   * Compare two voice fingerprints. Returns similarity score 0..1.
   * Uses normalized distance on pitch and spectral centroid.
   */
  function compareFingerprints(fp1, fp2) {
    if (!fp1 || !fp2) return 0;

    // Pitch difference — normalize by typical human range (60-500 Hz)
    const pitchRange = 440;
    const pitchDiff = Math.abs(fp1.pitchAvg - fp2.pitchAvg) / pitchRange;

    // Spectral centroid difference — normalize by typical range (200-4000 Hz)
    const centroidRange = 3800;
    const centroidDiff = Math.abs(fp1.centroidAvg - fp2.centroidAvg) / centroidRange;

    // Weighted combination (pitch is stronger indicator)
    const distance = (pitchDiff * 0.6) + (centroidDiff * 0.4);

    // Convert distance to similarity (1 = identical, 0 = completely different)
    return Math.max(0, 1 - distance * 3);
  }

  /**
   * Update a speaker profile with new samples (running average).
   */
  function updateSpeakerProfile(speakerId, fingerprint) {
    if (!fingerprint) return;

    const existing = state.speakerProfiles[speakerId];
    if (!existing) {
      state.speakerProfiles[speakerId] = { ...fingerprint, sampleCount: 1 };
      return;
    }

    // Exponentially weighted moving average (more weight on recent)
    const alpha = Math.min(0.3, 1 / (existing.sampleCount + 1));
    existing.pitchAvg = existing.pitchAvg * (1 - alpha) + fingerprint.pitchAvg * alpha;
    existing.centroidAvg = existing.centroidAvg * (1 - alpha) + fingerprint.centroidAvg * alpha;
    existing.pitchVar = existing.pitchVar * (1 - alpha) + fingerprint.pitchVar * alpha;
    existing.centroidVar = existing.centroidVar * (1 - alpha) + fingerprint.centroidVar * alpha;
    existing.sampleCount++;
  }

  /**
   * Detect speaker change using voice fingerprinting + silence gap.
   * Returns the speaker ID for the current segment.
   */
  function detectSpeakerChange() {
    const now = Date.now();
    const silenceGap = state.lastSpeechTime ? (now - state.lastSpeechTime) : 0;

    if (silenceGap > SPEAKER_CHANGE_THRESHOLD) {
      // Silence detected — finalize current speaker's profile and try to match new voice
      const currentFingerprint = buildFingerprint(state.voiceSampleBuffer);
      updateSpeakerProfile(state.currentSpeakerId, currentFingerprint);

      // Reset sample buffer and start fresh sampling
      startVoiceSampling();

      // After a brief delay, try to match the new voice to an existing speaker
      // For now, collect a few samples first then match on next call
      state._pendingMatch = true;
    }

    // If we have a pending match and enough new samples, try to identify
    if (state._pendingMatch && state.voiceSampleBuffer.length >= VOICE_PROFILE_MIN_SAMPLES) {
      const newFingerprint = buildFingerprint(state.voiceSampleBuffer);
      if (newFingerprint) {
        let bestMatch = -1;
        let bestScore = 0;

        // Compare against all known speaker profiles
        for (const [id, profile] of Object.entries(state.speakerProfiles)) {
          const score = compareFingerprints(newFingerprint, profile);
          if (score > bestScore && score >= VOICE_MATCH_THRESHOLD) {
            bestScore = score;
            bestMatch = parseInt(id);
          }
        }

        if (bestMatch >= 0) {
          // Recognized existing speaker
          state.currentSpeakerId = bestMatch;
        } else {
          // New speaker
          state.currentSpeakerId = state.speakerCount;
          state.speakerCount++;
        }

        state._pendingMatch = false;
      }
    }

    state.lastSpeechTime = now;
    return state.currentSpeakerId;
  }

  function getSpeakerColor(speakerId) {
    if (!(speakerId in state.speakerColorMap)) {
      state.speakerColorMap[speakerId] = state.nextColorIndex % SPEAKER_COLORS.length;
      state.nextColorIndex++;
      updateSpeakerLegend();
    }
    return SPEAKER_COLORS[state.speakerColorMap[speakerId]];
  }

  function getSpeakerLabel(speakerId) {
    return `Spreker ${speakerId + 1}`;
  }

  function updateSpeakerLegend() {
    if (!els.speakerLegend || !els.speakerLegendList) return;

    const entries = Object.entries(state.speakerColorMap);
    if (entries.length === 0) {
      els.speakerLegend.classList.add('hidden');
      return;
    }

    els.speakerLegend.classList.remove('hidden');
    els.speakerLegendList.innerHTML = '';

    entries.forEach(([id, colorIdx]) => {
      const color = SPEAKER_COLORS[colorIdx];
      const chip = document.createElement('span');
      chip.className = 'speaker-chip';
      chip.style.setProperty('--speaker-color', color.hex);
      chip.textContent = getSpeakerLabel(parseInt(id));
      els.speakerLegendList.appendChild(chip);
    });
  }

  function resetSpeakerState() {
    state.currentSpeakerId = 0;
    state.speakerColorMap = {};
    state.nextColorIndex = 0;
    state.lastSpeechTime = null;
    state.speakerCount = 1; // Start with speaker 0
    state.speakerProfiles = {};
    state.voiceSampleBuffer = [];
    state._pendingMatch = false;
    stopVoiceSampling();
    updateSpeakerLegend();
  }

  function handleResults(event) {
    let interimTranscript = '';
    let finalTranscript = '';

    // Detect potential speaker change based on silence gap
    const speakerId = detectSpeakerChange();
    const speakerColor = getSpeakerColor(speakerId);

    for (let i = event.resultIndex; i < event.results.length; i++) {
      const result = event.results[i];
      const text = result[0].transcript;
      const confidence = result[0].confidence;

      if (result.isFinal) {
        finalTranscript += text;
        addCaptionBubble(text.trim(), confidence, speakerId, speakerColor);
      } else {
        interimTranscript += text;
      }
    }

    // Update live text
    if (interimTranscript) {
      showLiveText(interimTranscript, speakerColor);
    } else {
      hideLiveText();
    }

    // TV mode update
    if (state.currentMode === 'tv') {
      if (interimTranscript) {
        updateTVCaptions(interimTranscript, false, speakerColor);
      }
      if (finalTranscript) {
        updateTVCaptions(finalTranscript, true, speakerColor);
      }
    }
  }

  function scheduleRestart() {
    clearTimeout(state.restartTimer);
    state.restartTimer = setTimeout(() => {
      if (state.isListening && state.recognition) {
        try {
          state.recognition.start();
        } catch (e) {
          // Already started or other issue — recreate
          state.recognition = createRecognition();
          if (state.recognition) {
            try {
              state.recognition.start();
            } catch (e2) {
              console.error('Failed to restart recognition:', e2);
              stopListening();
              showToast('⚠️ Kon spraakherkenning niet herstarten');
            }
          }
        }
      }
    }, AUTO_RESTART_DELAY);
  }

  // ==========================================
  // LISTENING CONTROL
  // ==========================================
  function toggleListening() {
    if (state.isListening) {
      stopListening();
    } else {
      startListening();
    }
  }

  async function startListening() {
    // Request microphone access
    try {
      state.mediaStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: state.currentMode !== 'tv',
          noiseSuppression: state.currentMode !== 'tv',
          autoGainControl: true,
          channelCount: 1,
          sampleRate: 16000,
        }
      });
    } catch (err) {
      showToast('🎙️ Microfoon toegang nodig — sta dit toe in je instellingen');
      return;
    }

    // Set up audio analysis for volume meter
    setupAudioAnalysis();

    // Create and start recognition
    state.recognition = createRecognition();
    if (!state.recognition) {
      showToast('⚠️ Spraakherkenning niet beschikbaar');
      return;
    }

    try {
      state.recognition.start();
      state.sessionParagraphs = [];
      state.currentTranscript = '';
      resetSpeakerState();
      showToast('🎙️ Luisteren...');
    } catch (e) {
      console.error('Failed to start recognition:', e);
      showToast('⚠️ Kon spraakherkenning niet starten');
    }
  }

  function stopListening() {
    state.isListening = false;
    clearTimeout(state.restartTimer);
    clearTimeout(state.silenceTimer);

    if (state.recognition) {
      try {
        state.recognition.stop();
      } catch (e) {
        // Already stopped
      }
    }

    // Stop audio analysis
    stopAudioAnalysis();

    // Stop media stream
    if (state.mediaStream) {
      state.mediaStream.getTracks().forEach(track => track.stop());
      state.mediaStream = null;
    }

    updateMicUI(false);
    hideLiveText();
    showToast('⏹️ Gestopt');
    finalizeSession();
  }

  function resetSilenceTimer() {
    clearTimeout(state.silenceTimer);
    state.silenceTimer = setTimeout(() => {
      if (state.isListening) {
        showToast('⏸️ Automatisch gestopt (stilte)');
        stopListening();
      }
    }, SILENCE_TIMEOUT);
  }

  // ==========================================
  // AUDIO ANALYSIS (Volume meter)
  // ==========================================
  function setupAudioAnalysis() {
    try {
      state.audioContext = new (window.AudioContext || window.webkitAudioContext)();
      const source = state.audioContext.createMediaStreamSource(state.mediaStream);

      // Analyser for volume meter + spectral centroid
      state.analyser = state.audioContext.createAnalyser();
      state.analyser.fftSize = 256;
      state.analyser.smoothingTimeConstant = 0.8;
      source.connect(state.analyser);

      // Dedicated analyser for pitch detection (needs larger fftSize)
      state.pitchAnalyser = state.audioContext.createAnalyser();
      state.pitchAnalyser.fftSize = 2048;
      state.pitchAnalyser.smoothingTimeConstant = 0.3;
      source.connect(state.pitchAnalyser);

      // Start voice sampling for speaker fingerprinting
      startVoiceSampling();

      updateVolumeMeter();
    } catch (e) {
      console.warn('Audio analysis not available:', e);
    }
  }

  function updateVolumeMeter() {
    if (!state.analyser || !state.isListening) return;

    const dataArray = new Uint8Array(state.analyser.frequencyBinCount);
    state.analyser.getByteFrequencyData(dataArray);

    // Calculate average volume
    const avg = dataArray.reduce((sum, val) => sum + val, 0) / dataArray.length;
    const volume = Math.min(100, Math.round((avg / 128) * 100));

    els.volumeBar.style.width = volume + '%';

    state.volumeAnimFrame = requestAnimationFrame(updateVolumeMeter);
  }

  function stopAudioAnalysis() {
    if (state.volumeAnimFrame) {
      cancelAnimationFrame(state.volumeAnimFrame);
      state.volumeAnimFrame = null;
    }

    stopVoiceSampling();

    if (state.audioContext) {
      try {
        state.audioContext.close();
      } catch (e) {}
      state.audioContext = null;
      state.analyser = null;
      state.pitchAnalyser = null;
    }
  }

  // ==========================================
  // CAPTION DISPLAY
  // ==========================================
  function addCaptionBubble(text, confidence, speakerId, speakerColor) {
    if (!text) return;

    // Store in session
    state.sessionParagraphs.push({
      text,
      confidence,
      time: new Date(),
      speakerId,
    });

    if (state.currentMode === 'conversation') {
      // Hide empty state
      els.emptyState.classList.add('has-content');

      const bubble = document.createElement('div');
      bubble.className = 'caption-bubble';
      bubble.style.setProperty('--speaker-color', speakerColor.hex);
      bubble.style.setProperty('--speaker-border', speakerColor.border);

      // Confidence indicator
      if (confidence >= 0.85) {
        bubble.classList.add('high-confidence');
      } else if (confidence < 0.6) {
        bubble.classList.add('low-confidence');
      }

      // Speaker label
      const speakerEl = document.createElement('span');
      speakerEl.className = 'speaker-label';
      speakerEl.style.color = speakerColor.hex;
      speakerEl.textContent = getSpeakerLabel(speakerId);

      const textEl = document.createElement('span');
      textEl.textContent = text;

      const confEl = document.createElement('span');
      confEl.className = 'confidence';
      confEl.textContent = Math.round(confidence * 100) + '%';

      const timeEl = document.createElement('span');
      timeEl.className = 'timestamp';
      timeEl.textContent = formatTime(new Date());

      bubble.appendChild(speakerEl);
      bubble.appendChild(textEl);
      bubble.appendChild(confEl);
      bubble.appendChild(timeEl);

      els.captionsList.appendChild(bubble);

      // Auto-scroll to bottom
      scrollToBottom();

      // Keep only last 100 bubbles in DOM
      while (els.captionsList.children.length > 100) {
        els.captionsList.removeChild(els.captionsList.firstChild);
      }
    }
  }

  function showLiveText(text, speakerColor) {
    els.liveText.textContent = text;
    if (speakerColor) {
      els.captionLive.style.setProperty('--speaker-color', speakerColor.hex);
      els.captionLive.style.borderLeft = `4px solid ${speakerColor.hex}`;
    }
    els.captionLive.classList.add('visible');
    els.emptyState.classList.add('has-content');
    scrollToBottom();
  }

  function hideLiveText() {
    els.captionLive.classList.remove('visible');
    els.liveText.textContent = '';
  }

  function scrollToBottom() {
    const container = els.captionsList.parentElement;
    requestAnimationFrame(() => {
      container.scrollTop = container.scrollHeight;
    });
  }

  // ==========================================
  // TV MODE CAPTIONS
  // ==========================================
  let tvPreviousLine = '';

  let tvPreviousColor = null;

  function updateTVCaptions(text, isFinal, speakerColor) {
    els.tvCaptions.classList.add('visible');
    els.tvEmptyState.classList.add('has-content');

    if (isFinal) {
      // Move current to previous line
      els.tvCaptionLine1.textContent = tvPreviousLine;
      els.tvCaptionLine1.classList.remove('active');
      if (tvPreviousColor) {
        els.tvCaptionLine1.style.borderLeft = `4px solid ${tvPreviousColor.hex}`;
        els.tvCaptionLine1.style.paddingLeft = '0.8rem';
      }

      els.tvCaptionLine2.textContent = text;
      els.tvCaptionLine2.classList.add('active');
      if (speakerColor) {
        els.tvCaptionLine2.style.borderLeft = `4px solid ${speakerColor.hex}`;
        els.tvCaptionLine2.style.paddingLeft = '0.8rem';
      }

      tvPreviousLine = text;
      tvPreviousColor = speakerColor;
    } else {
      // Show interim on active line
      els.tvCaptionLine2.textContent = text;
      els.tvCaptionLine2.classList.add('active');
      if (speakerColor) {
        els.tvCaptionLine2.style.borderLeft = `4px solid ${speakerColor.hex}`;
        els.tvCaptionLine2.style.paddingLeft = '0.8rem';
      }
    }
  }

  // ==========================================
  // UI UPDATES
  // ==========================================
  function updateMicUI(isActive) {
    const buttons = [els.btnMic, els.btnTvMic];
    const rings = [els.micRing, els.tvMicRing];

    buttons.forEach((btn) => {
      btn.classList.toggle('active', isActive);
    });

    rings.forEach((ring) => {
      ring.classList.toggle('listening', isActive);
    });

    els.statusDot.classList.toggle('active', isActive);
    els.statusDot.setAttribute('aria-label', isActive ? 'Status: luistert' : 'Status: gestopt');
    els.statusDot.title = isActive ? 'Actief — luistert' : 'Niet actief';

    els.volumeMeter.classList.toggle('active', isActive);

    // Toggle mic icons
    if (els.micIcon && els.micIconOff) {
      els.micIcon.classList.toggle('hidden', !isActive && false);
    }
  }

  function switchMode(mode) {
    // If we were listening and switching modes, stop first if different mode type needs different audio config
    const wasListening = state.isListening;
    if (wasListening && (state.currentMode === 'tv' || mode === 'tv') && state.currentMode !== mode) {
      stopListening();
    }

    state.currentMode = mode;

    // Update tabs
    els.tabs.forEach((tab) => {
      const isActive = tab.dataset.mode === mode;
      tab.classList.toggle('active', isActive);
      tab.setAttribute('aria-selected', isActive);
    });

    // Update views
    Object.entries(els.views).forEach(([key, view]) => {
      view.classList.toggle('active', key === mode);
    });

    // Update mode label
    const labels = { conversation: 'Gesprek', tv: 'TV', history: 'Geschiedenis' };
    els.modeLabel.textContent = labels[mode];

    // Load history when switching to history tab
    if (mode === 'history') {
      renderHistory();
    }
  }

  // ==========================================
  // MENU
  // ==========================================
  function openMenu() {
    els.menuOverlay.classList.remove('hidden');
    document.body.style.overflow = 'hidden';
  }

  function closeMenu() {
    els.menuOverlay.classList.add('hidden');
    document.body.style.overflow = '';
  }

  // ==========================================
  // SETTINGS
  // ==========================================
  function loadSettings() {
    try {
      const saved = localStorage.getItem(SETTINGS_KEY);
      if (saved) {
        Object.assign(state.settings, JSON.parse(saved));
      }
    } catch (e) {
      console.warn('Could not load settings:', e);
    }
  }

  function saveSettings() {
    try {
      localStorage.setItem(SETTINGS_KEY, JSON.stringify(state.settings));
    } catch (e) {
      console.warn('Could not save settings:', e);
    }
  }

  function applySettings() {
    applyTheme();
    applyFontSize();

    // Sync UI controls
    els.fontSlider.value = state.settings.fontSize;
    els.fontSizeValue.textContent = state.settings.fontSize;
    els.toggleAutosave.checked = state.settings.autoSave;
    els.toggleHaptic.checked = state.settings.haptic;

    els.themeChips.forEach((chip) => {
      const isActive = chip.dataset.theme === state.settings.theme;
      chip.classList.toggle('active', isActive);
      chip.setAttribute('aria-checked', isActive);
    });
  }

  function applyTheme() {
    document.body.setAttribute('data-theme', state.settings.theme);
  }

  function applyFontSize() {
    document.documentElement.style.setProperty('--caption-font-size', state.settings.fontSize + 'px');
  }

  // ==========================================
  // TRANSCRIPT STORAGE
  // ==========================================
  function getTranscripts() {
    try {
      const data = localStorage.getItem(STORAGE_KEY);
      return data ? JSON.parse(data) : [];
    } catch (e) {
      return [];
    }
  }

  function saveTranscript(entry) {
    try {
      const transcripts = getTranscripts();
      transcripts.unshift(entry);
      // Keep max items
      while (transcripts.length > MAX_HISTORY) {
        transcripts.pop();
      }
      localStorage.setItem(STORAGE_KEY, JSON.stringify(transcripts));
    } catch (e) {
      console.warn('Could not save transcript:', e);
    }
  }

  function finalizeSession() {
    if (state.sessionParagraphs.length === 0) return;
    if (!state.settings.autoSave) return;

    const fullText = state.sessionParagraphs.map((p) => p.text).join('\n');
    const entry = {
      id: Date.now(),
      date: state.sessionStartTime ? state.sessionStartTime.toISOString() : new Date().toISOString(),
      mode: state.currentMode,
      text: fullText,
      paragraphs: state.sessionParagraphs.length,
      duration: state.sessionStartTime
        ? Math.round((Date.now() - state.sessionStartTime.getTime()) / 1000)
        : 0,
    };

    saveTranscript(entry);
    state.sessionParagraphs = [];
    state.sessionStartTime = null;
  }

  // ==========================================
  // HISTORY VIEW
  // ==========================================
  function renderHistory() {
    const transcripts = getTranscripts();

    if (transcripts.length === 0) {
      els.historyEmpty.classList.remove('has-content');
      // Remove all history items
      els.historyList.querySelectorAll('.history-item').forEach((el) => el.remove());
      return;
    }

    els.historyEmpty.classList.add('has-content');

    // Clear existing items
    els.historyList.querySelectorAll('.history-item, .history-detail').forEach((el) => el.remove());

    transcripts.forEach((entry) => {
      const item = document.createElement('div');
      item.className = 'history-item';
      item.dataset.id = entry.id;

      const modeLabels = { conversation: '💬 Gesprek', tv: '📺 TV' };
      const date = new Date(entry.date);
      const duration = entry.duration
        ? `${Math.floor(entry.duration / 60)}m ${entry.duration % 60}s`
        : '';

      item.innerHTML = `
        <div class="history-item-header">
          <span class="history-item-date">${formatDate(date)}</span>
          <span class="history-item-mode">${modeLabels[entry.mode] || entry.mode}</span>
        </div>
        <div class="history-item-preview">${escapeHtml(entry.text)}</div>
        <div class="history-item-actions">
          <button class="btn btn-small btn-primary btn-copy" data-id="${entry.id}" aria-label="Kopiëren">📋 Kopiëren</button>
          <button class="btn btn-small btn-share" data-id="${entry.id}" aria-label="Delen" style="background:var(--bg-tertiary);color:var(--text-primary)">📤 Delen</button>
          <button class="btn btn-small btn-danger btn-delete" data-id="${entry.id}" aria-label="Verwijderen">🗑️</button>
        </div>
      `;

      // Expand on click
      item.addEventListener('click', (e) => {
        if (e.target.closest('button')) return;
        toggleHistoryDetail(item, entry);
      });

      // Copy button
      item.querySelector('.btn-copy').addEventListener('click', () => {
        copyToClipboard(entry.text);
        showToast('📋 Gekopieerd!');
      });

      // Share button
      item.querySelector('.btn-share').addEventListener('click', () => {
        shareText(entry.text, date);
      });

      // Delete button
      item.querySelector('.btn-delete').addEventListener('click', () => {
        deleteTranscript(entry.id);
        item.remove();
        showToast('🗑️ Verwijderd');
        // Check if list is empty
        if (getTranscripts().length === 0) {
          els.historyEmpty.classList.remove('has-content');
        }
      });

      els.historyList.appendChild(item);
    });
  }

  function toggleHistoryDetail(item, entry) {
    const existing = item.nextElementSibling;
    if (existing && existing.classList.contains('history-detail')) {
      existing.remove();
      return;
    }

    const detail = document.createElement('div');
    detail.className = 'history-detail';
    detail.innerHTML = `<div class="history-detail-text">${escapeHtml(entry.text)}</div>`;
    item.after(detail);
  }

  function deleteTranscript(id) {
    const transcripts = getTranscripts().filter((t) => t.id !== id);
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(transcripts));
    } catch (e) {}
  }

  function clearHistory() {
    if (confirm('Weet je zeker dat je alle geschiedenis wilt verwijderen?')) {
      try {
        localStorage.removeItem(STORAGE_KEY);
      } catch (e) {}
      renderHistory();
      showToast('🗑️ Geschiedenis gewist');
    }
  }

  // ==========================================
  // SHARING & CLIPBOARD
  // ==========================================
  async function copyToClipboard(text) {
    try {
      await navigator.clipboard.writeText(text);
    } catch (e) {
      // Fallback
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
    }
  }

  async function shareText(text, date) {
    const shareData = {
      title: 'Bava Transcriptie',
      text: `Transcriptie van ${formatDate(date)}:\n\n${text}`,
    };

    try {
      if (navigator.share) {
        await navigator.share(shareData);
      } else {
        await copyToClipboard(shareData.text);
        showToast('📋 Gekopieerd naar klembord');
      }
    } catch (e) {
      if (e.name !== 'AbortError') {
        await copyToClipboard(shareData.text);
        showToast('📋 Gekopieerd naar klembord');
      }
    }
  }

  // ==========================================
  // HAPTIC FEEDBACK
  // ==========================================
  function hapticFeedback() {
    if (!state.settings.haptic) return;
    if (navigator.vibrate) {
      navigator.vibrate(50);
    }
  }

  // ==========================================
  // WAKE LOCK
  // ==========================================
  let wakeLock = null;

  async function requestWakeLock() {
    try {
      if ('wakeLock' in navigator) {
        wakeLock = await navigator.wakeLock.request('screen');
      }
    } catch (e) {
      // Wake lock not supported or failed
    }
  }

  // ==========================================
  // TOAST NOTIFICATIONS
  // ==========================================
  let toastTimer = null;

  function showToast(message, duration = 2500) {
    clearTimeout(toastTimer);
    els.toast.textContent = message;
    els.toast.classList.remove('hidden');

    toastTimer = setTimeout(() => {
      els.toast.classList.add('hidden');
    }, duration);
  }

  // ==========================================
  // UTILITIES
  // ==========================================
  function formatTime(date) {
    return date.toLocaleTimeString('nl-NL', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  }

  function formatDate(date) {
    return date.toLocaleDateString('nl-NL', {
      day: 'numeric',
      month: 'long',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // ==========================================
  // BOOT
  // ==========================================
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

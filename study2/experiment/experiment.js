import trialMinimisation from './trialMinimisation.js';

/* ==========================================================================
   Modeling Guilty Minds, Study 2
   --------------------------------------------------------------------------
   The main task (instructions, five cases, ranking) is the Study 1 task,
   copied from the Study 1 experiment.js without changes. Study 2 adds:
     - the jury-eligibility item (after consent, before the instructions)
     - the comprehension item and the element probe, in randomized order
     - the seriousness item
     - revised demographics with an embedded attention item
     - Prolific IDs and Prolific completion, screen-out, and no-consent links
   Participant-facing wording for the new items follows the preregistration
   ("Items added in Study 2" and "Demographics (revised)").
   ========================================================================== */

// --------------------------------------------------------------------------
// PROLIFIC SETTINGS: replace the three codes with the ones Prolific assigns
// to this study's completion paths before launching.
// --------------------------------------------------------------------------
const PROLIFIC_CODES = {
  complete:  'REDACTED',   // completion path: approve and pay
  screenout: 'REDACTED',    // completion path: screen-out payment
  noconsent: 'REDACTED'     // completion path: request a return
};
const prolificUrl = code => `https://app.prolific.com/submissions/complete?cc=${code}`;

// Exit state for the early-exit paths (declined consent, not eligible).
let _exitReason = null;

// Initialize jsPsych
const jsPsych = initJsPsych({
  // jsPsych 7 overwrites data.trial_type with the plugin name (as in the Study 1 data files),
  // so each trial's own label is copied into a separate "task" column.
  on_trial_start: function(trial) {
    if (trial.data && typeof trial.data === 'object' && trial.data.trial_type && trial.data.task === undefined) {
      trial.data.task = trial.data.trial_type;
    }
  },
  on_finish: function() {
    if (_exitReason === 'noconsent') {
      setTimeout(() => { window.location.href = prolificUrl(PROLIFIC_CODES.noconsent); }, 4000);
      return;
    }
    if (_exitReason === 'screenout') {
      setTimeout(() => { window.location.href = prolificUrl(PROLIFIC_CODES.screenout); }, 4000);
      return;
    }
    // Only show the debriefing if the study was actually completed
    const studyCompleted = jsPsych.data.get().filter({study_completed: true}).count() > 0;
    if (studyCompleted) {
      const display = jsPsych.getDisplayElement();
      display.innerHTML = `
        <div style="text-align:center; margin-top:50px;">
          <h2>Debriefing</h2>
          <p>Thank you for participating in this study. Your responses will help us understand how people make judgments about mental states in legal contexts.</p>
          <p>The scenarios you read varied systematically across several factors. We are investigating how these factors influence judgments about mental states.</p>
          <p>Some later questions asked about specific parts of the legal definitions so that we could check how the options were understood.</p>
          <p>If you have any questions about this study, please contact the researcher.</p>
          <p>Your responses have been recorded.</p>
          <p style="text-align:center;"><a class="jspsych-btn" href="${prolificUrl(PROLIFIC_CODES.complete)}">Return to Prolific to complete your submission</a></p>
          <p style="text-align:center; font-size:0.9em;">If the button does not work, enter this completion code on Prolific: <strong>${PROLIFIC_CODES.complete}</strong></p>
        </div>
      `;

    // Data is automatically saved by Pavlovia
    // jsPsych.data.get().localSave('csv', 'temp-data.csv') // For debugging during development
    }
  }
});window.jsPsych = jsPsych;

// DO NOT TOUCH THIS OR IT WILL ALL BREAK. I DO NOT KNOW WHY
if (!jsPsychHtmlButtonResponse.info.version) {  
  jsPsychHtmlButtonResponse.info.version = "1.2.0";
  jsPsychHtmlButtonResponse.info.data = {};
}

// --------------------------------------------------------------------------
// Participant-level properties written to every row of the data file
// --------------------------------------------------------------------------
// Order of the two post-task blocks, assigned by simple randomization (1:1).
const comprehensionFirst = jsPsych.randomization.sampleWithoutReplacement([true, false], 1)[0];
jsPsych.data.addProperties({
  study: 'study2',
  prolific_pid: jsPsych.data.getURLVariable('PROLIFIC_PID') || '',
  prolific_study_id: jsPsych.data.getURLVariable('STUDY_ID') || '',
  prolific_session_id: jsPsych.data.getURLVariable('SESSION_ID') || '',
  comprehension_first: comprehensionFirst
});

let rpmItems        = [];
let rpmBooklets     = [];
let selectedBooklet = [];
let rpmImageList    = [];
await fetch('rpm/rpm-items.json')
  .then(res => {
    if (!res.ok) throw new Error('Failed to load rpm-items.json');
    return res.json();
  })
  .then(json => {
    // json is an object with two arrays inside
    rpmItems    = json.items;     // now rpmItems is the array of 18 puzzles
    rpmBooklets = json.booklets;  // array of the 18 booklets

    // pick one 5-item booklet for this participant
    const myBookletIds = jsPsych.randomization
      .sampleWithoutReplacement(rpmBooklets, 1)[0];
    selectedBooklet = myBookletIds.map(id =>
      rpmItems.find(item => item.id === id)
    );

    // now build your preload list from that 5-item array
    rpmImageList = selectedBooklet.flatMap(item =>
      [ item.stimulus, ...item.choices ]
    );
  });

function makeRpmTrial(item) {
  const shuffledChoices = jsPsych.randomization.shuffle(item.choices);
  const correctIndex = shuffledChoices.indexOf(item.choices[item.correct]);
  
  const choicesHtml = shuffledChoices.map((choice, index) => 
    `<div class="rpm-choice" data-choice="${index}">
      <img src="${choice}" alt="Choice ${index + 1}">
    </div>`
  ).join('');

  return {
    type: jsPsychHtmlKeyboardResponse,
    stimulus: `
      <div class="rpm-container">
        <h3>Pattern Completion Task</h3>
        <div class="rpm-stimulus">
          <img src="${item.stimulus}" alt="Pattern to complete">
        </div>
        <p>Please select the option which corresponds to the pattern pictured above:</p>
        <div class="rpm-choices">
          ${choicesHtml}
        </div>
        <div id="submit-container">
          <button id="submit-btn" class="jspsych-btn submit-disabled" disabled>Continue</button>
        </div>
      </div>
    `,
    choices: "NO_KEYS",
    //trial_duration: 30000,  was fucking up and skipping later sections of the experiment
    on_load: function() {
      let selectedChoice = null;
      const choices = document.querySelectorAll('.rpm-choice');
      const submitBtn = document.getElementById('submit-btn');
      
      choices.forEach((choice, index) => {
        choice.addEventListener('click', () => {
          // Remove previous selection
          choices.forEach(c => c.classList.remove('selected'));
          // Add selection to clicked choice
          choice.classList.add('selected');
          selectedChoice = index;
          // Enable submit button
          submitBtn.disabled = false;
          submitBtn.classList.remove('submit-disabled');
          submitBtn.classList.add('submit-enabled');
        });
      });
      
      submitBtn.addEventListener('click', () => {
        if (selectedChoice !== null) {
          const correct = selectedChoice === correctIndex;
          jsPsych.finishTrial({
            response: selectedChoice,
            correct: correct,
            // rt: performance.now() - jsPsych.getCurrentTrial().time_elapsed
          });
        }
      });
    },
    data: { trial_type: 'rpm', correct_answer: correctIndex }
  };
}

// Helper functions for dynamic text substitution
const names = jsPsych.randomization.shuffle(["John", "David", "Andrew", "Robert", "Daniel"]);
const canadaLocs = jsPsych.randomization.shuffle(["Richmond, Canada", "Winnipeg, Canada", "Thunder Bay, Canada", "Windsor, Canada", "Kingston, Canada"]);
const mexicoLocs = jsPsych.randomization.shuffle(["Nogales, Mexico", "Reynosa, Mexico", "Agua Prieta, Mexico", "Nuevo Laredo, Mexico", "Mexicali, Mexico"]);
function personalizeVignette(template, idx) {
  let name = names[idx];
  let canadaLoc = canadaLocs[idx];
  let mexicoLoc = mexicoLocs[idx];
  return template.replace(/\[NAME\]/g, name).replace(/\[CANADA_LOC\]/g, canadaLoc).replace(/\[MEXICO_LOC\]/g, mexicoLoc);;
}
function getPersonalizedDefinitions(name) {
  // Define the definitions as an array of objects
  const definitions = [
    {
        key: 'Knowledge',
        text: `${name} was conscious and aware of the nature of their actions and of the surrounding facts and circumstances.`
    },
    {
        key: 'Recklessness',
        text: `${name} was aware of a substantial and unjustifiable risk of the outcome occurring and consciously ignored that risk.`
    },
    {
        key: 'Negligence',
        text: `${name} failed to use the care that a reasonably careful and thoughtful person would use under similar circumstances.`
    },
    {
        key: 'Blamelessness',
        text: `${name} lacked any of the mental states defined here.`
    }
  ];
  return definitions;
}


// calculates and loads the vignettes asynchronously
async function fetchPersonalizedVignettes() {
  const GLOBAL_COUNTS_PATH = 'global_data/global_counts.json';
  const VIGNETTE_TEXT_PATH = 'mensReaVignettes_binary.json';
  const NUM_TRIALS = 5;

  const [globalCounts, allVignettes] = await Promise.all([
    fetch(GLOBAL_COUNTS_PATH, { cache: 'no-store' }).then(r => r.json()),
    fetch(VIGNETTE_TEXT_PATH).then(r => r.json())
  ]);

  const selectedIds = await trialMinimisation(globalCounts, NUM_TRIALS);

  const decimalIds = selectedIds.map(binId => parseInt(binId, 2));

  const selectedVignettes = decimalIds.map(id => (allVignettes[id]));

  return selectedVignettes; // an array of 5 objects, each with id and vignette objs
}

// creates and loads the first part of the experiment containing the intro, consent, 
// eligibility item, and instructions, up until the first actual trial, so that the
// minimisation calculation has time to be run in the background until it is actually needed. 
let _consented = false;
let _eligible = false;
function createInitialTimeline() {

  const pavlovia_init = {
    type: jsPsychPavlovia,
    command: "init"
  };

  // Study 1 consent page with two changes (duration; former participants).
  const consentTrial = {
    type: jsPsychHtmlButtonResponse,
    stimulus: `
      <h2>Consent Form</h2>
      <p>This study investigates how people make judgments about others' mental states in legal contexts. You will read several scenarios and answer questions about them.</p>
      <p>Your participation is voluntary, and you may withdraw at any time without penalty. Your responses will be kept confidential and used for research purposes only.</p>
      <p>The study will take approximately 10-12 minutes to complete.</p>
      <p>If you took part in an earlier version of this study, please do not take part again.</p>
      <p>Before proceeding, do you consent to this experiment? For a link to the full consent form, click <a href="https://ucla.app.box.com/s/cdyfl1ajkwzpvrjjxdbrd0c1zx13ls1x" target="_blank">here</a>.</p>
    `,
    choices: [
      'I consent to do this experiment.',
      'No thanks, I do not consent to do this experiment.'
    ],
    button_html: Array(2).fill('<button class="jspsych-btn">%choice%</button>'),
    data: { trial_type: 'consent' },
    on_finish: data => {
      _consented = (data.response === 0);
      if (!_consented) {
        _exitReason = 'noconsent';
        jsPsych.endExperiment(`
          <div style="text-align:center; margin-top:50px;">
            <p style="text-align:center;">You chose not to take part. Please return this study on Prolific. You will be redirected to Prolific in a few seconds.</p>
            <p style="text-align:center;"><a class="jspsych-btn" href="${prolificUrl(PROLIFIC_CODES.noconsent)}">Go to Prolific now</a></p>
          </div>`);
      }
    }
  };

  // NEW (Study 2): jury-eligibility item. "No" ends the session with the screen-out payment.
  const eligibilityOptions = ['Yes', 'No', 'Not sure'];
  const eligibilityTrial = {
    type: jsPsychHtmlButtonResponse,
    stimulus: `
      <p>In most states, jurors must be U.S. citizens, at least 18 years old, residents of the area the court serves, and able to understand English, and some states exclude people with certain criminal convictions. To the best of your knowledge, are you currently eligible to serve on a jury in the state where you live?</p>
    `,
    choices: eligibilityOptions,
    button_html: Array(3).fill('<button class="jspsych-btn">%choice%</button>'),
    data: { trial_type: 'eligibility' },
    on_finish: data => {
      data.eligibility = eligibilityOptions[data.response];
      jsPsych.data.addProperties({ eligibility: data.eligibility });
      _eligible = (data.eligibility !== 'No');
      if (!_eligible) {
        _exitReason = 'screenout';
        jsPsych.endExperiment(`
          <div style="text-align:center; margin-top:50px;">
            <p style="text-align:center;">Thank you. Based on your answer, you are not eligible for this study. You will be redirected to Prolific in a few seconds, and you will receive the screen-out payment.</p>
            <p style="text-align:center;"><a class="jspsych-btn" href="${prolificUrl(PROLIFIC_CODES.screenout)}">Go to Prolific now</a></p>
          </div>`);
      }
    }
  };
  const eligibilityNode = {
    timeline: [eligibilityTrial],
    conditional_function: () => _consented
  };

  const instructionsNode = {
    timeline: [{
      type: jsPsychHtmlButtonResponse,
      stimulus: `
        <h2>Instructions</h2>
        <p>Imagine you’ve been selected for jury duty. Normally, a juror would only serve for one particular court case, but for today you will act as a juror for five separate court cases. In the course of a criminal trial, a juror may be asked many times to make judgments on certain questions surrounding the case. For each case, we’ll ask you to make some of these judgments yourself, to the best of your ability.</p>

        <p>Each of these cases correspond to similar criminal trials which occurred in real life, besides the necessary modifications to make sure no personally identifiable information is revealed. Although the defendants in these cases are unrelated to each other, each defendant was charged with violating the same statute, defined below:</p>

        <p><strong>Unlawful Trafficking:</strong> A person is guilty of unlawful trafficking if the person transports an illegal item across an international border.</p>

        <p>Although some cases deal with similar themes, none of the cases are identical— we ask that you read each summary as closely and thoroughly as you can. There are no right or wrong answers.</p>

        <p>When you are ready, click "Begin Study" below.</p>
      `,
      choices: ['Begin Study'],
      button_html: ['<button class="jspsych-btn">%choice%</button>']
    }],
    conditional_function: () => {
      // only show if they consented and did not answer "No" to the eligibility item
      return _consented && _eligible;
    }
  };

  return [ pavlovia_init, consentTrial, eligibilityNode, instructionsNode ];
}
  

// --------------------------------------------------------------------------
// NEW (Study 2): comprehension item
// --------------------------------------------------------------------------
const COMPREHENSION_OPTIONS = {
  a: 'The person was aware of what he was doing and of his situation, for example that he was carrying a package across a border',
  b: 'The person was aware that the package contained illicit material',
  c: 'The person intended to smuggle illicit material',
  d: 'The evidence was strong enough to prove the person guilty'
};
function makeComprehensionTrial() {
  // (a) to (d) in random order, (e) always last
  const order = jsPsych.randomization.shuffle(['a', 'b', 'c', 'd']);
  const optionsHtml = order.map(key => `
      <label class="choice-option"><input type="radio" name="comprehension" value="${key}" required> <span>${COMPREHENSION_OPTIONS[key]}</span></label>`
  ).join('') + `
      <label class="choice-option"><input type="radio" name="comprehension" value="e" required> <span>Something else</span></label>
      <input type="text" id="comprehension-other" name="comprehension_other" class="other-text" disabled aria-label="Something else">`;
  return {
    type: jsPsychSurveyHtmlForm,
    preamble: `
      <div class="question-text">
        <p>In the cases, one of the options you could choose read: “The person was conscious and aware of the nature of their actions and of the surrounding facts and circumstances.” When you read that option, what did you understand it to mean? Choose the answer closest to your understanding.</p>
      </div>`,
    html: `<div class="form-block">${optionsHtml}</div>`,
    button_label: 'Continue',
    on_load: function() {
      const other = document.getElementById('comprehension-other');
      document.querySelectorAll('input[name="comprehension"]').forEach(r => {
        r.addEventListener('change', () => {
          const isOther = document.querySelector('input[name="comprehension"][value="e"]').checked;
          other.disabled = !isOther;
          other.required = isOther;
          if (isOther) other.focus(); else other.value = '';
        });
      });
    },
    data: { trial_type: 'comprehension', comprehension_option_order: order.join('') },
    on_finish: data => {
      data.comprehension_answer = data.response.comprehension;
      data.comprehension_other = data.response.comprehension_other || '';
    }
  };
}

// --------------------------------------------------------------------------
// NEW (Study 2): element probe
// --------------------------------------------------------------------------
function makeProbeTimeline(selectedVignettes) {
  const probeIntro = {
    type: jsPsychHtmlButtonResponse,
    stimulus: `
      <p>In this part, you will see each of the five cases again, in the same order. For each case, please answer three questions. As before, “proof beyond a reasonable doubt” is proof that leaves you firmly convinced. There are no right or wrong answers.</p>
    `,
    choices: ['Continue'],
    button_html: ['<button class="jspsych-btn">%choice%</button>'],
    data: { trial_type: 'probe_intro' }
  };

  const yesNo = name => `
      <div class="yesno">
        <label class="choice-inline"><input type="radio" name="${name}" value="Yes" required> Yes</label>
        <label class="choice-inline"><input type="radio" name="${name}" value="No" required> No</label>
      </div>`;

  const probeTrials = selectedVignettes.map((vignette, index) => {
    const name = names[index];
    const personalizedVignette = personalizeVignette(vignette.vignette, index);
    return {
      type: jsPsychSurveyHtmlForm,
      preamble: `
        <div class="vignette">
          <div class="vignette-title">Scenario ${index + 1}</div>
          ${personalizedVignette}
        </div>`,
      html: `
        <div class="form-block">
          <div class="probe-question">
            <p>Does this scenario prove beyond a reasonable doubt that, at the moment ${name} crossed the border, he knew, or was practically certain, that illicit material was in the package?</p>
            ${yesNo('knew')}
          </div>
          <div class="probe-question">
            <p>Does this scenario prove beyond a reasonable doubt that, at the moment ${name} crossed the border, he was aware of a substantial risk that illicit material was in the package?</p>
            ${yesNo('aware')}
          </div>
          <div class="probe-question">
            <p>Does this scenario prove beyond a reasonable doubt that, at the moment ${name} crossed the border, a reasonably careful person in his position would have been aware of a substantial risk that illicit material was in the package?</p>
            ${yesNo('should')}
          </div>
        </div>`,
      button_label: 'Continue',
      data: {
        vignette_id: vignette.id,
        trial_type: 'element_probe',
        vignette_position: index + 1
      },
      on_finish: data => {
        data.knew = data.response.knew;
        data.aware = data.response.aware;
        data.should = data.response.should;
      }
    };
  });

  return [probeIntro, ...probeTrials];
}

// Now that they actually need the vignettes, build and load the actual trials
function createTrialTimeline(selectedVignettes) {
  let timeline = [];

  timeline.push({
    type: jsPsychPreload,
    images: rpmImageList,
    show_progress_bar: true,
    message: 'Loading puzzle images…'
  });

  const rpmTrials = jsPsych.randomization.shuffle(selectedBooklet.map(item => makeRpmTrial(item)));

  
  // 4. Add vignette trials with dynamic name and town replacement
  selectedVignettes.forEach((vignette, index) => {
    // Choose random values for [NAME] and [TOWN] for every trial
    const randomName = names[index]
    const personalizedVignette = personalizeVignette(vignette.vignette, index);

    const shuffledDefinitions = jsPsych.randomization.shuffle(getPersonalizedDefinitions(randomName));
    const judgmentOptionsHtml = shuffledDefinitions.map(def => `
          <div class="instruction-box" data-key="${def.key}">
            <p>${def.text}</p>
          </div>
      `).join('');
    const juryInstructions = `
      <div class="jury-instructions">
        <h3>Jury Instructions</h3>
        <p>Please select one of the following judgments which the above scenario proves beyond a reasonable doubt. </p>
        <p>"Proof beyond a reasonable doubt" is proof that leaves you firmly convinced your judgment is correct. It is not required that you prove this beyond all possible doubt.
        A reasonable doubt is a doubt based upon reason and common sense and is not based purely on speculation. It may arise from a careful and unbiased consideration of all the evidence, or from lack of evidence.        
        ${judgmentOptionsHtml}
      </div>
      `
    
    // Jury instructions and mental state judgment trial
    const judgmentTrial = {
      type: jsPsychHtmlKeyboardResponse,
      stimulus: `
        <div class="vignette">
          <div class="vignette-title">Scenario ${index + 1}</div>
          ${personalizedVignette}
        </div>
        ${juryInstructions}
        <div id="submit-container">
          <button id="submit-btn" class="jspsych-btn submit-disabled" disabled>Continue</button>
        </div>
      `,
      choices: "NO_KEYS",
      on_load: function() {
        let selectedChoice = null;
        const boxes = document.querySelectorAll('.instruction-box');
        const submitBtn = document.getElementById('submit-btn');
        
        boxes.forEach((box, index) => {
          box.style.cursor = 'pointer';
          box.addEventListener('click', () => {
            // Remove previous selection
            boxes.forEach(b => b.classList.remove('selected'));
            // Add selection to clicked box
            box.classList.add('selected');
            selectedChoice = index;
            // Enable submit button
            submitBtn.disabled = false;
            submitBtn.classList.remove('submit-disabled');
            submitBtn.classList.add('submit-enabled');
          });
        });
        
        submitBtn.addEventListener('click', () => {
          if (selectedChoice !== null) {
            jsPsych.finishTrial({response: selectedChoice});
          }
        });
      },
      on_finish: function(data) {
        const choiceIndex = data.response;
        const selectedKey = shuffledDefinitions[choiceIndex].key;
        data.judgment = selectedKey;
      },
      data: { 
        vignette_id: vignette.id, 
        trial_type: 'mental_state_judgment',
        vignette_position: index + 1
      }
    };    
    timeline.push(judgmentTrial);
    
    // Awareness of risk question
    const awarenessTrial = {
      type: jsPsychHtmlButtonResponse,
      stimulus: `
        <div class="vignette">
          <div class="vignette-title">Scenario ${index + 1}</div>
          ${personalizedVignette}
        </div>
        <h3>At the moment ${randomName} crossed the border, was he aware of a substantial risk that illicit material was in the package?</h3>
      `,
      choices: ['Yes', 'No'],
      data: { 
        vignette_id: vignette.id, 
        trial_type: 'awareness_judgment',
        vignette_position: index + 1
      },
      // Create a button_html array with two identical button templates
      button_html: Array(2).fill('<button class="jspsych-btn">%choice%</button>')
    };
    // timeline.push(awarenessTrial);
    
    // Risk magnitude question (only shown if awareness = Yes)
    const riskMagnitudeTrial = {
      type: jsPsychHtmlSliderResponse,
      stimulus: `
        <div class="vignette">
          <div class="vignette-title">Scenario ${index + 1}</div>
          ${personalizedVignette}
        </div>
        <h3>At the moment ${randomName} crossed the border, what did he believe was the chance that illicit material was in the package?</h3>
      `,
      labels: [
        `${randomName} was 100% certain that the package did not contain illicit material`,
        `${randomName} was 100% certain that the package contained illicit material`
      ],
      require_movement: true,
      css_classes: ['wrapped-slider-labels'],
      data: { 
        vignette_id: vignette.id, 
        trial_type: 'risk_magnitude',
        vignette_position: index + 1
      }
    };
    timeline.push(riskMagnitudeTrial);
    
    // Only show risk magnitude if they answered "Yes" to awareness
    const conditionalRiskMagnitude = {
      timeline: [riskMagnitudeTrial],
      conditional_function: () => {
        // Get the most recent awareness response (0 indicates "Yes")
        const lastAwarenessData = jsPsych.data.getLastTrialData().values()[0];
        return lastAwarenessData.response === 0;
      }
    };
    // timeline.push(conditionalRiskMagnitude);
    
    // Justification (free response)
    const justificationTrial = {
      type: jsPsychSurveyText,
      preamble: "<h3>Please briefly explain what contributed to you making the judgments that you did:</h3>",
      questions: [
        {
          prompt: "",
          name: "justification",
          rows: 5,
          required: true
        }
      ],
      data: { 
        vignette_id: vignette.id, 
        trial_type: 'justification',
        vignette_position: index + 1
      }
    };
    timeline.push(justificationTrial);
    
    // Add a distractor task after each vignette
    timeline.push(rpmTrials[index]);
  });

  // NEW: Ranking trial for MPC definitions with correct pre-shuffling
  const mpcRankingTrial = {
    type: jsPsychHtmlKeyboardResponse,
    stimulus: function() {

      // Use jsPsych's built-in function to shuffle the array
      const shuffledDefinitions = jsPsych.randomization.shuffle(getPersonalizedDefinitions(name="The person"));

      // Build the HTML for the ranking options from the shuffled array
      const rankingOptionsHtml = shuffledDefinitions.map(def => `
          <div class="instruction-box rank-option" data-key="${def.key}">
            <div class="rank-display"></div>
            <p>${def.text}</p>
          </div>
      `).join('');

      // Return the complete HTML for the stimulus
      return `
        <div class="vignette">
          <div class="vignette-title">Legal Definitions</div>
          <p>Please rank the following mental states in order of culpability, from <strong>1 = most guilty</strong> to <strong>4 = least guilty</strong>.</p>
          <p>Click on the definition that represents the highest level of guilt first. A number will appear to show its rank. Continue until all definitions are ranked.</p>
        </div>
        <div class="jury-instructions">
          ${rankingOptionsHtml}
        </div>
        <div id="submit-container">
          <button id="clear-btn" class="jspsych-btn">Clear Selections</button>
          <button id="submit-btn" class="jspsych-btn submit-disabled" disabled>Continue</button>
        </div>
      `;
    },
    choices: "NO_KEYS",
    on_load: function() {
      // This on_load function is now guaranteed to work because the HTML is already shuffled.
      const options = document.querySelectorAll('.rank-option');
      const submitBtn = document.getElementById('submit-btn');
      const clearBtn = document.getElementById('clear-btn');
      let rankedOrder = [];

      const updateRanks = () => {
        options.forEach(opt => {
          const key = opt.getAttribute('data-key');
          const rankIndex = rankedOrder.indexOf(key);
          const rankDisplay = opt.querySelector('.rank-display');
          
          if (rankIndex !== -1) {
            opt.classList.add('selected');
            rankDisplay.textContent = rankIndex + 1;
          } else {
            opt.classList.remove('selected');
            rankDisplay.textContent = '';
          }
        });

        if (rankedOrder.length === options.length) {
          submitBtn.disabled = false;
          submitBtn.classList.remove('submit-disabled');
          submitBtn.classList.add('submit-enabled');
        } else {
          submitBtn.disabled = true;
          submitBtn.classList.remove('submit-enabled');
          submitBtn.classList.add('submit-disabled');
        }
      };
      
      options.forEach(option => {
        option.addEventListener('click', () => {
          const key = option.getAttribute('data-key');
          const rank = rankedOrder.indexOf(key);
          if (rank === -1) rankedOrder.push(key);   // first click: give it the next number
          else rankedOrder.splice(rank, 1);         // clicked again: remove it; later numbers move up
          updateRanks();
        });
      });

      clearBtn.addEventListener('click', () => {
        rankedOrder = [];
        updateRanks();
      });

      submitBtn.addEventListener('click', () => {
        jsPsych.finishTrial({
          response: rankedOrder
        });
      });

      const style = document.createElement('style');
      style.innerHTML = `
        .rank-display { 
          position: absolute; top: 50%; left: -30px; transform: translateY(-50%); 
          width: 24px; height: 24px; background-color: #27ae60; color: white;
          border-radius: 50%; display: flex; align-items: center; justify-content: center;
          font-weight: bold; font-size: 14px; opacity: 0; transition: opacity 0.3s;
        }
        .instruction-box.selected .rank-display { opacity: 1; }
        .instruction-box { position: relative; }
      `;
      document.head.appendChild(style);
    },
    data: {
      trial_type: 'mpc_ranking'
    }
  };
  timeline.push(mpcRankingTrial);

  // NEW (Study 2): comprehension item and element probe, in the randomized order
  const comprehensionTrial = makeComprehensionTrial();
  const probeTimeline = makeProbeTimeline(selectedVignettes);
  if (comprehensionFirst) {
    timeline.push(comprehensionTrial, ...probeTimeline);
  } else {
    timeline.push(...probeTimeline, comprehensionTrial);
  }

  // have the study be set complete after the final task trial (main task, comprehension, probe)
  const markCompleteTrial = {
    type: jsPsychCallFunction,
    func: function() {
      // grab the ordered IDs of the 5 vignettes we showed
      const order = selectedVignettes.map(v => v.id);
      // write both the completion flag and the array into the data
      jsPsych.data.write({
        study_completed: true,
        vignette_order: JSON.stringify(order)
      });
    }
  };
  timeline.push(markCompleteTrial);
  
  // NEW (Study 2): seriousness item
  const seriousnessOptions = [
    'I took it seriously; please use my data',
    'I did not take it seriously; please do not use my data'
  ];
  const seriousnessTrial = {
    type: jsPsychHtmlButtonResponse,
    stimulus: `
      <p>It is important for our research that we only use data from people who took this study seriously. How seriously did you take this study? Your answer will not affect your payment.</p>
    `,
    choices: seriousnessOptions,
    button_html: Array(2).fill('<button class="jspsych-btn">%choice%</button>'),
    data: { trial_type: 'seriousness' },
    on_finish: data => {
      data.seriousness = (data.response === 0) ? 'serious' : 'not_serious';
    }
  };
  timeline.push(seriousnessTrial);

  // 5. Demographics (revised for Study 2), with the embedded attention item
  const attentionOptions = ['Strongly disagree', 'Somewhat disagree', 'Neither agree nor disagree', 'Somewhat agree', 'Strongly agree'];
  const raceOptions = [
    ['race_aian', 'American Indian or Alaska Native'],
    ['race_asian', 'Asian'],
    ['race_black', 'Black or African American'],
    ['race_hispanic', 'Hispanic or Latino'],
    ['race_mena', 'Middle Eastern or North African'],
    ['race_nhpi', 'Native Hawaiian or Pacific Islander'],
    ['race_white', 'White'],
    ['race_selfdescribe', 'Prefer to self-describe'],
    ['race_prefernot', 'Prefer not to say']
  ];
  const legalOptions = [
    ['legal_none', 'None'],
    ['legal_courses', 'Law courses in college or elsewhere'],
    ['legal_lawschool', 'Currently in law school'],
    ['legal_jd', 'Law degree (JD or equivalent)'],
    ['legal_work', 'Work as a paralegal or in another legal setting']
  ];
  const educationOptions = [
    'Less than high school',
    'High school diploma or equivalent',
    'Some college, no degree',
    'Associate degree',
    "Bachelor's degree",
    "Master's degree",
    'Professional degree (for example, JD or MD)',
    'Doctoral degree'
  ];
  const genderOptions = ['Woman', 'Man', 'Non-binary', 'Prefer to self-describe', 'Prefer not to say'];

  const demographicsTrial = {
    type: jsPsychSurveyHtmlForm,
    preamble: "<h3>Demographics</h3><p>Please answer the following questions:</p>",
    html: `
      <div class="form-block">
        <div class="demo-question">
          <label for="age">What is your age?</label>
          <input type="number" id="age" name="age" min="18" max="100" step="1" required>
        </div>

        <div class="demo-question">
          <p class="demo-label">What is your gender?</p>
          ${genderOptions.map(g => `<label class="choice-option"><input type="radio" name="gender" value="${g}" required> <span>${g}</span></label>` +
            (g === 'Prefer to self-describe' ? `<input type="text" id="gender-other" name="gender_selfdescribe" class="other-text" disabled aria-label="Prefer to self-describe">` : '')).join('')}
        </div>

        <div class="demo-question" id="race-group">
          <p class="demo-label">Which of the following describe your race or ethnicity? Select all that apply.</p>
          ${raceOptions.map(([n, t]) => `<label class="choice-option"><input type="checkbox" class="race-box" name="${n}" value="1" required> <span>${t}</span></label>` +
            (n === 'race_selfdescribe' ? `<input type="text" id="race-other" name="race_selfdescribe_text" class="other-text" disabled aria-label="Prefer to self-describe">` : '')).join('')}
        </div>

        <div class="demo-question">
          <label for="education">What is the highest level of education you have completed?</label>
          <select id="education" name="education" required>
            <option value="">Select one</option>
            ${educationOptions.map(e => `<option value="${e}">${e}</option>`).join('')}
          </select>
        </div>

        <div class="demo-question">
          <p class="demo-label">To show that you are reading carefully, please select “Somewhat disagree” for this item.</p>
          ${attentionOptions.map(a => `<label class="choice-option"><input type="radio" name="attention" value="${a}" required> <span>${a}</span></label>`).join('')}
        </div>

        <div class="demo-question">
          <p class="demo-label">Have you ever served on a jury?</p>
          <label class="choice-option"><input type="radio" name="jury_service" value="Yes" required> <span>Yes</span></label>
          <label class="choice-option"><input type="radio" name="jury_service" value="No" required> <span>No</span></label>
          <div id="jury-type-block" class="followup" style="display:none;">
            <p class="demo-label">What kind of case or cases?</p>
            ${['Criminal', 'Civil', 'Both', 'Not sure'].map(t => `<label class="choice-option"><input type="radio" name="jury_case_type" value="${t}" disabled> <span>${t}</span></label>`).join('')}
          </div>
        </div>

        <div class="demo-question" id="legal-group">
          <p class="demo-label">Which of the following describe your legal training or experience? Select all that apply.</p>
          ${legalOptions.map(([n, t]) => `<label class="choice-option"><input type="checkbox" class="legal-box" name="${n}" value="1" required> <span>${t}</span></label>`).join('')}
        </div>
      </div>
    `,
    button_label: "Proceed to Begin Submitting Study Data",
    on_load: function() {
      // "Prefer to self-describe" text boxes are required only when that option is chosen
      const genderOther = document.getElementById('gender-other');
      document.querySelectorAll('input[name="gender"]').forEach(r => r.addEventListener('change', () => {
        const on = document.querySelector('input[name="gender"][value="Prefer to self-describe"]').checked;
        genderOther.disabled = !on; genderOther.required = on;
        if (on) genderOther.focus(); else genderOther.value = '';
      }));

      // "Select all that apply" groups: at least one box required; exclusive options clear the others
      const wireCheckboxGroup = (selector, exclusiveName, otherInput, otherName) => {
        const boxes = Array.from(document.querySelectorAll(selector));
        const update = changed => {
          if (changed && changed.name === exclusiveName && changed.checked) {
            boxes.forEach(b => { if (b !== changed) b.checked = false; });
          } else if (changed && changed.checked) {
            boxes.forEach(b => { if (b.name === exclusiveName) b.checked = false; });
          }
          const any = boxes.some(b => b.checked);
          boxes.forEach(b => { b.required = !any; });
          if (otherInput) {
            const on = boxes.some(b => b.name === otherName && b.checked);
            otherInput.disabled = !on; otherInput.required = on;
            if (!on) otherInput.value = '';
          }
        };
        boxes.forEach(b => b.addEventListener('change', () => update(b)));
        update(null);
      };
      wireCheckboxGroup('.race-box', 'race_prefernot', document.getElementById('race-other'), 'race_selfdescribe');
      wireCheckboxGroup('.legal-box', 'legal_none', null, null);

      // Follow-up about the kind of case appears only after "Yes"
      const juryBlock = document.getElementById('jury-type-block');
      const juryTypeInputs = juryBlock.querySelectorAll('input');
      document.querySelectorAll('input[name="jury_service"]').forEach(r => r.addEventListener('change', () => {
        const yes = document.querySelector('input[name="jury_service"][value="Yes"]').checked;
        juryBlock.style.display = yes ? 'block' : 'none';
        juryTypeInputs.forEach(i => { i.disabled = !yes; i.required = yes; if (!yes) i.checked = false; });
      }));
    },
    data: {
      trial_type: "demographics"
    },
    on_finish: data => {
      const r = data.response;
      data.age = r.age;
      data.gender = r.gender;
      data.gender_selfdescribe = r.gender_selfdescribe || '';
      data.race = raceOptions.filter(([n]) => r[n]).map(([, t]) => t).join('; ');
      data.race_selfdescribe = r.race_selfdescribe_text || '';
      data.education = r.education;
      data.attention_response = r.attention;
      data.attention_pass = (r.attention === 'Somewhat disagree');
      data.jury_service = r.jury_service;
      data.jury_case_type = r.jury_case_type || '';
      data.legal_training = legalOptions.filter(([n]) => r[n]).map(([, t]) => t).join('; ');
      data.any_legal_training = legalOptions.some(([n]) => n !== 'legal_none' && r[n]);
    }
  };
  timeline.push(demographicsTrial);

  const pavloviaFinishTrial = {
    type: jsPsychPavlovia,
    command: 'finish'
  };
  timeline.push(pavloviaFinishTrial);
  
  return timeline;
}

async function startExperiment() {
  // run consent, eligibility, and instructions
  await jsPsych.run( createInitialTimeline() );

  if (!_consented || !_eligible) return;

  // otherwise, fetch vignettes and run the full study
  const vignettes = await fetchPersonalizedVignettes();
  const fullTimeline = createTrialTimeline(vignettes);
  await jsPsych.run(fullTimeline);
}


startExperiment();

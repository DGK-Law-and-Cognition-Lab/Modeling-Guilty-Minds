import trialMinimisation from './trialMinimisation.js';

// Initialize jsPsych
const jsPsych = initJsPsych({
  on_finish: function() {
    // Only show thank you if study was actually completed
    const studyCompleted = jsPsych.data.get().filter({study_completed: true}).count() > 0;
    if (studyCompleted) {
      const display = jsPsych.getDisplayElement();
      display.innerHTML = `
        <div style="text-align:center; margin-top:50px;">
          <h2>Debriefing</h2>
          <p>Thank you for participating in this study. Your responses will help us understand how people make judgments about mental states in legal contexts.</p>
          <p>The scenarios you read varied systematically across several factors. We are investigating how these factors influence judgments about mental states.</p>
          <p>If you have any questions about this study, please contact the researcher.</p>
          <p>Your responses have been recorded.</p>
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
    fetch(GLOBAL_COUNTS_PATH).then(r => r.json()),
    fetch(VIGNETTE_TEXT_PATH).then(r => r.json())
  ]);

  const selectedIds = await trialMinimisation(globalCounts, NUM_TRIALS);

  const decimalIds = selectedIds.map(binId => parseInt(binId, 2));

  const selectedVignettes = decimalIds.map(id => (allVignettes[id]));

  return selectedVignettes; // an array of 5 objects, each with id and vignette objs
}

// creates and loads the first part of the experiment containing the intro, consent, 
// instructions, etc. up until the first actual trial, so that the minimisation calculation
// has time to be run in the background until it is actually needed. 
let _consented = false;
function createInitialTimeline() {

  const pavlovia_init = {
    type: jsPsychPavlovia,
    command: "init"
  };

  const consentTrial = {
    type: jsPsychHtmlButtonResponse,
    stimulus: `
      <h2>Consent Form</h2>
      <p>This study investigates how people make judgments about others' mental states in legal contexts. You will read several scenarios and answer questions about them.</p>
      <p>Your participation is voluntary, and you may withdraw at any time without penalty. Your responses will be kept confidential and used for research purposes only.</p>
      <p>The study will take approximately 15-20 minutes to complete.</p>
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
        // drop everything and go straight to your on_finish thank-you
        jsPsych.endExperiment('Participant declined consent.');
      }
    }
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
      // only show if they consented (clicked the first button)
      const last = jsPsych.data.getLastTrialData().values()[0];
      return last.response === 0;
    }
  };

  return [ pavlovia_init, consentTrial, instructionsNode ];
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
          if (rankedOrder.includes(key)) return;
          rankedOrder.push(key);
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

  // have the study be set complete after final real trial
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
  
  // 5. Demographics 
  const demographicsTrial = {
    type: jsPsychSurveyHtmlForm,
    preamble: "<h3>Demographics</h3><p>Please answer the following questions:</p>",
    html: `
      <label for="age">Age:</label>
      <input type="number" id="age" name="age" min="10" max="100" required><br><br>
  
      <label for="education">Education Level:</label>
      <select id="education" name="education" required>
        <option value="">Select one</option>
        <option value="Freshman">Freshman</option>
        <option value="Sophomore">Sophomore</option>
        <option value="Junior">Junior</option>
        <option value="Senior">Senior</option>
        <option value="Bachelor's">Bachelor's</option>
        <option value="Master's">Master's</option>
        <option value="PhD">PhD</option>
        <option value="JD">JD</option>
      </select><br><br>
  
      <label for="legal_experience">Have you ever served on a jury or had other legal experience?</label>
      <select id="legal_experience" name="legal_experience" required>
        <option value="">Select one</option>
        <option value="Yes">Yes</option>
        <option value="No">No</option>
      </select>
    `,
    button_label: "Proceed to Begin Submitting Study Data",
    data: {
      trial_type: "demographics"
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
  // run consent + instructions
  await jsPsych.run( createInitialTimeline() );

  if (!_consented) return;

  // otherwise, fetch vignettes and run the full study
  const vignettes = await fetchPersonalizedVignettes();
  const fullTimeline = createTrialTimeline(vignettes);
  await jsPsych.run(fullTimeline);
}


startExperiment();

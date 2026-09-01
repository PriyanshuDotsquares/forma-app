"""Curated seed content for the exercise library and achievement
definitions, inserted by the initial fitness-schema migration.

This is FORMA's own curated set — a solid, accurate starting library
(~45 exercises across every major muscle group), not a literal "400+"
despite what placeholder copy in the design implies. Achievement criteria
are backed by whatever `app.services.achievements._compute_stats` can
actually measure from logged sets/sessions/records — titles borrow the
design's flavor, descriptions describe only what's genuinely tracked.
"""

import uuid


def _ex(
    slug: str,
    name: str,
    primary: list[str],
    secondary: list[str],
    equipment: list[str],
    difficulty: str,
    steps: list[str],
    cues: list[str],
    mistakes: list[dict[str, str]],
    camera: str | None = None,
) -> dict:
    return {
        "id": uuid.uuid4(),
        "slug": slug,
        "name": name,
        "primary_muscles": primary,
        "secondary_muscles": secondary,
        "equipment": equipment,
        "difficulty": difficulty,
        "execution_steps": steps,
        "pro_cues": cues,
        "mistakes": mistakes,
        "supports_camera": camera is not None,
        "camera_view": camera,
    }


_BENCH_MISTAKES = [
    {"title": "Elbows flared", "why": "Increases shoulder strain.", "fix": "Tuck elbows to ~60°."},
    {"title": "Bouncing the bar", "why": "Uses momentum, not muscle.", "fix": "Pause briefly at the bottom."},
    {"title": "Butt off the bench", "why": "Unstable and potentially unsafe.", "fix": "Keep glutes glued to the pad."},
]

_SQUAT_MISTAKES = [
    {"title": "Cutting depth", "why": "Undertrains the glutes and quads through full range.", "fix": "Sit a little deeper — hip crease below the knee."},
    {"title": "Knees caving in", "why": "Loads the knee joint unevenly.", "fix": "Push your knees out over your toes."},
    {"title": "Heels lifting", "why": "Shifts load forward, unstable.", "fix": "Keep weight through your whole foot."},
]

_DEADLIFT_MISTAKES = [
    {"title": "Rounded lower back", "why": "Puts uneven load on the spine.", "fix": "Brace your core and keep a neutral spine."},
    {"title": "Bar drifting forward", "why": "Increases lower-back torque.", "fix": "Keep the bar close, dragging up the shins."},
]

EXERCISES: list[dict] = [
    # Chest
    _ex("barbell-bench-press", "Barbell Bench Press", ["chest"], ["front_delts", "triceps"], ["barbell"], "intermediate",
        ["Lie flat on the bench with your feet planted.", "Grip the bar slightly wider than shoulder-width.",
         "Lower the bar to mid-chest with control.", "Drive the bar back up while keeping your feet anchored.",
         "Rack the bar safely after the final rep."],
        ["Squeeze your shoulder blades down and back.", "Keep a slight arch in your lower back.", "Drive through your heels throughout the lift."],
        _BENCH_MISTAKES, camera="side"),
    _ex("incline-dumbbell-press", "Incline Dumbbell Press", ["chest"], ["front_delts", "triceps"], ["dumbbell"], "intermediate",
        ["Set the bench to a 30–45° incline.", "Press the dumbbells up over your upper chest.", "Lower with control to chest level."],
        ["Keep wrists stacked over elbows.", "Don't let the dumbbells drift behind your head."],
        [{"title": "Flattening the incline", "why": "Turns it into a flat-bench movement.", "fix": "Keep the bench between 30–45°."}], camera="side"),
    _ex("dumbbell-bench-press", "Dumbbell Bench Press", ["chest"], ["triceps", "front_delts"], ["dumbbell"], "beginner",
        ["Lie back with a dumbbell in each hand at chest level.", "Press up until arms are extended.", "Lower slowly back to the start."],
        ["Let your shoulder blades stay retracted throughout."], [], camera="side"),
    _ex("decline-bench-press", "Decline Bench Press", ["chest"], ["triceps"], ["barbell"], "intermediate",
        ["Secure your legs on a decline bench.", "Lower the bar to your lower chest.", "Press back up to full extension."],
        ["Control the descent — don't let gravity do the work."], [], camera=None),
    _ex("dips", "Dips", ["chest"], ["triceps"], ["bodyweight"], "intermediate",
        ["Support yourself on parallel bars, arms locked.", "Lower until your shoulders dip below your elbows.", "Press back up to full lockout."],
        ["Lean forward slightly to bias the chest."], [{"title": "Shallow depth", "why": "Limits chest activation.", "fix": "Lower until you feel a stretch in the chest."}], camera="side"),
    _ex("push-up", "Push-up", ["chest"], ["triceps", "core"], ["bodyweight"], "beginner",
        ["Start in a plank with hands under shoulders.", "Lower your chest to the floor.", "Push back up to full extension."],
        ["Keep your body in a straight line."], [], camera="side"),
    _ex("cable-crossover", "Cable Crossover", ["chest"], [], ["cable"], "intermediate",
        ["Stand centered between two cable towers.", "Pull the handles down and across your body.", "Return with control."],
        ["Keep a slight bend in the elbows throughout."], [], camera="front"),
    _ex("chest-fly-dumbbell", "Dumbbell Chest Fly", ["chest"], [], ["dumbbell"], "beginner",
        ["Lie on a flat bench, arms extended above your chest.", "Lower the dumbbells out to your sides.", "Bring them back together over your chest."],
        ["Keep a soft bend in your elbows."], [], camera=None),
    _ex("close-grip-bench-press", "Close-grip Bench Press", ["triceps"], ["chest"], ["barbell"], "intermediate",
        ["Grip the bar just inside shoulder-width.", "Lower to your lower chest, elbows tucked.", "Press back to lockout."],
        ["Keep elbows close to your body throughout."], [], camera=None),
    _ex("dumbbell-pullover", "Dumbbell Pullover", ["chest"], ["lats"], ["dumbbell"], "intermediate",
        ["Lie across a bench holding one dumbbell over your chest.", "Lower it back over your head with a slight arm bend.", "Pull back over your chest."],
        ["Keep your hips low, don't let your ribs flare."], [], camera=None),
    _ex("pec-deck-machine", "Pec Deck Machine", ["chest"], [], ["machine"], "beginner",
        ["Sit with your back flat against the pad.", "Bring the handles together in front of your chest.", "Return with control."],
        ["Squeeze at the peak of the movement."], [], camera=None),
    # Back
    _ex("seated-cable-row", "Seated Cable Row", ["back"], ["lats", "biceps"], ["cable"], "beginner",
        ["Sit with knees slightly bent, grip the handle.", "Pull to your torso, squeezing your shoulder blades.", "Extend back out with control."],
        ["Keep your torso upright, avoid leaning back excessively."], [], camera="side"),
    _ex("weighted-pull-up", "Weighted Pull-up", ["back"], ["lats", "biceps"], ["bodyweight"], "advanced",
        ["Hang from the bar with an overhand grip.", "Pull your chin above the bar.", "Lower with control to a full hang."],
        ["Drive your elbows down and back."], [], camera="side"),
    _ex("lat-pulldown", "Lat Pulldown", ["back"], ["lats", "biceps"], ["cable"], "beginner",
        ["Grip the bar wider than shoulder-width.", "Pull down to your upper chest.", "Return with control to full stretch."],
        ["Lead with your elbows, not your hands."], [], camera="front"),
    _ex("barbell-deadlift", "Barbell Deadlift", ["back"], ["hamstrings", "glutes"], ["barbell"], "advanced",
        ["Stand with the bar over mid-foot.", "Hinge and grip just outside your legs.", "Drive through the floor to stand tall.", "Lower with control, hips back first."],
        ["Keep the bar path close to your shins.", "Brace your core before every rep."],
        _DEADLIFT_MISTAKES, camera="side"),
    _ex("bent-over-barbell-row", "Bent-over Barbell Row", ["back"], ["lats", "biceps"], ["barbell"], "intermediate",
        ["Hinge at the hips, torso near-parallel to the floor.", "Pull the bar to your lower ribs.", "Lower with control."],
        ["Keep your spine neutral throughout."], [], camera="side"),
    _ex("single-arm-dumbbell-row", "Single-arm Dumbbell Row", ["back"], ["lats", "biceps"], ["dumbbell"], "beginner",
        ["Support yourself with one hand and knee on a bench.", "Row the dumbbell to your hip.", "Lower with control."],
        ["Avoid twisting your torso as you pull."], [], camera=None),
    _ex("t-bar-row", "T-Bar Row", ["back"], ["lats"], ["barbell", "machine"], "intermediate",
        ["Straddle the bar, hinge at the hips.", "Pull the handles to your chest.", "Lower with control."],
        ["Keep your chest up throughout the pull."], [], camera=None),
    _ex("face-pull", "Face Pull", ["shoulders"], ["back"], ["cable"], "beginner",
        ["Set the cable to head height.", "Pull the rope toward your face, elbows high.", "Return with control."],
        ["Externally rotate at the top of the pull."], [], camera=None),
    # Shoulders
    _ex("overhead-press", "Overhead Press", ["shoulders"], ["triceps"], ["barbell"], "intermediate",
        ["Start with the bar at shoulder height.", "Press overhead to full lockout.", "Lower with control back to the shoulders."],
        ["Squeeze your glutes to keep your ribs down.", "Keep the bar path close to your face."],
        [{"title": "Excessive back arch", "why": "Turns the press into an incline press.", "fix": "Brace your core, keep ribs down."}], camera="side"),
    _ex("neutral-grip-db-press", "Neutral-grip DB Press", ["shoulders"], ["triceps"], ["dumbbell"], "beginner",
        ["Hold dumbbells with palms facing each other.", "Press overhead to full extension.", "Lower with control."],
        ["Easier on the shoulders than a barbell press."], [], camera="side"),
    _ex("dumbbell-lateral-raise", "Dumbbell Lateral Raise", ["shoulders"], [], ["dumbbell"], "beginner",
        ["Stand holding dumbbells at your sides.", "Raise your arms out to shoulder height.", "Lower with control."],
        ["Lead with your elbows, not your hands."], [], camera=None),
    _ex("rear-delt-fly", "Rear Delt Fly", ["shoulders"], ["back"], ["dumbbell"], "beginner",
        ["Hinge forward at the hips.", "Raise the dumbbells out to your sides.", "Lower with control."],
        ["Keep a slight bend in your elbows."], [], camera=None),
    _ex("front-raise", "Front Raise", ["shoulders"], [], ["dumbbell"], "beginner",
        ["Hold dumbbells in front of your thighs.", "Raise to shoulder height.", "Lower with control."],
        ["Avoid swinging — control the weight."], [], camera=None),
    _ex("arnold-press", "Arnold Press", ["shoulders"], ["triceps"], ["dumbbell"], "intermediate",
        ["Start with palms facing you at shoulder height.", "Press up while rotating palms outward.", "Reverse on the way down."],
        ["Keep the rotation smooth, not rushed."], [], camera="side"),
    # Arms
    _ex("barbell-bicep-curl", "Barbell Bicep Curl", ["biceps"], ["forearms"], ["barbell"], "beginner",
        ["Stand holding the bar with an underhand grip.", "Curl to shoulder height.", "Lower with control."],
        ["Keep your elbows pinned to your sides."], [], camera=None),
    _ex("dumbbell-bicep-curl", "Dumbbell Bicep Curl", ["biceps"], ["forearms"], ["dumbbell"], "beginner",
        ["Hold dumbbells at your sides, palms forward.", "Curl up to shoulder height.", "Lower with control."],
        ["Avoid swinging your torso for momentum."], [], camera=None),
    _ex("hammer-curl", "Hammer Curl", ["biceps"], ["forearms"], ["dumbbell"], "beginner",
        ["Hold dumbbells with a neutral grip.", "Curl up keeping palms facing in.", "Lower with control."],
        ["Keep wrists straight throughout."], [], camera=None),
    _ex("tricep-pushdown", "Tricep Pushdown", ["triceps"], [], ["cable"], "beginner",
        ["Grip the bar with elbows at your sides.", "Push down to full extension.", "Return with control."],
        ["Keep your elbows pinned — don't let them flare."], [], camera=None),
    _ex("overhead-tricep-extension", "Overhead Tricep Extension", ["triceps"], [], ["dumbbell"], "beginner",
        ["Hold a dumbbell overhead with both hands.", "Lower behind your head with control.", "Extend back to the top."],
        ["Keep your elbows pointed forward."], [], camera=None),
    _ex("skull-crusher", "Skull Crusher", ["triceps"], [], ["barbell"], "intermediate",
        ["Lie on a bench holding the bar over your chest.", "Lower to your forehead by bending elbows.", "Extend back to the top."],
        ["Keep your upper arms stationary throughout."], [], camera=None),
    # Legs
    _ex("barbell-back-squat", "Barbell Back Squat", ["quads"], ["glutes", "hamstrings"], ["barbell"], "advanced",
        ["Set the bar across your upper back.", "Bend your knees and hips to sit down.", "Drive back up to standing."],
        ["Keep your chest up throughout the descent.", "Push your knees out over your toes."],
        _SQUAT_MISTAKES, camera="side"),
    _ex("front-squat", "Front Squat", ["quads"], ["core"], ["barbell"], "advanced",
        ["Rest the bar across your front shoulders.", "Squat down keeping your torso upright.", "Drive back up to standing."],
        ["Keep your elbows high throughout."], [], camera="side"),
    _ex("leg-press", "Leg Press", ["quads"], ["glutes"], ["machine"], "beginner",
        ["Sit in the machine, feet shoulder-width on the platform.", "Lower until your knees reach ~90°.", "Press back to extension without locking out."],
        ["Don't let your lower back round off the pad."], [], camera=None),
    _ex("romanian-deadlift", "Romanian Deadlift", ["hamstrings"], ["glutes", "back"], ["barbell"], "intermediate",
        ["Hold the bar at hip height.", "Hinge back, lowering the bar along your legs.", "Drive your hips forward to stand."],
        ["Keep a soft bend in your knees throughout."], [], camera="side"),
    _ex("leg-curl", "Leg Curl", ["hamstrings"], [], ["machine"], "beginner",
        ["Lie face down on the machine.", "Curl your heels toward your glutes.", "Lower with control."],
        ["Avoid lifting your hips off the pad."], [], camera=None),
    _ex("leg-extension", "Leg Extension", ["quads"], [], ["machine"], "beginner",
        ["Sit with your shins behind the pad.", "Extend your legs to full lockout.", "Lower with control."],
        ["Avoid swinging or using momentum."], [], camera=None),
    _ex("walking-lunge", "Walking Lunge", ["quads"], ["glutes"], ["dumbbell", "bodyweight"], "beginner",
        ["Step forward into a lunge.", "Lower until both knees reach ~90°.", "Push off to step into the next lunge."],
        ["Keep your torso upright throughout."], [], camera="side"),
    _ex("bulgarian-split-squat", "Bulgarian Split Squat", ["quads"], ["glutes"], ["dumbbell"], "intermediate",
        ["Rest your rear foot on a bench behind you.", "Lower your back knee toward the floor.", "Drive back up through your front foot."],
        ["Keep most of your weight on the front leg."], [], camera="side"),
    _ex("hip-thrust", "Hip Thrust", ["glutes"], ["hamstrings"], ["barbell"], "intermediate",
        ["Rest your upper back on a bench, bar over your hips.", "Drive your hips up to full extension.", "Lower with control."],
        ["Squeeze your glutes hard at the top."], [], camera=None),
    _ex("standing-calf-raise", "Standing Calf Raise", ["calves"], [], ["machine", "bodyweight"], "beginner",
        ["Stand on the edge of a platform.", "Rise onto your toes.", "Lower below the platform for a full stretch."],
        ["Pause briefly at the top of each rep."], [], camera=None),
    _ex("seated-calf-raise", "Seated Calf Raise", ["calves"], [], ["machine"], "beginner",
        ["Sit with the pad across your knees.", "Rise onto your toes.", "Lower for a full stretch."],
        ["Move through a full range of motion."], [], camera=None),
    # Core
    _ex("plank", "Plank", ["core"], [], ["bodyweight"], "beginner",
        ["Support yourself on forearms and toes.", "Keep your body in a straight line.", "Hold, breathing steadily."],
        ["Squeeze your glutes to avoid sagging hips."], [], camera=None),
    _ex("cable-crunch", "Cable Crunch", ["core"], [], ["cable"], "intermediate",
        ["Kneel below a high pulley, rope behind your head.", "Crunch down, bringing elbows toward your knees.", "Return with control."],
        ["Move from your abs, not your hips."], [], camera=None),
    _ex("hanging-leg-raise", "Hanging Leg Raise", ["core"], [], ["bodyweight"], "advanced",
        ["Hang from a pull-up bar.", "Raise your legs to hip height or above.", "Lower with control."],
        ["Avoid swinging — control the movement."], [], camera=None),
    _ex("russian-twist", "Russian Twist", ["core"], [], ["bodyweight", "dumbbell"], "beginner",
        ["Sit with knees bent, torso leaned back slightly.", "Rotate your torso side to side.", "Keep your chest up throughout."],
        ["Move slowly — control beats speed here."], [], camera=None),
]


def _ach(key: str, category: str, title: str, description: str, icon: str, criteria: dict, is_secret: bool = False) -> dict:
    return {
        "id": uuid.uuid4(),
        "key": key,
        "category": category,
        "title": title,
        "description": description,
        "icon": icon,
        "criteria": criteria,
        "is_secret": is_secret,
    }


ACHIEVEMENTS: list[dict] = [
    _ach("first_rep", "consistency", "First Rep", "Complete your first workout.", "flag", {"type": "session_count", "target": 1}),
    _ach("half_century", "consistency", "Half Century", "Complete 50 workouts.", "military_tech", {"type": "session_count", "target": 50}),
    _ach("century", "consistency", "Century", "Complete 100 workouts.", "emoji_events", {"type": "session_count", "target": 100}),
    _ach("iron_week", "consistency", "Iron Week", "Train 4 or more times in a single week.", "link", {"type": "sessions_in_best_week", "target": 4}),
    _ach("two_week_streak", "consistency", "Two Week Streak", "Train 14 days in a row.", "local_fire_department", {"type": "streak_days", "target": 14}),
    _ach("thirty_day_streak", "consistency", "30 Day Streak", "Train 30 days in a row.", "local_fire_department", {"type": "streak_days", "target": 30}),
    _ach("early_bird", "consistency", "Early Bird", "Complete a workout before 7am.", "wb_sunny", {"type": "early_sessions", "target": 1}),
    _ach("deep_squatter", "strength", "Deep Squatter", "Log 20 sets with excellent form (85+ form score).", "architecture", {"type": "high_form_sets", "target": 20}),
    _ach("form_master", "strength", "Form Master", "Log 50 sets with excellent form (85+ form score).", "verified", {"type": "high_form_sets", "target": 50}),
    _ach("pr_hunter", "strength", "PR Hunter", "Set 5 personal records.", "trending_up", {"type": "pr_count", "target": 5}),
    _ach("pr_machine", "strength", "PR Machine", "Set 20 personal records.", "trending_up", {"type": "pr_count", "target": 20}),
    _ach("century_club", "strength", "Century Club", "Reach a 100kg+ estimated 1-rep max on any main lift.", "fitness_center", {"type": "max_est_1rm_kg", "target": 100}),
    _ach("double_bodyweight", "strength", "Double Bodyweight", "Hit an estimated 1RM of 2x your bodyweight on any lift.", "monitor_weight", {"type": "max_bodyweight_ratio", "target": 2}),
    _ach("volume_lord", "volume", "Volume Lord", "Lift 100,000kg of total volume.", "warehouse", {"type": "volume_kg_total", "target": 100000}),
    _ach("quarter_million", "volume", "Quarter Million", "Lift 250,000kg of total volume.", "warehouse", {"type": "volume_kg_total", "target": 250000}),
    _ach("secret_1", "secret", "???", "Keep training to find out.", "help_outline", {"type": "streak_days", "target": 60}, is_secret=True),
]


def _challenge(key: str, title: str, description: str, metric: str, period: str, target_value: float, icon: str, is_group: bool = True) -> dict:
    return {
        "id": uuid.uuid4(),
        "key": key,
        "title": title,
        "description": description,
        "metric": metric,
        "period": period,
        "target_value": target_value,
        "icon": icon,
        "is_group": is_group,
        "is_active": True,
    }


# Time-boxed, unlike ACHIEVEMENTS — progress is computed against the current
# week/month/streak by `app.services.challenges`, not lifetime totals.
CHALLENGES: list[dict] = [
    _challenge("weekly_3_sessions", "3 Sessions This Week", "Log 3 workouts before the week resets.", "session_count", "weekly", 3, "event_available"),
    _challenge("weekly_5_sessions", "5 Sessions This Week", "Log 5 workouts before the week resets.", "session_count", "weekly", 5, "military_tech"),
    _challenge("monthly_volume_10k", "10,000kg Volume This Month", "Move 10,000kg of total volume this month.", "volume_kg", "monthly", 10000, "warehouse"),
    _challenge("monthly_volume_25k", "25,000kg Volume This Month", "Move 25,000kg of total volume this month.", "volume_kg", "monthly", 25000, "warehouse"),
    _challenge("streak_7", "7-Day Streak", "Train 7 days in a row.", "streak_days", "ongoing", 7, "local_fire_department", is_group=False),
    _challenge("streak_30", "30-Day Streak", "Train 30 days in a row.", "streak_days", "ongoing", 30, "local_fire_department", is_group=False),
]

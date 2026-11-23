"""Read-only checks of authored data, generated tables, atlas and the Rojo build."""
import csv
import math
import re
import subprocess
import tempfile
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image

from build_item_icons import build
from sync_tables import sync

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / "src/ReplicatedStorage/Shared"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_rows(folder, name, fields):
    with (folder / (name + ".txt")).open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        require(set(fields.split()) <= set(reader.fieldnames or []), f"{name}: missing columns")
        rows = list(reader)
    ids = [row["Id"] for row in rows]
    require(rows and all(ids) and len(ids) == len(set(ids)), f"{name}: empty or duplicate Id")
    return rows


def count(row, key):
    require(re.fullmatch(r"[0-9]+", row[key]), f"{row['Id']}: invalid {key}")
    return int(row[key])


def check_data(folder):
    grades = read_rows(folder, "GradeDataSheet", "Id ColorHex")
    for row in grades:
        require(re.fullmatch(r"#[0-9a-fA-F]{6}", row["ColorHex"]), f"Invalid color {row}")
    questions = read_rows(folder, "QuestionDataSheet", "Id Kind GradeId Score Enabled en ko")
    require(any(r["Enabled"] == "1" for r in questions), "No enabled question")
    for row in questions:
        require(row["GradeId"] in {g["Id"] for g in grades}, f"Unknown grade {row}")
        require(row["Kind"] in ("Word", "Sentence") and count(row, "Score") > 0, f"Invalid question {row}")
        require(row["Enabled"] in ("0", "1"), f"Invalid question flag {row}")
        if row["Enabled"] == "1":
            require(re.fullmatch(r"[a-zA-Z]+(?: [a-zA-Z]+)*", row["en"]), f"QWERTY cannot type {row}")
    for row in read_rows(folder, "ShopDataSheet", "Id Category Currency Price Enabled PlatformProductId"):
        require(row["Category"] in ("Body", "Rim", "Effect"), f"Unknown slot {row}")
        require(row["Currency"] in ("Gold", "Robux") and row["Enabled"] in ("0", "1"), f"Invalid shop row {row}")
        count(row, "Price")
        if row["Enabled"] == "1" and row["Currency"] == "Robux":
            require(count(row, "PlatformProductId") > 0, f"Missing product {row}")
    rewards = read_rows(folder, "RewardDataSheet", "Id Gold Exp")
    require({"Word", "Sentence", "Complete"} <= {r["Id"] for r in rewards}, "Missing reward")
    for row in rewards:
        count(row, "Gold")
        count(row, "Exp")
    levels = sorted((count(r, "Id"), count(r, "TotalExp")) for r in read_rows(folder, "LevelDataSheet", "Id TotalExp"))
    require(levels[0] == (1, 0), "Level 1 must start at zero")
    for (a, x), (b, y) in zip(levels, levels[1:]):
        require(b == a + 1 and y > x, "Invalid experience thresholds")


def check_lobby_copy():
    with (ROOT / "src/localization/CoreStrings.csv").open(encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    by_key = {row["Key"]: row for row in rows}
    for key in (
        "Lobby.Pending",
        "Lobby.PhasePlay",
        "Lobby.PhaseResult",
        "Lobby.PhaseRest",
        "Lobby.Waiting",
        "Lobby.NotWaiting",
        "Lobby.Queue",
        "Lobby.TimeLeft",
    ):
        require(key in by_key and by_key[key]["ko"].strip() and by_key[key]["Source"].strip(), f"Missing string {key}")
    queue = by_key["Lobby.Queue"]["Source"]
    require("{count}" in queue and "{capacity}" in queue and "/12" not in queue, "Queue denominator must come from capacity")
    require("{time}" in by_key["Lobby.TimeLeft"]["Source"], "Time string")
    constants = (SHARED / "IngameConstants.luau").read_text(encoding="utf-8")
    require("PadCenterRadius" in constants and "math.sin" in constants, "Pad radius must be calculated")
    bootstrap = (ROOT / "src/StarterPlayerScripts/Bootstrap.client.luau").read_text(encoding="utf-8")
    require("LobbyHud" in bootstrap and "SafeRoot" in bootstrap, "HUD must mount on SafeRoot")
    server = (ROOT / "src/ServerScriptService/Core/Bootstrap.server.luau").read_text(encoding="utf-8")
    require("ArenaService" in server and "MatchService" in server, "Server bootstrap")


def select_participants(candidates, max_participants, min_participants):
    waiting = [dict(item) for item in candidates if item["inZone"]]
    waiting.sort(key=lambda item: (item["waitStartedAt"], item["userId"]))
    selected = [item["userId"] for item in waiting[:max_participants]]
    if len(selected) < min_participants:
        return []
    return selected


def assign_pads(user_ids, pad_count):
    pads = list(range(1, pad_count + 1))
    for index in range(pad_count, 1, -1):
        swap = 1
        pads[index - 1], pads[swap - 1] = pads[swap - 1], pads[index - 1]
    return {user_ids[order]: pads[order] for order in range(len(user_ids))}


def check_m1_rules():
    # Same pilot cases as MatchRules.selfCheck. 13 candidates are mock data, not live players.
    max_participants = 12
    min_participants = 1
    radius = (12 + 4) / (2 * math.sin(math.pi / max_participants))
    require(abs(radius - 30.91) < 0.01, "pad radius")
    points = [
        (math.cos(index / max_participants * math.tau) * radius, math.sin(index / max_participants * math.tau) * radius)
        for index in range(max_participants)
    ]
    gaps = []
    for index, point in enumerate(points):
        other = points[(index + 1) % len(points)]
        gaps.append(math.hypot(point[0] - other[0], point[1] - other[1]) - 12)
    require(abs(min(gaps) - 4) < 0.001, "adjacent pad gap")
    require(radius + 6 <= 50, "pads fit the arena")

    solo = select_participants([{"userId": 7, "inZone": True, "waitStartedAt": 3}], max_participants, min_participants)
    require(solo == [7], "solo join")
    one = select_participants(
        [
            {"userId": 2, "inZone": False, "waitStartedAt": 1},
            {"userId": 9, "inZone": True, "waitStartedAt": 4},
        ],
        max_participants,
        min_participants,
    )
    require(one == [9], "only the player inside the circle moves")
    one_map = assign_pads(one, max_participants)
    require(set(one_map) == {9}, "one pad assignment")

    twelve = select_participants(
        [{"userId": 100 + index, "inZone": True, "waitStartedAt": index} for index in range(1, 13)],
        max_participants,
        min_participants,
    )
    require(len(twelve) == 12 and len(set(assign_pads(twelve, max_participants).values())) == 12, "12 unique pads")

    first_twelve = select_participants(
        [{"userId": index, "inZone": True, "waitStartedAt": index} for index in range(1, 14)],
        max_participants,
        min_participants,
    )
    require(len(first_twelve) == 12 and 13 not in first_twelve and 1 in first_twelve, "13th waiter is excluded")
    tied = [{"userId": 100 + index, "inZone": True, "waitStartedAt": 0} for index in range(1, 12)]
    tied.append({"userId": 40, "inZone": True, "waitStartedAt": 10})
    tied.append({"userId": 4, "inZone": True, "waitStartedAt": 10})
    tie_pick = select_participants(tied, max_participants, min_participants)
    require(len(tie_pick) == 12 and 4 in tie_pick and 40 not in tie_pick, "tie keeps the smaller UserId")
    same_time = select_participants(
        [{"userId": 14 - index, "inZone": True, "waitStartedAt": 5} for index in range(1, 14)],
        max_participants,
        min_participants,
    )
    require(len(same_time) == 12 and 13 not in same_time and 1 in same_time, "same time drops the highest UserId")
    require(
        select_participants([{"userId": 1, "inZone": False, "waitStartedAt": 0}], max_participants, min_participants) == [],
        "empty cycle",
    )


def enabled_deck(rows):
    return [{"id": row["Id"], "text": row["en"]} for row in rows if row["Enabled"] == "1" and row["Id"] and row["en"]]


def client_match_id(phase, in_match, match_id):
    if phase != "Play" or not in_match or not isinstance(match_id, int) or match_id <= 0:
        return 0
    return match_id


def matches(typed, answer):
    return typed.lower() == answer.lower()


def prompt_at(deck, index):
    return deck[(index - 1) % len(deck)]


def begin_round(deck, match_id, ends_at, user_ids):
    return {
        "matchId": match_id,
        "endsAt": ends_at,
        "open": True,
        "deck": deck,
        "solvers": {user_id: {"issue": 1, "index": 1} for user_id in user_ids},
    }


def live(round_, now):
    return round_ is not None and round_["open"] and now < round_["endsAt"] and round_["deck"]


def current_question(round_, user_id, now):
    if not live(round_, now):
        return {"ok": False, "reason": "closed", "matchId": 0 if round_ is None else round_["matchId"]}
    solver = round_["solvers"].get(user_id)
    if solver is None:
        return {"ok": False, "reason": "not-participant", "matchId": round_["matchId"]}
    prompt = prompt_at(round_["deck"], solver["index"])
    return {"ok": True, "matchId": round_["matchId"], "issue": solver["issue"], "questionId": prompt["id"], "text": prompt["text"]}


def submit_answer(round_, user_id, match_id, issue, text, now):
    if round_ is None:
        return {"ok": False, "reason": "closed", "matchId": 0}
    if match_id != round_["matchId"]:
        return {"ok": False, "reason": "stale", "matchId": round_["matchId"]}
    if not live(round_, now):
        return {"ok": False, "reason": "closed", "matchId": round_["matchId"]}
    solver = round_["solvers"].get(user_id)
    if solver is None:
        return {"ok": False, "reason": "not-participant", "matchId": round_["matchId"]}
    if solver.get("lastIssue") == issue:
        return {
            "ok": True,
            "matchId": round_["matchId"],
            "issue": solver["lastIssue"],
            "nextIssue": solver["lastNextIssue"],
            "nextText": solver["lastNextText"],
        }
    if issue != solver["issue"]:
        return {"ok": False, "reason": "bad-issue", "matchId": round_["matchId"], "issue": solver["issue"]}
    prompt = prompt_at(round_["deck"], solver["index"])
    if not matches(text, prompt["text"]):
        return {"ok": False, "reason": "mismatch", "matchId": round_["matchId"], "issue": solver["issue"], "text": prompt["text"]}
    solver["lastIssue"] = solver["issue"]
    solver["issue"] += 1
    solver["index"] += 1
    nxt = prompt_at(round_["deck"], solver["index"])
    solver["lastNextIssue"] = solver["issue"]
    solver["lastNextText"] = nxt["text"]
    return {"ok": True, "matchId": round_["matchId"], "issue": solver["lastIssue"], "nextIssue": solver["lastNextIssue"], "nextText": nxt["text"]}


def apply_client(session, buffer, message, active_match_id):
    if message.get("matchId") != active_match_id or active_match_id <= 0:
        return session, buffer
    if (
        session is not None
        and message.get("ok") is True
        and message.get("issue") == session["issue"]
        and message.get("nextIssue") not in (None, session["issue"])
    ):
        return {"matchId": active_match_id, "issue": message["nextIssue"], "text": message.get("nextText") or ""}, ""
    if message.get("ok") is True and message.get("nextIssue") is None and message.get("questionId") is not None and message.get("text") is not None:
        if session is None or session["issue"] == message.get("issue"):
            return {"matchId": active_match_id, "issue": message["issue"], "text": message["text"]}, buffer
    return session, buffer


def typing_plan(width, height, show_keys):
    compact = height <= 430 or width <= 760
    margin = 6 if compact else 16
    gap = 4
    time_height = 22 if compact else 32
    input_height = 28 if compact else 40
    key_rows = 4
    row_height = 0
    key_block = 0
    if show_keys:
        chrome = margin * 2 + gap + time_height + input_height + gap * 2 + 36
        available = height - chrome
        max_row = (available - gap * (key_rows - 1)) // key_rows
        row_height = 26 if max_row < 26 else min(max_row, 36 if compact else 48)
        key_block = row_height * key_rows + gap * (key_rows - 1)
    block_height = height - margin * 2 - (key_block + gap if show_keys else 0)
    question_height = block_height - time_height - input_height - gap * 2
    if question_height < 18:
        time_height = 18
        input_height = 22
        question_height = block_height - time_height - input_height - gap * 2
    question_height = max(0, question_height)
    return {
        "rowHeight": row_height,
        "keyBlock": key_block,
        "questionHeight": question_height,
        "inputHeight": input_height,
        "timeHeight": time_height,
        "blockHeight": block_height,
        "margin": margin,
        "gap": gap,
        "showKeys": show_keys,
    }


def check_m2_rules():
    rows = read_rows(SHARED / "Table", "QuestionDataSheet", "Id Kind GradeId Score Enabled en ko")
    deck = enabled_deck(rows)
    require([item["text"] for item in deck] == ["apple", "star", "we play together"], "sample English deck")
    require(client_match_id("Play", True, 4) == 4, "participant play")
    require(client_match_id("Result", True, 4) == 0, "result closes typing")
    require(client_match_id("Play", False, 4) == 0, "non-participant keeps the lobby")

    first = deck[0]["text"]
    sentence = next(item["text"] for item in deck if " " in item["text"])
    require(matches(sentence.upper(), sentence) and not matches(sentence.replace(" ", ""), sentence), "spaces and case")
    require(not matches(first[:-1], first) and not matches(first + " ", first), "partial answer stays incomplete")

    both = begin_round(deck, 4, 100, [10, 20])
    mine = current_question(both, 10, 50)
    theirs = current_question(both, 20, 50)
    require(mine["text"] == first and theirs["text"] == first and mine["issue"] == 1, "shared first prompt")
    again = current_question(both, 10, 50)
    require(again["issue"] == 1 and again["text"] == first, "re-request returns the same prompt")
    wrong = submit_answer(both, 10, 4, 1, "nope", 50)
    require(wrong["reason"] == "mismatch" and current_question(both, 10, 50)["issue"] == 1, "incomplete Enter keeps the prompt")
    done = submit_answer(both, 10, 4, 1, first.upper(), 99.999)
    duplicate = submit_answer(both, 10, 4, 1, first.upper(), 99.999)
    require(done["nextIssue"] == 2 and duplicate["nextIssue"] == 2 and duplicate["nextText"] == done["nextText"], "duplicate completion")
    require(current_question(both, 10, 50)["text"] == deck[1]["text"], "one completion advances once")
    require(current_question(both, 20, 50)["text"] == first and current_question(both, 20, 50)["issue"] == 1, "the other player stays")

    cycling = begin_round(deck, 8, 500, [3])
    expected = first
    for step in range(1, len(deck) + 2):
        current = current_question(cycling, 3, 10)
        require(current["issue"] == step and current["text"] == expected, "deck order")
        completed = submit_answer(cycling, 3, 8, step, current["text"], 10)
        require(completed["nextIssue"] == step + 1, "next issue")
        expected = completed["nextText"]
    wrapped = current_question(cycling, 3, 10)
    require(wrapped["issue"] == len(deck) + 2 and wrapped["text"] == deck[1]["text"], "play continues after the last prompt")

    timed = begin_round(deck, 9, 30, [1])
    before = submit_answer(timed, 1, 9, 1, first, 29.999)
    require(before["ok"] and before["nextIssue"] == 2, "input just before the deadline")
    timed["open"] = False
    require(submit_answer(timed, 1, 9, 2, before["nextText"], 10)["reason"] == "closed", "closed match rejects")
    deadline = begin_round(deck, 9, 30, [1])
    require(submit_answer(deadline, 1, 9, 1, first, 30)["reason"] == "closed", "arrival at the deadline is closed")
    require(current_question(deadline, 1, 29.999)["issue"] == 1, "a late packet does not advance")
    fresh = begin_round(deck, 2, 100, [5])
    require(submit_answer(fresh, 5, 1, 1, first, 10)["reason"] == "stale", "previous match")
    require(current_question(fresh, 5, 10)["issue"] == 1, "stale packet keeps the prompt")

    session, buffer = apply_client(None, "", mine, 4)
    session, buffer = apply_client(session, first[:1], mine, 4)
    require(buffer == first[:1], "state refresh keeps the draft")
    moved, cleared = apply_client(session, first, done, 4)
    require(moved["issue"] == 2 and cleared == "", "accepted submit clears once")
    stayed, typed = apply_client(moved, "s", done, 4)
    require(stayed["issue"] == 2 and typed == "s", "late duplicate keeps the new draft")
    ignored, kept = apply_client(moved, "s", done, 0)
    require(ignored["issue"] == 2 and kept == "s", "result and the next match ignore the old packet")

    phone = typing_plan(568, 320, True)
    require(phone["rowHeight"] == 36 and phone["keyBlock"] == 156, "four phone key rows")
    require(phone["questionHeight"] == 90 and phone["inputHeight"] == 28 and phone["timeHeight"] == 22, "phone prompt and input")
    used = phone["margin"] * 2 + phone["blockHeight"] + phone["gap"] + phone["keyBlock"]
    require(used == 320, "568×320 shows the prompt, input, and Enter together")
    desktop = typing_plan(1366, 768, False)
    require(desktop["questionHeight"] == 656 and desktop["questionHeight"] > phone["questionHeight"], "desktop prompt grows")

    runtime = [
        SHARED / "QuestionRules.luau",
        SHARED / "TypingLayout.luau",
        ROOT / "src/ServerScriptService/Core/QuestionService.luau",
        ROOT / "src/ServerScriptService/Core/MatchService.luau",
        ROOT / "src/StarterPlayerScripts/TypingScreen.luau",
    ]
    for path in runtime:
        text = path.read_text(encoding="utf-8")
        require(re.search(r"\bapple\b", text, re.I) is None, f"{path.name} hardcodes a sample prompt")
        require(re.search(r"\bstar\b", text) is None, f"{path.name} hardcodes a sample prompt")
        require("we play together" not in text, f"{path.name} hardcodes a sample prompt")

    service = (ROOT / "src/ServerScriptService/Core/QuestionService.luau").read_text(encoding="utf-8")
    require('rows("QuestionDataSheet")' in service and "QuestionRules" in service, "questions come from the sheet")
    match = (ROOT / "src/ServerScriptService/Core/MatchService.luau").read_text(encoding="utf-8")
    require("QuestionService.openMatch" in match and "QuestionService.closeMatch" in match and "QuestionService.forget" in match, "match hooks")
    typing = (ROOT / "src/StarterPlayerScripts/TypingScreen.luau").read_text(encoding="utf-8")
    require(
        "CaptureFocus" in typing and "if UserInputService.TouchEnabled then" in typing,
        "touch mode must not open the OS keyboard",
    )
    require("ContextActionService" in typing and "Enum.KeyCode.Space" in typing and "Enum.KeyCode.Backspace" in typing, "physical keys")
    require("qwertyuiop" in typing.replace('", "', "") or all(part in typing for part in ("q", "w", "e", "r", "t", "y")), "QWERTY")
    require(all(key in typing for key in ("Match.Space", "Match.Backspace", "Match.Enter", "Match.TypeHere")), "key copy")
    require("TypingLayout.plan" in typing and "CompactHeight" in typing, "shared layout")
    bootstrap = (ROOT / "src/StarterPlayerScripts/Bootstrap.client.luau").read_text(encoding="utf-8")
    require("TypingScreen" in bootstrap and "SafeRoot" in bootstrap, "typing screen mounts on SafeRoot")
    lobby = (ROOT / "src/StarterPlayerScripts/LobbyHud.luau").read_text(encoding="utf-8")
    require('phaseName == "Play"' in lobby and "InMatch" in lobby and "Visible" in lobby, "participants hide the lobby HUD")
    with (ROOT / "src/localization/CoreStrings.csv").open(encoding="utf-8", newline="") as stream:
        copy = {row["Key"]: row for row in csv.DictReader(stream)}
    for key in ("Match.TypeHere", "Match.Space", "Match.Backspace", "Match.Enter", "Match.NoQuestion"):
        require(key in copy and copy[key]["Source"].strip() and copy[key]["ko"].strip(), f"Missing string {key}")


def verify():
    with tempfile.TemporaryDirectory() as tmp:
        stage = Path(tmp)
        tables = stage / "tables"
        sync(ROOT / "tables", tables)
        check_data(tables)
        actual = SHARED / "Table"
        require({p.name for p in tables.glob("*.txt")} == {p.name for p in actual.glob("*.txt")}, "Table file set differs")
        for p in tables.glob("*.txt"):
            require(p.read_bytes() == (actual / p.name).read_bytes(), f"Regenerate {p.name}")
        build(ROOT / "tables/ItemDataSheet.xlsx", ROOT / "assets/item-icons/source", stage)
        generated = stage / "src/ReplicatedStorage/Shared/ItemIconSlots.luau"
        require(generated.read_text() == (SHARED / generated.name).read_text(), "Regenerate icon slots")
        atlas = Path("assets/item-icons/atlas")
        pages = sorted(p.name for p in (stage / atlas).glob("*.png"))
        require(pages == sorted(p.name for p in (ROOT / atlas).glob("*.png")), "Atlas page set differs")
        for name in pages:
            with Image.open(stage / atlas / name) as src, Image.open(ROOT / atlas / name) as dest:
                require(src.size == dest.size and src.mode == dest.mode and src.tobytes() == dest.tobytes(), f"Regenerate {name}")
        output = stage / "Lobby.rbxlx"
        subprocess.run(["rojo", "build", str(ROOT / "default.project.json"), "-o", str(output)], check=True)
        tree = ElementTree.parse(output)
        check_lobby_copy()
        check_m1_rules()
        check_m2_rules()
        for kind, name in [
            ("LocalizationTable", "CoreStrings"),
            ("LocalScript", "Bootstrap"),
            ("ModuleScript", "PlayerStore"),
            ("ModuleScript", "IngameConstants"),
            ("ModuleScript", "MatchRules"),
            ("ModuleScript", "QuestionRules"),
            ("ModuleScript", "TypingLayout"),
            ("ModuleScript", "ArenaService"),
            ("ModuleScript", "MatchService"),
            ("ModuleScript", "QuestionService"),
            ("ModuleScript", "LobbyHud"),
            ("ModuleScript", "TypingScreen"),
            ("Script", "Bootstrap"),
        ]:
            require(any(i.findtext("Properties/string[@name='Name']") == name for i in tree.iterfind(f".//Item[@class='{kind}']")), f"Missing {name} in place")
        strings = {i.findtext("Properties/string[@name='Name']") for i in tree.iterfind(".//Item[@class='StringValue']")}
        require(all(p.stem in strings for p in tables.glob("*.txt")), "Missing StringValue")
    print("PASS: workbook contracts, generated data, icon atlas, match rules, question rules and single-place build")


if __name__ == "__main__":
    verify()

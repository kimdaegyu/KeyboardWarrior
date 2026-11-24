"""Read-only checks of authored data, generated tables, atlas and the Rojo build."""
import csv
import math
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image

from build_item_icons import build
from build_ui_atlas import build as build_ui_atlas
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


def tutorial_problem(rows):
    seen = set()
    for row in rows:
        code = row.get("Id", "")
        if code in seen:
            return "duplicate"
        seen.add(code)
        if re.fullmatch(r"[a-z][a-z0-9]+", code or "") is None or not 2 <= len(code) <= 16:
            return "id"
        if not str(row.get("TitleKey", "")).strip() or not str(row.get("BodyKey", "")).strip():
            return "key"
        try:
            order = int(row["SortOrder"])
        except (KeyError, TypeError, ValueError):
            return "order"
        if order < 0:
            return "order"
        if row.get("Enabled") not in ("0", "1"):
            return "flag"
    return None


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
            require(re.fullmatch(r"[a-z]+(?: [a-z]+)*", row["en"]), f"QWERTY cannot type {row['Id']}")
    shop_rows = read_rows(folder, "ShopDataSheet", "Id Category Currency Price Enabled PlatformProductId Release Style")
    styles = {"Body": {"purple", "cyan"}, "Rim": {"none", "gold"}, "Effect": {"none", "spark"}}
    for row in shop_rows:
        require(row["Category"] in styles and row["Style"] in styles[row["Category"]], f"Unknown shop style {row}")
        require(row["Currency"] in ("Gold", "Robux") and row["Enabled"] in ("0", "1"), f"Invalid shop row {row}")
        require(row["Release"] in ("Default", "Studio", "Live"), f"Unknown shop release {row}")
        price = count(row, "Price")
        if row["Release"] == "Default":
            require(price == 0 and row["Enabled"] == "1", f"A default cosmetic is free {row}")
        if row["Release"] == "Studio" and row["Enabled"] == "1" and row["Currency"] == "Gold":
            require(price > 0, f"A studio sample needs a gold price {row}")
        if row["Enabled"] == "1" and row["Currency"] == "Robux":
            require(count(row, "PlatformProductId") > 0, f"Missing product {row}")
    by_shop = {row["Id"]: row for row in shop_rows}
    require(
        by_shop["starter_body"]["Release"] == "Default"
        and by_shop["starter_rim"]["Release"] == "Default"
        and by_shop["starter_effect"]["Release"] == "Default",
        "starter cosmetics stay free defaults",
    )
    require(
        by_shop["pilot_body"]["Price"] == "20"
        and by_shop["pilot_rim"]["Price"] == "30"
        and by_shop["pilot_effect"]["Price"] == "40"
        and by_shop["pilot_body"]["Release"] == "Studio"
        and by_shop["pilot_rim"]["Release"] == "Studio"
        and by_shop["pilot_effect"]["Release"] == "Studio",
        "pilot samples sell only in Studio at the short-play prices",
    )
    require(not any(row["Release"] == "Live" and row["Enabled"] == "1" for row in shop_rows), "live sales stay closed")
    rewards = read_rows(folder, "RewardDataSheet", "Id Gold Exp")
    require({"Word", "Sentence", "Complete"} <= {r["Id"] for r in rewards}, "Missing reward")
    for row in rewards:
        count(row, "Gold")
        count(row, "Exp")
    levels = sorted((count(r, "Id"), count(r, "TotalExp")) for r in read_rows(folder, "LevelDataSheet", "Id TotalExp"))
    require(levels[0] == (1, 0), "Level 1 must start at zero")
    for (a, x), (b, y) in zip(levels, levels[1:]):
        require(b == a + 1 and y > x, "Invalid experience thresholds")
    languages = read_rows(
        folder,
        "LanguageDataSheet",
        "Id NativeName SortOrder UiEnabled PcTypingEnabled MobileTypingEnabled GlossEnabled",
    )
    require(language_problem(languages) is None, "Invalid language sheet")
    by_language = {row["Id"]: row for row in languages}
    english = by_language["en"]
    korean = by_language["ko"]
    require(
        english["NativeName"] == "English"
        and english["UiEnabled"] == "1"
        and english["PcTypingEnabled"] == "1"
        and english["MobileTypingEnabled"] == "1"
        and english["GlossEnabled"] == "1",
        "English stays available for UI, typing, and gloss",
    )
    require(
        korean["NativeName"] == "한국어"
        and korean["UiEnabled"] == "1"
        and korean["PcTypingEnabled"] == "1"
        and korean["MobileTypingEnabled"] == "0"
        and korean["GlossEnabled"] == "1",
        "Korean is available for UI, gloss, and PC typing, not for mobile typing",
    )
    require({row["Id"] for row in languages if row["UiEnabled"] == "1"} == {"en", "ko"}, "shipping UI languages")
    require({row["Id"] for row in languages if row["GlossEnabled"] == "1"} == {"en", "ko"}, "shipping gloss languages")
    require({row["Id"] for row in languages if row["PcTypingEnabled"] == "1"} == {"en", "ko"}, "shipping PC typing languages")
    require({row["Id"] for row in languages if row["MobileTypingEnabled"] == "1"} == {"en"}, "shipping mobile typing languages")
    pc_columns = {row["Id"] for row in languages if row["PcTypingEnabled"] == "1"}
    for question in questions:
        if question["Enabled"] != "1":
            continue
        for column in sorted(pc_columns):
            text = str(question.get(column) or "")
            require(text.strip(), f"question {question['Id']} is missing {column}")
            require(text == text.strip() and "  " not in text, f"question {question['Id']} has broken spaces in {column}")
    by_question = {row["Id"]: row for row in questions}
    original = {
        "1": ("Word", "Basic", "10", "apple", "사과"),
        "2": ("Word", "Basic", "10", "star", "별"),
        "3": ("Sentence", "Bright", "25", "we play together", "우리는 함께 놀아요"),
    }
    for question_id, expected in original.items():
        row = by_question[question_id]
        require(
            (row["Kind"], row["GradeId"], row["Score"], row["en"], row["ko"]) == expected,
            f"original prompt {question_id} changed",
        )
    require(by_question["book"]["en"] == "book" and by_question["book"]["ko"] == "책" and by_question["book"]["Kind"] == "Word", "book keeps both languages on one row")
    require(by_question["moon"]["ko"] == "달" and by_question["moon"]["Kind"] == "Word", "moon stays a separate answer from chicken")
    require(by_question["chicken"]["ko"] == "닭" and by_question["chicken"]["en"] == "chicken" and by_question["chicken"]["Kind"] == "Word", "chicken keeps the double batchim")
    tutorials = read_rows(folder, "TutorialDataSheet", "Id SortOrder TitleKey BodyKey Enabled")
    require(tutorial_problem(tutorials) is None, "Invalid tutorial sheet")
    by_tutorial = {row["Id"]: row for row in tutorials}
    require(
        by_tutorial["join"]["Enabled"] == "1"
        and by_tutorial["typing"]["Enabled"] == "1"
        and by_tutorial["practice"]["Enabled"] == "1"
        and by_tutorial["shop"]["Enabled"] == "1",
        "the shop tutorial page is active",
    )
    active = [row["Id"] for row in sorted(tutorials, key=lambda row: int(row["SortOrder"])) if row["Enabled"] == "1"]
    require(active == ["join", "typing", "practice", "shop"], "enabled tutorial pages")
    for row in tutorials:
        require(row["TitleKey"].startswith("Tutorial.") and row["BodyKey"].startswith("Tutorial."), f"tutorial copy key {row['Id']}")


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


def field_answer(text, cursor, content):
    rendered = text
    if isinstance(content, str) and content != text and len(content.encode("utf-8")) > len(text.encode("utf-8")) and content.encode("utf-8").startswith(text.encode("utf-8")):
        rendered = content
    raw = rendered.encode("utf-8")
    if not isinstance(cursor, int) or cursor < 1 or cursor > len(raw) + 1:
        return rendered
    return (raw[: cursor - 1] + raw[cursor - 1 :]).decode("utf-8")


def revives(text, accepted):
    if not accepted or not text:
        return False
    if text == accepted:
        return True
    raw_text = text.encode("utf-8")
    raw_accepted = accepted.encode("utf-8")
    if len(raw_text) > len(raw_accepted) and raw_text.startswith(raw_accepted):
        return raw_text[len(raw_accepted) :].decode("utf-8").strip(" ") == "" and raw_text != raw_accepted
    if len(raw_text) < len(raw_accepted) and raw_accepted.endswith(raw_text):
        return True
    return False


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
        kept = buffer if buffer and buffer != session.get("text") else ""
        return {"matchId": active_match_id, "issue": message["nextIssue"], "text": message.get("nextText") or ""}, kept
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
    question_cap = 112
    if show_keys:
        question_cap = 64 if compact else 96
    elif compact:
        question_cap = 72
    if show_keys:
        chrome = margin * 2 + time_height + input_height + gap * 2 + question_cap
        available = height - chrome
        max_row = (available - gap * (key_rows - 1)) // key_rows
        row_height = 26 if max_row < 26 else min(max_row, 36 if compact else 48)
        key_block = row_height * key_rows + gap * (key_rows - 1)
    room = height - margin * 2 - time_height - input_height - gap * 2 - key_block
    question_height = min(question_cap, max(0, room))
    if question_height < 18:
        time_height = 18
        input_height = 22
        room = height - margin * 2 - time_height - input_height - gap * 2 - key_block
        question_height = min(question_cap, max(0, room))
    block_height = time_height + question_height + input_height + gap * 2
    inner = max(0, width - margin * 2)
    rank_width = 0
    question_width = inner
    rank_mode = "drawer"
    if not compact and inner > 0:
        rank_mode = "side"
        rank_width = min(340, max(220, int(inner * 0.28)))
        question_width = max(0, inner - rank_width - gap)
    view_lane = 0
    if compact and show_keys and question_width > 360:
        view_lane = question_width - 360
        question_width = 360
    view_gap = max(0, height - (margin * 2 + block_height + key_block))
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
        "compact": compact,
        "rankMode": rank_mode,
        "rankWidth": rank_width,
        "questionWidth": question_width,
        "viewGap": view_gap,
        "viewLane": view_lane,
    }


def accept_enter(locked, buffer):
    return (not locked) and buffer != ""


def check_m2_rules():
    rows = read_rows(SHARED / "Table", "QuestionDataSheet", "Id Kind GradeId Score Enabled en ko")
    deck = enabled_deck(rows)
    require([item["text"] for item in deck[:3]] == ["apple", "star", "we play together"], "the original prompts stay first")
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
    early, kept_next = apply_client(session, "b", done, 4)
    require(early["issue"] == 2 and kept_next == "b", "a character typed before the result stays")
    stayed, typed = apply_client(moved, "s", done, 4)
    require(stayed["issue"] == 2 and typed == "s", "late duplicate keeps the new draft")
    ignored, kept = apply_client(moved, "s", done, 0)
    require(ignored["issue"] == 2 and kept == "s", "result and the next match ignore the old packet")

    phone = typing_plan(568, 320, True)
    require(phone["rowHeight"] == 36 and phone["keyBlock"] == 156, "four phone key rows")
    require(phone["questionHeight"] == 64 and phone["inputHeight"] == 28 and phone["timeHeight"] == 22, "phone prompt and input")
    require(phone["rankMode"] == "drawer" and phone["rankWidth"] == 0 and phone["questionWidth"] == 360, "phone rank drawer")
    require(phone["viewLane"] == 196 and phone["viewGap"] == 30, "phone keeps an arena lane beside the prompt")
    used = phone["margin"] * 2 + phone["blockHeight"] + phone["keyBlock"]
    require(used + phone["viewGap"] == 320, "568×320 shows the prompt, keys, and an arena gap")
    desktop = typing_plan(1366, 768, False)
    require(desktop["questionHeight"] == 112 and desktop["viewGap"] == 544 and desktop["questionHeight"] > phone["questionHeight"], "desktop returns leftover height to the arena")
    require(desktop["rankMode"] == "side" and desktop["rankWidth"] == 340 and desktop["questionWidth"] == 990 and desktop["viewLane"] == 0, "desktop rank board stays beside the prompt")
    require(accept_enter(False, "look out") and not accept_enter(True, "look out") and not accept_enter(False, ""), "Enter after an auto-correct does not submit the next prompt")
    draft = ""
    for piece in ("lo", "ok", " out"):
        draft += piece
    require(draft == "look out", "a device change keeps the same draft and applies the first character once")

    runtime = [
        SHARED / "QuestionRules.luau",
        SHARED / "PracticeRules.luau",
        SHARED / "TypingLayout.luau",
        ROOT / "src/ServerScriptService/Core/QuestionService.luau",
        ROOT / "src/ServerScriptService/Core/MatchService.luau",
        ROOT / "src/StarterPlayerScripts/TypingScreen.luau",
        ROOT / "src/StarterPlayerScripts/TypingPad.luau",
        ROOT / "src/StarterPlayerScripts/PracticeScreen.luau",
        ROOT / "src/StarterPlayerScripts/MatchCamera.luau",
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
    pad = (ROOT / "src/StarterPlayerScripts/TypingPad.luau").read_text(encoding="utf-8")
    require(
        "CaptureFocus" in pad and "if UserInputService.TouchEnabled then" in pad,
        "touch mode must not open the OS keyboard",
    )
    require("ContextActionService" in pad and "Enum.KeyCode.Space" in pad and "Enum.KeyCode.Backspace" in pad, "physical keys")
    require("GetFocusedTextBox" in pad and "MenuIsOpen" in pad and "WindowFocused" in pad and "shouldYield" in pad, "chat, menu, and blur release typing ownership")
    require("TouchEnabled" in pad and "BindActionAtPriority" in pad, "a touch device still receives a physical key")
    require("InputBegan" in pad and "Enum.KeyCode.O" in pad and "Enum.KeyCode.I" in pad, "camera zoom keys still reach the draft on touch devices")
    require("InputPress.event" in pad and "InputPress.sample" in pad and "IsKeyDown" in pad and "releasesHold" in pad, "O uses the shared press and ownership rules")
    require('UnbindAction("RbxCameraKeypress")' in pad and "setInputEnabled" in pad, "typing releases the camera zoom keys")
    require("recentlyHandled" not in pad and "0.02" not in pad, "a second O is not dropped by a fixed time window")
    require("setIme" in pad and "utf8.offset" in pad and "HangulInput" in pad and "settleField" in pad, "Korean assembly uses the typed syllable and still settles once")
    focus = pad[pad.find("hardware.FocusLost"):pad.find("local ownership")]
    require("task.defer" not in focus and "composeEvent" in pad, "IME completion follows the text event, not a delay")
    require("qwertyuiop" in pad.replace('", "', "") or all(part in pad for part in ("q", "w", "e", "r", "t", "y")), "QWERTY")
    require(all(key in pad for key in ("Match.Space", "Match.Backspace", "Match.Enter")), "key copy")
    typing = (ROOT / "src/StarterPlayerScripts/TypingScreen.luau").read_text(encoding="utf-8")
    require("TypingPad" in typing and "QuestionSubmit" in typing, "match answers still submit through the shared pad")
    require("TypingLayout.plan" in typing and "CompactHeight" in typing and "Match.TypeHere" in typing, "shared layout")
    require("acceptEnter" in typing and "autoSubmits" in typing and "usesIme" in typing and "settleField" in typing and "MatchCamera.setPlaying" in typing and "screen.BackgroundTransparency = 1" in typing, "the match returns focus and shows the arena")
    require("size.Y - plan.margin - plan.keyBlock" in typing, "the touch keyboard stays at the bottom of the arena gap")
    practice = (ROOT / "src/StarterPlayerScripts/PracticeScreen.luau").read_text(encoding="utf-8")
    require("MatchCamera" not in practice, "practice does not use the match camera")
    require("sessionTyping" in practice and "setIme" in practice and "usesIme" in practice and "settleField" in practice, "practice uses the session typing language")
    camera = (ROOT / "src/StarterPlayerScripts/MatchCamera.luau").read_text(encoding="utf-8")
    require("Enum.CameraType.Scriptable" in camera and "savedType" in camera and "setPlaying" in camera, "the match camera can be restored")
    bootstrap = (ROOT / "src/StarterPlayerScripts/Bootstrap.client.luau").read_text(encoding="utf-8")
    require("TypingScreen" in bootstrap and "SafeRoot" in bootstrap, "typing screen mounts on SafeRoot")
    lobby = (ROOT / "src/StarterPlayerScripts/LobbyHud.luau").read_text(encoding="utf-8")
    require('phaseName == "Play"' in lobby and "InMatch" in lobby and "Visible" in lobby, "participants hide the lobby HUD")
    with (ROOT / "src/localization/CoreStrings.csv").open(encoding="utf-8", newline="") as stream:
        copy = {row["Key"]: row for row in csv.DictReader(stream)}
    for key in ("Match.TypeHere", "Match.Space", "Match.Backspace", "Match.Enter", "Match.NoQuestion"):
        require(key in copy and copy[key]["Source"].strip() and copy[key]["ko"].strip(), f"Missing string {key}")


def multiplier_for(remain, double_seconds=30, multiplier=2):
    if remain > 0 and remain <= double_seconds:
        return multiplier
    return 1


def begin_scored(deck, match_id, ends_at, user_ids, now=0):
    factor = multiplier_for(ends_at - now)
    return {
        "matchId": match_id,
        "endsAt": ends_at,
        "open": True,
        "sealed": False,
        "startedAt": now,
        "deck": deck,
        "finalOrder": None,
        "solvers": {
            user_id: {
                "issue": 1,
                "index": 1,
                "score": 0,
                "multiplier": factor,
                "reachedAt": now,
                "scoredIssue": 0,
            }
            for user_id in user_ids
        },
    }


def current_scored(round_, user_id, now):
    if not live(round_, now):
        return {"ok": False, "reason": "closed", "matchId": 0 if round_ is None else round_["matchId"]}
    solver = round_["solvers"].get(user_id)
    if solver is None:
        return {"ok": False, "reason": "not-participant", "matchId": round_["matchId"]}
    prompt = prompt_at(round_["deck"], solver["index"])
    return {
        "ok": True,
        "issue": solver["issue"],
        "text": prompt["text"],
        "points": prompt["score"] * solver["multiplier"],
        "multiplier": solver["multiplier"],
        "total": solver["score"],
    }


def submit_scored(round_, user_id, match_id, issue, text, now):
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
        return {"ok": True, "awarded": False, "total": solver["lastTotal"], "nextIssue": solver["lastNextIssue"], "nextPoints": solver["lastNextPoints"], "nextMultiplier": solver["lastNextMultiplier"]}
    if issue != solver["issue"]:
        return {"ok": False, "reason": "bad-issue", "matchId": round_["matchId"], "issue": solver["issue"]}
    prompt = prompt_at(round_["deck"], solver["index"])
    if not matches(text, prompt["text"]):
        return {"ok": False, "reason": "mismatch", "matchId": round_["matchId"], "issue": solver["issue"]}
    if solver["scoredIssue"] != solver["issue"]:
        solver["score"] += prompt["score"] * solver["multiplier"]
        solver["reachedAt"] = now
        solver["scoredIssue"] = solver["issue"]
    solver["lastIssue"] = solver["issue"]
    solver["lastTotal"] = solver["score"]
    solver["issue"] += 1
    solver["index"] += 1
    nxt = prompt_at(round_["deck"], solver["index"])
    solver["multiplier"] = multiplier_for(round_["endsAt"] - now)
    solver["lastNextIssue"] = solver["issue"]
    solver["lastNextPoints"] = nxt["score"] * solver["multiplier"]
    solver["lastNextMultiplier"] = solver["multiplier"]
    return {
        "ok": True,
        "awarded": True,
        "total": solver["lastTotal"],
        "nextIssue": solver["lastNextIssue"],
        "nextText": nxt["text"],
        "nextPoints": solver["lastNextPoints"],
        "nextMultiplier": solver["lastNextMultiplier"],
    }


def standings_of(round_):
    rows = [
        {"userId": user_id, "score": solver["score"], "reachedAt": solver["reachedAt"]}
        for user_id, solver in round_["solvers"].items()
    ]
    rows.sort(key=lambda row: (-row["score"], row["reachedAt"], row["userId"]))
    for index, row in enumerate(rows, start=1):
        row["rank"] = index
    return rows


def visible_ranks(rows, user_id, limit):
    shown = [row for row in rows if row["rank"] <= limit]
    mine = next((row for row in rows if row["userId"] == user_id), None)
    if mine is not None and mine["rank"] > limit:
        shown.append(mine)
    return shown


def check_m3_rules():
    rows = read_rows(SHARED / "Table", "QuestionDataSheet", "Id Kind GradeId Score Enabled en ko")
    grades = {row["Id"]: row["ColorHex"] for row in read_rows(SHARED / "Table", "GradeDataSheet", "Id ColorHex")}
    deck = [
        {"id": row["Id"], "text": row["en"], "score": int(row["Score"]), "colorHex": grades[row["GradeId"]]}
        for row in rows
        if row["Enabled"] == "1" and row["Id"] and row["en"]
    ]
    require([item["score"] for item in deck[:3]] == [10, 10, 25], "sample scores")
    require(deck[0]["colorHex"] == grades["Basic"] and deck[2]["colorHex"] == grades["Bright"], "grade color")

    play = begin_scored(deck, 15, 500, [4], 0)
    total = 0
    for step, item in enumerate(deck[:3], start=1):
        current = current_scored(play, 4, 10)
        require(current["multiplier"] == 1 and current["points"] == item["score"] and current["text"] == item["text"], "base card")
        scored = submit_scored(play, 4, 15, step, current["text"], 10)
        total += item["score"]
        require(scored["awarded"] is True and scored["total"] == total, "first completion scores once")
        replay = submit_scored(play, 4, 15, step, current["text"], 10)
        require(replay["awarded"] is False and replay["total"] == total, "duplicate submit does not score")
    require(total == 45, "the first three prompts accumulate 10, 20, 45")
    issue = 4
    while current_scored(play, 4, 10)["text"] != deck[0]["text"]:
        current = current_scored(play, 4, 10)
        scored = submit_scored(play, 4, 15, issue, current["text"], 10)
        require(scored["awarded"] is True and scored["total"] == total + current["points"], "later prompts score once")
        total += current["points"]
        issue += 1
    wrapped = current_scored(play, 4, 10)
    require(wrapped["text"] == deck[0]["text"], "the deck repeats")
    again = submit_scored(play, 4, 15, issue, wrapped["text"], 10)
    require(again["awarded"] is True and again["total"] == total + deck[0]["score"], "a new issue of the same prompt scores again")

    ends_at = 120
    issued = begin_scored(deck, 11, ends_at, [1], ends_at - 31)
    early = current_scored(issued, 1, ends_at - 31)
    require(early["multiplier"] == 1 and early["points"] == 10, "31 seconds keeps the base score")
    solved = submit_scored(issued, 1, 11, 1, deck[0]["text"], ends_at - 29)
    require(solved["total"] == 10 and solved["nextMultiplier"] == 2 and solved["nextPoints"] == 20, "the next issue locks 2x")
    reread = current_scored(issued, 1, ends_at - 5)
    require(reread["multiplier"] == 2 and reread["points"] == 20, "re-request keeps the issued multiplier")
    echo = submit_scored(issued, 1, 11, 1, deck[0]["text"], ends_at - 29)
    require(echo["awarded"] is False and echo["total"] == 10, "resent submit does not score again")

    at_thirty = current_scored(begin_scored(deck, 12, ends_at, [1], ends_at - 30), 1, ends_at - 30)
    require(at_thirty["multiplier"] == 2 and at_thirty["points"] == 20, "exactly 30 seconds is double")
    outside = current_scored(begin_scored(deck, 13, ends_at, [1], ends_at - 30.001), 1, ends_at - 30.001)
    require(outside["multiplier"] == 1 and outside["points"] == 10, "just over 30 seconds stays single")
    expired = begin_scored(deck, 14, ends_at, [1], ends_at - 31)
    require(submit_scored(expired, 1, 14, 1, deck[0]["text"], ends_at)["reason"] == "closed", "the deadline closes scoring")
    require(standings_of(expired)[0]["score"] == 0, "a closed submit adds nothing")

    ordered = begin_scored(deck, 16, 1000, [9, 2], 0)
    zeros = standings_of(ordered)
    require([row["userId"] for row in zeros] == [2, 9] and zeros[0]["score"] == 0, "zero scores share the start time")
    submit_scored(ordered, 9, 16, 1, deck[0]["text"], 10)
    submit_scored(ordered, 2, 16, 1, deck[0]["text"], 11)
    chased = standings_of(ordered)
    require(chased[0]["userId"] == 9 and chased[1]["userId"] == 2 and chased[0]["score"] == chased[1]["score"], "earlier equal score stays ahead")
    same_time = begin_scored(deck, 17, 1000, [9, 2], 0)
    submit_scored(same_time, 9, 17, 1, deck[0]["text"], 5)
    submit_scored(same_time, 2, 17, 1, deck[0]["text"], 5)
    require(standings_of(same_time)[0]["userId"] == 2, "the same reach time keeps the smaller UserId")

    sample = [{"userId": index, "rank": index, "score": 7 - index} for index in range(1, 7)]
    require(len(visible_ranks(sample, 6, 5)) == 6, "a player outside the top five is added once")
    require(len(visible_ranks(sample, 2, 5)) == 5, "a player already in the top five is not repeated")

    service = (ROOT / "src/ServerScriptService/Core/QuestionService.luau").read_text(encoding="utf-8")
    require('rows("GradeDataSheet")' in service, "grade colors come from the sheet")
    require("DoubleScoreSeconds" in service and "EndScoreMultiplier" in service, "multiplier constants")
    require("ScoreState" in service and "ScoreRequest" in service and "QuestionRules.seal" in service, "rank snapshot")
    require("sessionTyping" in service and "languageCode" in service, "the server freezes each player's typing language")
    require('language = "EN"' not in service, "rank language comes from the issued language")
    typing = (ROOT / "src/StarterPlayerScripts/TypingScreen.luau").read_text(encoding="utf-8")
    for key in ("Match.MyScore", "Match.MyRank", "Match.Points", "Match.DoubleTime", "Match.Language", "Match.RankTitle", "Match.ShowRanks", "Match.HideRanks"):
        require(key in typing, key)
    require("scoreState.OnClientEvent" in typing and "setDraft" not in typing[typing.find("function onScore"):typing.find("rankButton.Activated")], "rank updates do not rewrite the draft")
    with (ROOT / "src/localization/CoreStrings.csv").open(encoding="utf-8", newline="") as stream:
        copy = {row["Key"]: row for row in csv.DictReader(stream)}
    for key in ("Match.MyScore", "Match.MyRank", "Match.Points", "Match.DoubleTime", "Match.Language", "Match.RankTitle", "Match.ShowRanks", "Match.HideRanks"):
        require(key in copy and copy[key]["Source"].strip() and copy[key]["ko"].strip(), f"Missing string {key}")


def sheet_amount(value):
    if not re.fullmatch(r"[0-9]+", value or ""):
        return 0
    return int(value)


def reward_rates(rows):
    found = {row["Id"]: row for row in rows}
    return {key: (sheet_amount(found[key]["Gold"]), sheet_amount(found[key]["Exp"])) for key in ("Word", "Sentence", "Complete")}


def answer_reward(rates, words, sentences, finished):
    gold = words * rates["Word"][0] + sentences * rates["Sentence"][0]
    exp = words * rates["Word"][1] + sentences * rates["Sentence"][1]
    if finished and words + sentences >= 1:
        gold += rates["Complete"][0]
        exp += rates["Complete"][1]
    return gold, exp


def level_progress(exp, levels):
    level, floor_exp = levels[0]
    next_exp = None
    for step_level, total in levels:
        if total <= exp:
            level, floor_exp, next_exp = step_level, total, None
        elif next_exp is None:
            next_exp = total
    return level, floor_exp, next_exp


def apply_grant(profile, settlement_id, gold, exp, score, finished):
    grants = list(profile.get("grants") or [])
    if settlement_id in grants:
        return profile, False
    grants.append(settlement_id)
    best = profile["bestScore"]
    ranked = profile.get("ranked") is True
    if finished:
        best = max(best, score)
        ranked = True
    updated = {
        "schemaVersion": profile["schemaVersion"],
        "gold": profile["gold"] + gold,
        "exp": profile["exp"] + exp,
        "bestScore": best,
        "grants": grants,
    }
    if ranked:
        updated["ranked"] = True
    if "uiLocale" in profile:
        updated["uiLocale"] = profile["uiLocale"]
    if "gloss" in profile:
        updated["gloss"] = profile["gloss"]
    if isinstance(profile.get("typing"), str):
        updated["typing"] = profile["typing"]
    if isinstance(profile.get("tutorialSeen"), bool):
        updated["tutorialSeen"] = profile["tutorialSeen"]
    if isinstance(profile.get("owned"), list):
        updated["owned"] = list(profile["owned"])
    for slot in ("body", "rim", "effect"):
        if isinstance(profile.get(slot), str):
            updated[slot] = profile[slot]
    return updated, True


def settlement_identity(token, match_id, nonce):
    return f"{token}:{match_id}:{nonce}"


def shop_id_ok(value):
    return isinstance(value, str) and re.fullmatch(r"[a-z][a-z0-9_]{1,31}", value) is not None


def owned_ok(value):
    if value is None:
        return True
    if not isinstance(value, list) or len(value) > 64:
        return False
    return all(shop_id_ok(entry) for entry in value)


def slot_ok(value):
    return value is None or shop_id_ok(value)


def grant_list_ok(value):
    if value is None:
        return True
    if not isinstance(value, list) or len(value) > 64:
        return False
    return all(isinstance(entry, str) and entry for entry in value)


def profile_ok(value):
    if not isinstance(value, dict) or value.get("schemaVersion") != 1:
        return False

    def count_ok(key):
        number = value.get(key)
        return isinstance(number, int) and not isinstance(number, bool) and number >= 0

    def code_ok(key, special):
        choice = value.get(key)
        if choice is None or choice == special:
            return True
        return isinstance(choice, str) and re.fullmatch(r"[a-z][a-z0-9]{1,7}", choice) is not None

    return (
        count_ok("gold")
        and count_ok("exp")
        and count_ok("bestScore")
        and grant_list_ok(value.get("grants"))
        and code_ok("uiLocale", "auto")
        and code_ok("gloss", "off")
        and code_ok("typing", None)
        and (value.get("tutorialSeen") is None or isinstance(value.get("tutorialSeen"), bool))
        and (value.get("ranked") is None or isinstance(value.get("ranked"), bool))
        and owned_ok(value.get("owned"))
        and slot_ok(value.get("body"))
        and slot_ok(value.get("rim"))
        and slot_ok(value.get("effect"))
    )


def result_plan(width, height):
    compact = height <= 430 or width <= 760
    margin = 6 if compact else 16
    gap = 4
    summary = 148 if compact else 168
    list_height = height - margin * 2 - summary - gap
    if list_height < 72:
        summary = max(96, height - margin * 2 - gap - 72)
        list_height = height - margin * 2 - summary - gap
    return {
        "compact": compact,
        "summaryHeight": summary,
        "listHeight": max(0, list_height),
        "margin": margin,
        "gap": gap,
    }


def check_m4_rules():
    rewards = read_rows(SHARED / "Table", "RewardDataSheet", "Id Gold Exp")
    rates = reward_rates(rewards)
    levels = sorted((count(row, "Id"), count(row, "TotalExp")) for row in read_rows(SHARED / "Table", "LevelDataSheet", "Id TotalExp"))
    gold, exp = answer_reward(rates, 2, 1, True)
    require(gold == rates["Word"][0] * 2 + rates["Sentence"][0] + rates["Complete"][0], "completion adds to answer gold")
    require(exp == rates["Complete"][1], "normal completion experience ignores rank")
    require(answer_reward(rates, 2, 1, True) == (gold, exp), "x2 does not change the reward inputs")
    require(gold == 56 and exp == 10, "sample rewards are 56 gold and 10 exp")
    low_gold, low_exp = answer_reward(rates, 1, 0, True)
    require(low_exp == exp and low_gold == rates["Word"][0] + rates["Complete"][0], "a lower rank still receives completion exp")
    require(answer_reward(rates, 0, 0, True) == (0, 0), "zero answers pay nothing")
    require(answer_reward(rates, 1, 0, False) == (rates["Word"][0], rates["Word"][1]), "a leaver keeps approved answer gold")

    fresh = {"schemaVersion": 1, "gold": 0, "exp": 90, "bestScore": 20}
    paid, applied = apply_grant(fresh, "server-a:1:once", gold, exp, 45, True)
    require(applied and paid["gold"] == 56 and paid["exp"] == 100 and paid["bestScore"] == 45, "the profile records one settlement")
    replay, again = apply_grant(paid, "server-a:1:once", gold, exp, 45, True)
    require(not again and replay["gold"] == 56, "requery and retry do not double gold")
    doubled, doubled_applied = apply_grant(fresh, "server-a:1:score", gold, exp, 90, True)
    require(doubled_applied and doubled["gold"] == 56 and doubled["bestScore"] == 90, "a doubled score does not change gold")
    left, left_applied = apply_grant(fresh, "server-a:1:left", rates["Word"][0], rates["Word"][1], 10, False)
    require(left_applied and left["gold"] == rates["Word"][0] and left["bestScore"] == 20, "leaving keeps the previous best score")
    level, floor_exp, next_exp = level_progress(100, levels)
    require(level == 2 and floor_exp == 100 and next_exp is None, "100 exp reaches level 2")
    require(level_progress(90, levels)[0] == 1, "90 exp stays on level 1")

    sealed = [{"userId": 9, "score": 10, "rank": 1}, {"userId": 2, "score": 10, "rank": 2}]
    shown = list(sealed)
    require([row["userId"] for row in shown] == [9, 2], "the result UI keeps the sealed tie order")
    require(settlement_identity("server-a", 1, "n") != settlement_identity("server-b", 1, "n"), "servers do not share a local match number")
    require(settlement_identity("server-a", 1, "n") != "1", "a local match number is not the settlement id")
    require(profile_ok({"schemaVersion": 1, "gold": 3, "exp": 90, "bestScore": 4}), "a v1 profile without grants still opens")
    require(not profile_ok(None), "a failed open is not a default profile")
    zero_row = {"userId": 4, "score": 0, "rank": 2}
    require(zero_row["score"] == 0 and answer_reward(rates, 0, 0, True) == (0, 0), "a scoreless finisher stays on the result")

    phone = result_plan(568, 320)
    require(phone["summaryHeight"] == 148 and phone["listHeight"] == 156, "568×320 shows the summary before the scrolling list")
    require(phone["margin"] * 2 + phone["summaryHeight"] + phone["gap"] + phone["listHeight"] == 320, "the result screen fits 568×320")
    desktop = result_plan(1366, 768)
    require(desktop["listHeight"] > phone["listHeight"], "a wide result list has more room")

    rules = (SHARED / "RewardRules.luau").read_text(encoding="utf-8")
    require("ratesFromRows" in rules and "function RewardRules.reward" in rules, "rewards are read from rows")
    reward_fn = rules[rules.find("function RewardRules.reward"):rules.find("function RewardRules.progress")]
    require("56" not in reward_fn and "50" not in reward_fn, "reward amounts stay in the sheet")
    service = (ROOT / "src/ServerScriptService/Core/RewardService.luau").read_text(encoding="utf-8")
    query = service[service.find("function RewardService.query"):service.find("function RewardService.finalize")]
    require("commit" not in query and "task.spawn" in service, "a result query does not grant again")
    questions = (ROOT / "src/ServerScriptService/Core/QuestionService.luau").read_text(encoding="utf-8")
    require("settlementId" in questions and "GenerateGUID" in questions, "settlement ids are unique across servers")
    match = (ROOT / "src/ServerScriptService/Core/MatchService.luau").read_text(encoding="utf-8")
    require("RewardService.finalize" in match and "ProfileService.close" in match, "result settlement is outside the per-answer path")
    screen = (ROOT / "src/StarterPlayerScripts/ResultScreen.luau").read_text(encoding="utf-8")
    require("DataStore" not in screen and "PlayerStore" not in screen and "SetCache" not in screen, "the result UI only reads")
    require('current.saveState == "saved"' in screen and "Result.Saved" in screen and "Result.Saving" in screen, "save complete is a distinct state")
    for path in (
        SHARED / "RewardRules.luau",
        SHARED / "ResultLayout.luau",
        ROOT / "src/ServerScriptService/Core/RewardService.luau",
        ROOT / "src/StarterPlayerScripts/ResultScreen.luau",
    ):
        text = path.read_text(encoding="utf-8")
        require(re.search(r"\bapple\b", text, re.I) is None and "we play together" not in text, f"{path.name} hardcodes a sample prompt")
    design = (ROOT / "docs/GameDesign.ko.md").read_text(encoding="utf-8")
    require("중도 이탈" in design and "완료 보상" in design, "the pilot reward policy is recorded")
    with (ROOT / "src/localization/CoreStrings.csv").open(encoding="utf-8", newline="") as stream:
        copy = {row["Key"]: row for row in csv.DictReader(stream)}
    for key in (
        "Result.Place",
        "Result.Score",
        "Result.Language",
        "Result.Gold",
        "Result.Exp",
        "Result.Level",
        "Result.ExpBar",
        "Result.ExpMax",
        "Result.LevelUnknown",
        "Result.Saving",
        "Result.Saved",
        "Result.SaveFailed",
        "Result.SaveUnavailable",
        "Result.Next",
    ):
        require(key in copy and copy[key]["Source"].strip() and copy[key]["ko"].strip(), f"Missing string {key}")


def practice_plan(width, height, show_keys, compact_height=430, compact_width=760):
    compact = height <= compact_height or width <= compact_width
    margin = 6 if compact else 16
    gap = 4
    toolbar = 36 if compact else 44
    input_height = 28 if compact else 40
    key_rows = 4
    row_height = 0
    key_block = 0
    if show_keys:
        chrome = margin * 2 + toolbar + input_height + gap * 3 + 36
        available = height - chrome
        max_row = (available - gap * (key_rows - 1)) // key_rows
        row_height = 26 if max_row < 26 else min(max_row, 36 if compact else 48)
        key_block = row_height * key_rows + gap * (key_rows - 1)
    question = height - margin * 2 - toolbar - input_height - gap * 3 - (key_block if show_keys else 0)
    if question < 18:
        input_height = 22
        question = height - margin * 2 - toolbar - input_height - gap * 3 - (key_block if show_keys else 0)
    return {
        "margin": margin,
        "gap": gap,
        "toolbar": toolbar,
        "rowHeight": row_height,
        "keyBlock": key_block,
        "inputHeight": input_height,
        "questionHeight": max(0, question),
    }


def practice_prompt(session, words, sentences):
    deck = sentences if session["mode"] == "Sentence" else words
    if not deck:
        return None
    return deck[(session["index"] - 1) % len(deck)]


def practice_complete(session, words, sentences):
    if session["busy"]:
        return
    current = practice_prompt(session, words, sentences)
    if current is None or session["buffer"].lower() != current.lower():
        return
    session["busy"] = True
    session["solved"] += 1
    session["index"] += 1
    session["buffer"] = ""
    session["busy"] = False


def check_m5_rules():
    rows = read_rows(SHARED / "Table", "QuestionDataSheet", "Id Kind GradeId Score Enabled en ko")
    words = [row["en"] for row in rows if row["Enabled"] == "1" and row["Kind"] == "Word" and row["en"]]
    sentences = [row["en"] for row in rows if row["Enabled"] == "1" and row["Kind"] == "Sentence" and row["en"]]
    require(words[0] == "apple" and words[1] == "star" and sentences[0] == "we play together", "practice keeps the original prompts first")
    require(words == [row["en"] for row in rows if row["Enabled"] == "1" and row["Kind"] == "Word" and row["en"]], "word practice follows enabled words")
    require(sentences == [row["en"] for row in rows if row["Enabled"] == "1" and row["Kind"] == "Sentence" and row["en"]], "sentence practice follows enabled sentences")

    session = {"mode": "Word", "index": 1, "solved": 0, "buffer": "", "busy": False}
    session["buffer"] = words[0].upper()
    practice_complete(session, words, sentences)
    require(session["solved"] == 1 and session["buffer"] == "", "practice auto-complete clears the draft")
    practice_complete(session, words, sentences)
    require(session["solved"] == 1, "Enter after auto-complete does not solve a second prompt")
    solved = session["solved"]
    session["buffer"] = "zz"
    practice_complete(session, words, sentences)
    require(session["buffer"] == "zz" and session["solved"] == solved, "an incomplete Enter keeps the draft")
    session["mode"] = "Sentence"
    session["index"] = 1
    session["buffer"] = ""
    require(session["solved"] == solved, "switching mode keeps the solved count")
    for sentence in sentences:
        require(practice_prompt(session, words, sentences) == sentence, "sentence practice follows the sheet")
        session["buffer"] = sentence
        practice_complete(session, words, sentences)
    require(practice_prompt(session, words, sentences) == sentences[0] and session["buffer"] == "", "sentence practice cycles")
    require(session["solved"] == solved + len(sentences), "each sentence counts once")
    restarted = {"mode": "Word", "index": 1, "solved": 0, "buffer": "", "busy": False}
    require(restarted["solved"] == 0, "a new practice session starts at zero")

    def blocked(in_match, phase):
        return in_match and phase in ("Play", "Result")

    require(not blocked(True, "Rest"), "standing in the circle does not close practice")
    require(blocked(True, "Play") and blocked(True, "Result"), "a confirmed participant leaves practice")
    require(not blocked(False, "Play") and not blocked(False, "Result"), "another match does not close practice")

    phone = practice_plan(568, 320, True)
    require(phone["toolbar"] == 36 and phone["questionHeight"] == 76 and phone["inputHeight"] == 28, "phone practice prompt")
    require(phone["rowHeight"] == 36 and phone["keyBlock"] == 156, "phone practice keys")
    used = phone["margin"] * 2 + phone["toolbar"] + phone["questionHeight"] + phone["inputHeight"] + phone["keyBlock"] + phone["gap"] * 3
    require(used == 320, "568×320 shows the prompt, input, last key row, and exit")
    desktop = practice_plan(1366, 768, False)
    require(desktop["questionHeight"] == 640 and desktop["questionHeight"] > phone["questionHeight"], "desktop practice prompt grows")

    practice = (ROOT / "src/StarterPlayerScripts/PracticeScreen.luau").read_text(encoding="utf-8")
    typing = (ROOT / "src/StarterPlayerScripts/TypingScreen.luau").read_text(encoding="utf-8")
    for banned in ("QuestionSubmit", "RewardService", "ScoreState", "PlayerStore", "DataStore", "SetCache"):
        require(banned not in practice, f"practice must not call {banned}")
    require("TypingPad" in practice and "practicePlan" in practice and "blockedByMatch" in practice, "practice shares the pad")
    require("KeyboardWarriorPractice" in practice and "KeyboardWarriorTyping" in typing, "pads use separate key actions")
    require("QuestionSubmit" in typing and "TypingPad" in typing and "PracticeOpen" in typing and "inputMethod" in typing, "the match pad still submits and reports the input method")
    questions = (ROOT / "src/ServerScriptService/Core/QuestionService.luau").read_text(encoding="utf-8")
    require("PlaytestMetrics" in questions and "IsStudio" in questions and "noteClock" in questions, "Studio prints the playtest summary once when the match closes")
    metrics = (SHARED / "PlaytestMetrics.luau").read_text(encoding="utf-8")
    require("출제→정답 승인 시간" in metrics and "물리 키보드" in metrics and "화면 키보드" in metrics and "혼용" in metrics and "미확인" in metrics, "the summary names the measured interval and the input methods")
    rules = (SHARED / "PracticeRules.luau").read_text(encoding="utf-8")
    require("PlaytestMetrics" not in practice and "PlaytestMetrics" not in rules, "practice is outside the official match metrics")
    regression = (SHARED / "MatchRegression.luau").read_text(encoding="utf-8")
    check = (ROOT / "tools/m2_check.luau").read_text(encoding="utf-8")
    require("MatchRegression.selfCheck" in check and "selectParticipants" in regression and "assignPads" in regression and "RewardRules.applyGrant" in regression and "RankRules.storedValue" in regression, "the twelve-player regression reuses the match, reward, and rank rules")
    require("QuestionRules.outcome" in (ROOT / "src/ServerScriptService/Core/QuestionService.luau").read_text(encoding="utf-8"), "the result rows come from the shared outcome")
    result = (ROOT / "src/StarterPlayerScripts/ResultScreen.luau").read_text(encoding="utf-8")
    require("PracticeOpen" in result and 'phase == "Result"' in result, "result stays off the practice screen")
    lobby = (ROOT / "src/StarterPlayerScripts/LobbyHud.luau").read_text(encoding="utf-8")
    require("PracticeOpen" in lobby and "Practice.Start" in lobby and "Practice.Outside" in lobby, "lobby practice entry")
    require('phaseName == "Play"' in lobby and "InMatch" in lobby, "match HUD visibility stays")
    bootstrap = (ROOT / "src/StarterPlayerScripts/Bootstrap.client.luau").read_text(encoding="utf-8")
    require("PracticeScreen" in bootstrap and "TypingScreen" in bootstrap and "ResultScreen" in bootstrap and "SafeRoot" in bootstrap, "one root")
    design = (ROOT / "docs/GameDesign.ko.md").read_text(encoding="utf-8")
    harness = (ROOT / "docs/Harness.ko.md").read_text(encoding="utf-8")
    require("개인 연습은 참가 원 밖에서만 연다" in design, "practice pilot is recorded")
    require("QuestionSubmit" in harness and "568×320" in harness, "practice checks are recorded")
    with (ROOT / "src/localization/CoreStrings.csv").open(encoding="utf-8", newline="") as stream:
        copy = {row["Key"]: row for row in csv.DictReader(stream)}
    for key in ("Practice.Start", "Practice.Outside", "Practice.Exit", "Practice.Words", "Practice.Sentences", "Practice.Solved", "Practice.Empty"):
        require(key in copy and copy[key]["Source"].strip() and copy[key]["ko"].strip(), f"Missing string {key}")


def gloss_for(rows, question_id, column="ko"):
    if not question_id:
        return None
    for row in rows:
        if row["Id"] == question_id:
            text = row.get(column) or ""
            return text or None
    return None


def gloss_band(question_height, shown):
    if not shown or question_height < 48:
        return 0
    band = int(question_height * 0.34)
    band = min(band, 32)
    if question_height - band < 36:
        band = question_height - 36
    if band < 16:
        return 0
    return band


def language_problem(rows):
    seen = set()
    for row in rows:
        code = row.get("Id", "")
        if code in seen:
            return "duplicate"
        seen.add(code)
        if code in {"auto", "off"} or re.fullmatch(r"[a-z][a-z0-9]{1,7}", code or "") is None:
            return "id"
        if not str(row.get("NativeName", "")).strip():
            return "name"
        try:
            order = int(row["SortOrder"])
        except (KeyError, TypeError, ValueError):
            return "order"
        if order < 0:
            return "order"
        for flag in ("UiEnabled", "PcTypingEnabled", "MobileTypingEnabled", "GlossEnabled"):
            if row.get(flag) not in ("0", "1"):
                return "flag"
    return None


def settings_list_plan(width, height, count):
    compact = height <= 430 or width <= 760
    margin = 8 if compact else 20
    gap = 4
    row = 36 if compact else 44
    list_height = height - margin * 2 - row - gap
    canvas = max(0, count) * row + max(0, count - 1) * gap
    return {
        "margin": margin,
        "gap": gap,
        "row": row,
        "back": row,
        "listHeight": max(0, list_height),
        "canvas": canvas,
        "scrolls": canvas > list_height,
    }


def accepts_choice(rows, value, special, flag):
    if value == special:
        return True
    return value in {row["Id"] for row in rows if row[flag] == "1"}


def shown_choice(rows, value, special, flag):
    if accepts_choice(rows, value, special, flag):
        return value
    return special


def apply_settings(profile, ui_locale, gloss, rows, typing=None):
    if not accepts_choice(rows, ui_locale, "auto", "UiEnabled") or not accepts_choice(rows, gloss, "off", "GlossEnabled"):
        return None
    stored = profile.get("typing") if typing is None else typing
    if stored is not None:
        pc_ids = {row["Id"] for row in rows if row.get("PcTypingEnabled") == "1"}
        if stored not in pc_ids:
            return None
    return {
        "schemaVersion": profile["schemaVersion"],
        "gold": profile["gold"],
        "exp": profile["exp"],
        "bestScore": profile["bestScore"],
        "grants": list(profile.get("grants") or []),
        "uiLocale": ui_locale,
        "gloss": gloss,
        **({"typing": stored} if isinstance(stored, str) else {}),
        **({"tutorialSeen": profile["tutorialSeen"]} if isinstance(profile.get("tutorialSeen"), bool) else {}),
        **({"ranked": True} if profile.get("ranked") is True else {}),
        **({"owned": list(profile["owned"])} if isinstance(profile.get("owned"), list) else {}),
        **({"body": profile["body"]} if isinstance(profile.get("body"), str) else {}),
        **({"rim": profile["rim"]} if isinstance(profile.get("rim"), str) else {}),
        **({"effect": profile["effect"]} if isinstance(profile.get("effect"), str) else {}),
    }


def check_settings_rules():
    rows = read_rows(SHARED / "Table", "QuestionDataSheet", "Id Kind GradeId Score Enabled en ko")
    require(gloss_for(rows, "1") == "사과" and gloss_for(rows, "3") == "우리는 함께 놀아요", "meaning comes from the question id")
    require(gloss_for(rows, "apple") is None and gloss_for(rows, "") is None, "the visible prompt is not a meaning key")
    require(gloss_band(90, False) == 0 and gloss_band(90, True) == 30, "a hidden gloss gives the prompt its space back")
    require(gloss_band(76, True) == 25 and gloss_band(64, True) == 21 and 64 - gloss_band(64, True) >= 36, "the gloss stays inside the prompt")
    phone = typing_plan(568, 320, True)
    require(phone["inputHeight"] == 28 and phone["keyBlock"] == 156 and phone["questionHeight"] == 64, "meaning text does not move the input or last key row")

    require(gloss_for(rows, "2", "ko") == "별" and gloss_for(rows, "2", "en") == "star", "meaning follows the selected language column")
    languages = read_rows(
        SHARED / "Table",
        "LanguageDataSheet",
        "Id NativeName SortOrder UiEnabled PcTypingEnabled MobileTypingEnabled GlossEnabled",
    )
    require(language_problem([dict(languages[0]), dict(languages[0])]) == "duplicate", "duplicate language codes fail")
    flagged = dict(languages[0])
    flagged["UiEnabled"] = "2"
    require(language_problem([flagged]) == "flag", "a language flag must be zero or one")
    fixture = []
    for index in range(12):
        fixture.append({
            "Id": "t" + "abcdefghijkl"[index],
            "NativeName": f"Language {index + 1}",
            "SortOrder": str(index + 1),
            "UiEnabled": "1",
            "PcTypingEnabled": "0",
            "MobileTypingEnabled": "0",
            "GlossEnabled": "0",
        })
    require(language_problem(fixture) is None and all(row["Id"] not in {item["Id"] for item in languages} for row in fixture), "twelve test languages stay out of the shipping sheet")
    dozen = settings_list_plan(568, 320, 12)
    last_top = 11 * (dozen["row"] + dozen["gap"])
    require(dozen["scrolls"] and dozen["margin"] * 2 + dozen["listHeight"] + dozen["gap"] + dozen["back"] <= 320, "568×320 keeps back outside the language scroller")
    require(last_top + dozen["row"] <= dozen["canvas"] and last_top >= dozen["listHeight"], "the twelfth language is reached by scrolling")
    require(shown_choice(languages, "ja", "auto", "UiEnabled") == "auto", "a disabled UI code is shown as automatic")
    require(shown_choice(languages, "en", "off", "GlossEnabled") == "en", "English gloss is selectable")
    require(shown_choice(languages, "off", "off", "GlossEnabled") == "off", "an explicit off gloss stays off")
    require(shown_choice(languages, "ko", "off", "GlossEnabled") == "ko", "Korean gloss stays available")

    fresh = {"schemaVersion": 1, "gold": 3, "exp": 9, "bestScore": 4, "grants": ["keep"], "uiLocale": "ko", "gloss": "ko", "typing": "ko", "tutorialSeen": True}
    paid, applied = apply_grant(fresh, "server-a:1:keep-settings", 1, 0, 10, False)
    require(applied and paid["gold"] == 4 and paid["exp"] == 9 and paid["bestScore"] == 4, "a reward keeps balances beside settings")
    require(paid["uiLocale"] == "ko" and paid["gloss"] == "ko" and paid["typing"] == "ko" and paid["tutorialSeen"] is True and paid["grants"] == ["keep", "server-a:1:keep-settings"], "a reward keeps settings and older grants")
    saved = apply_settings(paid, "en", "off", languages)
    require(saved is not None and saved["gold"] == 4 and saved["exp"] == 9 and saved["bestScore"] == 4, "settings keep the reward")
    require(saved["grants"] == paid["grants"] and saved["uiLocale"] == "en" and saved["gloss"] == "off" and saved["typing"] == "ko" and saved["tutorialSeen"] is True, "settings replace only the choices")
    require(apply_settings(fresh, "ja", "ko", languages) is None and fresh["uiLocale"] == "ko" and fresh["gold"] == 3, "a disabled code is rejected and the stored choice stays")
    require(apply_settings(fresh, "ko", "ja", languages) is None and fresh["gloss"] == "ko", "a disabled gloss does not replace the stored gloss")
    english_gloss = apply_settings(fresh, "ko", "en", languages)
    require(english_gloss is not None and english_gloss["gloss"] == "en" and english_gloss["uiLocale"] == "ko" and english_gloss["typing"] == "ko" and fresh["gloss"] == "ko", "English meaning is stored with Korean typing")
    require(apply_settings(fresh, "ko", "ko", languages, "ja") is None and fresh["typing"] == "ko", "a disabled typing language is not saved")
    switched = apply_settings(fresh, "ko", "off", languages, "en")
    require(switched is not None and switched["typing"] == "en" and switched["gloss"] == "off" and fresh["typing"] == "ko", "an enabled typing language is stored without editing the previous profile")
    pc_ids = [row["Id"] for row in languages if row["PcTypingEnabled"] == "1"]
    mobile_ids = [row["Id"] for row in languages if row["MobileTypingEnabled"] == "1"]

    def session_language(saved_typing, mobile):
        preference = saved_typing if saved_typing in pc_ids else pc_ids[0]
        allowed = mobile_ids if mobile else pc_ids
        return preference if preference in allowed else allowed[0]

    require(session_language(None, False) == "en" and session_language("ko", False) == "ko", "a missing profile starts in English and a PC session keeps Korean")
    require(session_language("ko", True) == "en" and session_language("ko", False) == "ko", "mobile plays English and PC returns to the saved language")

    def missing_prompt(sheet_rows, columns):
        for row in sheet_rows:
            if row.get("Enabled") == "1" and row.get("Id"):
                for column in columns:
                    if not str(row.get(column) or "").strip():
                        return row["Id"], column
        return None

    require(missing_prompt(rows, ["en", "ko"]) is None, "enabled questions fill en and ko")
    blank = dict(rows[0])
    blank["Enabled"] = "1"
    blank["ko"] = " "
    require(missing_prompt([blank], ["ko"]) == (blank["Id"], "ko"), "an empty Korean cell names the question and column")
    require("".join(list("사과")[:1]) == "사" and "벼" != "별", "a Hangul character stays whole and an unfinished syllable is not the answer")
    apple_caret = len("사".encode("utf-8")) + 1
    require(field_answer("사과", apple_caret, "사과") == "사과" and matches(field_answer("사", apple_caret, "사과"), "사과"), "a syllable shown after the caret completes the answer")
    require(not matches(field_answer("사", apple_caret, "사"), "사과") and not matches(field_answer("벼", 1, "벼"), "별"), "an unfinished field does not match")
    require(matches(field_answer("별", 1, "별"), "별"), "the finished syllable matches with the caret in front")
    sentence = "우리는 함께 놀아요"
    last_caret = len(sentence.encode("utf-8")) - len("요".encode("utf-8")) + 1
    require(matches(field_answer(sentence, last_caret, sentence), sentence), "the sentence matches when its last syllable is displayed")
    require(not matches(sentence.replace(" ", "", 1), sentence), "a missing space stays incomplete")
    require(matches(field_answer("apple", 3, "apple"), "apple") and matches(field_answer("look out", 5, "look out"), "look out"), "English words and spaces use the whole field")
    require(not matches(field_answer("lookout", 5, "lookout"), "look out"), "a missing English space does not match")
    require(not matches(field_answer("あ", 1, "あ"), "亜") and matches(field_answer("亜", 1, "亜"), "亜"), "only a conversion shown in the field matches")
    require(revives("사과", "사과") and revives("과", "사과") and revives("사과 ", "사과") and not revives("사", "사과"), "a late commit is not a new draft")
    require(profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0}), "a profile without settings still opens")
    require(profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0, "uiLocale": "auto", "gloss": "off"}), "explicit defaults are valid")
    require(profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0, "uiLocale": "auto", "gloss": "off", "typing": "ko"}), "a saved typing code still opens")
    require(not profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0, "typing": "English"}), "a typing name is not a stored code")
    require(profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0, "uiLocale": "ja", "gloss": "off"}), "a disabled language code still opens")
    require(not profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0, "uiLocale": "English"}), "a language name is not a stored code")

    rules = (SHARED / "RewardRules.luau").read_text(encoding="utf-8")
    grant_fn = rules[rules.find("function RewardRules.applyGrant"):rules.find("function RewardRules.selfCheck")]
    require("uiLocale" in grant_fn and "gloss" in grant_fn and "typing" in grant_fn and "tutorialSeen" in grant_fn, "reward updates keep settings fields")
    settings_rules = (SHARED / "SettingsRules.luau").read_text(encoding="utf-8")
    require("gold" in settings_rules and "bestScore" in settings_rules and "grants" in settings_rules, "settings updates keep the economy")
    apply_fn = settings_rules[settings_rules.find("function SettingsRules.apply"):settings_rules.find("function SettingsRules.selfCheck")]
    require('"ko"' not in apply_fn and '"en"' not in apply_fn, "saving a choice uses the language sheet")
    localization = (SHARED / "Localization.luau").read_text(encoding="utf-8")
    require("function Localization.setPreferredLocale" in localization and "pinnedLocale" in localization, "a chosen UI language can override automatic detection")
    preferred = localization[localization.find("function Localization.setPreferredLocale"):localization.find("\nwatchTranslator")]
    require('choice == "ko"' not in preferred and 'choice == "en"' not in preferred, "an explicit UI language is not limited to Korean and English")
    state = (ROOT / "src/StarterPlayerScripts/SettingsState.luau").read_text(encoding="utf-8")
    gloss_fn = state[state.find("function SettingsState.glossText"):state.find("function SettingsState.onChanged")]
    require("applied.gloss" in gloss_fn and '"ko"' not in gloss_fn, "meaning lookup uses the selected language column")
    require("LanguageDataSheet" in state and "TypingDevice" in state and "sessionTyping" in state, "the client reports its device and resolves the session language")
    screen = (ROOT / "src/StarterPlayerScripts/SettingsScreen.luau").read_text(encoding="utf-8")
    for banned in ("DataStore", "PlayerStore", "SetCache", "QuestionSubmit"):
        require(banned not in screen, f"settings UI must not call {banned}")
    require('saveState == "saved"' not in screen and "Settings.Saved" in screen, "saved copy is selected from the server state")
    require('state == "saved"' in screen, "save complete is a distinct settings state")
    require("ScrollingFrame" in screen and "Settings.Back" in screen and "koreanButton" not in screen and "Settings.TypingMobile" in screen, "language choices use one scrolling list")
    service = (ROOT / "src/ServerScriptService/Core/SettingsService.luau").read_text(encoding="utf-8")
    require("ProfileService.applySettings" in service and "ProfileService.save" in service, "settings go through the profile session")
    require("LanguageDataSheet" in service and "TypingDevice" in service and "isMobile" in service, "the server validates choices from the language sheet and stores the device")
    profile_service = (ROOT / "src/ServerScriptService/Core/ProfileService.luau").read_text(encoding="utf-8")
    require("savePending" in profile_service and "function ProfileService.applySettings" in profile_service, "profile writes do not overlap a stale snapshot")
    require("RewardService" not in service, "settings do not grant a reward")
    lobby = (ROOT / "src/StarterPlayerScripts/LobbyHud.luau").read_text(encoding="utf-8")
    require("SettingsOpen" in lobby and "Settings.Open" in lobby and 'phaseName == "Play"' in lobby, "settings shares the lobby menu")
    typing = (ROOT / "src/StarterPlayerScripts/TypingScreen.luau").read_text(encoding="utf-8")
    practice = (ROOT / "src/StarterPlayerScripts/PracticeScreen.luau").read_text(encoding="utf-8")
    require("SettingsState.glossText" in typing and "SettingsState.glossText" in practice, "both screens read the meaning by id")
    require("SettingsOpen" in typing, "a confirmed participant sees the match before settings")
    design = (ROOT / "docs/GameDesign.ko.md").read_text(encoding="utf-8")
    harness = (ROOT / "docs/Harness.ko.md").read_text(encoding="utf-8")
    require("설정은 로비 메뉴에서 연다" in design, "the settings pilot is recorded")
    require("저장 완료는 저장이 성공한 뒤에만" in harness, "the settings checks are recorded")
    require("언어 한 개를 추가할 때" in harness, "adding a language has a recorded checklist")
    with (ROOT / "src/localization/CoreStrings.csv").open(encoding="utf-8", newline="") as stream:
        copy = {row["Key"]: row for row in csv.DictReader(stream)}
    for key in (
        "Settings.Open",
        "Settings.Title",
        "Settings.UiLanguage",
        "Settings.TypingLanguage",
        "Settings.TypingEnglish",
        "Settings.Gloss",
        "Settings.Auto",
        "Settings.Korean",
        "Settings.English",
        "Settings.GlossOff",
        "Settings.GlossKorean",
        "Settings.Apply",
        "Settings.Close",
        "Settings.Back",
        "Settings.TypingNote",
        "Settings.Saving",
        "Settings.Saved",
        "Settings.SaveFailed",
        "Settings.Unavailable",
    ):
        require(key in copy and copy[key]["Source"].strip() and copy[key]["ko"].strip(), f"Missing string {key}")


def check_tutorial():
    rows = read_rows(SHARED / "Table", "TutorialDataSheet", "Id SortOrder TitleKey BodyKey Enabled")
    require(tutorial_problem([dict(rows[0]), dict(rows[0])]) == "duplicate", "duplicate tutorial ids fail")
    flagged = dict(rows[0])
    flagged["Enabled"] = "2"
    require(tutorial_problem([flagged]) == "flag", "a tutorial flag must be zero or one")
    released = [dict(row, Enabled="1") for row in rows]
    released_ids = [row["Id"] for row in sorted(released, key=lambda row: int(row["SortOrder"]))]
    require(len(released_ids) == 4, "enabling the shop page makes four steps")
    margin, gap, title, body, step, row = 8, 4, 22, 64, 16, 36
    panel = gap * 2 + title + body + step + row + gap * 3
    require(320 - margin - panel >= 96 and panel + margin <= 320 and body >= 48, "568×320 shows the circle and the done button")
    profile = {"schemaVersion": 1, "gold": 4, "exp": 9, "bestScore": 8, "grants": ["a"], "uiLocale": "ko", "gloss": "ko"}

    def acknowledge(source):
        updated = {
            "schemaVersion": source["schemaVersion"],
            "gold": source["gold"],
            "exp": source["exp"],
            "bestScore": source["bestScore"],
            "grants": list(source.get("grants") or []),
            "tutorialSeen": True,
        }
        if "uiLocale" in source:
            updated["uiLocale"] = source["uiLocale"]
        if "gloss" in source:
            updated["gloss"] = source["gloss"]
        if isinstance(source.get("typing"), str):
            updated["typing"] = source["typing"]
        return updated

    first = acknowledge(profile)
    second = acknowledge(first)
    require(first["tutorialSeen"] is True and second["tutorialSeen"] is True and second["gold"] == 4 and second["uiLocale"] == "ko", "confirming twice keeps the profile")
    require(profile.get("tutorialSeen") is None, "confirmation does not edit the previous profile")
    require(profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0}), "a profile without a tutorial flag still opens")
    require(profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0, "tutorialSeen": True}), "a seen flag is valid")
    require(not profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0, "tutorialSeen": "yes"}), "a tutorial flag must be boolean")
    screen = (ROOT / "src/StarterPlayerScripts/TutorialScreen.luau").read_text(encoding="utf-8")
    close_fn = screen[screen.find("local function closeForMatch"):screen.find("local function acknowledge")]
    require("FireServer" not in close_fn and "TutorialState.acknowledge" not in close_fn, "a match start does not mark the tutorial seen")
    require('SetAttribute("SettingsOpen"' not in screen and "SettingsState.apply" not in screen, "replay does not apply settings")
    require("DoubleScoreSeconds" in screen and "EndScoreMultiplier" in screen, "the double-score copy reads the match constants")
    require("ScrollingFrame" in screen and "Tutorial.Done" in screen, "the body scrolls above the done button")
    for banned in ("DataStore", "PlayerStore", "SetCache", "QuestionSubmit"):
        require(banned not in screen, f"tutorial UI must not call {banned}")
    lobby = (ROOT / "src/StarterPlayerScripts/LobbyHud.luau").read_text(encoding="utf-8")
    typing = (ROOT / "src/StarterPlayerScripts/TypingScreen.luau").read_text(encoding="utf-8")
    result = (ROOT / "src/StarterPlayerScripts/ResultScreen.luau").read_text(encoding="utf-8")
    require("TutorialOpen" in lobby and "TutorialOpen" in typing and "TutorialOpen" in result, "one screen at a time")
    service = (ROOT / "src/ServerScriptService/Core/TutorialService.luau").read_text(encoding="utf-8")
    require("ProfileService.acknowledgeTutorial" in service and "ProfileService.save" in service, "tutorial confirmation uses the profile session")
    design = (ROOT / "docs/GameDesign.ko.md").read_text(encoding="utf-8")
    harness = (ROOT / "docs/Harness.ko.md").read_text(encoding="utf-8")
    require("아직 보지 않은 플레이어" in design, "the tutorial pilot is recorded")
    require("프로필 열기 실패는 미확인으로 취급하지 않는다" in harness, "the tutorial checks are recorded")
    with (ROOT / "src/localization/CoreStrings.csv").open(encoding="utf-8", newline="") as stream:
        copy = {row["Key"]: row for row in csv.DictReader(stream)}
    for key in (
        "Tutorial.JoinTitle",
        "Tutorial.JoinBody",
        "Tutorial.TypingTitle",
        "Tutorial.TypingBody",
        "Tutorial.PracticeTitle",
        "Tutorial.PracticeBody",
        "Tutorial.ShopTitle",
        "Tutorial.ShopBody",
        "Tutorial.Previous",
        "Tutorial.Next",
        "Tutorial.Done",
        "Tutorial.Skip",
        "Tutorial.Replay",
    ):
        require(key in copy and copy[key]["Source"].strip() and copy[key]["ko"].strip(), f"Missing string {key}")
    require("{seconds}" in copy["Tutorial.TypingBody"]["Source"] and "{multiplier}" in copy["Tutorial.TypingBody"]["ko"], "score timing comes from placeholders")


def rank_record(best, ranked):
    if isinstance(best, bool) or not isinstance(best, int) or best < 0:
        return None, False
    if ranked is True or best > 0:
        return best, True
    return None, False


def rank_place(entries):
    placed = []
    rank = 1
    for index, entry in enumerate(entries, start=1):
        if index > 1 and entry["score"] < entries[index - 2]["score"]:
            rank = index
        placed.append({**entry, "rank": rank})
    return placed


def check_rank():
    best = 0
    ranked = False
    for score, finished in ((100, True), (80, True), (120, True), (150, False)):
        if finished:
            best = max(best, score)
            ranked = True
    require(best == 120 and ranked, "official scores keep the greater best and practice does not")
    require(rank_record(0, None) == (None, False), "a legacy zero is not a finished record")
    require(rank_record(0, True) == (0, True), "a finished zero is a record")
    require(rank_record(80, None) == (80, True), "a legacy positive best score is a record")
    require(not profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0, "ranked": "yes"}), "a rank flag must be boolean")

    def stored(previous, score):
        if isinstance(previous, int) and not isinstance(previous, bool) and previous >= score:
            return None
        return score

    require(stored(None, 0) == 0 and stored(100, 80) is None and stored(100, 120) == 120 and stored(120, 120) is None, "the board keeps the larger score")
    rows = rank_place([
        {"userId": 1, "score": 120},
        {"userId": 2, "score": 120},
        {"userId": 3, "score": 100},
    ])
    require([row["rank"] for row in rows] == [1, 1, 3], "tied scores share a rank and the next rank skips")
    margin, gap, title, mine, header, close = 8, 4, 22, 32, 18, 36
    chrome = margin * 2 + title + mine + header + close + gap * 4
    require(chrome + (320 - chrome) <= 320 and 320 - chrome >= 28 and close == 36, "568×320 keeps the title and close button outside the scroller")
    constants = (SHARED / "IngameConstants.luau").read_text(encoding="utf-8")
    require("TopCount = 50" in constants and "CacheSeconds = 60" in constants, "rank size and cache live in the shared constants")
    service = (ROOT / "src/ServerScriptService/Core/RankService.luau").read_text(encoding="utf-8")
    require("GetOrderedDataStore" in service and "studioScope" in service and "UpdateAsync" in service, "global rank uses the ordered store and the studio scope")
    require("ProfileService.commit" not in service, "a rank write does not settle rewards again")
    require("setReadyHandler" in service and "noteSaved" in service, "an existing record is published on the next profile load")
    rewards = (ROOT / "src/ServerScriptService/Core/RewardService.luau").read_text(encoding="utf-8")
    save_fn = rewards[rewards.find("local function saveLater"):rewards.find("local function grant")]
    require("if saved then" in save_fn and "RankService.noteSaved" in save_fn and "ProfileService.commit" not in save_fn, "rank follows a successful profile save")
    screen = (ROOT / "src/StarterPlayerScripts/RankScreen.luau").read_text(encoding="utf-8")
    require("ScrollingFrame" in screen and "Rank.Close" in screen and "blockedByMatch" in screen, "the list scrolls and a match closes the popup")
    for banned in ("DataStore", "PlayerStore", "SetCache", "QuestionSubmit", "SettingsState.apply"):
        require(banned not in screen, f"rank UI must not call {banned}")
    lobby = (ROOT / "src/StarterPlayerScripts/LobbyHud.luau").read_text(encoding="utf-8")
    typing = (ROOT / "src/StarterPlayerScripts/TypingScreen.luau").read_text(encoding="utf-8")
    require("RankOpen" in lobby and "Rank.Open" in lobby and "RankOpen" in typing, "rank shares the lobby menu and releases match input")
    design = (ROOT / "docs/GameDesign.ko.md").read_text(encoding="utf-8")
    harness = (ROOT / "docs/Harness.ko.md").read_text(encoding="utf-8")
    require("정식 경기를 끝까지 완료" in design and "아직 기록이 없습니다" in design, "the rank pilot is recorded")
    require("랭크 반영이 실패해도" in harness and "1위, 1위, 3위" in harness, "the rank checks are recorded")
    with (ROOT / "src/localization/CoreStrings.csv").open(encoding="utf-8", newline="") as stream:
        copy = {row["Key"]: row for row in csv.DictReader(stream)}
    for key in (
        "Rank.Open",
        "Rank.Title",
        "Rank.Mine",
        "Rank.None",
        "Rank.Empty",
        "Rank.Loading",
        "Rank.Failed",
        "Rank.Stale",
        "Rank.Place",
        "Rank.Player",
        "Rank.Score",
        "Rank.Close",
    ):
        require(key in copy and copy[key]["Source"].strip() and copy[key]["ko"].strip(), f"Missing string {key}")
    require("{score}" in copy["Rank.Mine"]["ko"], "the personal best uses a placeholder")


def check_shop():
    profile = {"schemaVersion": 1, "gold": 51, "exp": 9, "bestScore": 8, "grants": ["keep"], "uiLocale": "ko", "ranked": True}
    closed = dict(profile)
    require(closed["gold"] == 51 and "owned" not in closed, "closing a preview does not write the profile")
    bought, applied = apply_grant(profile, "shop:keep", 0, 0, 0, False)
    bought = dict(bought)
    bought["gold"] = 31
    bought["owned"] = ["pilot_body"]
    bought["body"] = "pilot_body"
    again, again_applied = apply_grant(bought, "shop:later", 1, 0, 10, False)
    require(applied and again_applied and again["gold"] == 32 and again["owned"] == ["pilot_body"] and again["body"] == "pilot_body", "a reward keeps a purchase")
    require(profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0}), "a profile without cosmetics still opens")
    require(profile_ok({"schemaVersion": 1, "gold": 31, "exp": 0, "bestScore": 0, "owned": ["pilot_body"], "body": "pilot_body"}), "a saved cosmetic opens")
    require(not profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0, "owned": [1]}), "ownership entries are ids")
    require(not profile_ok({"schemaVersion": 1, "gold": 0, "exp": 0, "bestScore": 0, "body": "Pilot"}), "a slot id stays lowercase")
    margin, gap, title, gold, tab, action = 8, 4, 22, 18, 32, 36
    chrome = margin * 2 + title + gold + tab + action + gap * 4
    require(chrome + (320 - chrome) <= 320 and 320 - chrome >= 72 and action == 36, "568×320 keeps the shop action outside the list")
    service = (ROOT / "src/ServerScriptService/Core/ShopService.luau").read_text(encoding="utf-8")
    require("ProfileService.replace" in service and "ProfileService.commit" not in service and "IsStudio" in service, "shop writes do not settle a match reward")
    require('reason == "bought"' in service and 'action == "equip"' in service, "buy and equip are different server actions")
    match = (ROOT / "src/ServerScriptService/Core/MatchService.luau").read_text(encoding="utf-8")
    require("ArenaService.dress" in match and "ArenaService.undress" in match and "undressAll" in match and "ShopService.paintFor" in match, "assigned pads wear and then clear the saved look")
    screen = (ROOT / "src/StarterPlayerScripts/ShopScreen.luau").read_text(encoding="utf-8")
    require("ViewportFrame" in screen and "ScrollingFrame" in screen and "blockedByMatch" in screen, "the shop previews a pad and scrolls the list")
    close_fn = screen[screen.find("closeButton.Activated"):screen.find("buyButton.Activated")]
    require("FireServer" not in close_fn and "ShopState.buy" not in close_fn and "ShopState.equip" not in close_fn, "closing the shop does not buy or equip")
    for banned in ("DataStore", "PlayerStore", "SetCache", "QuestionSubmit"):
        require(banned not in screen, f"shop UI must not call {banned}")
    lobby = (ROOT / "src/StarterPlayerScripts/LobbyHud.luau").read_text(encoding="utf-8")
    typing = (ROOT / "src/StarterPlayerScripts/TypingScreen.luau").read_text(encoding="utf-8")
    require("ShopOpen" in lobby and "Shop.Open" in lobby and "ShopOpen" in typing, "shop shares the lobby menu and releases match input")
    design = (ROOT / "docs/GameDesign.ko.md").read_text(encoding="utf-8")
    harness = (ROOT / "docs/Harness.ko.md").read_text(encoding="utf-8")
    require("Studio에서만 판매" in design and "한 번만 차감" in design, "the shop pilot is recorded")
    require("한 번만 차감" in harness and "20골드" in harness, "the shop checks are recorded")
    with (ROOT / "src/localization/CoreStrings.csv").open(encoding="utf-8", newline="") as stream:
        copy = {row["Key"]: row for row in csv.DictReader(stream)}
    for key in (
        "Shop.Open",
        "Shop.Title",
        "Shop.Gold",
        "Shop.TabBody",
        "Shop.TabRim",
        "Shop.TabEffect",
        "Shop.Buy",
        "Shop.Equip",
        "Shop.Equipped",
        "Shop.Close",
        "Shop.Loading",
        "Shop.Processing",
        "Shop.Funds",
        "Shop.Closed",
        "Shop.Unavailable",
        "Shop.Name.starter_body",
        "Shop.Name.starter_rim",
        "Shop.Name.starter_effect",
        "Shop.Name.pilot_body",
        "Shop.Name.pilot_rim",
        "Shop.Name.pilot_effect",
    ):
        require(key in copy and copy[key]["Source"].strip() and copy[key]["ko"].strip(), f"Missing string {key}")
    require("{price}" in copy["Shop.Buy"]["ko"] and "{gold}" in copy["Shop.Gold"]["ko"], "shop prices use placeholders")


def check_key_press():
    candidates = [Path(tempfile.gettempdir()) / "lune-kw" / "lune.exe"]
    local = os.environ.get("LOCALAPPDATA")
    if local:
        candidates.append(Path(local) / "lune-kw" / "lune.exe")
    lune = next((path for path in candidates if path.exists()), None)
    if lune is None:
        found = shutil.which("lune")
        lune = Path(found) if found else None
    require(lune is not None, "lune is required to run the O-key press check")
    subprocess.run([str(lune), "run", str(ROOT / "tools" / "m2_check.luau")], check=True, cwd=ROOT)


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
        build_ui_atlas(stage)
        ui_page = Path("assets/ui-images/atlas/KeyboardWarriorUI.png")
        with Image.open(stage / ui_page) as expected, Image.open(ROOT / ui_page) as actual_page:
            require(expected.size == actual_page.size and expected.mode == actual_page.mode and expected.tobytes() == actual_page.tobytes(), "Regenerate UI atlas")
        ui_manifest = Path("src/ReplicatedStorage/Shared/UIImageAtlasData.luau")
        require((stage / ui_manifest).read_text() == (ROOT / ui_manifest).read_text(), "Regenerate UI atlas rectangles")
        output = stage / "Lobby.rbxlx"
        subprocess.run(["rojo", "build", str(ROOT / "default.project.json"), "-o", str(output)], check=True)
        tree = ElementTree.parse(output)
        check_lobby_copy()
        check_m1_rules()
        check_m2_rules()
        check_m3_rules()
        check_m4_rules()
        check_m5_rules()
        check_settings_rules()
        check_tutorial()
        check_rank()
        check_shop()
        check_key_press()
        for kind, name in [
            ("LocalizationTable", "CoreStrings"),
            ("LocalScript", "Bootstrap"),
            ("ModuleScript", "PlayerStore"),
            ("ModuleScript", "IngameConstants"),
            ("ModuleScript", "MatchRules"),
            ("ModuleScript", "QuestionRules"),
            ("ModuleScript", "PracticeRules"),
            ("ModuleScript", "SettingsRules"),
            ("ModuleScript", "Gloss"),
            ("ModuleScript", "SettingsLayout"),
            ("ModuleScript", "TutorialRules"),
            ("ModuleScript", "TutorialLayout"),
            ("ModuleScript", "TypingLayout"),
            ("ModuleScript", "ArenaService"),
            ("ModuleScript", "MatchService"),
            ("ModuleScript", "QuestionService"),
            ("ModuleScript", "RewardRules"),
            ("ModuleScript", "ResultLayout"),
            ("ModuleScript", "ProfileService"),
            ("ModuleScript", "RewardService"),
            ("ModuleScript", "SettingsService"),
            ("ModuleScript", "TutorialService"),
            ("ModuleScript", "RankRules"),
            ("ModuleScript", "RankLayout"),
            ("ModuleScript", "RankService"),
            ("ModuleScript", "RankState"),
            ("ModuleScript", "RankScreen"),
            ("ModuleScript", "ShopRules"),
            ("ModuleScript", "ShopLayout"),
            ("ModuleScript", "PadLook"),
            ("ModuleScript", "ShopService"),
            ("ModuleScript", "ShopState"),
            ("ModuleScript", "ShopScreen"),
            ("ModuleScript", "LobbyHud"),
            ("ModuleScript", "TypingPad"),
            ("ModuleScript", "TypingScreen"),
            ("ModuleScript", "MatchCamera"),
            ("ModuleScript", "PracticeScreen"),
            ("ModuleScript", "SettingsState"),
            ("ModuleScript", "SettingsScreen"),
            ("ModuleScript", "TutorialState"),
            ("ModuleScript", "TutorialScreen"),
            ("ModuleScript", "ResultScreen"),
            ("Script", "Bootstrap"),
        ]:
            require(any(i.findtext("Properties/string[@name='Name']") == name for i in tree.iterfind(f".//Item[@class='{kind}']")), f"Missing {name} in place")
        strings = {i.findtext("Properties/string[@name='Name']") for i in tree.iterfind(".//Item[@class='StringValue']")}
        require(all(p.stem in strings for p in tables.glob("*.txt")), "Missing StringValue")
    print("PASS: workbook contracts, generated data, icon atlas, match rules, question rules and single-place build")


if __name__ == "__main__":
    verify()

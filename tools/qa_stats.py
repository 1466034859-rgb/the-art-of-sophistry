# -*- coding: utf-8 -*-
"""统计四场故事的阅读量与预计时长（用于 QA 报告）。"""
import json
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data", "stories.json")
CHARS_PER_MIN = 300.0
DECISIONS_PER_ROUND = 3
SECONDS_PER_DECISION = 8


def line_len(items):
    return sum(len(str(x.get("text", ""))) + len(str(x.get("speaker", ""))) for x in items)


def main():
    stories = json.load(io.open(DATA, encoding="utf-8"))
    for story in stories:
        prologue = line_len(story["prologue"])
        statements = sum(line_len(r.get("statements", [])) for r in story["rounds"])
        options = 0
        for rnd in story["rounds"]:
            options += sum(len(o.get("text", "")) for o in rnd.get("question", {}).get("options", []))
            options += sum(len(o.get("text", "")) for o in rnd.get("rebuttal", {}).get("options", []))
            options += len(rnd.get("correct", {}).get("reply", ""))
        closing = sum(len(o.get("text", "")) for o in story["closing"]["options"])
        epilogue = line_len(story.get("epilogue_win", [])) + line_len(story.get("epilogue_lose", []))
        debrief = len(story["debrief"].get("note", ""))
        debrief += sum(len(q.get("q", "")) + len(q.get("a", "")) for q in story["debrief"].get("quiz", []))
        total = prologue + statements + options + closing + epilogue + debrief
        read_min = total / CHARS_PER_MIN
        decide_min = DECISIONS_PER_ROUND * 3 * SECONDS_PER_DECISION / 60.0
        print(
            "%s: chars=%d read=%.1fmin decide=%.1fmin total=%.1fmin"
            % (story["id"], total, read_min, decide_min, read_min + decide_min)
        )


if __name__ == "__main__":
    main()

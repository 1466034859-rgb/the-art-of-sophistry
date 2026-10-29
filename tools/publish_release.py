# -*- coding: utf-8 -*-
"""发布 GitHub Release 并上传试玩包（一次性脚本）。

用法：
  python tools/publish_release.py --token <PAT> --tag v0.6-playtest

需要令牌具备 public_repo 权限；令牌只在内存中使用，不落盘、不打印。
"""
import argparse
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
UPLOAD = "https://uploads.github.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OWNER = "1466034859-rgb"
REPO = "the-art-of-sophistry"


def request(url, token, method="GET", payload=None, raw=None, content_type=None):
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "sophistry-release",
        "Authorization": "Bearer " + token,
    }
    data = raw
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            body = response.read().decode("utf-8", errors="replace")
            return response.status, (json.loads(body) if body else {})
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        try:
            return error.code, json.loads(body)
        except json.JSONDecodeError:
            return error.code, {"raw": body}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--token", required=True)
    parser.add_argument("--tag", default="v0.6-playtest")
    parser.add_argument("--asset", default=os.path.join(ROOT, "dist", "Sophistry-playtest.zip"))
    parser.add_argument("--name", default="v0.6-playtest · 四场故事试玩版")
    parser.add_argument("--body", default="")
    args = parser.parse_args()

    if not os.path.exists(args.asset):
        print("asset not found:", args.asset)
        sys.exit(1)

    body = args.body or (
        "《诡辩之术》试玩版 v0.6。\n\n"
        "## 怎么玩\n"
        "1. 下载附件 `Sophistry-playtest.zip` 并解压；\n"
        "2. 安装 Godot 4.7（https://godotengine.org/download/）；\n"
        "3. 双击 `run_game.bat`，或打开 `project.godot` 按 F5。\n\n"
        "## 内容\n"
        "- 四场完整故事：茶水间·加班本分 / 评论区·帮扶门槛 / 年夜饭·快乐成绩 / 咖啡馆·科学情感\n"
        "- 找漏洞、补救、观众跑票、评委三票、复盘时间线\n"
        "- 内置反馈与日志（F3 调试浮层）\n\n"
        "遇到问题请点游戏内「反馈」，把生成文件夹发到 Issues。"
    )

    status, release = request(
        "%s/repos/%s/%s/releases" % (API, OWNER, REPO),
        args.token,
        "POST",
        {"tag_name": args.tag, "name": args.name, "body": body, "draft": False, "prerelease": True},
    )
    if status not in (200, 201):
        print("create release failed:", status, json.dumps(release, ensure_ascii=False)[:400])
        sys.exit(1)
    print("release:", release["html_url"])

    filename = os.path.basename(args.asset)
    content_type = mimetypes.guess_type(filename)[0] or "application/zip"
    with open(args.asset, "rb") as handle:
        raw = handle.read()
    status, asset = request(
        "%s/repos/%s/%s/releases/%s/assets?name=%s" % (UPLOAD, OWNER, REPO, release["id"], filename),
        args.token,
        "POST",
        raw=raw,
        content_type=content_type,
    )
    if status not in (200, 201):
        print("upload asset failed:", status, json.dumps(asset, ensure_ascii=False)[:400])
        sys.exit(1)
    print("asset:", asset["browser_download_url"])
    print("DONE")


if __name__ == "__main__":
    main()

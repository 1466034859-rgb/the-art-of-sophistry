# -*- coding: utf-8 -*-
"""用 GitHub 设备授权令牌创建公开仓库并上传项目（一次性发布脚本）。

用法：
  python tools/publish_github.py --device-code <code> --repo the-art-of-sophistry

令牌只在内存中使用，不落盘、不打印。
"""
import argparse
import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

CLIENT_ID = "Iv1.b507a08c87ecfe98"
TOKEN_URL = "https://github.com/login/oauth/access_token"
API = "https://api.github.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXCLUDE_DIRS = {".godot", ".appdata", "dist", ".the-sound-backup"}


def request_json(url, token=None, method="GET", payload=None, timeout=40):
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "sophistry-publisher",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = "Bearer " + token
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    last_error = None
    for attempt in range(5):
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as response:
                body = response.read().decode("utf-8")
                return response.status, json.loads(body) if body else {}
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", errors="replace")
            try:
                return error.code, json.loads(body)
            except json.JSONDecodeError:
                return error.code, {"raw": body}
        except Exception as error:  # 网络抖动 / SSL 中断，重试
            last_error = error
            time.sleep(2 + attempt * 2)
    raise last_error


def git_blob_sha(content: bytes) -> str:
    header = b"blob " + str(len(content)).encode("ascii") + b"\x00"
    return hashlib.sha1(header + content).hexdigest()


def get_token(device_code):
    payload = {
        "client_id": CLIENT_ID,
        "device_code": device_code,
        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
    }
    deadline = time.time() + 120
    while time.time() < deadline:
        req = urllib.request.Request(
            TOKEN_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Accept": "application/json", "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=30) as response:
            body = json.loads(response.read().decode("utf-8"))
        if body.get("access_token"):
            return body["access_token"], body.get("scope", "")
        if body.get("error") == "authorization_pending":
            time.sleep(5)
            continue
        raise RuntimeError("OAuth error: " + json.dumps(body, ensure_ascii=False))
    raise RuntimeError("timeout waiting for device authorization")


def collect_files():
    files = []
    for current, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS and d != ".git"]
        for name in names:
            full = os.path.join(current, name)
            rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
            files.append((rel, full))
    files.sort()
    return files


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device-code", default="")
    parser.add_argument("--token", default="")
    parser.add_argument("--repo", default="the-art-of-sophistry")
    parser.add_argument("--description", default="像素风 1v1 辩论卡牌游戏 · 四场故事可玩试玩版（Godot 4.7）")
    args = parser.parse_args()

    if args.token:
        token = args.token
        scope = "provided-token"
        print("using provided token")
    else:
        token, scope = get_token(args.device_code)
        print("scope:", scope)
        if not ("repo" in scope.split() or "public_repo" in scope.split()):
            print("ERROR: token has no repo scope.")
            sys.exit(2)
    status, user = request_json(API + "/user", token)
    if status != 200:
        print("failed to read user:", status, user)
        sys.exit(1)
    owner = user["login"]
    print("owner:", owner)

    repo_url = "%s/repos/%s/%s" % (API, owner, args.repo)
    status, repo = request_json(repo_url, token)
    if status == 404:
        status, repo = request_json(
            API + "/user/repos",
            token,
            "POST",
            {
                "name": args.repo,
                "description": args.description,
                "private": False,
                "has_issues": True,
                "has_wiki": False,
                "auto_init": False,
            },
        )
        if status not in (200, 201):
            print("create repo failed:", status, json.dumps(repo, ensure_ascii=False))
            sys.exit(1)
        print("created repo:", repo["html_url"])
        time.sleep(3)
    elif status == 200:
        print("repo exists, will push a new commit:", repo["html_url"])
    else:
        print("read repo failed:", status, json.dumps(repo, ensure_ascii=False))
        sys.exit(1)

    # 空仓库需要先引导一个初始提交，否则 Git Data API 会返回 409 "Git Repository is empty"
    # 注意：空仓库查询 ref 也可能返回 409 而不是 404，两种都要当“空仓库”处理。
    ref_url = "%s/repos/%s/%s/git/ref/heads/main" % (API, owner, args.repo)
    status, ref = request_json(ref_url, token)
    if status in (404, 409):
        readme = base64.b64encode("# 诡辩之术\n\n仓库初始化占位文件。\n".encode("utf-8")).decode("ascii")
        status, bootstrap = request_json(
            "%s/repos/%s/%s/contents/README.md" % (API, owner, args.repo),
            token,
            "PUT",
            {"message": "chore: bootstrap repository", "content": readme},
        )
        print("bootstrap status:", status)
        if status not in (200, 201):
            print("bootstrap failed:", status, bootstrap)
            sys.exit(1)
        time.sleep(2)
        status, ref = request_json(ref_url, token)
    parent_sha = str(ref.get("object", {}).get("sha", "")) if status == 200 else ""

    files = collect_files()
    print("uploading %d files..." % len(files))
    # 复用远端已有 blob：只上传内容变化的文件，减少请求、避免网络抖动导致整体失败
    existing: dict[str, str] = {}
    status, remote_tree = request_json(
        "%s/repos/%s/%s/git/trees/main?recursive=1" % (API, owner, args.repo),
        token,
    )
    if status == 200:
        for item in remote_tree.get("tree", []):
            if item.get("type") == "blob":
                existing[item["path"]] = item["sha"]
    entries = []
    uploaded = 0
    for index, (rel, full) in enumerate(files, 1):
        with open(full, "rb") as handle:
            raw = handle.read()
        sha = git_blob_sha(raw)
        if existing.get(rel) == sha:
            entries.append({"path": rel, "mode": "100644", "type": "blob", "sha": sha})
            if index % 20 == 0 or index == len(files):
                print("  %d/%d (reused)" % (index, len(files)))
            continue
        content = base64.b64encode(raw).decode("ascii")
        blob = None
        for attempt in range(5):
            status, blob = request_json(
                "%s/repos/%s/%s/git/blobs" % (API, owner, args.repo),
                token,
                "POST",
                {"content": content, "encoding": "base64"},
            )
            if status in (200, 201):
                break
            if status in (409, 422, 500, 502, 503):
                time.sleep(2 + attempt)
                continue
            break
        if blob is None or status not in (200, 201):
            print("blob failed:", rel, status, blob)
            sys.exit(1)
        entries.append({"path": rel, "mode": "100644", "type": "blob", "sha": blob["sha"]})
        uploaded += 1
        if index % 20 == 0 or index == len(files):
            print("  %d/%d" % (index, len(files)))
    print("new blobs:", uploaded, "reused:", len(files) - uploaded)

    status, tree = request_json(
        "%s/repos/%s/%s/git/trees" % (API, owner, args.repo),
        token,
        "POST",
        {"tree": entries},
    )
    if status not in (200, 201):
        print("tree failed:", status, tree)
        sys.exit(1)

    commit_payload = {"message": "Initial commit: playable build", "tree": tree["sha"]}
    if parent_sha:
        commit_payload["parents"] = [parent_sha]
    status, commit = request_json(
        "%s/repos/%s/%s/git/commits" % (API, owner, args.repo),
        token,
        "POST",
        commit_payload,
    )
    if status not in (200, 201):
        print("commit failed:", status, commit)
        sys.exit(1)

    if parent_sha:
        status, ref = request_json(
            "%s/repos/%s/%s/git/refs/heads/main" % (API, owner, args.repo),
            token,
            "PATCH",
            {"sha": commit["sha"], "force": True},
        )
    else:
        status, ref = request_json(
            "%s/repos/%s/%s/git/refs" % (API, owner, args.repo),
            token,
            "POST",
            {"ref": "refs/heads/main", "sha": commit["sha"]},
        )
    if status not in (200, 201):
        print("ref failed:", status, ref)
        sys.exit(1)

    print("DONE: https://github.com/%s/%s" % (owner, args.repo))


if __name__ == "__main__":
    main()

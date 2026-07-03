import os
import sys
import html
import random
import re
import string
from pathlib import Path

import requests

# Keep stdout/stderr UTF-8 on GitHub runner and local terminals.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8")
        except Exception:
            pass

FINAL_STATUSES = {"success", "fail", "cancelled"}
STATUS_ALIASES = {
    "failure": "fail",
    "failed": "fail",
    "error": "fail",
    "cancel": "cancelled",
    "canceled": "cancelled",
    "cancelled": "cancelled",
}

STATUS_INFO = {
    "start": ("START", "INITIALIZING BUILD ENVIRONMENT", "Preparing the ROM build environment."),
    "sync": ("SYNC", "SYNCING DATA", "Syncing or downloading required source data."),
    "download": ("DOWNLOAD", "DOWNLOADING SOURCE ROM", "Downloading the source ROM to the runner."),
    "unpack": ("UNPACK", "UNPACKING PARTITIONS", "Unpacking payload/new.dat/super image files."),
    "build": ("BUILD", "BUILDING AND PATCHING ROM", "Processing, modifying, and patching the ROM."),
    "pack": ("PACK", "PACKAGING ROM ZIP", "Repacking partitions and creating the flashable package."),
    "upload": ("UPLOAD", "UPLOADING OUTPUT", "Uploading the completed ROM file to cloud storage."),
    "success": ("SUCCESS", "BUILD COMPLETED", "The ROM build finished successfully."),
    "fail": ("FAILED", "BUILD FAILED", "An error occurred during the build. See diagnostics below."),
    "cancelled": ("CANCELLED", "BUILD CANCELLED", "The workflow was cancelled or stopped before completion."),
}

UNKNOWN_VALUES = {
    "",
    "unknown",
    "none",
    "null",
    "n/a",
    "na",
    "pending",
    "detecting...",
    "scanning...",
}

ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def normalize_status(status: str) -> str:
    value = (status or "").strip().lower()
    return STATUS_ALIASES.get(value, value or "start")


def escape(value) -> str:
    return html.escape(str(value), quote=True)


def strip_ansi(value: str) -> str:
    return ANSI_RE.sub("", value or "")


def read_file_if_exists(path, default="") -> str:
    try:
        path = Path(path)
        if not path.exists() or not path.is_file():
            return default
        value = path.read_text(encoding="utf-8", errors="replace").strip()
        return value if value else default
    except Exception:
        return default


def read_first(paths, default="") -> str:
    for item in paths:
        value = read_file_if_exists(item)
        if is_available(value):
            return value
    return default


def write_file(path, value: str) -> None:
    try:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(str(value), encoding="utf-8")
    except Exception:
        pass


def is_available(value) -> bool:
    if value is None:
        return False
    text = str(value).strip()
    if not text:
        return False
    return text.lower() not in UNKNOWN_VALUES


def compact_one_line(value: str, max_len: int = 180) -> str:
    text = strip_ansi(str(value)).replace("\r", " ").replace("\n", " ").strip()
    text = re.sub(r"\s+", " ", text)
    if len(text) > max_len:
        text = text[: max_len - 3].rstrip() + "..."
    return text


def tail_text(path: Path, max_lines: int = 24, max_chars: int = 1400) -> str:
    try:
        if not path.exists() or not path.is_file():
            return ""
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        cleaned = [strip_ansi(line).rstrip() for line in lines if strip_ansi(line).strip()]
        text = "\n".join(cleaned[-max_lines:]).strip()
        if len(text) > max_chars:
            text = "...\n" + text[-max_chars:]
        return text
    except Exception:
        return ""


def collect_log_candidates():
    candidates = []
    env_log = os.environ.get("NOTIFY_ERROR_LOG", "")
    if env_log:
        for item in re.split(r"[;,]", env_log):
            item = item.strip()
            if item:
                candidates.append(item)

    runner_temp = os.environ.get("RUNNER_TEMP", "")
    if runner_temp:
        candidates.extend([
            str(Path(runner_temp) / "build_action.log"),
            str(Path(runner_temp) / "build_error.log"),
        ])

    candidates.extend([
        "build_action.log",
        "build.log",
        "build_error.log",
        "error.log",
        "last_error.log",
        "bin/ddevice/error_reason.txt",
        "bin/ddevice/error.log",
        "out/error.log",
    ])

    seen = set()
    result = []
    for item in candidates:
        path = Path(item)
        key = str(path.resolve()) if path.exists() else str(path)
        if key not in seen:
            seen.add(key)
            result.append(path)
    return result


def extract_reason_from_log(log_tail: str) -> str:
    if not log_tail:
        return ""
    patterns = (
        "[error]",
        " error",
        "error:",
        "failed",
        "failure",
        "exception",
        "traceback",
        "fatal",
        "no space left",
        "permission denied",
        "command not found",
        "not found",
        "cannot",
        "unable",
    )
    lines = [line.strip() for line in log_tail.splitlines() if line.strip()]
    for line in reversed(lines):
        lower = line.lower()
        if any(pattern in lower for pattern in patterns):
            return compact_one_line(line)
    return compact_one_line(lines[-1]) if lines else ""


def collect_diagnostics(status: str):
    env_reason = (
        os.environ.get("NOTIFY_ERROR_REASON")
        or os.environ.get("ERROR_REASON")
        or os.environ.get("FAILURE_REASON")
        or os.environ.get("CANCEL_REASON")
        or ""
    )

    selected_path = ""
    selected_tail = ""
    for candidate in collect_log_candidates():
        tail = tail_text(candidate)
        if tail:
            selected_path = str(candidate)
            selected_tail = tail
            break

    reason = compact_one_line(env_reason) if env_reason else extract_reason_from_log(selected_tail)
    if not reason:
        if status == "cancelled":
            reason = "The workflow was cancelled before completion; check the Run ID and Attempt in GitHub Actions."
        elif status == "fail":
            reason = "No local log tail was found; open the GitHub Actions log for full details."

    return reason, selected_path, selected_tail


def build_action_url(repo_name: str) -> str:
    repo = repo_name or os.environ.get("GITHUB_REPOSITORY", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if repo and run_id:
        return f"https://github.com/{repo}/actions/runs/{run_id}"
    if repo:
        return f"https://github.com/{repo}/actions"
    return ""


def collect_device_info():
    rom_os = read_first([
        "bin/ddevice/rom_os.txt",
        "bin/ddevice/brand_os.txt",
        "bin/ddevice/brand.txt",
        "bin/ddevice/os_type.txt",
    ])
    if rom_os in {"OS1", "OS2", "OS3"}:
        rom_os = "HyperOS"

    android_ver = read_file_if_exists("bin/ddevice/androidver.txt")
    sdk_level = read_file_if_exists("bin/ddevice/sdkLevel.txt")

    return {
        "Device": read_first([
            "bin/ddevice/device_name.txt",
            "bin/ddevice/name_devices.txt",
            "bin/ddevice/name_device.txt",
        ]),
        "Codename": read_first([
            "bin/ddevice/device_code.txt",
            "bin/ddevice/device_model.txt",
            "bin/ddevice/device_f.txt",
        ]),
        "ROM": " | ".join(
            part
            for part in [
                rom_os,
                read_first([
                    "bin/ddevice/rom_version.txt",
                    "bin/ddevice/base_rom_code.txt",
                    "bin/ddevice/base_build_id.txt",
                ]),
            ]
            if is_available(part)
        ),
        "Region": read_first([
            "bin/ddevice/rom_region.txt",
            "bin/ddevice/device_type.txt",
        ]),
        "Android": " | ".join(
            part
            for part in [
                f"Android {android_ver}" if is_available(android_ver) else "",
                f"SDK {sdk_level}" if is_available(sdk_level) else "",
            ]
            if is_available(part)
        ),
        "ROM type": read_first(["bin/ddevice/romtype.txt"]),
        "FS/Structure": " | ".join(
            part
            for part in [
                read_first(["bin/ddevice/fstype.txt"]),
                read_first(["bin/script2flash/META-INF/Data/Structure"]),
            ]
            if is_available(part)
        ),
        "Chip": read_first(["bin/script2flash/META-INF/Data/Chip"]),
        "Tool version": read_first(["Version"]),
        "Output zip": read_first(["bin/ddevice/output_zip.txt"]),
    }


def collect_run_info(repo_name: str, build_id: str):
    sha = os.environ.get("GITHUB_SHA", "")
    sha_short = sha[:7] if sha else ""
    run_number = os.environ.get("GITHUB_RUN_NUMBER", "")
    run_attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    run_parts = []
    if run_number:
        run_parts.append(f"#{run_number}")
    if run_attempt:
        run_parts.append(f"attempt {run_attempt}")
    if run_id:
        run_parts.append(f"id {run_id}")

    workflow = os.environ.get("GITHUB_WORKFLOW", "")
    job = os.environ.get("GITHUB_JOB", "")
    workflow_job = " / ".join(part for part in [workflow, job] if is_available(part))

    actor = os.environ.get("GITHUB_ACTOR", "")
    triggering_actor = os.environ.get("GITHUB_TRIGGERING_ACTOR", "")
    actor_text = actor
    if triggering_actor and triggering_actor != actor:
        actor_text = f"{actor} (trigger: {triggering_actor})" if actor else triggering_actor

    ref = os.environ.get("GITHUB_REF_NAME", "") or os.environ.get("GITHUB_REF", "")
    ref_sha = " / ".join(part for part in [ref, sha_short] if is_available(part))

    return {
        "Build ID": build_id,
        "Repository": repo_name or os.environ.get("GITHUB_REPOSITORY", ""),
        "Run": " / ".join(run_parts),
        "Workflow/Job": workflow_job,
        "Event": os.environ.get("GITHUB_EVENT_NAME", ""),
        "Ref/SHA": ref_sha,
        "Triggered by": actor_text,
        "Runner": os.environ.get("RUNNER_NAME", ""),
        "Conclusion": os.environ.get("NOTIFY_WORKFLOW_CONCLUSION", ""),
    }


def progress_text(status: str, previous_status: str = "") -> str:
    stages = ["start", "download", "unpack", "build", "pack", "upload", "success"]
    stage_labels = {
        "start": "start",
        "download": "download",
        "unpack": "unpack",
        "build": "build",
        "pack": "pack",
        "upload": "upload",
        "success": "success",
    }
    marker_status = previous_status if status in {"fail", "cancelled"} and previous_status else status
    marker_status = normalize_status(marker_status)
    current_index = stages.index(marker_status) if marker_status in stages else -1
    items = []
    for idx, stage in enumerate(stages):
        if idx < current_index:
            state = "done"
        elif idx == current_index:
            state = "running" if status not in {"success", "fail", "cancelled"} else ("done" if status == "success" else "last")
        else:
            state = "pending"
        items.append(f"{stage_labels[stage]}:{state}")
    if status in {"fail", "cancelled"} and previous_status:
        items.append(f"stop:{'cancelled' if status == 'cancelled' else 'failed'}")
    return " > ".join(items)


def add_field(lines, label: str, value, code: bool = False):
    if not is_available(value):
        return
    text = compact_one_line(str(value), 260)
    if code:
        lines.append(f"<b>{escape(label)}:</b> <code>{escape(text)}</code>")
    else:
        lines.append(f"<b>{escape(label)}:</b> {escape(text)}")


def add_link(lines, label: str, url: str, text: str):
    if not is_available(url):
        return
    lines.append(f"<b>{escape(label)}:</b> <a href=\"{escape(url)}\">{escape(text)}</a>")


def compose_message(status, repo_name, rom_link, build_id, builder_name):
    status = normalize_status(status)
    marker, status_title, status_desc = STATUS_INFO.get(
        status,
        ("INFO", "STATUS UPDATE", str(status).upper()),
    )

    previous_status = read_file_if_exists("bin/ddevice/last_status.txt")
    if status not in FINAL_STATUSES:
        write_file("bin/ddevice/last_status.txt", status)

    action_url = build_action_url(repo_name)
    builder_text = builder_name if builder_name else "System"

    lines = [
        "<b>ROM BUILD PROGRESS</b>",
        "-------------------------",
        f"<b>Status:</b> <code>{escape(marker)}</code> <b>{escape(status_title)}</b>",
        f"<b>Details:</b> {escape(status_desc)}",
        f"<b>Progress:</b> <code>{escape(progress_text(status, previous_status))}</code>",
        "",
        "<b>Build information</b>",
    ]

    add_field(lines, "Builder", builder_text)
    for label, value in collect_device_info().items():
        add_field(lines, label, value, code=True)

    lines.extend(["", "<b>Check information</b>"])
    for label, value in collect_run_info(repo_name, build_id).items():
        add_field(lines, label, value, code=True)
    add_link(lines, "Build log", action_url, "Open GitHub Actions log")
    add_link(lines, "Source ROM", rom_link, "Open source ROM link")

    if status in {"fail", "cancelled"}:
        reason, log_path, log_tail = collect_diagnostics(status)
        lines.extend(["", "<b>Diagnostics</b>"])
        add_field(lines, "Latest reason", reason, code=True)
        add_field(lines, "Local log", log_path, code=True)
        if status == "cancelled":
            lines.append("<b>Cancellation check:</b> open the build log and inspect Timeline/Jobs, Run ID, and Attempt to identify when or who cancelled it.")
        if log_tail:
            lines.append("<b>Log tail:</b>")
            lines.append(f"<pre>{escape(log_tail)}</pre>")

    message = "\n".join(lines)
    if len(message) <= 3900:
        return message

    # If the Telegram message is too long, shorten the log while keeping key fields and links.
    if status in {"fail", "cancelled"}:
        reason, log_path, log_tail = collect_diagnostics(status)
        short_tail = log_tail[-700:] if log_tail else ""
        if short_tail:
            trimmed_lines = []
            skipping = False
            for line in lines:
                if line == "<b>Log tail:</b>":
                    trimmed_lines.append(line)
                    trimmed_lines.append(f"<pre>{escape('...\n' + short_tail)}</pre>")
                    skipping = True
                    continue
                if skipping:
                    if line.startswith("<pre>"):
                        skipping = False
                    continue
                trimmed_lines.append(line)
            message = "\n".join(trimmed_lines)
    if len(message) > 3900:
        message = message[:3800] + "\n...\n(Open the build log for the full output.)"
    return message


def save_env(name: str, value: str) -> None:
    env_path = os.environ.get("GITHUB_ENV")
    if not env_path or not value:
        return
    try:
        with open(env_path, "a", encoding="utf-8") as env_file:
            env_file.write(f"{name}={value}\n")
    except Exception:
        pass


def post_telegram(url: str, payload: dict):
    response = requests.post(url, json=payload, timeout=25)
    try:
        data = response.json()
    except Exception:
        data = {}
    return response, data


def send_notification(status, repo_name, rom_link, channel_id, bot_token, msg_id=None, build_id="Unknown", builder_name="", builder_id=""):
    status = normalize_status(status)
    message = compose_message(status, repo_name, rom_link, build_id, builder_name)

    base_url = f"https://api.telegram.org/bot{bot_token}"
    payload = {
        "chat_id": channel_id,
        "text": message,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }

    try:
        if msg_id:
            edit_payload = dict(payload)
            edit_payload["message_id"] = msg_id
            response, data = post_telegram(f"{base_url}/editMessageText", edit_payload)
            if not response.ok:
                description = str(data.get("description", response.text))
                if "message is not modified" in description.lower():
                    print("Telegram message was not modified; update skipped.")
                else:
                    print(f"Could not edit the old Telegram message; sending a new one. Reason: {description}")
                    response, data = post_telegram(f"{base_url}/sendMessage", payload)
                    response.raise_for_status()
                    new_msg_id = data.get("result", {}).get("message_id")
                    if new_msg_id:
                        save_env("TELEGRAM_MSG_ID", str(new_msg_id))
            else:
                print("Telegram notification updated.")
        else:
            response, data = post_telegram(f"{base_url}/sendMessage", payload)
            response.raise_for_status()
            new_msg_id = data.get("result", {}).get("message_id")
            if new_msg_id:
                save_env("TELEGRAM_MSG_ID", str(new_msg_id))
                print(f"Saved TELEGRAM_MSG_ID={new_msg_id} to GITHUB_ENV.")
            print("Telegram notification sent.")

        if status in {"success", "fail", "cancelled"} and builder_id:
            pm_title = {
                "success": "YOUR ROM BUILD REQUEST COMPLETED",
                "fail": "YOUR ROM BUILD REQUEST FAILED",
                "cancelled": "YOUR ROM BUILD REQUEST WAS CANCELLED",
            }[status]
            pm_lines = [f"<b>{escape(pm_title)}</b>", "", message]
            if status == "success":
                pm_lines.extend(["", "<b>Download ROM:</b> <a href=\"https://nothingsvn.vercel.app/\">nothingsvn.vercel.app</a>"])
            else:
                pm_lines.extend(["", "<b>Tip:</b> open the Build log link in the notification to view the full error or cancellation details."])
            pm_text = "\n".join(pm_lines)
            if len(pm_text) > 3900:
                pm_text = pm_text[:3800] + "\n...\n(Open the build log for the full output.)"
            pm_payload = {
                "chat_id": builder_id,
                "text": pm_text,
                "parse_mode": "HTML",
                "disable_web_page_preview": True,
            }
            pm_response, pm_data = post_telegram(f"{base_url}/sendMessage", pm_payload)
            if pm_response.ok:
                print(f"Private message sent to user {builder_id}.")
            else:
                print(f"Could not send a private message to user {builder_id}: {pm_data or pm_response.text}")
    except Exception as exc:
        print(f"Error while sending/updating the Telegram notification: {exc}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python notify.py <status> <repo_name> <rom_link> [prefix_id] [builder_name] [builder_id]")
        sys.exit(1)

    status_arg = sys.argv[1]
    repo_name_arg = sys.argv[2]
    rom_link_arg = sys.argv[3]
    prefix = sys.argv[4] if len(sys.argv) > 4 else "build"
    builder_name_arg = sys.argv[5] if len(sys.argv) > 5 else ""
    builder_id_arg = sys.argv[6] if len(sys.argv) > 6 else ""

    bot_token_arg = os.environ.get("TELEGRAM_BOT_TOKEN")
    channel_id_arg = os.environ.get("TELEGRAM_CHANNEL_ID")
    msg_id_arg = os.environ.get("TELEGRAM_MSG_ID")
    build_id_arg = os.environ.get("TELEGRAM_BUILD_ID")

    if not build_id_arg:
        random_digits = "".join(random.choices(string.digits, k=8))
        build_id_arg = f"{prefix}_{random_digits}"
        save_env("TELEGRAM_BUILD_ID", build_id_arg)

    write_file("bin/ddevice/telegram_build_id.txt", build_id_arg)

    if not bot_token_arg or not channel_id_arg:
        print("Error: TELEGRAM_BOT_TOKEN or TELEGRAM_CHANNEL_ID is missing from environment variables.")
        sys.exit(1)

    send_notification(
        status_arg,
        repo_name_arg,
        rom_link_arg,
        channel_id_arg,
        bot_token_arg,
        msg_id_arg,
        build_id_arg,
        builder_name_arg,
        builder_id_arg,
    )

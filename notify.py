import os
import sys
import requests
import random
import string

def get_status_info(status):
    status = status.lower()
    if status == 'start': return "🚀", "BẮT ĐẦU BUILD", "Đang khởi tạo môi trường..."
    if status == 'sync': return "🔄", "ĐANG ĐỒNG BỘ", "Đang tải mã nguồn..."
    if status == 'build': return "🛠️", "ĐANG BIÊN DỊCH", "Đang tiến hành build ROM..."
    if status == 'upload': return "📤", "ĐANG TẢI LÊN", "Đang upload ROM..."
    if status == 'success': return "✅", "THÀNH CÔNG", "Quá trình hoàn tất!"
    if status == 'fail': return "❌", "THẤT BẠI", "Đã xảy ra lỗi!"
    
    # Nếu truyền trạng thái bất kỳ không nằm trong list trên
    return "ℹ️", "CẬP NHẬT TRẠNG THÁI", status

def send_notification(status, repo_name, rom_link, channel_id, bot_token, msg_id=None, build_id="Unknown", builder_name="", builder_id=""):
    icon, status_title, status_desc = get_status_info(status)

    # Lấy GITHUB_RUN_ID để tạo link trỏ tới log của Action
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if run_id:
        action_url = f"https://github.com/{repo_name}/actions/runs/{run_id}"
    else:
        action_url = f"https://github.com/{repo_name}/actions"

    builder_text = f"👤 *Người build:* {builder_name}\n" if builder_name else ""

    # Đọc Codename, Phiên bản ROM và Phiên bản Tool từ file nếu tồn tại
    codename = "Đang xác định..."
    version_rom = "Đang xác định..."
    version_tool = "Đang xác định..."
    
    if os.path.exists("bin/ddevice/device_code.txt"):
        with open("bin/ddevice/device_code.txt", "r", encoding="utf-8") as f:
            codename = f.read().strip()
    elif os.path.exists("bin/ddevice/device_model.txt"):
        with open("bin/ddevice/device_model.txt", "r", encoding="utf-8") as f:
            codename = f.read().strip()
            
    if os.path.exists("bin/ddevice/base_rom_code.txt"):
        with open("bin/ddevice/base_rom_code.txt", "r", encoding="utf-8") as f:
            version_rom = f.read().strip()
    elif os.path.exists("bin/ddevice/base_build_id.txt"):
        with open("bin/ddevice/base_build_id.txt", "r", encoding="utf-8") as f:
            version_rom = f.read().strip()
            
    if os.path.exists("Version"):
        with open("Version", "r", encoding="utf-8") as f:
            version_tool = f.read().strip()

    message = (
        f"{icon} *{status_title}*\n"
        f"━━━━━━━━━━━━━━━━━━\n"
        f"{builder_text}"
        f"📱 *Thiết bị (Codename):* `{codename}`\n"
        f"🎯 *Phiên bản ROM:* `{version_rom}`\n"
        f"🛠️ *Phiên bản Tool:* `{version_tool}`\n"
        f"🚀 *Log build:* [Xem chi tiết tại đây]({action_url})\n"
        f"📝 *Trạng thái:* _{status_desc}_\n"
        f"🔗 *Nguồn:* [Nhấn vào đây để xem/tải ROM]({rom_link})\n"
        f"🆔 *Build ID:* `{build_id}`\n"
    )

    if msg_id:
        # Nếu đã có msg_id, ta sẽ Edit tin nhắn cũ
        url = f"https://api.telegram.org/bot{bot_token}/editMessageText"
        payload = {
            "chat_id": channel_id,
            "message_id": msg_id,
            "text": message,
            "parse_mode": "Markdown",
            "disable_web_page_preview": True
        }
    else:
        # Nếu chưa có, gửi tin nhắn mới
        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        payload = {
            "chat_id": channel_id,
            "text": message,
            "parse_mode": "Markdown",
            "disable_web_page_preview": True
        }

    try:
        response = requests.post(url, json=payload)
        response.raise_for_status()
        res_data = response.json()
        
        # Lấy message_id của tin nhắn vừa gửi
        new_msg_id = res_data.get('result', {}).get('message_id')
        
        # Ghi message_id vào biến môi trường của GitHub Actions để các step sau tái sử dụng
        if not msg_id and new_msg_id and "GITHUB_ENV" in os.environ:
            with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as f:
                f.write(f"TELEGRAM_MSG_ID={new_msg_id}\n")
            print(f"Đã lưu TELEGRAM_MSG_ID={new_msg_id} vào GITHUB_ENV để tự động update tin nhắn.")
            
        print("Đã gửi/cập nhật thông báo lên kênh thành công!")
        # Gửi tin nhắn riêng (PM) cho người build nếu trạng thái là success hoặc fail
        if status.lower() in ['success', 'fail'] and builder_id:
            pm_url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
            
            if status.lower() == 'success':
                pm_text = (
                    f"🎉 *YÊU CẦU BUILD ROM ĐÃ HOÀN TẤT!*\n\n"
                    f"{message}\n"
                    f"⬇️ *Tải ROM tại:* [https://nothingsvn.vercel.app/](https://nothingsvn.vercel.app/)"
                )
            else:
                pm_text = (
                    f"⚠️ *YÊU CẦU BUILD ROM ĐÃ THẤT BẠI!*\n\n"
                    f"{message}\n"
                    f"💡 *Gợi ý:* Hãy bấm vào link Log build ở trên để xem chi tiết lỗi nhé."
                )
                
            pm_payload = {
                "chat_id": builder_id,
                "text": pm_text,
                "parse_mode": "Markdown",
                "disable_web_page_preview": True
            }
            try:
                requests.post(pm_url, json=pm_payload)
                print(f"Đã gửi tin nhắn riêng (PM) cho user {builder_id}")
            except Exception as e:
                print(f"Lỗi gửi tin nhắn riêng: {e}")

    except Exception as e:
        print(f"Lỗi khi gửi thông báo: {e}")
        if 'response' in locals():
            print(response.text)

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Sử dụng: python notify.py <status> <repo_name> <rom_link> [prefix_id] [builder_name] [builder_id]")
        sys.exit(1)

    status = sys.argv[1]
    repo_name = sys.argv[2]
    rom_link = sys.argv[3]
    
    # Prefix cho build id (ví dụ: xiaomi, xst, oplus)
    prefix = sys.argv[4] if len(sys.argv) > 4 else "build"
    
    # Thông tin người build
    builder_name = sys.argv[5] if len(sys.argv) > 5 else ""
    builder_id = sys.argv[6] if len(sys.argv) > 6 else ""
    
    # Lấy token, channel ID, message ID và Build ID từ biến môi trường
    bot_token = os.environ.get("TELEGRAM_BOT_TOKEN")
    channel_id = os.environ.get("TELEGRAM_CHANNEL_ID")
    msg_id = os.environ.get("TELEGRAM_MSG_ID") 
    build_id = os.environ.get("TELEGRAM_BUILD_ID")

    # Tạo Build ID mới nếu chưa có
    if not build_id:
        random_digits = ''.join(random.choices(string.digits, k=8))
        build_id = f"{prefix}_{random_digits}"
        
        # Lưu vào GITHUB_ENV để dùng cho các step sau
        if "GITHUB_ENV" in os.environ:
            with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as f:
                f.write(f"TELEGRAM_BUILD_ID={build_id}\n")

    if not bot_token or not channel_id:
        print("Lỗi: Thiếu TELEGRAM_BOT_TOKEN hoặc TELEGRAM_CHANNEL_ID trong biến môi trường.")
        sys.exit(1)

    send_notification(status, repo_name, rom_link, channel_id, bot_token, msg_id, build_id, builder_name, builder_id)

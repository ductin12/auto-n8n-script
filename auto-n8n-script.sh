#!/bin/bash

N8N_DIR="${N8N_DIR:-$HOME/n8n-data}"

echo "Cài đặt n8n trên localhost với cổng 5678 (mặc định)."
echo "Bạn có thể truy cập n8n tại: http://localhost:5678"
echo ""

# Kiểm tra FFmpeg, yt-dlp và Puppeteer trong container n8n
echo "Kiểm tra FFmpeg, yt-dlp và Puppeteer trong container n8n..."

# Xác định lệnh docker phù hợp với quyền truy cập
if ! docker ps &>/dev/null; then
    DOCKER_CMD="sudo docker"
else
    DOCKER_CMD="docker"
fi

N8N_CONTAINER=$($DOCKER_CMD ps -q --filter "name=n8n" 2>/dev/null)
if [ -n "$N8N_CONTAINER" ]; then
    if $DOCKER_CMD exec $N8N_CONTAINER ffmpeg -version &> /dev/null; then
        echo "FFmpeg đã được cài đặt thành công trong container n8n."
        echo "Phiên bản FFmpeg:"
        $DOCKER_CMD exec $N8N_CONTAINER ffmpeg -version | head -n 1
    else
        echo "Lưu ý: FFmpeg có thể chưa được cài đặt đúng cách trong container."
    fi

    if $DOCKER_CMD exec $N8N_CONTAINER yt-dlp --version &> /dev/null; then
        echo "yt-dlp đã được cài đặt thành công trong container n8n."
        echo "Phiên bản yt-dlp:"
        $DOCKER_CMD exec $N8N_CONTAINER yt-dlp --version
    else
        echo "Lưu ý: yt-dlp có thể chưa được cài đặt đúng cách trong container."
    fi
    
    if $DOCKER_CMD exec $N8N_CONTAINER chromium-browser --version &> /dev/null; then
        echo "Chromium đã được cài đặt thành công trong container n8n."
        echo "Phiên bản Chromium:"
        $DOCKER_CMD exec $N8N_CONTAINER chromium-browser --version
    else
        echo "Lưu ý: Chromium có thể chưa được cài đặt đúng cách trong container."
    fi
else
    echo "Lưu ý: Không thể kiểm tra công cụ ngay lúc này. Container n8n chưa sẵn sàng."
fi

# Tạo script kiểm tra cập nhật tự động
echo "Tạo script cập nhật tự động..."
cat << EOF > $N8N_DIR/update-n8n.sh
#!/bin/bash

# Đường dẫn đến thư mục n8n
N8N_DIR="$N8N_DIR"

# Hàm ghi log
log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" >> \$N8N_DIR/update.log
}

log "Bắt đầu kiểm tra cập nhật..."

# Kiểm tra Docker command
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    log "Không tìm thấy lệnh docker-compose hoặc docker compose."
    exit 1
fi

# Cập nhật yt-dlp trên host
log "Cập nhật yt-dlp trên host system..."
if command -v pipx &> /dev/null; then
    pipx upgrade yt-dlp
elif [ -d "/opt/yt-dlp-venv" ]; then
    /opt/yt-dlp-venv/bin/pip install -U yt-dlp
else
    log "Không tìm thấy cài đặt yt-dlp đã biết"
fi

# Lấy phiên bản hiện tại
CURRENT_IMAGE_ID=\$(docker images -q n8n-ffmpeg-latest)
if [ -z "\$CURRENT_IMAGE_ID" ]; then
    log "Không tìm thấy image n8n-ffmpeg-latest"
    exit 1
fi

# Kiểm tra và xóa image gốc n8nio/n8n cũ nếu cần
OLD_BASE_IMAGE_ID=\$(docker images -q n8nio/n8n)

# Pull image gốc mới nhất
log "Kéo image n8nio/n8n mới nhất"
docker pull n8nio/n8n

# Lấy image ID mới
NEW_BASE_IMAGE_ID=\$(docker images -q n8nio/n8n)

# Kiểm tra xem image gốc đã thay đổi chưa
if [ "\$NEW_BASE_IMAGE_ID" != "\$OLD_BASE_IMAGE_ID" ]; then
    log "Phát hiện image mới (\${NEW_BASE_IMAGE_ID}), tiến hành cập nhật..."
    
    # Sao lưu dữ liệu n8n
    BACKUP_DATE=\$(date '+%Y%m%d_%H%M%S')
    BACKUP_FILE="\$N8N_DIR/backup_\${BACKUP_DATE}.zip"
    log "Tạo bản sao lưu tại \$BACKUP_FILE"
    zip -r \$BACKUP_FILE \$N8N_DIR -x \$N8N_DIR/update-n8n.sh -x \$N8N_DIR/backup_* -x \$N8N_DIR/files/temp/* -x \$N8N_DIR/Dockerfile -x \$N8N_DIR/docker-compose.yml
    
    # Build lại image n8n-ffmpeg
    cd \$N8N_DIR
    log "Đang build lại image n8n-ffmpeg-latest..."
    \$DOCKER_COMPOSE build
    
    # Khởi động lại container
    log "Khởi động lại container..."
    \$DOCKER_COMPOSE down
    \$DOCKER_COMPOSE up -d
    
    log "Cập nhật hoàn tất, phiên bản mới: \${NEW_BASE_IMAGE_ID}"
else
    log "Không có cập nhật mới cho n8n"
    
    # Cập nhật yt-dlp trong container
    log "Cập nhật yt-dlp trong container n8n..."
    N8N_CONTAINER=\$(docker ps -q --filter "name=n8n" 2>/dev/null)
    if [ -n "\$N8N_CONTAINER" ]; then
        docker exec -u root \$N8N_CONTAINER pip3 install --break-system-packages -U yt-dlp
        log "yt-dlp đã được cập nhật thành công trong container"
    else
        log "Không tìm thấy container n8n đang chạy"
    fi
fi
EOF

# Đặt quyền thực thi cho script cập nhật
chmod +x $N8N_DIR/update-n8n.sh

# Tạo cron job để chạy mỗi 12 giờ
echo "Thiết lập cron job cập nhật tự động mỗi 12 giờ và sao lưu hàng ngày..."
UPDATE_CRON="0 */12 * * * $N8N_DIR/update-n8n.sh"
BACKUP_CRON="0 2 * * * $N8N_DIR/backup-workflows.sh"
(crontab -l 2>/dev/null | grep -v "update-n8n.sh\|backup-workflows.sh"; echo "$UPDATE_CRON"; echo "$BACKUP_CRON") | crontab -

echo "======================================================================"
echo "N8n đã được cài đặt và cấu hình với FFmpeg, yt-dlp, Puppeteer."
echo "Truy cập http://localhost:5678 để sử dụng."

# Hiển thị thông tin về swap
if [ "$(swapon --show | wc -l)" -gt 0 ]; then
    SWAP_SIZE=$(free -h | grep Swap | awk '{print $2}')
    echo "► Swap đã được thiết lập:"
    echo "  - Kích thước: ${SWAP_SIZE}"
    echo "  - Swappiness: $(cat /proc/sys/vm/swappiness) (Mức càng thấp càng ưu tiên dùng RAM)"
    echo "  - Vfs_cache_pressure: $(cat /proc/sys/vm/vfs_cache_pressure) (Mức càng thấp càng giữ cache lâu hơn)"
fi
echo "Các file cấu hình và dữ liệu được lưu trong $N8N_DIR"
echo ""
echo "► Tính năng tự động cập nhật đã được thiết lập:"
echo "  - Kiểm tra cập nhật mỗi 12 giờ"
echo "  - Log cập nhật được lưu tại $N8N_DIR/update.log"
echo "  - Tự động sao lưu trước khi cập nhật"
echo "  - Tự động cập nhật yt-dlp trên cả host và container"
echo ""
echo "► Tính năng sao lưu workflow và credentials:"
echo "  - Sao lưu tự động hàng ngày vào lúc 2 giờ sáng"
echo "  - File sao lưu được lưu tại $N8N_DIR/files/backup_full với tên theo thời gian"
echo "  - Giữ lại 30 bản sao lưu gần nhất"
echo "  - Log sao lưu được lưu tại $N8N_DIR/files/backup_full/backup.log"
echo ""
echo "► Thông tin về thư mục tải video:"
echo "  - Thư mục lưu video YouTube: $N8N_DIR/files/youtube_content_anylystic/"
echo ""
echo "► Thông tin về Puppeteer:"
echo "  - Chromium Browser đã được cài đặt trong container cho Puppeteer"
echo "  - n8n-nodes-puppeteer package đã được cài đặt sẵn"
echo "  - Để sử dụng nút Puppeteer trong n8n, tìm kiếm 'Puppeteer' trong bộ nút"
echo ""
echo "Script được chỉnh sửa từ script gốc của Nguyễn Ngọc Thiện, https://www.youtube.com/@EtoolsAICONTENT"
echo "======================================================================"
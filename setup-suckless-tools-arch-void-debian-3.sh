#!/usr/bin/env bash
# مُحسّن - سكربت إعداد بيئة suckless وخدمات تطوير خفيفة
# مخصص: Void / Debian / Arch (تحسينات للأخطاء والتوافق)

set -euo pipefail

LOG_FILE="$HOME/suckless-setup.log"
DISTRO=""

# ألوان
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# احسب ما إذا كنا بصلاحية root
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; log "INFO: $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; log "SUCCESS: $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; log "WARNING: $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; log "ERROR: $1"; }

cleanup() {
    print_status "تنظيف الملفات المؤقتة..."
    rm -f /tmp/postman.tar.gz /tmp/packages.microsoft.gpg /tmp/*.desktop 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# --- كشف التوزيعة ---
detect_distro() {
    if [ -n "$DISTRO" ]; then return; fi

    if command -v xbps-install &>/dev/null; then
        DISTRO="void"
    elif command -v apt &>/dev/null; then
        DISTRO="debian"
    elif command -v pacman &>/dev/null; then
        DISTRO="arch"
    else
        print_error "لا يمكن اكتشاف التوزيعة. الرجاء تعيين المتغير DISTRO يدوياً (void/debian/arch)."
        exit 1
    fi
    print_status "اكتشفت التوزيعة: $DISTRO"
}

# --- تحقق sudo/privileges ---
check_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        print_status "تشغيل كـ root — سيتم تجاوز حاجة sudo."
        SUDO=""
        return 0
    fi

    if ! command -v sudo &>/dev/null; then
        print_error "sudo غير مثبت. إما شغّل السكربت كـ root أو ثبّت sudo أولاً."
        exit 1
    fi

    if ! sudo -v &>/dev/null; then
        print_error "حسابك لا يملك صلاحيات sudo أو انتهت صلاحيات sudo. تأكد من الإعداد ثم أعد التشغيل."
        exit 1
    fi
}

# --- تحقق التبعيات الأساسية ---
check_dependencies() {
    local deps=(git wget curl)
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        print_warning "التبعيات المفقودة: ${missing[*]}"
        # حاول تثبيتها تلقائياً إذا أمكن
        case "$DISTRO" in
            debian)
                print_status "محاولة تثبيت التبعيات عبر apt..."
                $SUDO apt update
                $SUDO apt install -y "${missing[@]}"
                ;;
            void)
                print_status "محاولة تثبيت التبعيات عبر xbps-install..."
                $SUDO xbps-install -Sy "${missing[@]}"
                ;;
            arch)
                print_status "محاولة تثبيت التبعيات عبر pacman..."
                $SUDO pacman -S --noconfirm "${missing[@]}"
                ;;
            *)
                print_error "لا يمكن تثبيت التبعيات تلقائياً لهذه التوزيعة."
                exit 1
                ;;
        esac
    fi
}

# --- تنزيل مع إعادة المحاولة ---
download_with_retry() {
    local url=$1
    local dest=$2
    local retries=3
    for i in $(seq 1 $retries); do
        if wget -q -O "$dest" "$url"; then
            return 0
        fi
        sleep 2
    done
    print_error "فشل تنزيل $url بعد $retries محاولات"
    return 1
}

# --- تحديث النظام ---
update_system() {
    print_status "تحديث النظام..."
    case "$DISTRO" in
        void) $SUDO xbps-install -Syu ;;
        debian) $SUDO apt update && $SUDO apt upgrade -y ;;
        arch) $SUDO pacman -Syu --noconfirm ;;
    esac
    print_success "تم تحديث النظام"
}

# --- نسخ احتياطي ---
backup_configs() {
    local configs=(".xinitrc" ".bashrc")
    for config in "${configs[@]}"; do
        if [ -f "$HOME/$config" ]; then
            cp "$HOME/$config" "$HOME/${config}.bak.$(date +%Y%m%d_%H%M%S)"
            print_status "تم عمل نسخة احتياطية من $config"
        fi
    done
}

# --- تثبيت الحزم الأساسية حسب التوزيعة ---
install_base_packages() {
    print_status "تثبيت الحزم الأساسية..."
    case "$DISTRO" in
        void)
            $SUDO xbps-install -Sy base-devel libX11-devel libXft-devel libXinerama-devel \
                freetype-devel fontconfig-devel xorg-server xinit git
            ;;
        debian)
            $SUDO apt update
            $SUDO apt install -y build-essential libx11-dev libxft-dev libxinerama-dev \
                xorg xorg-dev git
            ;;
        arch)
            $SUDO pacman -Sy --noconfirm base-devel libx11 libxft libxinerama \
                xorg-server xorg-xinit terminus-font git
            ;;
        *)
            print_error "توزيعتك غير مدعومة"
            exit 1
            ;;
    esac
    print_success "تم تثبيت الحزم الأساسية"
}

# --- تثبيت أداوت suckless ---
install_suckless_tool() {
    local tool_name=$1
    local src_dir="$HOME/.local/src/$tool_name"
    local bin_path="/usr/local/bin/$tool_name"

    print_status "تثبيت $tool_name..."
    mkdir -p "$HOME/.local/src"

    if [ ! -d "$src_dir" ]; then
        if ! git clone "https://git.suckless.org/$tool_name" "$src_dir"; then
            print_error "فشل في استنساخ $tool_name"
            return 1
        fi
    else
        print_status "المجلد $src_dir موجود — تحديثه..."
        (cd "$src_dir" && git pull) || { print_warning "فشل تحديث $tool_name — سأتابع"; }
    fi

    (cd "$src_dir" && make clean 2>/dev/null || true)
    if ! (cd "$src_dir" && make); then
        print_error "فشل في ترجمة $tool_name"
        return 1
    fi

    local built_bin="$src_dir/$tool_name"
    if [ -f "$built_bin" ]; then
        $SUDO install -Dm755 "$built_bin" "$bin_path"
    else
        print_error "لم أجد الملف التنفيذي بعد البناء: $built_bin"
        return 1
    fi

    print_success "تم تثبيت $tool_name بنجاح."
}

install_suckless_stack() {
    mkdir -p "$HOME/.local/src"
    for tool in dwm st dmenu; do
        install_suckless_tool "$tool" || print_warning "تخطي $tool بسبب خطأ" 
    done
}

# --- إعداد .xinitrc ---
setup_xinitrc() {
    if [ -f "$HOME/.xinitrc" ]; then
        if ! grep -q "exec dwm" "$HOME/.xinitrc"; then
            echo "exec dwm" >> "$HOME/.xinitrc"
            print_status "تم إضافة 'exec dwm' إلى .xinitrc"
        else
            print_warning "'exec dwm' موجود بالفعل"
        fi
    else
        echo "exec dwm" > "$HOME/.xinitrc"
        print_status "تم إنشاء .xinitrc جديد"
    fi
    print_success "تم إعداد .xinitrc"
}

# --- تثبيت أدوات تطوير خفيفة ---
install_light_dev_tools() {
    print_status "تثبيت أدوات التطوير الخفيفة..."
    case "$DISTRO" in
        debian)
            local pkgs=(neovim micro tmux htop ripgrep fzf bat git curl wget)
            $SUDO apt install -y "${pkgs[@]}"
            ;;
        void)
            local pkgs=(neovim micro tmux htop ripgrep fzf bat git curl wget)
            $SUDO xbps-install -Sy "${pkgs[@]}"
            ;;
        arch)
            local pkgs=(neovim micro tmux htop ripgrep fzf bat git curl wget)
            $SUDO pacman -S --noconfirm "${pkgs[@]}"
            ;;
        *) print_warning "تجاهل تثبيت أدوات التطوير — توزيعتك غير مدعومة" ;;
    esac
    print_success "تم تثبيت أدوات التطوير الخفيفة"
}

# --- إعداد بايثون خفيف ---
setup_python_light() {
    print_status "تثبيت pip وأدوات بايثون الخفيفة..."
    case "$DISTRO" in
        debian)
            $SUDO apt install -y python3-pip python3-venv
            ;;
        void)
            $SUDO xbps-install -Sy python3-pip
            ;;
        arch)
            $SUDO pacman -S --noconfirm python-pip
            ;;
    esac

    if ! python3 -m pip --version &>/dev/null; then
        print_error "فشل تثبيت pip"
        exit 1
    fi

    python3 -m pip install --user virtualenv
    mkdir -p "$HOME/.local/bin"
    if ! grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' "$HOME/.bashrc" 2>/dev/null ; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    print_success "تم إعداد بايثون"
}

# --- إعداد Docker خفيف (اختياري) ---
setup_docker_light() {
    print_status "تثبيت Docker..."
    case "$DISTRO" in
        void)
            $SUDO xbps-install -Sy docker
            $SUDO usermod -aG docker "$SUDO_USER" 2>/dev/null || true
            ;;
        debian)
            $SUDO apt install -y docker.io
            $SUDO usermod -aG docker "$SUDO_USER" 2>/dev/null || true
            $SUDO systemctl enable --now docker || true
            ;;
        arch)
            $SUDO pacman -S --noconfirm docker
            $SUDO usermod -aG docker "$SUDO_USER" 2>/dev/null || true
            $SUDO systemctl enable --now docker || true
            ;;
    esac

    print_warning "أعد تسجيل الدخول لتفعيل Docker (logout/login)"
    print_success "تم تثبيت Docker"
}

# --- إعدادات .bashrc ---
setup_bashrc() {
    if ! grep -q "alias ll='ls -alF" "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" <<'EOF'

# === إعدادات خفيفة وسريعة ===
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias gs='git status'
alias gp='git push'
alias gc='git commit -m'
alias docker-clean='docker system prune -af'
EOF
    fi
    print_success "تم إضافة الإعدادات إلى .bashrc"
}

# --- التثبيت التلقائي الكامل ---
auto_install() {
    print_status "بدء التثبيت التلقائي..."

    detect_distro
    check_sudo
    check_dependencies
    backup_configs
    update_system
    install_base_packages
    install_suckless_stack
    setup_xinitrc
    install_light_dev_tools
    setup_python_light
    setup_bashrc

    print_status "هل تريد تثبيت Docker؟ (y/N)"
    read -r ans
    if [[ $ans =~ ^[Yy]$ ]]; then
        setup_docker_light
    fi

    print_success "✅ تم الإعداد التلقائي الكامل بنجاح!"
    echo -e "${YELLOW}⚠️  ملاحظات:${NC}"
    echo "1. أعد تشغيل الطرفية: exec bash"
    echo "2. لإعادة تسجيل الدخول: logout ثم login (لتفعيل Docker)"
    echo "3. ابدأ بـ: startx"
}

# --- التثبيت التفاعلي (يدوي) ---
interactive_install() {
    echo -e "${BLUE}--- مرحباً في سكربت الإعداد الخفيف ---${NC}"
    echo "الرجاء اختيار توزيعتك:"
    echo "1) Void Linux"
    echo "2) Debian"
    echo "3) Arch Linux"
    read -p "أدخل رقم التوزيعة (1/2/3): " choice
    case "$choice" in
        1) DISTRO="void" ;;
        2) DISTRO="debian" ;;
        3) DISTRO="arch" ;;
        *) print_error "اختيار غير صحيح"; exit 1 ;;
    esac

    check_sudo
    check_dependencies

    read -p "هل تريد تحديث النظام؟ (y/N): " ans
    [[ $ans =~ ^[Yy]$ ]] && update_system

    backup_configs
    install_base_packages

    for tool in dwm st dmenu; do
        read -p "تثبيت $tool؟ (y/N): " ans
        [[ $ans =~ ^[Yy]$ ]] && install_suckless_tool "$tool"
    done

    if [[ -f "$HOME/.local/src/dwm/dwm" || -f "/usr/local/bin/dwm" ]]; then
        read -p "إعداد .xinitrc لتشغيل dwm؟ (y/N): " ans
        [[ $ans =~ ^[Yy]$ ]] && setup_xinitrc
    fi

    read -p "تثبيت أدوات تطوير خفيفة (neovim, tmux, git...)? (y/N): " ans
    [[ $ans =~ ^[Yy]$ ]] && install_light_dev_tools

    read -p "تثبيت بايثون و virtualenv؟ (y/N): " ans
    [[ $ans =~ ^[Yy]$ ]] && setup_python_light

    read -p "تثبيت Docker؟ (y/N): " ans
    [[ $ans =~ ^[Yy]$ ]] && setup_docker_light

    read -p "إضافة إعدادات .bashrc؟ (y/N): " ans
    [[ $ans =~ ^[Yy]$ ]] && setup_bashrc

    print_success "✅ تم الإعداد بنجاح!"
    echo -e "${YELLOW}⚠️  لا تنسَ: source ~/.bashrc أو exec bash${NC}"
}

# --- نقطة الدخول الرئيسية ---
main() {
    : > "$LOG_FILE"

    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}     🚀 سكربت إعداد بيئة خفيفة مع suckless     ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo -e "${YELLOW}اختر وضع التثبيت:${NC}"
    echo "1) التلقائي (مُحسّن للجهاز الضعيف — بدون أسئلة)"
    echo "2) اليدوي (تحكم كامل — خطوة بخطوة)"
    echo ""

    read -p "أدخل اختيارك (1 أو 2): " mode

    case $mode in
        1)
            echo -e "${GREEN}→ تم اختيار: التلقائي${NC}"
            auto_install
            ;;
        2)
            echo -e "${GREEN}→ تم اختيار: اليدوي${NC}"
            interactive_install
            ;;
        *)
            print_error "اختيار غير صالح. يرجى اختيار 1 أو 2."
            exit 1
            ;;
    esac
}

main "$@"


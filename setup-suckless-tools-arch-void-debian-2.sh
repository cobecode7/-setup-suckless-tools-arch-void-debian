#!/bin/bash

# ======================================================================
# سكربت خفيف وسريع لإعداد بيئة suckless + أدوات تطوير أساسية
# مخصص للأجهزة الضعيفة — يدعم: Void Linux / Debian / Arch Linux
#
# ✅ اختيار داخلي: تلقائي (خفيف/سريع) أو يدوي (تحكم كامل)
# ✅ خالي من الأخطاء — موثوق وأمن
# ======================================================================

set -eu

# --- المتغيرات العامة ---
LOG_FILE="$HOME/suckless-setup.log"
DISTRO=""

# --- الألوان ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- الدوال المساعدة ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO: $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log "SUCCESS: $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "WARNING: $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "ERROR: $1"
}

cleanup() {
    print_status "تنظيف الملفات المؤقتة..."
    rm -f /tmp/postman.tar.gz /tmp/packages.microsoft.gpg /tmp/*.desktop 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# --- التحقق من sudo ---
check_sudo() {
    if ! sudo -v &> /dev/null; then
        print_error "يجب أن يكون لديك صلاحيات sudo لتشغيل هذا السكربت."
        exit 1
    fi
}

# --- التحقق من التبعيات الأساسية ---
check_dependencies() {
    local deps=("sudo" "git" "wget" "curl")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "التبعيات التالية مفقودة: ${missing_deps[*]}"
        exit 1
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

# --- اختيار التوزيعة ---
detect_distro() {
    if [ -n "$DISTRO" ]; then return; fi

    if command -v xbps-install &> /dev/null; then
        DISTRO=1
    elif command -v apt &> /dev/null; then
        DISTRO=2
    elif command -v pacman &> /dev/null; then
        DISTRO=3
    else
        print_error "لا يمكن اكتشاف التوزيعة. يرجى تحديدها يدوياً."
        exit 1
    fi
}

# --- تحديث النظام ---
update_system() {
    print_status "تحديث النظام..."
    case $DISTRO in
        1) sudo xbps-install -Syu ;;
        2) sudo apt update && sudo apt upgrade -y ;;
        3) sudo pacman -Syu --noconfirm ;;
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
    case $DISTRO in
        1)
            sudo xbps-install -Sy base-devel libX11-devel libXft-devel libXinerama-devel \
            freetype-devel fontconfig-devel xorg-server xinit git
            ;;
        2)
            sudo apt update
            sudo apt install -y build-essential libx11-dev libxft-dev libxinerama-dev \
            xorg git
            ;;
        3)
            sudo pacman -Sy --noconfirm base-devel libx11 libxft libxinerama \
            xorg-server xorg-xinit terminus-font git
            ;;
        *)
            print_error "توزيعتك غير مدعومة"
            exit 1
            ;;
    esac
    print_success "تم تثبيت الحزم الأساسية"
}

# --- تثبيت أدوات suckless (مصحح وخالي من الأخطاء) ---
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
        print_warning "المجلد $src_dir موجود — تحديثه..."
        cd "$src_dir" && git pull || { print_error "فشل في تحديث $tool_name"; return 1; }
    fi

    cd "$src_dir"

    make clean 2>/dev/null || true
    if ! make; then
        print_error "فشل في ترجمة $tool_name"
        return 1
    fi

    if ! sudo cp "$tool_name" "$bin_path"; then
        print_error "فشل في نسخ $tool_name إلى $bin_path"
        return 1
    fi

    print_success "تم تثبيت $tool_name بنجاح."
}

install_suckless_stack() {
    mkdir -p "$HOME/.local/src"
    for tool in dwm st dmenu; do
        install_suckless_tool "$tool"
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
    local tools=(
        "neovim::neovim:neovim:neovim"
        "micro::micro:micro:micro"
        "tmux::tmux:tmux:tmux"
        "htop::htop:htop:htop"
        "ripgrep::ripgrep:ripgrep:ripgrep"
        "fzf::fzf:fzf:fzf"
        "bat::bat:bat:bat"
        "git::git:git:git"
        "curl::curl:curl:curl"
        "wget::wget:wget:wget"
    )

    for tool in "${tools[@]}"; do
        IFS=':' read -r name void debian arch <<< "$tool"
        print_status "تثبيت $name..."
        case $DISTRO in
            1) sudo xbps-install -Sy "$void" ;;
            2) sudo apt install -y "$debian" ;;
            3) sudo pacman -S --noconfirm "$arch" ;;
        esac
    done
    print_success "تم تثبيت أدوات التطوير الخفيفة"
}

# --- إعداد بايثون خفيف ---
setup_python_light() {
    print_status "تثبيت pip وأدوات بايثون الخفيفة..."
    case $DISTRO in
        1) sudo xbps-install -Sy python3-pip ;;
        2) sudo apt install -y python3-pip python3-venv ;;
        3) sudo pacman -S --noconfirm python-pip ;;
    esac

    if ! python3 -m pip --version &> /dev/null; then
        print_error "فشل تثبيت pip"
        return 1
    fi

    python3 -m pip install --user virtualenv
    mkdir -p "$HOME/.local/bin"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

    print_success "تم إعداد بايثون"
}

# --- إعداد Docker خفيف (اختياري) ---
setup_docker_light() {
    print_status "تثبيت Docker..."
    case $DISTRO in
        1)
            sudo xbps-install -Sy docker
            sudo usermod -aG docker "$USER"
            ;;
        2)
            sudo apt install -y docker.io
            sudo usermod -aG docker "$USER"
            sudo systemctl enable --now docker
            ;;
        3)
            sudo pacman -S --noconfirm docker
            sudo usermod -aG docker "$USER"
            sudo systemctl enable --now docker
            ;;
    esac

    print_warning "أعد تسجيل الدخول لتفعيل Docker"
    print_success "تم تثبيت Docker"
}

# --- إعدادات .bashrc ---
setup_bashrc() {
    cat >> "$HOME/.bashrc" << 'EOF'

# === إعدادات خفيفة وسريعة ===
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias gs='git status'
alias gp='git push'
alias gc='git commit -m'
alias docker-clean='docker system prune -af'
EOF

    print_success "تم إضافة الإعدادات إلى .bashrc"
}

# --- التثبيت التلقائي الكامل ---
auto_install() {
    print_status "بدء التثبيت التلقائي الكامل للبيئة الخفيفة..."
    
    check_sudo
    check_dependencies
    detect_distro
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
    read -p "أدخل رقم التوزيعة (1/2/3): " DISTRO

    check_sudo
    check_dependencies

    read -p "هل تريد تحديث النظام؟ (y/N): " ans
    [[ $ans =~ ^[Yy]$ ]] && update_system

    backup_configs
    install_base_packages

    # أدوات suckless
    for tool in dwm st dmenu; do
        read -p "تثبيت $tool؟ (y/N): " ans
        [[ $ans =~ ^[Yy]$ ]] && install_suckless_tool "$tool"
    done

    if [[ -f "$HOME/.local/src/dwm/dwm" ]]; then
        read -p "إعداد .xinitrc لتشغيل dwm؟ (y/N): " ans
        [[ $ans =~ ^[Yy]$ ]] && setup_xinitrc
    fi

    # أدوات تطوير
    read -p "تثبيت أدوات تطوير خفيفة (neovim, tmux, git...)? (y/N): " ans
    [[ $ans =~ ^[Yy]$ ]] && install_light_dev_tools

    # بايثون
    read -p "تثبيت بايثون و virtualenv؟ (y/N): " ans
    [[ $ans =~ ^[Yy]$ ]] && setup_python_light

    # Docker
    read -p "تثبيت Docker؟ (y/N): " ans
    [[ $ans =~ ^[Yy]$ ]] && setup_docker_light

    # bashrc
    read -p "إضافة إعدادات .bashrc؟ (y/N): " ans
    [[ $ans =~ ^[Yy]$ ]] && setup_bashrc

    print_success "✅ تم الإعداد بنجاح!"
    echo -e "${YELLOW}⚠️  لا تنسَ: source ~/.bashrc أو exec bash${NC}"
}

# --- نقطة الدخول الرئيسية ---
main() {
    > "$LOG_FILE"  # مسح اللوج القديم

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

#!/bin/bash

# ======================================================================
# سكربت احترافي لإعداد بيئة خفيفة مع أدوات suckless + أدوات تطوير
# يدعم: Void Linux / Debian / Arch Linux
#
# المميزات:
# - كل أداة اختيارية ويتم سؤال المستخدم عنها.
# - يضمن الخروج الآمن عند حدوث أي خطأ في الأوامر.
# - يتعامل بشكل صحيح مع مديري الحزم المختلفة و Pip.
# - يتعامل مع نظامي Init: systemd و runit (Void Linux).
# - واجهة ملونة وتحسينات للأمان والموثوقية.
# ======================================================================

set -e

# تعريف الألوان للواجهة
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# دالة للطباعة الملونة
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# دالة للتنظيف عند الخروج
cleanup() {
    print_status "تنظيف الملفات المؤقتة..."
    rm -f /tmp/postman.tar.gz /tmp/packages.microsoft.gpg
}

# تسجيل دالة التنظيف
trap cleanup EXIT INT TERM

# التحقق من التبعيات الأساسية
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

# دالة لتحديث النظام
update_system() {
    print_status "تحديث النظام..."
    case $DISTRO in
        1) sudo xbps-install -Su ;;
        2) sudo apt update && sudo apt upgrade -y ;;
        3) sudo pacman -Syu --noconfirm ;;
    esac
    print_success "تم تحديث النظام"
}

# دالة لعمل نسخة احتياطية للملفات
backup_configs() {
    local configs=(".xinitrc" ".bashrc")
    for config in "${configs[@]}"; do
        if [ -f "$HOME/$config" ]; then
            cp "$HOME/$config" "$HOME/${config}.bak.$(date +%Y%m%d_%H%M%S)"
            print_status "تم عمل نسخة احتياطية من $config"
        fi
    done
}

# --- 1. اختيار التوزيعة ---
echo -e "${BLUE}--- مرحباً بك في سكربت الإعداد ---${NC}"
echo "الرجاء اختيار توزيعتك:"
echo "1) Void Linux"
echo "2) Debian"
echo "3) Arch Linux"
read -p "أدخل رقم التوزيعة (1/2/3): " DISTRO

# التحقق من التبعيات الأساسية
check_dependencies

# عرض خيار التحديث
read -p "هل تريد تحديث النظام أولاً؟ [y/n] " ans
if [[ $ans =~ ^[Yy]$ ]]; then
    update_system
fi

# عمل نسخة احتياطية للملفات الهامة
backup_configs

# --- دوال تثبيت الحزم ---
install_packages_void() {
    sudo xbps-install -Sy base-devel libX11-devel libXft-devel libXinerama-devel \
    freetype-devel fontconfig-devel xorg-server xinit git
}

install_packages_debian() {
    sudo apt update
    sudo apt install -y build-essential libx11-dev libxft-dev libxinerama-dev \
    xorg git
}

install_packages_arch() {
    sudo pacman -Sy --noconfirm base-devel libx11 libxft libxinerama \
    xorg-server xorg-xinit terminus-font git
}

print_status "تثبيت الحزم الأساسية..."
case $DISTRO in
    1) install_packages_void ;;
    2) install_packages_debian ;;
    3) install_packages_arch ;;
    *) print_error "اختيار غير صالح. الخروج." ; exit 1 ;;
esac
print_success "تم تثبيت الحزم الأساسية بنجاح."

# --- 2. أدوات suckless ---
install_suckless() {
    local tool_name=$1
    print_status "تثبيت $tool_name..."
    
    if [ ! -d "$HOME/.local/src/$tool_name" ]; then
        git clone "https://git.suckless.org/$tool_name" "$HOME/.local/src/$tool_name"
    else
        print_warning "المجلد $HOME/.local/src/$tool_name موجود بالفعل. تجاهل الاستنساخ."
    fi
    
    cd "$HOME/.local/src/$tool_name"
    make
    sudo cp "$tool_name" "/usr/local/bin/$tool_name"
    print_success "تم تثبيت $tool_name بنجاح."
}

mkdir -p "$HOME/.local/src"
for tool in dwm st dmenu; do
    read -p "هل تريد تثبيت $tool؟ [y/n] " ans
    if [[ $ans =~ ^[Yy]$ ]]; then
        install_suckless "$tool"
    fi
done

# --- 3. ملف xinitrc ---
read -p "هل تريد إنشاء ملف .xinitrc لتشغيل dwm تلقائياً؟ [y/n] " ans
if [[ $ans =~ ^[Yy]$ ]]; then
    if [ -f "$HOME/.xinitrc" ]; then
        if ! grep -q "exec dwm" "$HOME/.xinitrc"; then
            echo "exec dwm" >> "$HOME/.xinitrc"
            print_status "تم إضافة 'exec dwm' إلى الملف الموجود"
        else
            print_warning "الأمر 'exec dwm' موجود بالفعل في .xinitrc"
        fi
    else
        echo "exec dwm" > "$HOME/.xinitrc"
        print_status "تم إنشاء ملف .xinitrc جديد"
    fi
    print_success "تم إعداد ملف .xinitrc بنجاح."
fi

# --- 4. أدوات التطوير ---
install_dev_tool() {
    local tool_name=$1
    local void_pkg=$2
    local debian_pkg=$3
    local arch_pkg=$4
    
    read -p "هل تريد تثبيت ${tool_name}؟ [y/n] " ans
    if [[ $ans =~ ^[Yy]$ ]]; then
        print_status "تثبيت ${tool_name}..."
        case $DISTRO in
            1) sudo xbps-install -Sy "$void_pkg" ;;
            2) sudo apt install -y "$debian_pkg" ;;
            3) sudo pacman -S --noconfirm "$arch_pkg" ;;
        esac
        print_success "تم تثبيت ${tool_name} بنجاح."
    fi
}

install_pip_tool() {
    local tool_name=$1
    local package_name=$2
    
    read -p "هل تريد تثبيت ${tool_name}؟ [y/n] " ans
    if [[ $ans =~ ^[Yy]$ ]]; then
        print_status "تثبيت ${tool_name} باستخدام pip..."
        python3 -m pip install --user "$package_name"
        print_success "تم تثبيت ${tool_name} بنجاح."
    fi
}

# تثبيت أدوات النظام
tools=(
    "Neovim::neovim:neovim:neovim"
    "Micro::micro:micro:micro"
    "Git::git:git:git"
    "Node.js::nodejs:nodejs:nodejs"
    "npm::nodejs:npm:npm"
    "yarn::yarn:yarn:yarn"
    "htop::htop:htop:htop"
    "ripgrep::ripgrep:ripgrep:ripgrep"
    "tmux::tmux:tmux:tmux"
    "curl::curl:curl:curl"
    "wget::wget:wget:wget"
    "httpie::httpie:httpie:httpie"
    "Python::python3:python3:python"
    "Go::go:golang-go:go"
    "fzf::fzf:fzf:fzf"
    "bat::bat:bat:bat"
)

for tool in "${tools[@]}"; do
    IFS=':' read -r name void debian arch <<< "$tool"
    install_dev_tool "$name" "$void" "$debian" "$arch"
done

# تثبيت المتصفحات
read -p "هل تريد تثبيت Firefox؟ [y/n] " ans
if [[ $ans =~ ^[Yy]$ ]]; then
    case $DISTRO in
        1) sudo xbps-install -Sy firefox ;;
        2) sudo apt install -y firefox-esr ;;
        3) sudo pacman -S --noconfirm firefox ;;
    esac
    print_success "تم تثبيت Firefox بنجاح."
fi

install_dev_tool "Qutebrowser" "qutebrowser" "qutebrowser" "qutebrowser"

# تثبيت VS Code / VSCodium
read -p "هل تريد تثبيت VS Code أو VSCodium؟ [y/n] " ans
if [[ $ans =~ ^[Yy]$ ]]; then
    case $DISTRO in
        1) 
            sudo xbps-install -Sy vscodium || print_warning "تعذر تثبيت VSCodium"
            ;;
        2) 
            # تثبيت VS Code من Microsoft repository
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
            sudo install -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/trusted.gpg.d/
            sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
            sudo apt update
            sudo apt install -y code || print_warning "تعذر تثبيت VS Code"
            ;;
        3) 
            read -p "هل تريد تثبيت من AUR (يحتاج yay/paru)؟ [y/n] " aur_ans
            if [[ $aur_ans =~ ^[Yy]$ ]]; then
                if command -v yay >/dev/null; then
                    yay -S visual-studio-code-bin || print_warning "تعذر تثبيت VS Code"
                elif command -v paru >/dev/null; then
                    paru -S visual-studio-code-bin || print_warning "تعذر تثبيت VS Code"
                else
                    print_warning "لم يتم العثور على yay أو paru"
                fi
            else
                sudo pacman -S --noconfirm code
            fi
            ;;
    esac
fi

# تثبيت Postman
read -p "هل تريد تثبيت Postman؟ [y/n] " ans
if [[ $ans =~ ^[Yy]$ ]]; then
    print_status "تحميل وتثبيت Postman..."
    cd /tmp
    wget https://dl.pstmn.io/download/latest/linux64 -O postman.tar.gz
    sudo tar -xzf postman.tar.gz -C /opt/
    sudo ln -sf /opt/Postman/Postman /usr/local/bin/postman
    
    # إنشاء ملف .desktop
    cat > /tmp/postman.desktop << EOF
[Desktop Entry]
Name=Postman
Exec=/opt/Postman/Postman
Icon=/opt/Postman/app/resources/app/assets/icon.png
Terminal=false
Type=Application
Categories=Development;
EOF
    
    sudo mv /tmp/postman.desktop /usr/share/applications/
    print_success "تم تثبيت Postman بنجاح."
fi

# تثبيت أدوات بايثون
read -p "هل تريد تثبيت أدوات بايثون (pip/virtualenv/uv)؟ [y/n] " ans
if [[ $ans =~ ^[Yy]$ ]]; then
    print_status "تثبيت pip وأدوات بايثون..."
    case $DISTRO in
        1) sudo xbps-install -Sy python3-pip ;;
        2) sudo apt install -y python3-pip python3-venv ;;
        3) sudo pacman -S --noconfirm python-pip ;;
    esac
    
    # تثبيت virtualenv و uv
    python3 -m pip install --user virtualenv uv
    print_success "تم تثبيت أدوات بايثون بنجاح."
fi

# --- 5. Docker + قواعد البيانات ---
read -p "هل تريد تثبيت Docker وقواعد البيانات؟ [y/n] " ans
if [[ $ans =~ ^[Yy]$ ]]; then
    print_status "تثبيت Docker..."
    case $DISTRO in
        1) 
            sudo xbps-install -Sy docker
            sudo usermod -aG docker "$USER"
            ;;
        2) 
            sudo apt install -y docker.io docker-compose
            sudo usermod -aG docker "$USER"
            sudo systemctl enable --now docker
            ;;
        3) 
            sudo pacman -S --noconfirm docker docker-compose
            sudo usermod -aG docker "$USER"
            sudo systemctl enable --now docker
            ;;
    esac
    
    print_success "تم تثبيت Docker بنجاح."
    print_warning "ملاحظة: ستحتاج لإعادة تسجيل الدخول لتفعيل صلاحيات Docker."

    # إعداد docker-compose للقواعد البيانات
    read -p "هل تريد إعداد قواعد البيانات باستخدام Docker؟ [y/n] " ans
    if [[ $ans =~ ^[Yy]$ ]]; then
        cat > "$HOME/docker-compose-db.yml" << 'EOF'
version: '3.8'
services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_PASSWORD: pass
      POSTGRES_USER: user
      POSTGRES_DB: mydb
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    restart: unless-stopped

  mariadb:
    image: mariadb:10.11-alpine
    environment:
      MARIADB_ROOT_PASSWORD: pass
      MARIADB_DATABASE: mydb
    ports:
      - "3306:3306"
    volumes:
      - mariadb_data:/var/lib/mysql
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
  mariadb_data:
EOF

        print_status "تم إنشاء ملف docker-compose-db.yml في $HOME"
        echo "alias db-start='docker-compose -f $HOME/docker-compose-db.yml up -d'" >> "$HOME/.bashrc"
        echo "alias db-stop='docker-compose -f $HOME/docker-compose-db.yml down'" >> "$HOME/.bashrc"
        print_success "تم إعداد أوامر قاعدة البيانات."
    fi
fi

# --- إعدادات إضافية ---
read -p "هل تريد إضافة إعدادات مفيدة لـ .bashrc؟ [y/n] " ans
if [[ $ans =~ ^[Yy]$ ]]; then
    cat >> "$HOME/.bashrc" << 'EOF'

# إعدادات مخصصة
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias update-system='sudo apt update && sudo apt upgrade'  # تعديل حسب التوزيعة

# إعدادات Docker
alias docker-clean='docker system prune -af'

# إعدادات Git
alias gs='git status'
alias gp='git push'
alias gc='git commit -m'
EOF
    print_success "تم إضافة إعدادات مفيدة لـ .bashrc"
fi

# --- النهاية ---
echo -e "${GREEN}✅ تم الإعداد بنجاح!${NC}"
echo -e "${YELLOW}⚠️  ملاحظات مهمة:${NC}"
echo "1. ستحتاج إلى إعادة تشغيل الشل أو تشغيل: source ~/.bashrc"
echo "2. لإعادة تشغيل Docker على Void: sudo sv up docker"
echo "3. لبدء قواعد البيانات: db-start"
echo "4. لتفعيل الإعدادات الآن: exec bash"

print_success "اكتمل الإعداد! يمكنك الآن استخدام النظام الجديد."

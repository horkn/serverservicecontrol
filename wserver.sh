#!/bin/bash

# Ubuntu 24.04 Modüler Kurulum Betiği - Seçmeli Servis Kurulumu ve Yönetim

# Renk tanımlamaları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Kök kullanıcı kontrolü
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Hata: Lütfen bu betiği 'sudo' ile çalıştırın: sudo $0${NC}"
    exit 1
fi

# Fonksiyonlar
print_header() {
    echo -e "${GREEN}"
    echo "=========================================="
    echo "   $1"
    echo "=========================================="
    echo -e "${NC}"
}

print_info() {
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

ask_yes_no() {
    while true; do
        read -p "$1 (E/H): " yn
        case $yn in
            [Ee]* ) return 0;;
            [Hh]* ) return 1;;
            * ) echo "Lütfen E (Evet) veya H (Hayır) giriniz.";;
        esac
    done
}

ask_password() {
    while true; do
        read -s -p "$1: " password
        echo
        if [ -z "$password" ]; then
            echo "Şifre boş olamaz. Lütfen tekrar deneyin."
            continue
        fi
        read -s -p "Şifreyi tekrar girin: " password_confirm
        echo
        if [ "$password" != "$password_confirm" ]; then
            echo "Şifreler eşleşmiyor. Lütfen tekrar deneyin."
        else
            eval "$2='$password'"
            break
        fi
    done
}

ask_input() {
    local prompt=$1
    local var_name=$2
    local default_value=$3
    local input
    
    if [ -n "$default_value" ]; then
        read -p "$prompt [$default_value]: " input
        eval "$var_name=\${input:-\$default_value}"
    else
        while true; do
            read -p "$prompt: " input
            if [ -n "$input" ]; then
                eval "$var_name='$input'"
                break
            else
                echo "Bu alan boş bırakılamaz. Lütfen bir değer girin."
            fi
        done
    fi
}

select_framework() {
    echo -e "${CYAN}Desteklenen Framework'ler:${NC}"
    echo "1) Laravel (public/)"
    echo "2) Symfony (public/)"
    echo "3) CodeIgniter (public/)"
    echo "4) WordPress"
    echo "5) Vanilla PHP"
    echo "6) Özel Dizin"
    
    while true; do
        read -p "Framework seçin (1-6) [1]: " choice
        case $choice in
            1|"") 
                FRAMEWORK="laravel"
                WEB_ROOT="public"
                return 0
                ;;
            2) 
                FRAMEWORK="symfony"
                WEB_ROOT="public"
                return 0
                ;;
            3) 
                FRAMEWORK="codeigniter"
                WEB_ROOT="public"
                return 0
                ;;
            4) 
                FRAMEWORK="wordpress"
                WEB_ROOT=""
                return 0
                ;;
            5) 
                FRAMEWORK="vanilla"
                WEB_ROOT=""
                return 0
                ;;
            6) 
                read -p "Özel web root dizinini girin (örn: public, web, app/public): " custom_root
                FRAMEWORK="custom"
                WEB_ROOT="$custom_root"
                return 0
                ;;
            *) 
                echo "Lütfen 1-6 arasında bir seçenek girin."
                ;;
        esac
    done
}

# Servis kurulum fonksiyonları
install_nginx() {
    print_info "Nginx kuruluyor..."
    apt install -y nginx
    systemctl enable nginx
    
    # Nginx kurulumundan sonra PHP kontrolü yap
    if systemctl is-active --quiet nginx || systemctl start nginx; then
        print_success "Nginx kurulumu tamamlandı"
        
        # PHP kurulu mu kontrol et (birden fazla yöntem dene)
        local php_version=""
        
        # Yöntem 1: php -v komutundan versiyon al
        if command -v php &> /dev/null; then
            php_version=$(php -v 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
            if [ -n "$php_version" ]; then
                print_info "PHP CLI'den versiyon tespit edildi: $php_version"
            fi
        fi
        
        # Yöntem 2: /usr/bin/php* dosyalarından versiyon bul
        if [ -z "$php_version" ]; then
            for php_bin in /usr/bin/php[0-9]* /usr/bin/php[0-9]*.[0-9]*; do
                if [ -f "$php_bin" ] && [ -x "$php_bin" ]; then
                    php_version=$(basename "$php_bin" | sed 's/php//' | grep -oE "^[0-9]+\.[0-9]+")
                    if [ -n "$php_version" ]; then
                        print_info "PHP binary'den versiyon tespit edildi: $php_version"
                        break
                    fi
                fi
            done
        fi
        
        # Yöntem 3: PHP-FPM servislerinden versiyon bul
        if [ -z "$php_version" ]; then
            local php_fpm_version=$(systemctl list-units --type=service --all 2>/dev/null | grep "php.*-fpm" | head -1 | sed 's/.*php\([0-9.]*\)-fpm.*/\1/' | grep -E "^[0-9]+\.[0-9]+" || echo "")
            if [ -n "$php_fpm_version" ]; then
                php_version="$php_fpm_version"
                print_info "PHP-FPM servisinden versiyon tespit edildi: $php_version"
            fi
        fi
        
        # Yöntem 4: dpkg ile kurulu PHP paketlerini kontrol et
        if [ -z "$php_version" ]; then
            local php_package=$(dpkg -l 2>/dev/null | grep -E "^ii.*php[0-9]+\.[0-9]+-fpm" | head -1 | awk '{print $2}' | sed 's/php\([0-9.]*\)-fpm.*/\1/' || echo "")
            if [ -n "$php_package" ]; then
                php_version="$php_package"
                print_info "Kurulu paketlerden versiyon tespit edildi: $php_version"
            fi
        fi
        
        if [ -n "$php_version" ]; then
            print_info "Kurulu PHP versiyonu tespit edildi: $php_version"
            print_info "Nginx yapılandırmaları PHP için kontrol ediliyor..."
            
            # Mevcut Nginx yapılandırmalarını PHP için güncelle
            update_nginx_for_php $php_version
        else
            print_info "PHP kurulu değil veya tespit edilemedi, Nginx yapılandırması PHP olmadan hazır"
        fi
    else
        print_warning "Nginx kuruldu ancak başlatılamadı"
    fi
}

install_php() {
    local version=$1
    print_info "PHP $version kuruluyor..."
    
    # Mevcut PHP kurulumunu kontrol et
    local existing_php_cli=false
    local existing_php_fpm=false
    local existing_php_version=""
    
    if command -v php &> /dev/null; then
        existing_php_cli=true
        existing_php_version=$(php -v 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
        print_info "Mevcut PHP CLI kurulumu tespit edildi: $existing_php_version"
    fi
    
    # PHP-FPM servislerini kontrol et
    local php_fpm_services=$(systemctl list-units --type=service --all 2>/dev/null | grep "php.*-fpm" | awk '{print $1}' || echo "")
    if [ -n "$php_fpm_services" ]; then
        existing_php_fpm=true
        print_info "Mevcut PHP-FPM servisleri tespit edildi"
    fi
    
    # Eğer sadece PHP-CLI kuruluysa ve PHP-FPM yoksa
    if [ "$existing_php_cli" = true ] && [ "$existing_php_fpm" = false ]; then
        print_warning "Sadece PHP-CLI kurulu, PHP-FPM bulunamadı!"
        print_info "Nginx ile çalışmak için PHP-FPM gereklidir."
        
        if ask_yes_no "PHP-CLI'yi kaldırıp PHP-FPM ile yeniden kurmak ister misiniz?"; then
            print_info "Mevcut PHP-CLI paketleri kaldırılıyor..."
            
            # PHP-CLI paketlerini kaldır
            apt remove -y php*cli php*common 2>/dev/null || true
            apt autoremove -y
            
            print_info "PHP-CLI kaldırıldı, PHP-FPM kurulumuna devam ediliyor..."
        else
            print_info "PHP-CLI korunuyor, PHP-FPM ekleniyor..."
        fi
    fi
    
    # Gerekli paketlerin kurulu olduğundan emin ol
    if ! command -v add-apt-repository &> /dev/null; then
        print_info "software-properties-common kuruluyor..."
        apt update
        apt install -y software-properties-common
    fi
    
    # PPA ekleme (Ubuntu 24.04 için güncellenmiş yöntem)
    print_info "PHP repository ekleniyor..."
    
    # Önce PPA'nın zaten ekli olup olmadığını kontrol et
    if grep -q "ondrej/php" /etc/apt/sources.list.d/*.list 2>/dev/null || \
       grep -q "ondrej/php" /etc/apt/sources.list 2>/dev/null; then
        print_info "PHP PPA zaten ekli"
    else
        # PPA ekleme işlemi
        if ! add-apt-repository -y ppa:ondrej/php 2>&1; then
            print_warning "PPA ekleme başarısız, alternatif yöntem deneniyor..."
            # Alternatif: Manuel repository ekleme (Sury repository)
            apt install -y lsb-release ca-certificates apt-transport-https gnupg2
            
            # GPG key ekle
            if ! wget -qO - https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/deb.sury.org-php.gpg 2>/dev/null; then
                print_error "PHP repository GPG key eklenemedi!"
                return 1
            fi
            
            # Repository ekle
            echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
            print_info "Alternatif PHP repository eklendi"
        else
            print_success "PHP PPA başarıyla eklendi"
        fi
    fi
    
    # APT güncelleme
    print_info "Paket listesi güncelleniyor..."
    apt update
    
    if [ $? -ne 0 ]; then
        print_error "APT güncelleme başarısız oldu!"
        return 1
    fi
    
    # PHP versiyonunu kontrol et
    print_info "PHP $version paketi kontrol ediliyor..."
    if ! apt-cache search "^php$version-fpm" 2>/dev/null | grep -q "php$version-fpm"; then
        print_warning "PHP $version paketi bulunamadı, mevcut versiyonlar kontrol ediliyor..."
        print_info "Mevcut PHP versiyonları:"
        apt-cache search php | grep -E "^php[0-9]+\.[0-9]+-fpm" | head -5 || \
        apt-cache search php | grep "fpm" | grep -E "php[0-9]" | head -5
        
        if ask_yes_no "PHP $version bulunamadı. Mevcut bir versiyonla devam etmek ister misiniz?"; then
            read -p "Kullanılacak PHP versiyonunu girin (örn: 8.3, 8.4): " version
        else
            print_error "PHP kurulumu iptal edildi"
            return 1
        fi
    fi
    
    # Temel PHP paketleri (PHP-FPM öncelikli)
    print_info "PHP-FPM ve temel paketler kuruluyor..."
    
    # Önce PHP-FPM'i kur (Nginx için gerekli)
    print_info "PHP-FPM kuruluyor (Nginx için gerekli)..."
    apt install -y php$version-fpm
    
    if [ $? -ne 0 ]; then
        print_error "PHP-FPM kurulumu başarısız oldu!"
        return 1
    fi
    
    # PHP-FPM başarıyla kuruldu, şimdi diğer paketleri kur
    print_info "PHP eklentileri ve CLI kuruluyor..."
    
    # Temel paketler listesi
    local php_packages="php$version-cli php$version-common php$version-mysql php$version-zip php$version-gd php$version-mbstring php$version-curl php$version-xml php$version-bcmath php$version-opcache php$version-intl"
    
    # JSON paketi (bazı versiyonlarda ayrı paket olarak gelmeyebilir)
    if apt-cache search "php$version-json" 2>/dev/null | grep -q "php$version-json"; then
        php_packages="$php_packages php$version-json"
    fi
    
    # Paketleri kur
    if ! apt install -y $php_packages; then
        print_warning "Bazı PHP paketleri kurulamadı, eksik paketler kontrol ediliyor..."
        
        # Her paketi tek tek kur (hata toleranslı)
        for pkg in $php_packages; do
            if apt install -y $pkg 2>/dev/null; then
                print_success "$pkg kuruldu"
            else
                print_warning "$pkg kurulamadı (atlanıyor)"
            fi
        done
    else
        print_success "Temel PHP paketleri kuruldu"
    fi
    
    # PHP-FPM'in düzgün kurulduğunu doğrula
    if ! systemctl list-unit-files | grep -q "php$version-fpm.service"; then
        print_error "PHP-FPM servisi bulunamadı! Kurulum başarısız olmuş olabilir."
        return 1
    fi
    
    print_success "PHP-FPM başarıyla kuruldu"
    
    # Tüm gerekli eklentiler (zorunlu)
    print_info "Tüm gerekli PHP eklentileri kuruluyor..."
    local required_packages="php$version-imagick php$version-soap php$version-xsl php$version-tidy php$version-imap php$version-gmp php$version-sodium php$version-pdo php$version-sqlite3 php$version-pgsql php$version-ldap php$version-readline php$version-pcntl"
    
    for pkg in $required_packages; do
        if apt-cache search "$pkg" 2>/dev/null | grep -q "$pkg"; then
            if apt install -y $pkg 2>/dev/null; then
                print_success "$pkg kuruldu"
            else
                print_warning "$pkg kurulamadı, tekrar deneniyor..."
                # Broken dependencies düzelt
                apt --fix-broken install -y 2>/dev/null || true
                # Tekrar dene
                if apt install -y $pkg 2>/dev/null; then
                    print_success "$pkg kuruldu (ikinci deneme)"
                else
                    print_error "$pkg kurulamadı!"
                fi
            fi
        else
            print_warning "$pkg paketi repository'de bulunamadı"
        fi
    done
    
    # Framework'e özel ek paketler
    case $FRAMEWORK in
        "laravel")
            print_info "Laravel için ek paketler kuruluyor..."
            apt install -y php$version-redis php$version-memcached php$version-pcntl \
                php$version-pdo php$version-sqlite3 2>/dev/null || print_warning "Bazı Laravel paketleri kurulamadı"
            ;;
        "symfony")
            print_info "Symfony için ek paketler kuruluyor..."
            apt install -y php$version-redis php$version-memcached php$version-pdo \
                php$version-pdo-mysql php$version-phar 2>/dev/null || \
            apt install -y php$version-redis php$version-memcached php$version-pdo \
                php$version-pdo_mysql php$version-phar 2>/dev/null || \
            print_warning "Bazı Symfony paketleri kurulamadı"
            ;;
        "codeigniter")
            print_info "CodeIgniter için ek paketler kuruluyor..."
            apt install -y php$version-pdo php$version-pdo-mysql php$version-phar 2>/dev/null || \
            apt install -y php$version-pdo php$version-pdo_mysql php$version-phar 2>/dev/null || \
            print_warning "Bazı CodeIgniter paketleri kurulamadı"
            ;;
    esac
    
    # PHP-FPM pool yapılandırmasını kontrol et ve düzenle
    print_info "PHP-FPM pool yapılandırması kontrol ediliyor..."
    local php_fpm_pool="/etc/php/$version/fpm/pool.d/www.conf"
    
    if [ -f "$php_fpm_pool" ]; then
        # Pool yapılandırmasının doğru olduğundan emin ol
        # listen ayarını kontrol et (Unix socket olmalı)
        if ! grep -q "^listen = /var/run/php/php$version-fpm.sock" "$php_fpm_pool"; then
            print_info "PHP-FPM pool yapılandırması güncelleniyor..."
            
            # listen ayarını Unix socket olarak ayarla
            if grep -q "^listen = " "$php_fpm_pool"; then
                sed -i "s|^listen = .*|listen = /var/run/php/php$version-fpm.sock|" "$php_fpm_pool"
            else
                sed -i "/^\[www\]/a listen = /var/run/php/php$version-fpm.sock" "$php_fpm_pool"
            fi
            
            # listen.owner ve listen.group ayarlarını kontrol et
            if ! grep -q "^listen.owner = www-data" "$php_fpm_pool"; then
                sed -i "/^listen = /a listen.owner = www-data" "$php_fpm_pool"
            fi
            if ! grep -q "^listen.group = www-data" "$php_fpm_pool"; then
                sed -i "/^listen.owner = /a listen.group = www-data" "$php_fpm_pool"
            fi
            if ! grep -q "^listen.mode = 0660" "$php_fpm_pool"; then
                sed -i "/^listen.group = /a listen.mode = 0660" "$php_fpm_pool"
            fi
            
            print_success "PHP-FPM pool yapılandırması güncellendi"
        else
            print_info "PHP-FPM pool yapılandırması doğru"
        fi
    else
        print_warning "PHP-FPM pool yapılandırma dosyası bulunamadı: $php_fpm_pool"
    fi
    
    # PHP-FPM servisini etkinleştir ve başlat
    print_info "PHP-FPM servisi yapılandırılıyor..."
    
    if systemctl list-unit-files | grep -q "php$version-fpm.service"; then
        systemctl enable php$version-fpm
        
        # PHP-FPM servisini başlat
        if systemctl start php$version-fpm; then
            sleep 2  # Servisin başlaması için kısa bir bekleme
            
            if systemctl is-active --quiet php$version-fpm; then
                print_success "PHP $version kurulumu tamamlandı ve PHP-FPM servisi başlatıldı"
                echo -e "${GREEN}PHP Versiyonu:${NC} $(php$version -v | head -1 | cut -d' ' -f2)"
                echo -e "${GREEN}PHP-FPM Durumu:${NC} $(systemctl is-active php$version-fpm)"
                echo -e "${GREEN}PHP-FPM Socket:${NC} /var/run/php/php$version-fpm.sock"
                
                # Socket dosyasının varlığını kontrol et
                if [ -S "/var/run/php/php$version-fpm.sock" ]; then
                    print_success "PHP-FPM socket dosyası oluşturuldu"
                else
                    print_warning "PHP-FPM socket dosyası henüz oluşmadı, birkaç saniye bekleyin"
                fi
                
                # Kurulu eklentileri kontrol et ve eksik olanları kur
                print_info "Kurulu PHP eklentileri kontrol ediliyor..."
                check_and_install_missing_php_extensions $version
                
                # PHP eklenti yükleme sırasını düzelt
                fix_php_extension_loading_order $version
                
                # Mevcut Nginx yapılandırmalarını PHP için güncelle
                update_nginx_for_php $version
            else
                print_warning "PHP $version kuruldu ancak PHP-FPM servisi başlatılamadı"
                print_info "Servis durumunu kontrol edin: systemctl status php$version-fpm"
                print_info "Log dosyasını kontrol edin: journalctl -u php$version-fpm -n 50"
            fi
        else
            print_error "PHP-FPM servisi başlatılamadı!"
            print_info "Hata detayları için: systemctl status php$version-fpm"
            return 1
        fi
    else
        print_error "PHP-FPM servisi bulunamadı!"
        print_info "Kurulu paketleri kontrol edin: dpkg -l | grep php$version-fpm"
        return 1
    fi
}

fix_php_extension_loading_order() {
    local version=$1
    
    print_info "PHP eklenti yükleme sırası düzeltiliyor..."
    
    # PHP mods-available dizini
    local mods_dir="/etc/php/$version/mods-available"
    
    if [ ! -d "$mods_dir" ]; then
        print_warning "PHP mods dizini bulunamadı: $mods_dir"
        return 1
    fi
    
    # Kritik: Çift yükleme sorununu çöz
    print_info "Çift yükleme sorunları kontrol ediliyor..."
    
    # pdo_mysql.ini içeriğini kontrol et ve düzelt
    if [ -f "$mods_dir/pdo_mysql.ini" ]; then
        local pdo_mysql_content=$(cat "$mods_dir/pdo_mysql.ini")
        
        if echo "$pdo_mysql_content" | grep -q "^extension=pdo_mysql.so"; then
            print_info "pdo_mysql.ini düzeltiliyor..."
            cp "$mods_dir/pdo_mysql.ini" "$mods_dir/pdo_mysql.ini.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            
            cat > "$mods_dir/pdo_mysql.ini" <<'EOF'
; configuration for php mysql module
; priority=30
; Depends: pdo, mysqlnd
EOF
        fi
    fi
    
    # Tüm conf.d dizinlerindeki linkleri temizle
    for conf_dir in "/etc/php/$version/cli/conf.d" "/etc/php/$version/fpm/conf.d"; do
        if [ -d "$conf_dir" ]; then
            print_info "Temizleniyor: $conf_dir"
            
            # Tüm ilgili linkleri kaldır (çift yüklemeyi önlemek için)
            find "$conf_dir" -type l -name "*mysqlnd*" -delete 2>/dev/null || true
            find "$conf_dir" -type l -name "*pdo.ini" -delete 2>/dev/null || true
            find "$conf_dir" -type l -name "*mysqli*" -delete 2>/dev/null || true
            find "$conf_dir" -type l -name "*pdo_mysql*" -delete 2>/dev/null || true
            find "$conf_dir" -type l -name "*dom.ini" -delete 2>/dev/null || true
            find "$conf_dir" -type l -name "*xml.ini" -delete 2>/dev/null || true
            find "$conf_dir" -type l -name "*xsl*" -delete 2>/dev/null || true
        fi
    done
    
    # pdo_mysql ve pdo modüllerini önce devre dışı bırak (temiz başlangıç)
    print_info "Modüller devre dışı bırakılıyor..."
    phpdismod -v $version pdo_mysql 2>/dev/null || true
    phpdismod -v $version pdo 2>/dev/null || true
    phpdismod -v $version mysqli 2>/dev/null || true
    phpdismod -v $version mysqlnd 2>/dev/null || true
    phpdismod -v $version dom 2>/dev/null || true
    phpdismod -v $version xml 2>/dev/null || true
    phpdismod -v $version xsl 2>/dev/null || true
    
    # Şimdi doğru sırayla etkinleştir
    print_info "Modüller doğru sırayla etkinleştiriliyor..."
    
    # 1. mysqlnd (en önce)
    phpenmod -v $version mysqlnd 2>/dev/null || true
    
    # 2. pdo (mysqlnd'den sonra)
    phpenmod -v $version pdo 2>/dev/null || true
    
    # 3. dom ve xml (xsl için)
    phpenmod -v $version dom 2>/dev/null || true
    phpenmod -v $version xml 2>/dev/null || true
    
    # 4. mysqli (mysqlnd'ye bağımlı)
    phpenmod -v $version mysqli 2>/dev/null || true
    
    # 5. xsl (dom/xml'e bağımlı)
    phpenmod -v $version xsl 2>/dev/null || true
    
    # 6. pdo_mysql DEVRE DIŞI KALIYOR (sorun kaynağı)
    
    # Manuel olarak doğru sırayla linkler oluştur (phpenmod bazen yanlış sıralama yapabiliyor)
    for conf_dir in "/etc/php/$version/cli/conf.d" "/etc/php/$version/fpm/conf.d"; do
        if [ -d "$conf_dir" ]; then
            print_info "Yeniden yapılandırılıyor: $conf_dir"
            
            # Önce tüm linkleri temizle
            find "$conf_dir" -type l \( -name "*mysqlnd*" -o -name "*pdo.ini" -o -name "*mysqli*" -o -name "*pdo_mysql*" -o -name "*dom.ini" -o -name "*xml.ini" -o -name "*xsl*" \) -delete 2>/dev/null || true
            
            # Doğru sırayla yeniden oluştur
            if [ -f "$mods_dir/mysqlnd.ini" ]; then
                ln -sf "$mods_dir/mysqlnd.ini" "$conf_dir/10-mysqlnd.ini"
            fi
            
            if [ -f "$mods_dir/pdo.ini" ]; then
                ln -sf "$mods_dir/pdo.ini" "$conf_dir/15-pdo.ini"
            fi
            
            if [ -f "$mods_dir/dom.ini" ]; then
                ln -sf "$mods_dir/dom.ini" "$conf_dir/15-dom.ini"
            fi
            
            if [ -f "$mods_dir/xml.ini" ]; then
                ln -sf "$mods_dir/xml.ini" "$conf_dir/15-xml.ini"
            fi
            
            if [ -f "$mods_dir/mysqli.ini" ]; then
                ln -sf "$mods_dir/mysqli.ini" "$conf_dir/20-mysqli.ini"
            fi
            
            if [ -f "$mods_dir/xsl.ini" ]; then
                ln -sf "$mods_dir/xsl.ini" "$conf_dir/30-xsl.ini"
            fi
            
            # pdo_mysql linklerini KALDIR (varsa)
            rm -f "$conf_dir"/*pdo_mysql* 2>/dev/null || true
        fi
    done
    
    print_success "PHP eklenti yükleme sırası düzeltildi"
    print_info "Etkin modüller: mysqlnd, pdo, dom, xml, mysqli, xsl"
    print_info "Devre dışı: pdo_mysql (sorun kaynağı, mysqli kullanılacak)"
    
    return 0
}

check_and_install_missing_php_extensions() {
    local version=$1
    
    print_info "PHP eklentileri kontrol ediliyor..."
    
    # Tüm gerekli eklentiler listesi
    local required_extensions=(
        "curl" "gd" "mbstring" "mysql" "mysqli" "pdo" "pdo_mysql" 
        "zip" "xml" "intl" "opcache" "bcmath" "soap" "xsl" 
        "tidy" "imap" "gmp" "sodium" "imagick" "openssl" 
        "fileinfo" "exif" "sockets" "pcntl" "gettext" "shmop"
        "phar" "json" "readline" "tokenizer" "iconv" "ctype"
        "simplexml" "xmlreader" "xmlwriter" "redis" "memcached"
    )
    
    # Kurulu eklentileri al
    local installed_extensions=$(php$version -m 2>/dev/null | tr '[:upper:]' '[:lower:]')
    
    # Eksik eklentileri tespit et
    local missing_extensions=()
    local missing_count=0
    
    for ext in "${required_extensions[@]}"; do
        # Eklenti adını küçük harfe çevir
        local ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        
        # Eklenti kurulu mu kontrol et
        if ! echo "$installed_extensions" | grep -qi "^${ext_lower}$"; then
            missing_extensions+=("$ext_lower")
            ((missing_count++))
        fi
    done
    
    if [ $missing_count -eq 0 ]; then
        print_success "Tüm gerekli PHP eklentileri kurulu"
        return 0
    fi
    
    print_warning "$missing_count eksik PHP eklentisi tespit edildi"
    print_info "Eksik eklentiler: ${missing_extensions[*]}"
    print_info "Eksik eklentiler kuruluyor..."
    
    # Eksik eklentileri kur
    local installed_count=0
    local failed_count=0
    
    for ext in "${missing_extensions[@]}"; do
        # Paket adını belirle (bazı eklentiler farklı paket adlarına sahip)
        local pkg_name="php$version-$ext"
        
        # Özel paket adları
        case $ext in
            "mysqli"|"pdo_mysql")
                pkg_name="php$version-mysql"
                ;;
            "pdo")
                # PDO genellikle php-common ile gelir, ayrı paket olmayabilir
                if apt-cache search "php$version-pdo" 2>/dev/null | grep -q "php$version-pdo"; then
                    pkg_name="php$version-pdo"
                else
                    print_info "PDO zaten php-common ile kurulu olmalı, atlanıyor"
                    continue
                fi
                ;;
            "openssl")
                # OpenSSL genellikle php-common ile gelir
                if apt-cache search "php$version-openssl" 2>/dev/null | grep -q "php$version-openssl"; then
                    pkg_name="php$version-openssl"
                else
                    print_info "OpenSSL zaten php-common ile kurulu olmalı, atlanıyor"
                    continue
                fi
                ;;
            "fileinfo"|"exif"|"sockets"|"gettext"|"shmop"|"tokenizer"|"iconv"|"ctype"|"simplexml"|"xmlreader"|"xmlwriter")
                # Bu eklentiler genellikle php-common veya php-xml ile gelir ama etkinleştirilmemiş olabilir
                print_info "$ext eklentisi kontrol ediliyor..."
                
                # Önce etkinleştirmeyi dene
                if [ -f "/etc/php/$version/mods-available/$ext.ini" ]; then
                    phpenmod -v $version $ext 2>/dev/null || true
                else
                    # .ini dosyası yoksa oluştur
                    echo "; configuration for php $ext module" > "/etc/php/$version/mods-available/$ext.ini"
                    echo "extension=$ext.so" >> "/etc/php/$version/mods-available/$ext.ini"
                    phpenmod -v $version $ext 2>/dev/null || true
                fi
                
                # Hala yoksa ilgili paketi yeniden kur
                if ! php$version -m 2>/dev/null | grep -qi "^$ext$"; then
                    # simplexml, xmlreader, xmlwriter için php-xml paketi gerekli
                    if [ "$ext" = "simplexml" ] || [ "$ext" = "xmlreader" ] || [ "$ext" = "xmlwriter" ]; then
                        print_info "php$version-xml yeniden kuruluyor ($ext için)..."
                        apt install --reinstall -y php$version-xml 2>/dev/null || true
                    else
                        print_info "php$version-common yeniden kuruluyor ($ext için)..."
                        apt install --reinstall -y php$version-common 2>/dev/null || true
                    fi
                    ((installed_count++))
                fi
                continue
                ;;
            "phar")
                # phar genellikle php-common ile gelir ama etkinleştirilmemiş olabilir
                print_info "phar eklentisi kontrol ediliyor..."
                
                if [ -f "/etc/php/$version/mods-available/phar.ini" ]; then
                    phpenmod -v $version phar 2>/dev/null || true
                else
                    # phar.ini yoksa oluştur
                    echo "; configuration for php phar module" > "/etc/php/$version/mods-available/phar.ini"
                    echo "extension=phar.so" >> "/etc/php/$version/mods-available/phar.ini"
                    phpenmod -v $version phar 2>/dev/null || true
                fi
                
                # Hala yoksa php-common'ı yeniden kur
                if ! php$version -m 2>/dev/null | grep -qi "^phar$"; then
                    print_info "php$version-common yeniden kuruluyor (phar için)..."
                    apt install --reinstall -y php$version-common 2>/dev/null || true
                    ((installed_count++))
                fi
                continue
                ;;
            "json")
                # json genellikle php-common ile gelir
                if apt-cache search "php$version-json" 2>/dev/null | grep -q "php$version-json"; then
                    pkg_name="php$version-json"
                else
                    print_info "json zaten php-common ile kurulu olmalı, atlanıyor"
                    continue
                fi
                ;;
            "readline")
                # readline genellikle php-cli ile gelir
                if apt-cache search "php$version-readline" 2>/dev/null | grep -q "php$version-readline"; then
                    pkg_name="php$version-readline"
                else
                    print_info "readline zaten php-cli ile kurulu olmalı, atlanıyor"
                    continue
                fi
                ;;
            "redis")
                # Redis eklentisi ayrı paket olarak kurulur
                pkg_name="php$version-redis"
                ;;
            "memcached")
                # Memcached eklentisi ayrı paket olarak kurulur
                pkg_name="php$version-memcached"
                ;;
        esac
        
        # Paketi kur
        if apt-cache search "$pkg_name" 2>/dev/null | grep -q "^$pkg_name "; then
            print_info "$pkg_name kuruluyor..."
            
            if apt install -y $pkg_name 2>/dev/null; then
                print_success "$pkg_name kuruldu"
                ((installed_count++))
            else
                print_warning "$pkg_name kurulamadı, düzeltme deneniyor..."
                
                # Broken dependencies düzelt
                apt --fix-broken install -y 2>/dev/null || true
                
                # Tekrar dene
                if apt install -y $pkg_name 2>/dev/null; then
                    print_success "$pkg_name kuruldu (ikinci deneme)"
                    ((installed_count++))
                else
                    print_error "$pkg_name kurulamadı!"
                    ((failed_count++))
                fi
            fi
        else
            print_warning "$pkg_name paketi repository'de bulunamadı"
            ((failed_count++))
        fi
    done
    
    # PHP eklenti yükleme sırasını düzelt (bağımlılık sorunlarını önlemek için)
    print_info "PHP eklenti bağımlılıkları düzeltiliyor..."
    fix_php_extension_loading_order $version
    
    # PHP-FPM'i yeniden başlat (eklentilerin yüklenmesi için)
    if [ $installed_count -gt 0 ] || [ $failed_count -gt 0 ]; then
        print_info "PHP-FPM yeniden başlatılıyor (eklentilerin yüklenmesi için)..."
        systemctl restart php$version-fpm
        sleep 2
        
        if systemctl is-active --quiet php$version-fpm; then
            print_success "PHP-FPM başarıyla yeniden başlatıldı"
            
            # PHP-FPM loglarını kontrol et (hata var mı?)
            local fpm_errors=$(journalctl -u php$version-fpm -n 20 --no-pager 2>/dev/null | grep -i "warning\|error" | grep -i "unable to load" || echo "")
            
            if [ -n "$fpm_errors" ]; then
                print_warning "PHP-FPM'de bazı eklenti yükleme hataları tespit edildi"
                print_info "Hatalar düzeltiliyor..."
                
                # pdo_mysql hatası özel durumu (en yaygın sorun)
                if echo "$fpm_errors" | grep -qi "pdo_mysql"; then
                    print_info "pdo_mysql sorunu tespit edildi - agresif düzeltme yapılıyor..."
                    
                    # 1. pdo_mysql modülünü tamamen devre dışı bırak
                    phpdismod -v $version pdo_mysql 2>/dev/null || true
                    
                    # 2. Tüm pdo_mysql linklerini kaldır
                    for conf_dir in "/etc/php/$version/cli/conf.d" "/etc/php/$version/fpm/conf.d"; do
                        rm -f "$conf_dir"/*pdo_mysql* 2>/dev/null || true
                    done
                    
                    # 3. php-mysql paketini yeniden kur (mysqli için)
                    print_info "php$version-mysql paketi yeniden kuruluyor..."
                    apt install --reinstall -y php$version-mysql 2>/dev/null || true
                    
                    # 4. mysqlnd, pdo ve mysqli'yi etkinleştir
                    phpenmod -v $version mysqlnd 2>/dev/null || true
                    phpenmod -v $version pdo 2>/dev/null || true
                    phpenmod -v $version mysqli 2>/dev/null || true
                    
                    print_success "pdo_mysql devre dışı bırakıldı, mysqli aktif"
                fi
                
                # mysqli hatası
                if echo "$fpm_errors" | grep -qi "mysqli.*mysqlnd_global_stats"; then
                    print_info "mysqli bağımlılığı düzeltiliyor..."
                    
                    # mysqlnd'yi önce etkinleştir
                    phpenmod -v $version mysqlnd 2>/dev/null || true
                    
                    # php-mysql paketini yeniden kur
                    apt install --reinstall -y php$version-mysql 2>/dev/null || true
                    
                    # mysqli'yi etkinleştir
                    phpenmod -v $version mysqli 2>/dev/null || true
                fi
                
                # xsl hatası
                if echo "$fpm_errors" | grep -qi "xsl.*dom_node_class_entry"; then
                    print_info "xsl bağımlılığı düzeltiliyor..."
                    
                    # dom ve xml'i önce etkinleştir
                    phpenmod -v $version dom 2>/dev/null || true
                    phpenmod -v $version xml 2>/dev/null || true
                    
                    # xsl paketini yeniden kur
                    apt install --reinstall -y php$version-xml php$version-xsl 2>/dev/null || true
                    
                    # xsl'i etkinleştir
                    phpenmod -v $version xsl 2>/dev/null || true
                fi
                
                # Yükleme sırasını tekrar düzelt
                fix_php_extension_loading_order $version
                
                # PHP-FPM'i tekrar başlat
                print_info "PHP-FPM tekrar başlatılıyor..."
                systemctl restart php$version-fpm
                sleep 3
                
                # Son kontrol
                local final_errors=$(journalctl -u php$version-fpm -n 10 --no-pager 2>/dev/null | grep -i "warning\|error" | grep -i "unable to load" || echo "")
                
                if [ -z "$final_errors" ]; then
                    print_success "Tüm PHP eklenti hataları düzeltildi!"
                else
                    print_warning "Bazı eklenti hataları devam ediyor"
                    
                    # Hala pdo_mysql hatası varsa, kullanıcıyı bilgilendir
                    if echo "$final_errors" | grep -qi "pdo_mysql"; then
                        print_info "pdo_mysql devre dışı bırakıldı (sorun kaynağı)"
                        print_info "PDO MySQL desteği için mysqli kullanın:"
                        echo "  \$pdo = new PDO('mysql:host=localhost;dbname=test', 'user', 'pass');"
                        echo "  // mysqli otomatik olarak PDO MySQL sürücüsü olarak çalışır"
                    else
                        echo "$final_errors"
                    fi
                fi
            else
                print_success "PHP eklentileri hatasız yüklendi!"
            fi
        else
            print_error "PHP-FPM yeniden başlatılamadı!"
            return 1
        fi
    fi
    
    # Sonuçları göster
    print_info "Eklenti kurulum özeti:"
    echo -e "  ${GREEN}Başarıyla kuruldu:${NC} $installed_count"
    if [ $failed_count -gt 0 ]; then
        echo -e "  ${RED}Kurulamadı:${NC} $failed_count"
    fi
    
    # Kurulu eklentileri tekrar kontrol et
    print_info "Kurulu PHP eklentileri:"
    php$version -m 2>/dev/null | grep -v "^\[" | sort
    
    return 0
}

update_nginx_configs_for_php() {
    print_header "Nginx Yapılandırmalarını PHP için Güncelle"
    
    if ! command -v nginx &> /dev/null; then
        print_error "Nginx kurulu değil!"
        return 1
    fi
    
    # Kurulu PHP versiyonlarını bul (birden fazla yöntem dene)
    local php_versions=""
    
    # Yöntem 1: php -v komutundan versiyon al
    if command -v php &> /dev/null; then
        local php_version_from_cli=$(php -v 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
        if [ -n "$php_version_from_cli" ]; then
            php_versions="$php_version_from_cli"
            print_info "PHP CLI'den versiyon tespit edildi: $php_version_from_cli"
        fi
    fi
    
    # Yöntem 2: /usr/bin/php* dosyalarından versiyon bul
    if [ -z "$php_versions" ]; then
        for php_bin in /usr/bin/php[0-9]* /usr/bin/php[0-9]*.[0-9]*; do
            if [ -f "$php_bin" ] && [ -x "$php_bin" ]; then
                local version=$(basename "$php_bin" | sed 's/php//' | grep -oE "^[0-9]+\.[0-9]+")
                if [ -n "$version" ]; then
                    if [ -z "$php_versions" ]; then
                        php_versions="$version"
                    else
                        php_versions="$php_versions\n$version"
                    fi
                fi
            fi
        done
    fi
    
    # Yöntem 3: PHP-FPM servislerinden versiyon bul
    local php_fpm_versions=$(systemctl list-units --type=service --all 2>/dev/null | grep "php.*-fpm" | sed 's/.*php\([0-9.]*\)-fpm.*/\1/' | grep -E "^[0-9]+\.[0-9]+" || echo "")
    if [ -n "$php_fpm_versions" ]; then
        if [ -z "$php_versions" ]; then
            php_versions="$php_fpm_versions"
        else
            # Versiyonları birleştir ve tekrarları kaldır
            php_versions=$(echo -e "$php_versions\n$php_fpm_versions" | sort -V -u)
        fi
    fi
    
    # Yöntem 4: dpkg/apt ile kurulu PHP paketlerini kontrol et
    if [ -z "$php_versions" ]; then
        local php_packages=$(dpkg -l 2>/dev/null | grep -E "^ii.*php[0-9]+\.[0-9]+-fpm" | awk '{print $2}' | sed 's/php\([0-9.]*\)-fpm.*/\1/' | sort -V -u || echo "")
        if [ -n "$php_packages" ]; then
            php_versions="$php_packages"
        fi
    fi
    
    if [ -z "$php_versions" ]; then
        print_error "Kurulu PHP versiyonu bulunamadı!"
        print_info "PHP kurulu görünüyor ama versiyon tespit edilemedi."
        print_info "Lütfen manuel olarak PHP versiyonunu girin:"
        read -p "PHP versiyonu (örn: 8.3, 8.4): " manual_version
        if [ -n "$manual_version" ]; then
            php_versions="$manual_version"
        else
            print_error "PHP versiyonu belirtilmedi, işlem iptal edildi."
            return 1
        fi
    fi
    
    # PHP versiyonlarını listele
    echo -e "${CYAN}Kurulu PHP Versiyonları:${NC}"
    local version_list=($(echo "$php_versions" | sort -V))
    local count=1
    for version in "${version_list[@]}"; do
        echo "$count) PHP $version"
        ((count++))
    done
    echo ""
    
    # Eğer tek versiyon varsa otomatik seç
    if [ ${#version_list[@]} -eq 1 ]; then
        local selected_version="${version_list[0]}"
        print_info "Tek PHP versiyonu bulundu: PHP $selected_version"
    else
        read -p "Hangi PHP versiyonu için güncelleme yapılacak? (1-${#version_list[@]}) [1]: " version_choice
        version_choice=${version_choice:-1}
        if [ "$version_choice" -ge 1 ] && [ "$version_choice" -le ${#version_list[@]} ]; then
            local selected_version="${version_list[$((version_choice-1))]}"
        else
            print_error "Geçersiz seçim!"
            return 1
        fi
    fi
    
    print_info "PHP $selected_version için Nginx yapılandırmaları güncelleniyor..."
    update_nginx_for_php $selected_version
}

update_nginx_for_php() {
    local php_version=$1
    
    if ! command -v nginx &> /dev/null; then
        print_info "Nginx kurulu değil, PHP yapılandırması atlanıyor"
        return 0
    fi
    
    print_info "Mevcut Nginx yapılandırmaları PHP için güncelleniyor..."
    
    # Tüm aktif Nginx site yapılandırmalarını bul
    local nginx_configs=$(find /etc/nginx/sites-available -type f -name "*" ! -name "default" 2>/dev/null)
    
    if [ -z "$nginx_configs" ]; then
        print_info "Güncellenecek Nginx yapılandırması bulunamadı"
        return 0
    fi
    
    local updated_count=0
    
    for config_file in $nginx_configs; do
        local domain=$(basename "$config_file")
        
        # Eğer zaten PHP yapılandırması varsa sadece versiyonu güncelle
        if grep -q "location ~.*\.php" "$config_file" 2>/dev/null || grep -q "fastcgi_pass.*php.*-fpm" "$config_file" 2>/dev/null; then
            # PHP versiyonunu güncelle
            sed -i "s|php[0-9.]*-fpm|php${php_version}-fpm|g" "$config_file"
            print_info "✓ $domain - PHP versiyonu güncellendi"
            updated_count=$((updated_count + 1))
            continue
        fi
        
        # PHP yapılandırması yoksa ekle
        print_info "PHP yapılandırması ekleniyor: $domain"
        
        # Root dizinini bul
        local root_dir=$(grep -E "^\s*root\s+" "$config_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d ';' | tr -d ' ')
        
        if [ -z "$root_dir" ]; then
            print_warning "$domain için root dizini bulunamadı, atlanıyor"
            continue
        fi
        
        # index.php'yi index listesine ekle (yoksa)
        if ! grep -q "index.*index.php" "$config_file" 2>/dev/null; then
            sed -i "s|index \(.*\);|index \1 index.php;|g" "$config_file"
        fi
        
        # PHP location bloğunu ekle
        cat >> "$config_file" <<EOF

# PHP Configuration - Added automatically
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${php_version}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }
EOF
        
        # .htaccess koruması ekle (yoksa)
        if ! grep -q "location ~ /\.ht" "$config_file" 2>/dev/null; then
            cat >> "$config_file" <<EOF

    location ~ /\.ht {
        deny all;
    }
EOF
        fi
        
        updated_count=$((updated_count + 1))
        print_success "✓ $domain - PHP yapılandırması eklendi"
    done
    
    if [ $updated_count -gt 0 ]; then
        # Nginx yapılandırmasını test et
        if nginx -t 2>/dev/null; then
            systemctl reload nginx
            print_success "$updated_count Nginx yapılandırması PHP için güncellendi"
        else
            print_error "Nginx yapılandırma hatası! Lütfen manuel kontrol edin: nginx -t"
            return 1
        fi
    else
        print_info "Güncellenecek yapılandırma bulunamadı"
    fi
}

install_mysql() {
    print_info "MySQL/MariaDB kuruluyor..."
    
    # Eğer MySQL zaten kuruluysa ve hata veriyorsa, temizleme seçeneği
    if systemctl is-active --quiet mariadb 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null || \
       dpkg -l | grep -q "mariadb\|mysql-server" 2>/dev/null; then
        print_warning "MySQL/MariaDB zaten kurulu görünüyor"
        if ask_yes_no "Mevcut kurulumu kaldırıp yeniden kurmak ister misiniz? (UYARI: Tüm veriler silinecek!)"; then
            print_info "Mevcut MySQL/MariaDB kapsamlı temizleme yapılıyor..."
            
            # Önce çalışan tüm MySQL/MariaDB process'lerini zorla durdur
            print_info "Çalışan MySQL/MariaDB process'leri durduruluyor..."
            pkill -9 mysqld 2>/dev/null || true
            pkill -9 mariadbd 2>/dev/null || true
            pkill -9 mysqld_safe 2>/dev/null || true
            pkill -9 mariadb 2>/dev/null || true
            sleep 3
            
            # Servisleri durdur (systemd varsa)
            systemctl stop mariadb 2>/dev/null || true
            systemctl stop mysql 2>/dev/null || true
            systemctl disable mariadb 2>/dev/null || true
            systemctl disable mysql 2>/dev/null || true
            sleep 2
            
            # Broken dependencies'i düzelt
            print_info "Broken dependencies düzeltiliyor..."
            apt --fix-broken install -y 2>/dev/null || true
            
            # Tüm MariaDB/MySQL paketlerini kaldır
            print_info "MariaDB/MySQL paketleri kaldırılıyor..."
            
            # Önce kısmi kurulumları temizle
            dpkg --remove --force-remove-reinstreq mariadb-server mariadb-client mariadb-common 2>/dev/null || true
            dpkg --remove --force-remove-reinstreq mysql-server mysql-client mysql-common 2>/dev/null || true
            
            # Sonra normal kaldırma
            apt remove --purge -y \
                mariadb-server mariadb-client mariadb-common \
                mysql-server mysql-client mysql-common \
                mariadb-server-* mariadb-client-* \
                mysql-server-* mysql-client-* \
                galera-* 2>/dev/null || true
            
            # update-alternatives temizliği
            print_info "update-alternatives temizleniyor..."
            update-alternatives --remove-all mysql 2>/dev/null || true
            update-alternatives --remove-all mysqldump 2>/dev/null || true
            update-alternatives --remove-all mysqladmin 2>/dev/null || true
            update-alternatives --remove-all mysqlcheck 2>/dev/null || true
            
            # Eksik dosyaları oluştur (dpkg hatasını önlemek için)
            if [ ! -d "/etc/mysql" ]; then
                mkdir -p /etc/mysql
            fi
            if [ ! -f "/etc/mysql/mariadb.cnf" ]; then
                touch /etc/mysql/mariadb.cnf
            fi
            
            # dpkg yapılandırmasını düzelt
            print_info "dpkg yapılandırması düzeltiliyor..."
            dpkg --configure -a 2>/dev/null || true
            
            # Broken dependencies'i tekrar düzelt
            apt --fix-broken install -y 2>/dev/null || true
            
            # Kalan paketleri temizle
            apt autoremove -y
            apt autoclean
            
            # Eksik bağımlılıkları kur
            apt-get -f install -y 2>/dev/null || true
            
            # dpkg durumunu kontrol et ve düzelt
            print_info "dpkg durumu kontrol ediliyor..."
            dpkg --configure -a 2>/dev/null || true
            
            # Veri ve yapılandırma dizinlerini temizle
            print_info "Veri ve yapılandırma dizinleri temizleniyor..."
            rm -rf /var/lib/mysql
            rm -rf /etc/mysql
            rm -rf /var/log/mysql
            rm -rf /run/mysqld
            rm -f /etc/init.d/mysql
            rm -f /etc/init.d/mariadb
            
            # Systemd servis dosyalarını temizle
            rm -f /etc/systemd/system/mariadb.service
            rm -f /etc/systemd/system/mysql.service
            rm -f /lib/systemd/system/mariadb.service
            rm -f /lib/systemd/system/mysql.service
            systemctl daemon-reload
            
            print_success "Kapsamlı temizleme tamamlandı"
            sleep 2
        fi
    fi
    
    # Kurulum öncesi çalışan process kontrolü
    print_info "Kurulum öncesi kontrol yapılıyor..."
    
    # Çalışan MySQL/MariaDB process'lerini kontrol et ve durdur
    if pgrep -x mysqld > /dev/null 2>&1 || pgrep -x mariadbd > /dev/null 2>&1 || \
       pgrep -f mysqld_safe > /dev/null 2>&1; then
        print_warning "Çalışan MySQL/MariaDB process'leri tespit edildi, durduruluyor..."
        pkill -9 mysqld 2>/dev/null || true
        pkill -9 mariadbd 2>/dev/null || true
        pkill -9 mysqld_safe 2>/dev/null || true
        sleep 2
    fi
    
    # Broken dependencies kontrolü
    if dpkg -l | grep -q "^..r" 2>/dev/null; then
        print_info "Broken dependencies tespit edildi, düzeltiliyor..."
        apt --fix-broken install -y 2>/dev/null || true
        dpkg --configure -a 2>/dev/null || true
    fi
    
    # Önce eksik dizinleri ve dosyaları oluştur (dpkg hatasını önlemek için)
    print_info "Gerekli dizinler ve dosyalar oluşturuluyor..."
    mkdir -p /etc/mysql
    mkdir -p /var/log/mysql
    mkdir -p /run/mysqld
    
    # /var/lib/mysql dizinini kontrol et ve temizle (InnoDB/Aria hatalarını önlemek için)
    if [ -d "/var/lib/mysql" ]; then
        print_info "Mevcut veri dizini kontrol ediliyor..."
        
        # Eğer dizin bozuk görünüyorsa (ibdata1 veya mysql klasörü yoksa), temizle
        if [ ! -f "/var/lib/mysql/ibdata1" ] && [ ! -d "/var/lib/mysql/mysql" ]; then
            print_warning "Bozuk veri dizini tespit edildi, temizleniyor..."
            rm -rf /var/lib/mysql/*
            rm -rf /var/lib/mysql/.* 2>/dev/null || true
        elif [ -f "/var/lib/mysql/ibdata1" ] && [ ! -d "/var/lib/mysql/mysql" ]; then
            print_warning "Eksik sistem tabloları tespit edildi, veri dizini temizleniyor..."
            rm -rf /var/lib/mysql/*
            rm -rf /var/lib/mysql/.* 2>/dev/null || true
        fi
    else
        mkdir -p /var/lib/mysql
    fi
    
    # Eksik mariadb.cnf dosyasını oluştur (update-alternatives hatasını önlemek için)
    if [ ! -f "/etc/mysql/mariadb.cnf" ]; then
        cat > /etc/mysql/mariadb.cnf <<'EOF'
# MariaDB yapılandırma dosyası
# Bu dosya update-alternatives için gerekli
[client-server]
EOF
        chmod 644 /etc/mysql/mariadb.cnf
    fi
    
    # dpkg yapılandırmasını düzelt (varsa hatalar)
    print_info "dpkg yapılandırması kontrol ediliyor..."
    dpkg --configure -a 2>/dev/null || true
    
    # MariaDB kurulumu için debconf ayarları
    print_info "MariaDB kurulum yapılandırması hazırlanıyor..."
    
    # MariaDB için debconf ayarları (non-interactive kurulum)
    # Tüm MariaDB versiyonları için genel ayarlar
    debconf-set-selections <<EOF
mariadb-server-* mariadb-server/root_password password $MYSQL_ROOT_PASSWORD
mariadb-server-* mariadb-server/root_password_again password $MYSQL_ROOT_PASSWORD
mariadb-server-* mariadb-server/oneway_migration boolean true
mariadb-server-* mariadb-server/upgrade_backup boolean false
mariadb-common mariadb-common/selected-server select mariadb-server
EOF
    
    # APT paket listesini güncelle
    print_info "Paket listesi güncelleniyor..."
    apt update
    
    # MariaDB kurulumu (non-interactive)
    print_info "MariaDB kuruluyor..."
    
    # Kurulum öncesi son kontrol
    if pgrep -x mysqld > /dev/null 2>&1 || pgrep -x mariadbd > /dev/null 2>&1; then
        print_warning "Hala çalışan process'ler var, zorla durduruluyor..."
        pkill -9 mysqld 2>/dev/null || true
        pkill -9 mariadbd 2>/dev/null || true
        sleep 2
    fi
    
    if ! DEBIAN_FRONTEND=noninteractive apt install -y mariadb-server mariadb-client mariadb-common; then
        print_warning "MariaDB kurulumunda bazı hatalar oluştu, kapsamlı düzeltme yapılıyor..."
        
        # Çalışan process'leri durdur
        pkill -9 mysqld 2>/dev/null || true
        pkill -9 mariadbd 2>/dev/null || true
        pkill -9 mysqld_safe 2>/dev/null || true
        sleep 2
        
        # Broken dependencies'i düzelt
        print_info "Broken dependencies düzeltiliyor..."
        apt --fix-broken install -y 2>/dev/null || true
        
        # dpkg yapılandırmasını düzelt
        print_info "dpkg yapılandırması düzeltiliyor..."
        dpkg --configure -a 2>/dev/null || true
        
        # Kısmi kurulumları temizle
        print_info "Kısmi kurulumlar temizleniyor..."
        dpkg --remove --force-remove-reinstreq mariadb-server mariadb-client mariadb-common 2>/dev/null || true
        
        # Eksik bağımlılıkları kur
        print_info "Eksik bağımlılıklar kuruluyor..."
        apt-get -f install -y 2>/dev/null || true
        
        # Tekrar kurulum dene
        print_info "Kurulum tekrar deneniyor..."
        if ! DEBIAN_FRONTEND=noninteractive apt install -y mariadb-server mariadb-client mariadb-common; then
            print_error "MariaDB kurulumu başarısız oldu!"
            print_info "Manuel kurulum için:"
            echo "  1. sudo pkill -9 mysqld mariadbd mysqld_safe"
            echo "  2. sudo apt --fix-broken install"
            echo "  3. sudo apt install -y mariadb-server mariadb-client"
            return 1
        fi
    fi
    
    # Veri dizinini kontrol et ve gerekirse initialize et
    print_info "MariaDB veri dizini kontrol ediliyor..."
    
    # MySQL kullanıcısının varlığını kontrol et
    if ! id mysql &>/dev/null; then
        print_info "MySQL kullanıcısı oluşturuluyor..."
        useradd -r -s /bin/false mysql 2>/dev/null || true
    fi
    
    # Dizin izinlerini ayarla
    chown -R mysql:mysql /var/lib/mysql 2>/dev/null || true
    chown -R mysql:mysql /var/log/mysql 2>/dev/null || true
    chown -R mysql:mysql /run/mysqld 2>/dev/null || true
    
    # Veri dizini boşsa veya sistem tabloları yoksa initialize et
    if [ ! -d "/var/lib/mysql/mysql" ] || [ -z "$(ls -A /var/lib/mysql 2>/dev/null)" ]; then
        print_info "MariaDB veri dizini initialize ediliyor (InnoDB/Aria hatalarını önlemek için)..."
        
        # mysql_install_db veya mariadb-install-db komutunu kullan
        if command -v mariadb-install-db &>/dev/null; then
            sudo -u mysql mariadb-install-db --datadir=/var/lib/mysql --auth-root-authentication-method=normal --auth-root-socket-user=mysql --skip-test-db 2>&1 | tail -20
        elif command -v mysql_install_db &>/dev/null; then
            sudo -u mysql mysql_install_db --datadir=/var/lib/mysql --auth-root-authentication-method=normal --skip-test-db 2>&1 | tail -20
        else
            print_warning "mysql_install_db veya mariadb-install-db bulunamadı, servis başlatma ile initialize edilecek"
        fi
        
        # İzinleri tekrar ayarla
        chown -R mysql:mysql /var/lib/mysql
        chmod 755 /var/lib/mysql
    else
        print_info "Veri dizini zaten mevcut, izinler kontrol ediliyor..."
        chown -R mysql:mysql /var/lib/mysql
    fi
    
    # Servis dosyasının varlığını kontrol et
    print_info "MariaDB servis dosyası kontrol ediliyor..."
    local service_file=""
    
    if [ -f "/lib/systemd/system/mariadb.service" ]; then
        service_file="/lib/systemd/system/mariadb.service"
    elif [ -f "/etc/systemd/system/mariadb.service" ]; then
        service_file="/etc/systemd/system/mariadb.service"
    elif [ -f "/usr/lib/systemd/system/mariadb.service" ]; then
        service_file="/usr/lib/systemd/system/mariadb.service"
    fi
    
    if [ -z "$service_file" ]; then
        print_warning "MariaDB servis dosyası bulunamadı, oluşturuluyor..."
        
        # Basit bir systemd servis dosyası oluştur
        cat > /etc/systemd/system/mariadb.service <<'EOF'
[Unit]
Description=MariaDB database server
After=network.target

[Service]
Type=notify
User=mysql
Group=mysql
ExecStart=/usr/bin/mysqld_safe
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        service_file="/etc/systemd/system/mariadb.service"
    fi
    
    # Servis başlatma
    print_info "MariaDB servisi başlatılıyor..."
    
    # Systemd daemon'u yeniden yükle
    systemctl daemon-reload
    
    # Servisi etkinleştir
    systemctl enable mariadb 2>/dev/null || systemctl enable mariadb.service 2>/dev/null || true
    
    # Servisi başlat
    systemctl start mariadb 2>/dev/null || systemctl start mariadb.service 2>/dev/null || true
    
    # Alternatif: mysqld_safe ile başlat
    if ! systemctl is-active --quiet mariadb 2>/dev/null; then
        print_warning "systemctl ile başlatılamadı, alternatif yöntem deneniyor..."
        
        # MySQL kullanıcısının varlığını kontrol et
        if ! id mysql &>/dev/null; then
            print_info "MySQL kullanıcısı oluşturuluyor..."
            useradd -r -s /bin/false mysql 2>/dev/null || true
        fi
        
        # Dizin izinlerini ayarla
        chown -R mysql:mysql /var/lib/mysql 2>/dev/null || true
        chown -R mysql:mysql /var/log/mysql 2>/dev/null || true
        chown -R mysql:mysql /run/mysqld 2>/dev/null || true
        
        # mysqld_safe ile başlat
        sudo -u mysql mysqld_safe --user=mysql > /dev/null 2>&1 &
        sleep 5
    fi
    
    # Servisin başladığından emin ol
    local retry_count=0
    while [ $retry_count -lt 15 ]; do
        if systemctl is-active --quiet mariadb 2>/dev/null || \
           pgrep -x mysqld > /dev/null 2>&1 || \
           pgrep -f mysqld_safe > /dev/null 2>&1; then
            break
        fi
        sleep 1
        ((retry_count++))
    done
    
    # Servis durumunu kontrol et
    if systemctl is-active --quiet mariadb 2>/dev/null; then
        print_success "MariaDB servisi başlatıldı (systemd)"
    elif pgrep -x mysqld > /dev/null 2>&1 || pgrep -f mysqld_safe > /dev/null 2>&1; then
        print_success "MariaDB servisi başlatıldı (manuel)"
    else
        print_error "MariaDB başlatılamadı!"
        
        # Log kontrolü - InnoDB/Aria hatalarını kontrol et
        local error_log=$(journalctl -u mariadb -n 20 --no-pager 2>/dev/null | grep -i "innodb\|aria\|storage engine" || echo "")
        
        if echo "$error_log" | grep -qi "innodb\|aria\|storage engine"; then
            print_warning "InnoDB/Aria storage engine hatası tespit edildi!"
            print_info "Veri dizini yeniden initialize ediliyor..."
            
            # Servisi durdur
            systemctl stop mariadb 2>/dev/null || true
            pkill -9 mysqld 2>/dev/null || true
            pkill -9 mysqld_safe 2>/dev/null || true
            sleep 3
            
            # Veri dizinini temizle
            rm -rf /var/lib/mysql/*
            rm -rf /var/lib/mysql/.* 2>/dev/null || true
            
            # Veri dizinini yeniden initialize et
            if command -v mariadb-install-db &>/dev/null; then
                sudo -u mysql mariadb-install-db --datadir=/var/lib/mysql --auth-root-authentication-method=normal --auth-root-socket-user=mysql --skip-test-db
            elif command -v mysql_install_db &>/dev/null; then
                sudo -u mysql mysql_install_db --datadir=/var/lib/mysql --auth-root-authentication-method=normal --skip-test-db
            fi
            
            # İzinleri ayarla
            chown -R mysql:mysql /var/lib/mysql
            chmod 755 /var/lib/mysql
            
            # Servisi tekrar başlat
            systemctl start mariadb
            sleep 5
            
            # Tekrar kontrol et
            if systemctl is-active --quiet mariadb 2>/dev/null; then
                print_success "MariaDB servisi başlatıldı (veri dizini yeniden initialize edildi)"
            else
                print_error "MariaDB hala başlatılamadı!"
                print_info "Log kontrolü: journalctl -u mariadb -n 50"
                print_info "Manuel başlatma: sudo -u mysql mysqld_safe --user=mysql &"
                return 1
            fi
        else
            print_info "Log kontrolü: journalctl -u mariadb -n 50"
            print_info "Manuel başlatma: sudo -u mysql mysqld_safe --user=mysql &"
            return 1
        fi
    fi
    
    # MariaDB 10.4+ için root şifresi yapılandırması
    print_info "MySQL root şifresi yapılandırılıyor..."
    
    # Önce servis durumunu ve bağlantıyı kontrol et
    print_info "MariaDB servis durumu kontrol ediliyor..."
    local service_status=""
    if systemctl is-active --quiet mariadb 2>/dev/null; then
        service_status="active"
        print_info "MariaDB servisi çalışıyor"
    elif pgrep -x mysqld > /dev/null 2>&1 || pgrep -x mariadbd > /dev/null 2>&1; then
        service_status="running"
        print_info "MariaDB process çalışıyor"
    else
        print_error "MariaDB servisi çalışmıyor!"
        print_info "Servis durumunu kontrol edin: systemctl status mariadb"
        return 1
    fi
    
    # Bağlantı testi
    print_info "MariaDB bağlantı testi yapılıyor..."
    local connection_test=false
    
    # sudo mysql ile test
    if sudo mysql -e "SELECT 1;" 2>/dev/null; then
        connection_test=true
        print_success "sudo mysql ile bağlantı başarılı"
    elif mysql -u root -e "SELECT 1;" 2>/dev/null; then
        connection_test=true
        print_success "mysql -u root ile bağlantı başarılı"
    else
        print_warning "Bağlantı testi başarısız, şifre ayarlama deneniyor..."
    fi
    
    # MariaDB 10.4+ varsayılan olarak unix_socket authentication kullanır
    # Bu yüzden önce sudo mysql ile erişim sağlayıp şifre ayarlayacağız
    local password_set=false
    local max_attempts=3
    local attempt=0
    
    while [ $attempt -lt $max_attempts ] && [ "$password_set" = false ]; do
        ((attempt++))
        print_info "Şifre ayarlama denemesi $attempt/$max_attempts..."
        
        # Yöntem 1: sudo mysql ile şifre ayarla (MariaDB 10.4+ için en güvenilir)
        local sql_result=0
        local sql_error=""
        
        sql_error=$(sudo mysql <<EOF 2>&1
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('$MYSQL_ROOT_PASSWORD');
ALTER USER 'root'@'127.0.0.1' IDENTIFIED VIA mysql_native_password USING PASSWORD('$MYSQL_ROOT_PASSWORD');
ALTER USER 'root'@'::1' IDENTIFIED VIA mysql_native_password USING PASSWORD('$MYSQL_ROOT_PASSWORD');
FLUSH PRIVILEGES;
EOF
        )
        sql_result=$?
        
        if [ $sql_result -eq 0 ]; then
            password_set=true
            print_success "Root şifresi sudo mysql ile ayarlandı (mysql_native_password)"
            break
        else
            # Alternatif: IDENTIFIED BY kullan (eğer VIA çalışmazsa)
            sql_error=$(sudo mysql <<EOF 2>&1
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
ALTER USER 'root'@'::1' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF
            )
            sql_result=$?
            
            if [ $sql_result -eq 0 ]; then
                password_set=true
                print_success "Root şifresi sudo mysql ile ayarlandı (ALTER USER BY)"
                break
            fi
        fi
        
        # Yöntem 2: Normal mysql ile dene (eğer şifresiz erişim varsa)
        if [ "$password_set" = false ]; then
            sql_error=$(mysql -u root <<EOF 2>&1
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF
            )
            sql_result=$?
            
            if [ $sql_result -eq 0 ]; then
                password_set=true
                print_success "Root şifresi normal mysql ile ayarlandı"
                break
            fi
        fi
        
        # Hata mesajını göster (debug için)
        if [ -n "$sql_error" ] && [ $attempt -eq $max_attempts ]; then
            print_warning "SQL hatası: $sql_error"
        fi
        
        # Kısa bir bekleme ve tekrar dene
        sleep 2
    done
    
    # Eğer hala şifre ayarlanamadıysa, alternatif yöntemler dene
    if [ "$password_set" = false ]; then
        print_info "Standart yöntemlerle şifre ayarlanamadı, alternatif yöntemler deneniyor..."
        
        # Yöntem 3: mysqladmin kullan
        if mysqladmin -u root password "$MYSQL_ROOT_PASSWORD" 2>/dev/null; then
            password_set=true
            print_success "Root şifresi mysqladmin ile ayarlandı"
        # Yöntem 4: sudo mysqladmin kullan
        elif sudo mysqladmin -u root password "$MYSQL_ROOT_PASSWORD" 2>/dev/null; then
            password_set=true
            print_success "Root şifresi sudo mysqladmin ile ayarlandı"
        fi
    fi
    
    # Eğer hala şifre ayarlanamadıysa, güvenli mod yöntemini kullan
    if [ "$password_set" = false ]; then
        print_info "Alternatif yöntemler başarısız, güvenli mod yöntemi deneniyor..."
        
        # Servisi durdur
        systemctl stop mariadb 2>/dev/null || true
        pkill -9 mysqld 2>/dev/null || true
        pkill -9 mariadbd 2>/dev/null || true
        pkill -9 mysqld_safe 2>/dev/null || true
        sleep 3
        
        # MariaDB'yi skip-grant-tables ile başlat
        print_info "MariaDB güvenli modda başlatılıyor..."
        sudo -u mysql mysqld_safe --skip-grant-tables --skip-networking --datadir=/var/lib/mysql > /tmp/mysqld_safe.log 2>&1 &
        local safe_pid=$!
        
        # MariaDB'nin başladığından emin ol
        local safe_retry=0
        while [ $safe_retry -lt 15 ]; do
            if mysql -u root -e "SELECT 1;" 2>/dev/null; then
                break
            fi
            sleep 1
            ((safe_retry++))
        done
        
        if mysql -u root -e "SELECT 1;" 2>/dev/null; then
            print_info "Güvenli modda bağlantı başarılı, şifre ayarlanıyor..."
            
            # Şifreyi ayarla
            mysql -u root <<EOF 2>/dev/null
USE mysql;
UPDATE user SET authentication_string='', plugin='mysql_native_password' WHERE User='root' AND Host='localhost';
UPDATE user SET authentication_string='', plugin='mysql_native_password' WHERE User='root' AND Host='127.0.0.1';
UPDATE user SET authentication_string='', plugin='mysql_native_password' WHERE User='root' AND Host='::1';
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
ALTER USER 'root'@'::1' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF
            
            # Güvenli moddaki MariaDB'yi durdur
            kill $safe_pid 2>/dev/null || true
            sleep 3
            pkill -9 mysqld_safe 2>/dev/null || true
            pkill -9 mysqld 2>/dev/null || true
            pkill -9 mariadbd 2>/dev/null || true
            sleep 2
            
            # Normal modda başlat
            systemctl start mariadb
            sleep 5
            
            # Şifre ile test et
            if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
                password_set=true
                print_success "Root şifresi güvenli mod yöntemi ile ayarlandı"
            fi
        else
            print_warning "Güvenli modda bağlantı kurulamadı"
            # Güvenli moddaki process'leri temizle
            kill $safe_pid 2>/dev/null || true
            pkill -9 mysqld_safe 2>/dev/null || true
            pkill -9 mysqld 2>/dev/null || true
            pkill -9 mariadbd 2>/dev/null || true
            sleep 2
            systemctl start mariadb 2>/dev/null || true
        fi
    fi
    
    # Son çare: UPDATE user tablosunu direkt güncelle
    if [ "$password_set" = false ]; then
        print_info "Son çare yöntemi deneniyor: Direkt user tablosu güncelleme..."
        
        # Servisi durdur
        systemctl stop mariadb 2>/dev/null || true
        pkill -9 mysqld 2>/dev/null || true
        pkill -9 mariadbd 2>/dev/null || true
        sleep 2
        
        # Güvenli modda başlat
        sudo -u mysql mysqld_safe --skip-grant-tables --skip-networking --datadir=/var/lib/mysql > /tmp/mysqld_safe2.log 2>&1 &
        local safe_pid2=$!
        sleep 5
        
        if mysql -u root -e "SELECT 1;" 2>/dev/null; then
            # authentication_string'ı temizle ve ALTER USER kullan
            mysql -u root <<EOF 2>/dev/null
USE mysql;
UPDATE user SET authentication_string='', plugin='mysql_native_password' WHERE User='root' AND Host='localhost';
UPDATE user SET authentication_string='', plugin='mysql_native_password' WHERE User='root' AND Host='127.0.0.1';
UPDATE user SET authentication_string='', plugin='mysql_native_password' WHERE User='root' AND Host='::1';
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
ALTER USER 'root'@'::1' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF
            
            # Güvenli moddaki process'leri temizle
            kill $safe_pid2 2>/dev/null || true
            sleep 3
            pkill -9 mysqld_safe 2>/dev/null || true
            pkill -9 mysqld 2>/dev/null || true
            pkill -9 mariadbd 2>/dev/null || true
            sleep 2
            
            # Normal modda başlat
            systemctl start mariadb
            sleep 5
            
            # Şifre ile test et
            if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
                password_set=true
                print_success "Root şifresi direkt user tablosu güncelleme ile ayarlandı"
            fi
        fi
    fi
    
    # Eğer hala şifre ayarlanamadıysa, kurulum başarısız
    if [ "$password_set" = false ]; then
        print_error "Root şifresi ayarlanamadı! Tüm yöntemler denendi."
        print_info "MariaDB servisi çalışıyor ancak şifre ayarlanamadı."
        print_info "Log dosyaları: /tmp/mysqld_safe.log, /tmp/mysqld_safe2.log"
        return 1
    fi
    
    # Şifre ile bağlantıyı test et
    print_info "Şifre doğrulanıyor..."
    local verify_count=0
    local verify_success=false
    
    while [ $verify_count -lt 10 ] && [ "$verify_success" = false ]; do
        if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
            verify_success=true
            print_success "MySQL root şifresi doğrulandı"
            break
        fi
        sleep 1
        ((verify_count++))
    done
    
    if [ "$verify_success" = false ]; then
        print_error "Şifre doğrulama başarısız!"
        print_info "Şifre ayarlandı ancak doğrulama başarısız, tekrar ayarlanıyor..."
        
        # Şifreyi tekrar ayarla
        if sudo mysql <<EOF 2>/dev/null; then
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF
            sleep 2
            # Tekrar doğrula
            if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
                verify_success=true
                print_success "MySQL root şifresi doğrulandı (ikinci deneme)"
            else
                print_error "Şifre doğrulama başarısız!"
                return 1
            fi
        else
            print_error "Şifre tekrar ayarlanamadı!"
            return 1
        fi
    fi
    
    # Güvenlik yapılandırması (manuel)
    print_info "MySQL güvenlik yapılandırması yapılıyor..."
    
    local security_success=false
    
    # Önce şifre ile dene
    if [ "$verify_success" = true ]; then
        if mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF 2>/dev/null; then
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
            security_success=true
        fi
    fi
    
    # Eğer şifre ile başarısız olduysa, sudo mysql ile dene
    if [ "$security_success" = false ]; then
        if sudo mysql <<EOF 2>/dev/null; then
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
            security_success=true
        fi
    fi
    
    if [ "$security_success" = true ]; then
        print_success "MySQL güvenlik yapılandırması tamamlandı"
    else
        print_warning "MySQL güvenlik yapılandırması başarısız, tekrar deneniyor..."
        
        # Şifre ile tekrar dene
        if mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF 2>/dev/null; then
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
            security_success=true
            print_success "MySQL güvenlik yapılandırması tamamlandı (ikinci deneme)"
        else
            print_error "MySQL güvenlik yapılandırması başarısız!"
            return 1
        fi
    fi
    
    # Servis durumunu kontrol et
    if systemctl is-active --quiet mariadb 2>/dev/null || \
       pgrep -x mysqld > /dev/null 2>&1 || \
       pgrep -x mariadbd > /dev/null 2>&1; then
        print_success "MySQL/MariaDB kurulumu tamamlandı ve çalışıyor"
        echo -e "${GREEN}MySQL Root Şifresi:${NC} Ayarlanmış ve doğrulandı"
        
        if systemctl is-active --quiet mariadb 2>/dev/null; then
            echo -e "${GREEN}Servis Durumu:${NC} $(systemctl is-active mariadb)"
        else
            echo -e "${GREEN}Servis Durumu:${NC} Çalışıyor (process)"
        fi
    else
        print_error "MySQL/MariaDB kuruldu ancak servis çalışmıyor!"
        print_info "Servisi başlatmaya çalışılıyor..."
        
        systemctl start mariadb
        sleep 5
        
        if systemctl is-active --quiet mariadb 2>/dev/null; then
            print_success "MariaDB servisi başlatıldı"
        else
            print_error "MariaDB servisi başlatılamadı!"
            print_info "Log kontrolü: journalctl -u mariadb -n 50"
            return 1
        fi
    fi
}

install_nodejs() {
    print_info "Node.js kuruluyor..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs npm
    
    # Framework'e özel global paketler
    case $FRAMEWORK in
        "laravel")
            npm install -g pm2
            ;;
        "symfony")
            npm install -g yarn
            ;;
    esac
    
    print_success "Node.js kurulumu tamamlandı"
}

install_redis() {
    print_info "Redis kuruluyor..."
    
    # APT paket listesini güncelle
    print_info "Paket listesi güncelleniyor..."
    apt update
    
    # Universe repository'sini etkinleştir (Redis genellikle universe'de)
    if ! grep -q "^deb.*universe" /etc/apt/sources.list 2>/dev/null && \
       ! grep -q "^deb.*universe" /etc/apt/sources.list.d/*.list 2>/dev/null; then
        print_info "Universe repository etkinleştiriliyor..."
        add-apt-repository -y universe 2>/dev/null || \
        sed -i 's/^# deb \(.*\) universe$/deb \1 universe/' /etc/apt/sources.list || true
        apt update
    fi
    
    # Redis kurulumu
    if ! apt install -y redis-server; then
        print_warning "Redis kurulumunda hata oluştu, düzeltme deneniyor..."
        
        # Broken dependencies düzelt
        apt --fix-broken install -y 2>/dev/null || true
        
        # Paket listesini tekrar güncelle
        apt update
        
        # Tekrar kurulum dene
        if ! apt install -y redis-server; then
            print_error "Redis kurulumu başarısız oldu!"
            print_info "Manuel kurulum için:"
            echo "  sudo apt update"
            echo "  sudo apt install -y redis-server"
            return 1
        fi
    fi
    
    # Redis yapılandırmasını düzenle (localhost bağlantısı için)
    local redis_conf="/etc/redis/redis.conf"
    if [ -f "$redis_conf" ]; then
        print_info "Redis yapılandırması kontrol ediliyor..."
        
        # bind adresini kontrol et
        if ! grep -q "^bind 127.0.0.1" "$redis_conf"; then
            print_info "Redis bind adresi ayarlanıyor..."
            sed -i 's/^bind .*/bind 127.0.0.1 ::1/' "$redis_conf"
        fi
        
        # protected-mode kontrolü
        if ! grep -q "^protected-mode yes" "$redis_conf"; then
            sed -i 's/^protected-mode .*/protected-mode yes/' "$redis_conf"
        fi
    fi
    
    # Redis servisini başlat ve etkinleştir
    print_info "Redis servisi başlatılıyor..."
    systemctl start redis-server 2>/dev/null || systemctl start redis 2>/dev/null || true
    systemctl enable redis-server 2>/dev/null || systemctl enable redis 2>/dev/null || true
    
    # Servis durumunu kontrol et
    sleep 2
    if systemctl is-active --quiet redis-server 2>/dev/null || \
       systemctl is-active --quiet redis 2>/dev/null || \
       pgrep -x redis-server > /dev/null 2>&1; then
        print_success "Redis kurulumu tamamlandı ve servis başlatıldı"
        echo -e "${GREEN}Redis Versiyonu:${NC} $(redis-server --version 2>/dev/null | cut -d' ' -f3 || echo "Kuruldu")"
        echo -e "${GREEN}Servis Durumu:${NC} $(systemctl is-active redis-server 2>/dev/null || systemctl is-active redis 2>/dev/null || echo "Çalışıyor")"
        
        # Bağlantı testi
        if redis-cli ping 2>/dev/null | grep -q "PONG"; then
            print_success "Redis bağlantı testi başarılı (PONG)"
        else
            print_warning "Redis çalışıyor ama bağlantı testi başarısız"
        fi
    else
        print_warning "Redis kuruldu ancak servis başlatılamadı"
        print_info "Servis durumunu kontrol edin: systemctl status redis-server"
        print_info "Manuel başlatma: sudo systemctl start redis-server"
    fi
}

fix_redis_connection() {
    print_header "Redis Bağlantı Sorunu Düzeltme"
    
    # Redis kurulu mu kontrol et
    if ! command -v redis-server &>/dev/null && ! command -v redis-cli &>/dev/null; then
        print_error "Redis kurulu değil!"
        if ask_yes_no "Redis kurmak ister misiniz?"; then
            install_redis
            return $?
        else
            return 1
        fi
    fi
    
    # Redis servis durumunu kontrol et
    local redis_running=false
    if systemctl is-active --quiet redis-server 2>/dev/null || \
       systemctl is-active --quiet redis 2>/dev/null; then
        redis_running=true
        print_success "Redis servisi çalışıyor"
    else
        print_warning "Redis servisi çalışmıyor!"
        print_info "Redis servisi başlatılıyor..."
        
        systemctl start redis-server 2>/dev/null || systemctl start redis 2>/dev/null || true
        sleep 2
        
        if systemctl is-active --quiet redis-server 2>/dev/null || \
           systemctl is-active --quiet redis 2>/dev/null; then
            redis_running=true
            print_success "Redis servisi başlatıldı"
        else
            print_error "Redis servisi başlatılamadı!"
            print_info "Log kontrolü: journalctl -u redis-server -n 50"
            return 1
        fi
    fi
    
    # Bağlantı testi
    if [ "$redis_running" = true ]; then
        print_info "Redis bağlantı testi yapılıyor..."
        
        if redis-cli ping 2>/dev/null | grep -q "PONG"; then
            print_success "Redis bağlantı testi başarılı!"
            echo -e "${GREEN}Redis Durumu:${NC} Çalışıyor ve bağlanılabilir"
            
            # Redis bilgileri
            echo ""
            print_info "Redis Bilgileri:"
            redis-cli INFO server 2>/dev/null | grep -E "redis_version|redis_mode|tcp_port" || true
        else
            print_error "Redis çalışıyor ama bağlantı kurulamıyor!"
            
            # Yapılandırmayı kontrol et
            local redis_conf="/etc/redis/redis.conf"
            if [ -f "$redis_conf" ]; then
                print_info "Redis yapılandırması kontrol ediliyor..."
                
                # bind adresini kontrol et
                local bind_address=$(grep "^bind" "$redis_conf" | head -1)
                echo "Mevcut bind adresi: $bind_address"
                
                if ! echo "$bind_address" | grep -q "127.0.0.1"; then
                    print_warning "Redis sadece localhost'a bind değil!"
                    if ask_yes_no "Redis'i localhost (127.0.0.1) için yapılandırmak ister misiniz?"; then
                        sed -i 's/^bind .*/bind 127.0.0.1 ::1/' "$redis_conf"
                        systemctl restart redis-server 2>/dev/null || systemctl restart redis 2>/dev/null
                        sleep 2
                        
                        if redis-cli ping 2>/dev/null | grep -q "PONG"; then
                            print_success "Redis yapılandırması düzeltildi ve bağlantı başarılı!"
                        else
                            print_error "Yapılandırma değişikliği sonrası hala bağlantı kurulamıyor"
                        fi
                    fi
                fi
            fi
        fi
    fi
    
    # Laravel .env için bilgi
    echo ""
    print_info "Laravel .env yapılandırması için:"
    echo -e "${CYAN}REDIS_HOST=127.0.0.1${NC}"
    echo -e "${CYAN}REDIS_PASSWORD=null${NC}"
    echo -e "${CYAN}REDIS_PORT=6379${NC}"
}

fix_git_safe_directory() {
    print_info "Git safe.directory yapılandırması kontrol ediliyor..."
    
    # /var/www altındaki tüm dizinleri safe.directory'e ekle
    if [ -d "/var/www" ]; then
        for dir in /var/www/*; do
            if [ -d "$dir/.git" ]; then
                local dir_name=$(basename "$dir")
                print_info "Git safe.directory ekleniyor: $dir"
                
                # Root için ekle
                git config --global --add safe.directory "$dir" 2>/dev/null || true
                
                # www-data kullanıcısı için ekle (varsa)
                if id -u www-data &>/dev/null; then
                    sudo -u www-data git config --global --add safe.directory "$dir" 2>/dev/null || true
                fi
                
                # Dizin sahipliğini düzelt (www-data:www-data)
                if [ -d "$dir" ]; then
                    print_info "Dizin sahipliği düzeltiliyor: $dir"
                    chown -R www-data:www-data "$dir" 2>/dev/null || true
                fi
            fi
        done
        
        print_success "Git safe.directory yapılandırması tamamlandı"
    fi
}

fix_php_duplicate_modules() {
    local php_version=$1
    
    print_header "PHP Çift Yükleme Sorunu Düzeltme"
    
    # Eğer parametre verilmediyse tespit et
    if [ -z "$php_version" ]; then
        # Yöntem 1: php -v
        php_version=$(php -v 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
        
        # Yöntem 2: PHP-FPM servisleri
        if [ -z "$php_version" ]; then
            php_version=$(systemctl list-units --type=service --all 2>/dev/null | grep "php.*-fpm" | head -1 | sed 's/.*php\([0-9.]*\)-fpm.*/\1/' | grep -E "^[0-9]+\.[0-9]+" || echo "")
        fi
        
        # Yöntem 3: dpkg paketleri
        if [ -z "$php_version" ]; then
            php_version=$(dpkg -l 2>/dev/null | grep -E "^ii.*php[0-9]+\.[0-9]+-fpm" | head -1 | awk '{print $2}' | sed 's/php\([0-9.]*\)-fpm.*/\1/' || echo "")
        fi
        
        if [ -z "$php_version" ]; then
            print_error "PHP kurulu değil veya versiyon tespit edilemedi!"
            print_info "Lütfen PHP versiyonunu parametre olarak verin: fix_php_duplicate_modules 8.3"
            return 1
        fi
    fi
    
    print_info "PHP versiyonu: $php_version"
    print_info "Çift yükleme sorunları kontrol ediliyor..."
    
    # Tüm conf.d dizinlerindeki linkleri kontrol et ve temizle
    for conf_dir in "/etc/php/$php_version/cli/conf.d" "/etc/php/$php_version/fpm/conf.d"; do
        if [ -d "$conf_dir" ]; then
            print_info "Kontrol ediliyor: $conf_dir"
            
            # dom ve xml için TÜMU linkleri say
            local dom_links=($(find "$conf_dir" -type l -name "*dom*" 2>/dev/null))
            local xml_links=($(find "$conf_dir" -type l -name "*xml*" 2>/dev/null))
            
            print_info "Mevcut dom linkleri: ${#dom_links[@]}, xml linkleri: ${#xml_links[@]}"
            
            # dom için temizlik ve yeniden oluşturma (link sayısı ne olursa olsun)
            if [ ${#dom_links[@]} -ge 1 ]; then
                # Uyarı seviyesini ayarla
                if [ ${#dom_links[@]} -gt 1 ]; then
                    print_warning "dom için ${#dom_links[@]} link bulundu, TEMİZLENİYOR..."
                else
                    print_info "dom için ${#dom_links[@]} link bulundu, YENİDEN YAPILANDIRILIYOR..."
                fi
                
                # HEPSİNİ sil (hatalı olanlar da olabilir)
                find "$conf_dir" -type l -name "*dom*" -delete 2>/dev/null || true
                
                # Sadece DOĞRU olanı yeniden oluştur
                if [ -f "/etc/php/$php_version/mods-available/dom.ini" ]; then
                    ln -sf "/etc/php/$php_version/mods-available/dom.ini" "$conf_dir/20-dom.ini"
                    print_success "✓ dom modülü: $conf_dir/20-dom.ini"
                fi
            elif [ -f "/etc/php/$php_version/mods-available/dom.ini" ]; then
                # Hiç link yok ama .ini var, oluştur
                print_info "dom linki eksik, oluşturuluyor..."
                ln -sf "/etc/php/$php_version/mods-available/dom.ini" "$conf_dir/20-dom.ini"
                print_success "✓ dom modülü: $conf_dir/20-dom.ini"
            fi
            
            # xml için temizlik ve yeniden oluşturma (link sayısı ne olursa olsun)
            if [ ${#xml_links[@]} -ge 1 ]; then
                # Uyarı seviyesini ayarla
                if [ ${#xml_links[@]} -gt 1 ]; then
                    print_warning "xml için ${#xml_links[@]} link bulundu, TEMİZLENİYOR..."
                else
                    print_info "xml için ${#xml_links[@]} link bulundu, YENİDEN YAPILANDIRILIYOR..."
                fi
                
                # HEPSİNİ sil (hatalı olanlar da olabilir)
                find "$conf_dir" -type l -name "*xml*" -delete 2>/dev/null || true
                
                # Sadece DOĞRU olanı yeniden oluştur
                if [ -f "/etc/php/$php_version/mods-available/xml.ini" ]; then
                    ln -sf "/etc/php/$php_version/mods-available/xml.ini" "$conf_dir/15-xml.ini"
                    print_success "✓ xml modülü: $conf_dir/15-xml.ini"
                fi
            elif [ -f "/etc/php/$php_version/mods-available/xml.ini" ]; then
                # Hiç link yok ama .ini var, oluştur
                print_info "xml linki eksik, oluşturuluyor..."
                ln -sf "/etc/php/$php_version/mods-available/xml.ini" "$conf_dir/15-xml.ini"
                print_success "✓ xml modülü: $conf_dir/15-xml.ini"
            fi
        fi
    done
    
    # mods-available dizinindeki .ini dosyalarını kontrol et ve düzelt
    local mods_dir="/etc/php/$php_version/mods-available"
    
    print_info ".ini dosyaları kontrol ediliyor: $mods_dir"
    
    # dom.ini kontrolü ve temizliği
    if [ -f "$mods_dir/dom.ini" ]; then
        local dom_content=$(cat "$mods_dir/dom.ini")
        local dom_extension_count=$(echo "$dom_content" | grep -c "^extension=dom.so" || echo "0")
        
        # Her durumda temiz bir .ini dosyası oluştur (duplicate veya bozuk olabilir)
        if [ "$dom_extension_count" -gt 1 ]; then
            print_warning "dom.ini içinde çift 'extension=dom.so' satırı var, düzeltiliyor..."
        elif [ "$dom_extension_count" -eq 0 ]; then
            print_warning "dom.ini içinde 'extension=dom.so' satırı yok, ekleniyor..."
        else
            print_info "dom.ini kontrol ediliyor ve yeniden yazılıyor (standart format)..."
        fi
        
        # Yedek oluştur
        cp "$mods_dir/dom.ini" "$mods_dir/dom.ini.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        
        # Temiz dosya oluştur
        cat > "$mods_dir/dom.ini" <<'EOF'
; configuration for php dom module
; priority=20
extension=dom.so
EOF
        chmod 644 "$mods_dir/dom.ini"
        print_success "✓ dom.ini standart formata getirildi"
    else
        print_warning "dom.ini bulunamadı, oluşturuluyor..."
        cat > "$mods_dir/dom.ini" <<'EOF'
; configuration for php dom module
; priority=20
extension=dom.so
EOF
        chmod 644 "$mods_dir/dom.ini"
        print_success "✓ dom.ini oluşturuldu"
    fi
    
    # xml.ini kontrolü ve temizliği
    if [ -f "$mods_dir/xml.ini" ]; then
        local xml_content=$(cat "$mods_dir/xml.ini")
        local xml_extension_count=$(echo "$xml_content" | grep -c "^extension=xml.so" || echo "0")
        
        # Her durumda temiz bir .ini dosyası oluştur
        if [ "$xml_extension_count" -gt 1 ]; then
            print_warning "xml.ini içinde çift 'extension=xml.so' satırı var, düzeltiliyor..."
        elif [ "$xml_extension_count" -eq 0 ]; then
            print_warning "xml.ini içinde 'extension=xml.so' satırı yok, ekleniyor..."
        else
            print_info "xml.ini kontrol ediliyor ve yeniden yazılıyor (standart format)..."
        fi
        
        # Yedek oluştur
        cp "$mods_dir/xml.ini" "$mods_dir/xml.ini.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        
        # Temiz dosya oluştur
        cat > "$mods_dir/xml.ini" <<'EOF'
; configuration for php xml module
; priority=15
extension=xml.so
EOF
        chmod 644 "$mods_dir/xml.ini"
        print_success "✓ xml.ini standart formata getirildi"
    else
        print_warning "xml.ini bulunamadı, oluşturuluyor..."
        cat > "$mods_dir/xml.ini" <<'EOF'
; configuration for php xml module
; priority=15
extension=xml.so
EOF
        chmod 644 "$mods_dir/xml.ini"
        print_success "✓ xml.ini oluşturuldu"
    fi
    
    # Şimdi linkleri YENİDEN oluştur (link sayısına bakılmaksızın)
    print_info "Modül linkleri yeniden oluşturuluyor (her iki durumda da aynı sonuç)..."
    for conf_dir in "/etc/php/$php_version/cli/conf.d" "/etc/php/$php_version/fpm/conf.d"; do
        if [ -d "$conf_dir" ]; then
            # dom linkini yeniden oluştur
            rm -f "$conf_dir"/*dom* 2>/dev/null || true
            if [ -f "$mods_dir/dom.ini" ]; then
                ln -sf "$mods_dir/dom.ini" "$conf_dir/20-dom.ini"
            fi
            
            # xml linkini yeniden oluştur
            rm -f "$conf_dir"/*xml* 2>/dev/null || true
            if [ -f "$mods_dir/xml.ini" ]; then
                ln -sf "$mods_dir/xml.ini" "$conf_dir/15-xml.ini"
            fi
            
            print_success "✓ Linkler yeniden oluşturuldu: $conf_dir"
        fi
    done
    
    # PHP-FPM'i yeniden başlat
    print_info "PHP-FPM yeniden başlatılıyor..."
    systemctl restart php$php_version-fpm 2>/dev/null || true
    sleep 3
    
    echo ""
    print_header "SONUÇ DOĞRULAMA"
    
    # Test et
    print_info "PHP modül yükleme testi yapılıyor..."
    
    local php_binary="php$php_version"
    # PHP binary'yi kontrol et
    if ! command -v $php_binary &> /dev/null; then
        php_binary="php"
    fi
    
    # CLI test
    print_info "1) PHP CLI testi..."
    local cli_warnings=$($php_binary -v 2>&1 | grep -i "warning.*already loaded" || echo "")
    
    if [ -z "$cli_warnings" ]; then
        print_success "✓ PHP CLI: Uyarı yok"
        echo "   $($php_binary -v 2>&1 | head -1)"
    else
        print_error "✗ PHP CLI: Hala uyarılar var"
        echo "$cli_warnings"
    fi
    
    # FPM test (eğer çalışıyorsa)
    if systemctl is-active --quiet php$php_version-fpm 2>/dev/null; then
        print_info "2) PHP-FPM log testi..."
        local fpm_warnings=$(journalctl -u php$php_version-fpm -n 10 --no-pager 2>/dev/null | grep -i "warning.*already loaded" || echo "")
        
        if [ -z "$fpm_warnings" ]; then
            print_success "✓ PHP-FPM: Uyarı yok"
        else
            print_error "✗ PHP-FPM: Hala uyarılar var"
            echo "$fpm_warnings"
        fi
    fi
    
    # Modül listesi
    echo ""
    print_info "3) Yüklü modüller kontrol ediliyor..."
    if $php_binary -m 2>&1 | grep -qi "^dom$" && $php_binary -m 2>&1 | grep -qi "^xml$"; then
        print_success "✓ dom ve xml modülleri YÜKLENDİ"
    else
        print_error "✗ dom veya xml modülü YÜKLENEMEDİ!"
        print_info "Yüklü modüller:"
        $php_binary -m 2>&1 | grep -E "^(dom|xml|simplexml|xmlreader|xmlwriter)$" || echo "  [Hiçbiri yüklü değil]"
    fi
    
    echo ""
    
    # Sonuç özeti
    if [ -z "$cli_warnings" ] && [ -z "$fpm_warnings" ]; then
        print_success "════════════════════════════════════════"
        print_success "  ✓ SORUN TAMAMEN DÜZELTİLDİ!"
        print_success "════════════════════════════════════════"
        echo ""
        print_info "Composer artık hatasız çalışmalı:"
        echo "  composer install"
        echo "  composer update"
    else
        print_warning "════════════════════════════════════════"
        print_warning "  ⚠ SORUN KISMEN DÜZELDİ"
        print_warning "════════════════════════════════════════"
        echo ""
        print_info "Link durumunu kontrol edin:"
        echo "  sudo ls -la /etc/php/$php_version/cli/conf.d/ | grep -E 'dom|xml'"
        echo "  sudo ls -la /etc/php/$php_version/fpm/conf.d/ | grep -E 'dom|xml'"
        echo ""
        print_info ".ini dosyalarını kontrol edin:"
        echo "  sudo cat /etc/php/$php_version/mods-available/dom.ini"
        echo "  sudo cat /etc/php/$php_version/mods-available/xml.ini"
    fi
}

quick_fix_php_extensions() {
    print_header "Eksik PHP Eklentilerini Hızlı Düzeltme"
    
    # PHP versiyonunu tespit et (birden fazla yöntem)
    local php_version=""
    local php_binary="php"
    
    # Yöntem 1: php -v komutundan versiyon al
    if command -v php &> /dev/null; then
        php_version=$(php -v 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
        if [ -n "$php_version" ]; then
            print_info "PHP CLI'den versiyon tespit edildi: $php_version"
        fi
    fi
    
    # Yöntem 2: /usr/bin/php* dosyalarından versiyon bul
    if [ -z "$php_version" ]; then
        print_info "Alternatif PHP binary'leri aranıyor..."
        for php_bin in /usr/bin/php8.4 /usr/bin/php8.3 /usr/bin/php8.2 /usr/bin/php8.1 /usr/bin/php[0-9]* /usr/bin/php[0-9]*.[0-9]*; do
            if [ -f "$php_bin" ] && [ -x "$php_bin" ]; then
                php_version=$($php_bin -v 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
                if [ -n "$php_version" ]; then
                    php_binary="$php_bin"
                    print_info "PHP binary bulundu: $php_bin (versiyon: $php_version)"
                    break
                fi
            fi
        done
    fi
    
    # Yöntem 3: PHP-FPM servislerinden versiyon bul
    if [ -z "$php_version" ]; then
        print_info "PHP-FPM servisleri kontrol ediliyor..."
        local php_fpm_version=$(systemctl list-units --type=service --all 2>/dev/null | grep "php.*-fpm" | head -1 | sed 's/.*php\([0-9.]*\)-fpm.*/\1/' | grep -E "^[0-9]+\.[0-9]+" || echo "")
        if [ -n "$php_fpm_version" ]; then
            php_version="$php_fpm_version"
            php_binary="php$php_version"
            print_info "PHP-FPM servisinden versiyon tespit edildi: $php_version"
        fi
    fi
    
    # Yöntem 4: dpkg ile kurulu PHP paketlerini kontrol et
    if [ -z "$php_version" ]; then
        print_info "Kurulu PHP paketleri kontrol ediliyor..."
        local php_package=$(dpkg -l 2>/dev/null | grep -E "^ii.*php[0-9]+\.[0-9]+-fpm" | head -1 | awk '{print $2}' | sed 's/php\([0-9.]*\)-fpm.*/\1/' || echo "")
        if [ -n "$php_package" ]; then
            php_version="$php_package"
            php_binary="php$php_version"
            print_info "Kurulu paketlerden versiyon tespit edildi: $php_version"
        fi
    fi
    
    # Hala bulunamadıysa
    if [ -z "$php_version" ]; then
        print_error "PHP kurulu değil veya versiyon tespit edilemedi!"
        echo ""
        print_info "PHP kurulumu kontrol ediliyor..."
        
        # PHP gerçekten kurulu değil mi?
        if ! dpkg -l 2>/dev/null | grep -qE "^ii.*php[0-9]"; then
            print_warning "PHP kurulu görünmüyor!"
            if ask_yes_no "PHP kurmak ister misiniz?"; then
                echo ""
                echo "PHP versiyonu seçin:"
                echo "1) PHP 8.3 (Önerilen)"
                echo "2) PHP 8.4"
                read -p "Seçiminiz (1-2) [1]: " php_choice
                local selected_version="8.3"
                case $php_choice in
                    2) selected_version="8.4";;
                    *) selected_version="8.3";;
                esac
                
                # PHP kurulumu için framework seçeneği (opsiyonel)
                local temp_framework=""
                if ask_yes_no "Framework'e özel ek paketler kurulsun mu?"; then
                    echo "1) Laravel"
                    echo "2) Symfony"
                    echo "3) CodeIgniter"
                    echo "4) Genel"
                    read -p "Seçiminiz (1-4) [1]: " fw_choice
                    case $fw_choice in
                        1) temp_framework="laravel";;
                        2) temp_framework="symfony";;
                        3) temp_framework="codeigniter";;
                        *) temp_framework="";;
                    esac
                fi
                
                local old_framework="$FRAMEWORK"
                FRAMEWORK="$temp_framework"
                
                install_php $selected_version
                local install_result=$?
                
                FRAMEWORK="$old_framework"
                
                if [ $install_result -eq 0 ]; then
                    php_version="$selected_version"
                    php_binary="php$selected_version"
                    print_success "PHP kurulumu tamamlandı, devam ediliyor..."
                else
                    print_error "PHP kurulumu başarısız!"
                    return 1
                fi
            else
                print_info "PHP kurulumu iptal edildi"
                return 1
            fi
        else
            # PHP kurulu ama versiyonu tespit edilemiyor
            print_warning "PHP kurulu ancak versiyon tespit edilemedi"
            read -p "PHP versiyonunu manuel olarak girin (örn: 8.3, 8.4): " manual_version
            if [ -n "$manual_version" ]; then
                php_version="$manual_version"
                php_binary="php$manual_version"
                print_info "Manuel versiyon kullanılıyor: $php_version"
            else
                print_error "Versiyon belirtilmedi, işlem iptal edildi"
                return 1
            fi
        fi
    fi
    
    print_success "PHP versiyonu: $php_version"
    print_info "PHP binary: $php_binary"
    echo ""
    
    # Önce çift yükleme sorunlarını HER ZAMAN düzelt (kontrol değil, önleyici bakım)
    print_info "PHP modül yapılandırması temizleniyor ve yeniden oluşturuluyor..."
    echo ""
    
    # dom/xml uyarısı var mı kontrol et
    local has_warnings=false
    local cli_warnings=$($php_binary -v 2>&1 | grep -i "warning.*already loaded" || echo "")
    
    if [ -n "$cli_warnings" ]; then
        has_warnings=true
        print_warning "PHP'de çift yükleme uyarıları tespit edildi:"
        echo "$cli_warnings"
        echo ""
    fi
    
    # Her durumda temizlik yap (önleyici)
    if [ "$has_warnings" = true ]; then
        print_info "Çift yükleme sorunları düzeltiliyor..."
    else
        print_info "Modül yapılandırması optimize ediliyor (önleyici bakım)..."
    fi
    
    fix_php_duplicate_modules "$php_version"
    
    echo ""
    
    # Şimdi mevcut durumu göster
    print_info "Mevcut PHP eklentileri kontrol ediliyor..."
    echo "Kurulu eklentiler:"
    $php_binary -m 2>/dev/null | grep -v "^\[" | head -20
    echo ""
    
    # Kritik eklentiler listesi (Composer ve Laravel için)
    local critical_extensions=("simplexml" "xmlreader" "xmlwriter" "fileinfo" "tokenizer" "iconv" "ctype" "phar" "redis" "memcached")
    local missing_extensions=()
    
    print_info "Eksik eklentiler tespit ediliyor..."
    for ext in "${critical_extensions[@]}"; do
        if ! $php_binary -m 2>/dev/null | grep -qi "^$ext$"; then
            missing_extensions+=("$ext")
            print_warning "✗ $ext eksik"
        else
            print_success "✓ $ext kurulu"
        fi
    done
    
    if [ ${#missing_extensions[@]} -eq 0 ]; then
        print_success "Tüm kritik eklentiler zaten kurulu!"
        fix_git_safe_directory
        return 0
    fi
    
    print_warning "${#missing_extensions[@]} eklenti eksik: ${missing_extensions[*]}"
    echo ""
    
    # php-xml ve php-common paketlerini önce kur/güncelle
    print_info "Gerekli PHP paketleri kuruluyor..."
    apt update
    
    # XML paketini kaldır ve yeniden kur (simplexml sorunu için)
    print_info "php$php_version-xml paketi temiz kurulum yapılıyor..."
    apt remove -y php$php_version-xml 2>/dev/null || true
    apt install -y php$php_version-xml php$php_version-common 2>/dev/null || true
    
    # Her eksik eklenti için düzeltme yap
    local fixed_count=0
    for ext in "${missing_extensions[@]}"; do
        print_info "[$ext] Düzeltiliyor..."
        
        # 1. mods-available dizininde .ini dosyası var mı?
        local ini_file="/etc/php/$php_version/mods-available/$ext.ini"
        
        if [ ! -f "$ini_file" ]; then
            print_info "[$ext] .ini dosyası oluşturuluyor: $ini_file"
            echo "; priority=20" > "$ini_file"
            echo "; configuration for php $ext module" >> "$ini_file"
            echo "extension=$ext.so" >> "$ini_file"
        else
            print_info "[$ext] .ini dosyası mevcut"
        fi
        
        # 2. Eklentiyi etkinleştir
        print_info "[$ext] Etkinleştiriliyor..."
        phpenmod -v $php_version $ext 2>/dev/null || true
        
        # 3. CLI ve FPM conf.d dizinlerinde link var mı kontrol et
        for conf_dir in "/etc/php/$php_version/cli/conf.d" "/etc/php/$php_version/fpm/conf.d"; do
            if [ -d "$conf_dir" ]; then
                local link_file="$conf_dir/20-$ext.ini"
                if [ ! -L "$link_file" ]; then
                    print_info "[$ext] Link oluşturuluyor: $link_file"
                    ln -sf "$ini_file" "$link_file" 2>/dev/null || true
                fi
            fi
        done
        
        # 4. Tekrar kontrol
        sleep 1
        if php -m 2>/dev/null | grep -qi "^$ext$"; then
            print_success "[$ext] Başarıyla etkinleştirildi!"
            ((fixed_count++))
        else
            print_error "[$ext] Hala yüklenemiyor!"
            
            # Son çare: İlgili paketi yeniden kur
            if [ "$ext" = "simplexml" ] || [ "$ext" = "xmlreader" ] || [ "$ext" = "xmlwriter" ]; then
                print_info "[$ext] php$php_version-xml paketi yeniden kuruluyor..."
                apt remove -y php$php_version-xml 2>/dev/null || true
                apt install -y php$php_version-xml 2>/dev/null || true
            elif [ "$ext" = "redis" ]; then
                print_info "[$ext] php$php_version-redis paketi kuruluyor..."
                apt install -y php$php_version-redis 2>/dev/null || true
            elif [ "$ext" = "memcached" ]; then
                print_info "[$ext] php$php_version-memcached paketi kuruluyor..."
                apt install -y php$php_version-memcached 2>/dev/null || true
            else
                print_info "[$ext] php$php_version-common paketi yeniden kuruluyor..."
                apt install --reinstall -y php$php_version-common 2>/dev/null || true
            fi
            
            # Tekrar etkinleştir
            phpenmod -v $php_version $ext 2>/dev/null || true
            
            # Son kontrol
            sleep 1
            if php -m 2>/dev/null | grep -qi "^$ext$"; then
                print_success "[$ext] Başarıyla etkinleştirildi (ikinci deneme)!"
                ((fixed_count++))
            else
                print_error "[$ext] Etkinleştirilemedi! Manuel kontrol gerekli."
            fi
        fi
    done
    
    # PHP-FPM'i yeniden başlat
    print_info "PHP-FPM yeniden başlatılıyor..."
    systemctl restart php$php_version-fpm 2>/dev/null || true
    sleep 2
    
    # simplexml özel kontrolü (genellikle php-xml ile gelir ama bazen görünmez)
    if ! $php_binary -m 2>/dev/null | grep -qi "^simplexml$"; then
        print_warning "simplexml hala görünmüyor, özel düzeltme yapılıyor..."
        
        # libxml2 ve php-xml bağımlılıklarını kontrol et
        apt install -y libxml2 libxml2-dev 2>/dev/null || true
        
        # php-xml'i tamamen kaldır ve yeniden kur
        apt purge -y php$php_version-xml 2>/dev/null || true
        apt autoremove -y 2>/dev/null || true
        apt install -y php$php_version-xml 2>/dev/null || true
        
        # Tüm XML eklentilerini etkinleştir
        phpenmod -v $php_version xml 2>/dev/null || true
        phpenmod -v $php_version simplexml 2>/dev/null || true
        phpenmod -v $php_version xmlreader 2>/dev/null || true
        phpenmod -v $php_version xmlwriter 2>/dev/null || true
        phpenmod -v $php_version dom 2>/dev/null || true
        
        # PHP-FPM'i tekrar başlat
        systemctl restart php$php_version-fpm 2>/dev/null || true
        sleep 2
        
        # Son kontrol
        if $php_binary -m 2>/dev/null | grep -qi "^simplexml$"; then
            print_success "simplexml başarıyla yüklendi (özel düzeltme)"
        else
            print_error "simplexml yüklenemedi! php$php_version-xml paketi sorunlu olabilir"
            print_info "Manuel düzeltme: sudo apt purge php$php_version-xml && sudo apt install php$php_version-xml"
        fi
    fi
    
    # Sonuçları göster
    echo ""
    print_info "=== SONUÇ ==="
    print_info "Düzeltilen eklentiler: $fixed_count / ${#missing_extensions[@]}"
    echo ""
    print_info "Tüm PHP eklentileri:"
    $php_binary -m 2>/dev/null | grep -v "^\[" | sort
    echo ""
    
    # Kritik eklentileri tekrar kontrol et
    print_info "Kritik eklentiler son kontrol:"
    for ext in "${critical_extensions[@]}"; do
        if $php_binary -m 2>/dev/null | grep -qi "^$ext$"; then
            print_success "✓ $ext"
        else
            print_error "✗ $ext HALA EKSİK!"
        fi
    done
    
    # Git safe.directory'yi de düzelt
    echo ""
    fix_git_safe_directory
    
    # Redis bağlantı testi (Laravel için önemli)
    echo ""
    print_info "Redis bağlantı durumu kontrol ediliyor..."
    if command -v redis-cli &>/dev/null; then
        if systemctl is-active --quiet redis-server 2>/dev/null || systemctl is-active --quiet redis 2>/dev/null; then
            if redis-cli ping 2>/dev/null | grep -q "PONG"; then
                print_success "✓ Redis çalışıyor ve bağlanılabilir"
            else
                print_warning "✗ Redis çalışıyor ama bağlantı kurulamıyor"
                print_info "Düzeltmek için: Ana Menü > 26) Redis Bağlantı Sorunu Düzelt"
            fi
        else
            print_warning "✗ Redis servisi çalışmıyor"
            print_info "Başlatmak için: sudo systemctl start redis-server"
        fi
    else
        print_info "Redis kurulu değil (Laravel için opsiyonel)"
    fi
    
    # Composer test (eğer varsa)
    echo ""
    if command -v composer &>/dev/null; then
        print_info "Composer çalışıyor mu test ediliyor..."
        if composer --version &>/dev/null 2>&1; then
            print_success "✓ Composer çalışıyor: $(composer --version 2>/dev/null | head -1)"
            echo ""
            print_info "════════════════════════════════════════"
            print_info "  🎉 HER ŞEY HAZIR!"
            print_info "════════════════════════════════════════"
            echo ""
            print_info "Laravel projenizde çalıştırabilirsiniz:"
            echo "  ${GREEN}composer install${NC}"
            echo "  ${GREEN}composer update${NC}"
            echo "  ${GREEN}php artisan migrate${NC}"
        else
            print_warning "✗ Composer kurulu ama hata veriyor"
            print_info "Tekrar test edin: composer --version"
        fi
    else
        print_info "Composer kurulu değil"
        print_info "Kurmak için: Ana Menü > 10) Tekil Servis Kurulumu > 6) Composer"
    fi
}

install_composer() {
    print_info "Composer kuruluyor..."
    
    # PHP kurulu mu kontrol et
    if ! command -v php &> /dev/null; then
        print_error "PHP kurulu değil! Önce PHP kurulumu yapmanız gerekiyor."
        return 1
    fi
    
    # PHP versiyonunu tespit et
    local php_version=$(php -v 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
    
    if [ -z "$php_version" ]; then
        print_error "PHP versiyonu tespit edilemedi!"
        return 1
    fi
    
    print_info "PHP versiyonu: $php_version"
    
    # Composer için gerekli PHP eklentilerini kontrol et
    print_info "Composer için gerekli PHP eklentileri kontrol ediliyor..."
    
    local required_for_composer=("phar" "json" "mbstring" "openssl" "curl" "zip" "fileinfo" "tokenizer" "iconv" "ctype" "simplexml" "xmlreader" "xmlwriter")
    local missing_for_composer=()
    
    for ext in "${required_for_composer[@]}"; do
        if ! php -m 2>/dev/null | grep -qi "^$ext$"; then
            missing_for_composer+=("$ext")
        fi
    done
    
    # Eksik eklentileri kur
    if [ ${#missing_for_composer[@]} -gt 0 ]; then
        print_warning "Composer için gerekli eklentiler eksik: ${missing_for_composer[*]}"
        print_info "Eksik eklentiler kuruluyor..."
        
        for ext in "${missing_for_composer[@]}"; do
            local pkg="php$php_version-$ext"
            
            # Özel durum: bazı eklentiler php-common veya php-xml ile gelir
            if [ "$ext" = "phar" ] || [ "$ext" = "fileinfo" ] || [ "$ext" = "tokenizer" ] || [ "$ext" = "iconv" ] || [ "$ext" = "ctype" ] || [ "$ext" = "simplexml" ] || [ "$ext" = "xmlreader" ] || [ "$ext" = "xmlwriter" ]; then
                print_info "$ext eklentisi etkinleştiriliyor..."
                
                # Eklenti genellikle PHP ile birlikte gelir, sadece etkinleştirmek gerekebilir
                if [ -f "/etc/php/$php_version/mods-available/$ext.ini" ]; then
                    phpenmod -v $php_version $ext 2>/dev/null || true
                else
                    # .ini dosyası yoksa oluştur
                    echo "; configuration for php $ext module" > "/etc/php/$php_version/mods-available/$ext.ini"
                    echo "extension=$ext.so" >> "/etc/php/$php_version/mods-available/$ext.ini"
                    phpenmod -v $php_version $ext 2>/dev/null || true
                fi
                
                # Hala yoksa ilgili paketi yeniden kur
                if ! php -m 2>/dev/null | grep -qi "^$ext$"; then
                    # simplexml, xmlreader, xmlwriter için php-xml paketi gerekli
                    if [ "$ext" = "simplexml" ] || [ "$ext" = "xmlreader" ] || [ "$ext" = "xmlwriter" ]; then
                        print_info "php$php_version-xml yeniden kuruluyor ($ext için)..."
                        apt install --reinstall -y php$php_version-xml 2>/dev/null || true
                    else
                        print_info "php$php_version-common yeniden kuruluyor ($ext için)..."
                        apt install --reinstall -y php$php_version-common 2>/dev/null || true
                    fi
                fi
            else
                # Diğer eklentiler için normal kurulum
                if apt-cache search "$pkg" 2>/dev/null | grep -q "^$pkg "; then
                    print_info "$pkg kuruluyor..."
                    apt install -y $pkg 2>/dev/null || true
                fi
            fi
        done
        
        # PHP-FPM'i yeniden başlat (varsa)
        if systemctl is-active --quiet php$php_version-fpm 2>/dev/null; then
            print_info "PHP-FPM yeniden başlatılıyor..."
            systemctl restart php$php_version-fpm
        fi
        
        # Tekrar kontrol et
        print_info "Eklentiler tekrar kontrol ediliyor..."
        local still_missing=()
        for ext in "${required_for_composer[@]}"; do
            if ! php -m 2>/dev/null | grep -qi "^$ext$"; then
                still_missing+=("$ext")
            fi
        done
        
        if [ ${#still_missing[@]} -gt 0 ]; then
            print_error "Bazı eklentiler hala eksik: ${still_missing[*]}"
            print_warning "Composer çalışmayabilir!"
        else
            print_success "Tüm gerekli eklentiler kuruldu"
        fi
    else
        print_success "Tüm gerekli eklentiler mevcut"
    fi
    
    # Mevcut Composer kurulumunu kontrol et
    if command -v composer &> /dev/null; then
        local current_version=$(composer --version 2>/dev/null | head -1 || echo "Bilinmiyor")
        print_info "Composer zaten kurulu: $current_version"
        
        if ask_yes_no "Composer'ı güncellemek ister misiniz?"; then
            print_info "Composer güncelleniyor..."
            composer self-update 2>/dev/null || {
                print_warning "Composer güncelleme başarısız, yeniden kurulum yapılıyor..."
                rm -f /usr/local/bin/composer
            }
        else
            print_info "Composer kurulumu atlandı"
            return 0
        fi
    fi
    
    # Composer kurulumu
    if [ ! -f "/usr/local/bin/composer" ]; then
        print_info "Composer indiriliyor ve kuruluyor..."
        
        # Composer installer'ı indir ve kur
        if curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer; then
            chmod +x /usr/local/bin/composer
            print_success "Composer kurulumu tamamlandı"
            
            # Versiyon bilgisi
            if command -v composer &> /dev/null; then
                local version=$(composer --version 2>/dev/null | head -1 || echo "Bilinmiyor")
                echo -e "${GREEN}Composer Versiyonu:${NC} $version"
            fi
        else
            print_error "Composer kurulumu başarısız oldu!"
            return 1
        fi
    fi
    
    # Son kontrol
    if command -v composer &> /dev/null; then
        print_info "Composer çalışıyor mu test ediliyor..."
        if composer --version &> /dev/null; then
            print_success "Composer başarıyla kuruldu ve çalışıyor!"
            
            # Git safe.directory yapılandırmasını düzelt
            fix_git_safe_directory
        else
            print_error "Composer kurulu ama çalışmıyor!"
            print_info "Eksik eklentileri kontrol edin: php -m"
            return 1
        fi
    else
        print_error "Composer kurulumu başarısız!"
        return 1
    fi
}

install_php_extensions() {
    print_header "PHP Eklentileri Kurulumu"
    
    # PHP kurulu mu kontrol et
    if ! command -v php &> /dev/null; then
        print_error "PHP kurulu değil! Önce PHP kurulumu yapmanız gerekiyor."
        return 1
    fi
    
    # PHP versiyonunu tespit et
    local php_version=$(php -v 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
    
    if [ -z "$php_version" ]; then
        # Alternatif yöntem: /usr/bin/php* dosyalarından
        for php_bin in /usr/bin/php[0-9]* /usr/bin/php[0-9]*.[0-9]*; do
            if [ -f "$php_bin" ] && [ -x "$php_bin" ]; then
                php_version=$(basename "$php_bin" | sed 's/php//' | grep -oE "^[0-9]+\.[0-9]+")
                if [ -n "$php_version" ]; then
                    break
                fi
            fi
        done
    fi
    
    if [ -z "$php_version" ]; then
        print_error "PHP versiyonu tespit edilemedi!"
        read -p "PHP versiyonunu manuel olarak girin (örn: 8.3, 8.4): " php_version
        if [ -z "$php_version" ]; then
            print_error "PHP versiyonu belirtilmedi, işlem iptal edildi."
            return 1
        fi
    fi
    
    print_info "Tespit edilen PHP versiyonu: $php_version"
    echo ""
    
    print_info "Tüm gerekli PHP eklentileri kontrol ediliyor ve eksikler kuruluyor..."
    echo ""
    
    # check_and_install_missing_php_extensions fonksiyonunu çağır
    check_and_install_missing_php_extensions $php_version
    
    if [ $? -eq 0 ]; then
        print_success "PHP eklentileri kurulumu tamamlandı!"
        echo ""
        print_info "Tüm kurulu PHP eklentileri:"
        php$php_version -m 2>/dev/null | grep -v "^\[" | sort
    else
        print_error "PHP eklentileri kurulumunda bazı hatalar oluştu!"
        return 1
    fi
}

# Otomatik optimizasyon fonksiyonları
get_server_specs() {
    # CPU bilgileri
    local cpu_cores=$(nproc)
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
    
    # RAM bilgileri (MB cinsinden)
    local total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    local available_ram_mb=$(free -m | awk '/^Mem:/{print $7}')
    
    # Disk bilgileri
    local total_disk_gb=$(df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')
    local available_disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    # Sistem için ayrılacak RAM (GB)
    local system_ram_gb=2  # Minimum 2GB sistem için
    
    # Kullanılabilir RAM (sistem hariç, MB)
    local usable_ram_mb=$((total_ram_mb - (system_ram_gb * 1024)))
    if [ $usable_ram_mb -lt 512 ]; then
        usable_ram_mb=512  # Minimum 512MB
    fi
    
    # Sonuçları döndür
    echo "$cpu_cores|$total_ram_mb|$usable_ram_mb|$total_disk_gb|$available_disk_gb|$cpu_model"
}

optimize_nginx() {
    print_header "Nginx Performans Optimizasyonu"
    
    if ! command -v nginx &> /dev/null; then
        print_error "Nginx kurulu değil!"
        return 1
    fi
    
    local specs=$(get_server_specs)
    local cpu_cores=$(echo "$specs" | cut -d'|' -f1)
    local total_ram_mb=$(echo "$specs" | cut -d'|' -f2)
    local usable_ram_mb=$(echo "$specs" | cut -d'|' -f3)
    
    print_info "Sunucu Özellikleri:"
    echo -e "  CPU Çekirdek: ${GREEN}$cpu_cores${NC}"
    echo -e "  Toplam RAM: ${GREEN}${total_ram_mb}MB${NC}"
    echo -e "  Kullanılabilir RAM: ${GREEN}${usable_ram_mb}MB${NC}"
    echo ""
    
    # Nginx yapılandırma dosyası
    local nginx_conf="/etc/nginx/nginx.conf"
    local nginx_conf_backup="/etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Yedek oluştur
    cp "$nginx_conf" "$nginx_conf_backup"
    print_info "Yedek oluşturuldu: $nginx_conf_backup"
    
    # Worker processes = CPU çekirdek sayısı
    local worker_processes=$cpu_cores
    if [ $worker_processes -lt 1 ]; then
        worker_processes=1
    fi
    
    # Worker connections hesaplama (RAM'e göre)
    local worker_connections=1024
    if [ $total_ram_mb -ge 4096 ]; then
        worker_connections=4096
    elif [ $total_ram_mb -ge 2048 ]; then
        worker_connections=2048
    elif [ $total_ram_mb -ge 1024 ]; then
        worker_connections=1024
    else
        worker_connections=512
    fi
    
    # Max connections = worker_processes * worker_connections
    local max_connections=$((worker_processes * worker_connections))
    
    # Keepalive timeout
    local keepalive_timeout=65
    
    # Gzip ayarları
    local gzip_types="text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript"
    
    print_info "Önerilen Nginx Ayarları:"
    echo -e "  worker_processes: ${GREEN}$worker_processes${NC}"
    echo -e "  worker_connections: ${GREEN}$worker_connections${NC}"
    echo -e "  max_connections: ${GREEN}$max_connections${NC}"
    echo ""
    
    if ! ask_yes_no "Nginx yapılandırmasını optimize etmek istiyor musunuz?"; then
        print_info "Optimizasyon iptal edildi"
        return 0
    fi
    
    # Nginx yapılandırmasını güncelle
    # worker_processes
    if grep -q "^worker_processes" "$nginx_conf"; then
        sed -i "s/^worker_processes.*/worker_processes $worker_processes;/" "$nginx_conf"
    else
        sed -i "/^user /a worker_processes $worker_processes;" "$nginx_conf"
    fi
    
    # worker_connections
    if grep -q "worker_connections" "$nginx_conf"; then
        sed -i "s/worker_connections.*/worker_connections $worker_connections;/" "$nginx_conf"
    else
        # events bloğunu bul ve ekle
        if grep -q "^events {" "$nginx_conf"; then
            sed -i "/^events {/a \    worker_connections $worker_connections;" "$nginx_conf"
        fi
    fi
    
    # Keepalive timeout
    if grep -q "keepalive_timeout" "$nginx_conf"; then
        sed -i "s/keepalive_timeout.*/keepalive_timeout $keepalive_timeout;/" "$nginx_conf"
    else
        sed -i "/http {/a \    keepalive_timeout $keepalive_timeout;" "$nginx_conf"
    fi
    
    # Gzip optimizasyonu
    if ! grep -q "gzip on" "$nginx_conf"; then
        cat >> "$nginx_conf" <<EOF

    # Gzip Compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types $gzip_types;
    gzip_min_length 1000;
    gzip_disable "msie6";
EOF
    fi
    
    # Open files limit için systemd override
    if [ ! -d "/etc/systemd/system/nginx.service.d" ]; then
        mkdir -p /etc/systemd/system/nginx.service.d
    fi
    
    cat > /etc/systemd/system/nginx.service.d/override.conf <<EOF
[Service]
LimitNOFILE=$max_connections
EOF
    
    systemctl daemon-reload
    
    # Nginx yapılandırmasını test et
    if nginx -t 2>/dev/null; then
        systemctl restart nginx
        print_success "Nginx optimizasyonu tamamlandı!"
        echo -e "${GREEN}Uygulanan Ayarlar:${NC}"
        echo "  • worker_processes: $worker_processes"
        echo "  • worker_connections: $worker_connections"
        echo "  • max_connections: $max_connections"
        echo "  • keepalive_timeout: $keepalive_timeout"
        echo "  • Gzip compression: Aktif"
    else
        print_error "Nginx yapılandırma hatası! Yedek geri yükleniyor..."
        cp "$nginx_conf_backup" "$nginx_conf"
        nginx -t
        return 1
    fi
}

optimize_php_fpm() {
    print_header "PHP-FPM Performans Optimizasyonu"
    
    # PHP versiyonunu tespit et
    local php_version=$(php -v 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
    
    if [ -z "$php_version" ]; then
        print_error "PHP kurulu değil veya versiyon tespit edilemedi!"
        return 1
    fi
    
    local php_fpm_pool="/etc/php/$php_version/fpm/pool.d/www.conf"
    
    if [ ! -f "$php_fpm_pool" ]; then
        print_error "PHP-FPM pool yapılandırma dosyası bulunamadı: $php_fpm_pool"
        return 1
    fi
    
    local specs=$(get_server_specs)
    local cpu_cores=$(echo "$specs" | cut -d'|' -f1)
    local total_ram_mb=$(echo "$specs" | cut -d'|' -f2)
    local usable_ram_mb=$(echo "$specs" | cut -d'|' -f3)
    
    print_info "Sunucu Özellikleri:"
    echo -e "  CPU Çekirdek: ${GREEN}$cpu_cores${NC}"
    echo -e "  Toplam RAM: ${GREEN}${total_ram_mb}MB${NC}"
    echo -e "  Kullanılabilir RAM: ${GREEN}${usable_ram_mb}MB${NC}"
    echo ""
    
    # PHP memory_limit'i al
    local memory_limit=$(php -i 2>/dev/null | grep "memory_limit" | awk '{print $3}' | head -1)
    if [ -z "$memory_limit" ]; then
        memory_limit="128M"
    fi
    
    # Memory limit'i MB'ye çevir
    local memory_limit_mb=$(echo "$memory_limit" | sed 's/M//' | sed 's/m//')
    if [ -z "$memory_limit_mb" ] || [ "$memory_limit_mb" = "0" ]; then
        memory_limit_mb=128
    fi
    
    # PHP-FPM max_children hesaplama
    # Formül: (Kullanılabilir RAM - 500MB) / (memory_limit * 1.2)
    local reserved_ram=500
    local available_for_php=$((usable_ram_mb - reserved_ram))
    if [ $available_for_php -lt 256 ]; then
        available_for_php=256
    fi
    
    local max_children=$((available_for_php / (memory_limit_mb * 120 / 100)))
    if [ $max_children -lt 5 ]; then
        max_children=5
    elif [ $max_children -gt 200 ]; then
        max_children=200
    fi
    
    # Diğer değerler
    local start_servers=$((max_children / 4))
    if [ $start_servers -lt 3 ]; then
        start_servers=3
    fi
    
    local min_spare_servers=$start_servers
    local max_spare_servers=$((max_children / 2))
    if [ $max_spare_servers -lt $min_spare_servers ]; then
        max_spare_servers=$min_spare_servers
    fi
    
    local max_requests=500  # Her süreç 500 istekten sonra yeniden başlatılır (memory leak önleme)
    
    print_info "Önerilen PHP-FPM Ayarları:"
    echo -e "  pm.max_children: ${GREEN}$max_children${NC}"
    echo -e "  pm.start_servers: ${GREEN}$start_servers${NC}"
    echo -e "  pm.min_spare_servers: ${GREEN}$min_spare_servers${NC}"
    echo -e "  pm.max_spare_servers: ${GREEN}$max_spare_servers${NC}"
    echo -e "  pm.max_requests: ${GREEN}$max_requests${NC}"
    echo ""
    
    if ! ask_yes_no "PHP-FPM yapılandırmasını optimize etmek istiyor musunuz?"; then
        print_info "Optimizasyon iptal edildi"
        return 0
    fi
    
    # Yedek oluştur
    local php_fpm_backup="$php_fpm_pool.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$php_fpm_pool" "$php_fpm_backup"
    print_info "Yedek oluşturuldu: $php_fpm_backup"
    
    # Process manager modunu dynamic yap
    sed -i "s/^pm = .*/pm = dynamic/" "$php_fpm_pool"
    
    # Ayarları güncelle
    sed -i "s/^pm.max_children = .*/pm.max_children = $max_children/" "$php_fpm_pool"
    sed -i "s/^pm.start_servers = .*/pm.start_servers = $start_servers/" "$php_fpm_pool"
    sed -i "s/^pm.min_spare_servers = .*/pm.min_spare_servers = $min_spare_servers/" "$php_fpm_pool"
    sed -i "s/^pm.max_spare_servers = .*/pm.max_spare_servers = $max_spare_servers/" "$php_fpm_pool"
    sed -i "s/^pm.max_requests = .*/pm.max_requests = $max_requests/" "$php_fpm_pool"
    
    # Process idle timeout
    if ! grep -q "^pm.process_idle_timeout" "$php_fpm_pool"; then
        sed -i "/^pm.max_requests/a pm.process_idle_timeout = 10s" "$php_fpm_pool"
    fi
    
    # PHP-FPM'i yeniden başlat
    if systemctl restart php$php_version-fpm; then
        sleep 2
        if systemctl is-active --quiet php$php_version-fpm; then
            print_success "PHP-FPM optimizasyonu tamamlandı!"
            echo -e "${GREEN}Uygulanan Ayarlar:${NC}"
            echo "  • pm.max_children: $max_children"
            echo "  • pm.start_servers: $start_servers"
            echo "  • pm.min_spare_servers: $min_spare_servers"
            echo "  • pm.max_spare_servers: $max_spare_servers"
            echo "  • pm.max_requests: $max_requests"
        else
            print_error "PHP-FPM başlatılamadı! Yedek geri yükleniyor..."
            cp "$php_fpm_backup" "$php_fpm_pool"
            systemctl restart php$php_version-fpm
            return 1
        fi
    else
        print_error "PHP-FPM yeniden başlatılamadı!"
        return 1
    fi
}

optimize_mysql() {
    print_header "MySQL/MariaDB Performans Optimizasyonu"
    
    if ! systemctl is-active --quiet mariadb && ! systemctl is-active --quiet mysql; then
        print_error "MySQL/MariaDB çalışmıyor veya kurulu değil!"
        return 1
    fi
    
    local specs=$(get_server_specs)
    local total_ram_mb=$(echo "$specs" | cut -d'|' -f2)
    local total_ram_gb=$((total_ram_mb / 1024))
    
    # MySQL yapılandırma dosyası
    local mysql_conf="/etc/mysql/mariadb.conf.d/50-server.cnf"
    if [ ! -f "$mysql_conf" ]; then
        mysql_conf="/etc/mysql/my.cnf"
    fi
    if [ ! -f "$mysql_conf" ]; then
        mysql_conf="/etc/mysql/mysql.conf.d/mysqld.cnf"
    fi
    
    if [ ! -f "$mysql_conf" ]; then
        print_error "MySQL yapılandırma dosyası bulunamadı!"
        return 1
    fi
    
    # InnoDB Buffer Pool Size hesaplama (RAM'in %70'i, min 1GB, max RAM'in %80'i)
    local buffer_pool_gb=$((total_ram_gb * 70 / 100))
    if [ $buffer_pool_gb -lt 1 ]; then
        buffer_pool_gb=1
    fi
    local max_buffer_pool_gb=$((total_ram_gb * 80 / 100))
    if [ $buffer_pool_gb -gt $max_buffer_pool_gb ]; then
        buffer_pool_gb=$max_buffer_pool_gb
    fi
    local buffer_pool_mb=$((buffer_pool_gb * 1024))
    
    # Max connections (RAM'e göre)
    local max_connections=200
    if [ $total_ram_gb -ge 8 ]; then
        max_connections=500
    elif [ $total_ram_gb -ge 4 ]; then
        max_connections=300
    elif [ $total_ram_gb -ge 2 ]; then
        max_connections=200
    else
        max_connections=100
    fi
    
    # Query cache (PHP 8+ ile genelde kullanılmaz ama eski uygulamalar için)
    local query_cache_size=0
    if [ $total_ram_gb -ge 4 ]; then
        query_cache_size=64
    fi
    
    print_info "Önerilen MySQL Ayarları:"
    echo -e "  innodb_buffer_pool_size: ${GREEN}${buffer_pool_mb}M${NC}"
    echo -e "  max_connections: ${GREEN}$max_connections${NC}"
    echo ""
    
    if ! ask_yes_no "MySQL yapılandırmasını optimize etmek istiyor musunuz?"; then
        print_info "Optimizasyon iptal edildi"
        return 0
    fi
    
    # Yedek oluştur
    local mysql_backup="$mysql_conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$mysql_conf" "$mysql_backup"
    print_info "Yedek oluşturuldu: $mysql_backup"
    
    # [mysqld] bölümüne ayarları ekle
    if ! grep -q "^\[mysqld\]" "$mysql_conf"; then
        echo "[mysqld]" >> "$mysql_conf"
    fi
    
    # InnoDB Buffer Pool
    if grep -q "^innodb_buffer_pool_size" "$mysql_conf"; then
        sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${buffer_pool_mb}M/" "$mysql_conf"
    else
        sed -i "/^\[mysqld\]/a innodb_buffer_pool_size = ${buffer_pool_mb}M" "$mysql_conf"
    fi
    
    # Max connections
    if grep -q "^max_connections" "$mysql_conf"; then
        sed -i "s/^max_connections.*/max_connections = $max_connections/" "$mysql_conf"
    else
        sed -i "/^\[mysqld\]/a max_connections = $max_connections" "$mysql_conf"
    fi
    
    # InnoDB log file size
    if ! grep -q "^innodb_log_file_size" "$mysql_conf"; then
        local log_file_size=$((buffer_pool_mb / 4))
        if [ $log_file_size -gt 2048 ]; then
            log_file_size=2048
        fi
        sed -i "/^\[mysqld\]/a innodb_log_file_size = ${log_file_size}M" "$mysql_conf"
    fi
    
    # MySQL'i yeniden başlat
    if systemctl restart mariadb 2>/dev/null || systemctl restart mysql 2>/dev/null; then
        sleep 3
        if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
            print_success "MySQL optimizasyonu tamamlandı!"
            echo -e "${GREEN}Uygulanan Ayarlar:${NC}"
            echo "  • innodb_buffer_pool_size: ${buffer_pool_mb}M"
            echo "  • max_connections: $max_connections"
        else
            print_error "MySQL başlatılamadı! Yedek geri yükleniyor..."
            cp "$mysql_backup" "$mysql_conf"
            systemctl restart mariadb 2>/dev/null || systemctl restart mysql 2>/dev/null
            return 1
        fi
    else
        print_error "MySQL yeniden başlatılamadı!"
        return 1
    fi
}

optimize_redis() {
    print_header "Redis Performans Optimizasyonu"
    
    if ! systemctl is-active --quiet redis; then
        print_error "Redis çalışmıyor veya kurulu değil!"
        return 1
    fi
    
    local specs=$(get_server_specs)
    local total_ram_mb=$(echo "$specs" | cut -d'|' -f2)
    local total_ram_gb=$((total_ram_mb / 1024))
    
    # Redis yapılandırma dosyası
    local redis_conf="/etc/redis/redis.conf"
    
    if [ ! -f "$redis_conf" ]; then
        print_error "Redis yapılandırma dosyası bulunamadı!"
        return 1
    fi
    
    # Max memory (RAM'in %10-20'si)
    local max_memory_mb=$((total_ram_mb * 15 / 100))
    if [ $max_memory_mb -lt 256 ]; then
        max_memory_mb=256
    fi
    
    # Max clients
    local maxclients=10000
    if [ $total_ram_gb -lt 4 ]; then
        maxclients=5000
    fi
    
    print_info "Önerilen Redis Ayarları:"
    echo -e "  maxmemory: ${GREEN}${max_memory_mb}mb${NC}"
    echo -e "  maxmemory-policy: ${GREEN}allkeys-lru${NC}"
    echo -e "  maxclients: ${GREEN}$maxclients${NC}"
    echo ""
    
    if ! ask_yes_no "Redis yapılandırmasını optimize etmek istiyor musunuz?"; then
        print_info "Optimizasyon iptal edildi"
        return 0
    fi
    
    # Yedek oluştur
    local redis_backup="$redis_conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$redis_conf" "$redis_backup"
    print_info "Yedek oluşturuldu: $redis_backup"
    
    # Max memory
    if grep -q "^maxmemory " "$redis_conf"; then
        sed -i "s/^maxmemory .*/maxmemory ${max_memory_mb}mb/" "$redis_conf"
    else
        sed -i "/^# maxmemory/a maxmemory ${max_memory_mb}mb" "$redis_conf"
    fi
    
    # Max memory policy
    if grep -q "^maxmemory-policy" "$redis_conf"; then
        sed -i "s/^maxmemory-policy.*/maxmemory-policy allkeys-lru/" "$redis_conf"
    else
        sed -i "/^maxmemory/a maxmemory-policy allkeys-lru" "$redis_conf"
    fi
    
    # Max clients
    if grep -q "^maxclients" "$redis_conf"; then
        sed -i "s/^maxclients.*/maxclients $maxclients/" "$redis_conf"
    else
        sed -i "/^# maxclients/a maxclients $maxclients" "$redis_conf"
    fi
    
    # Redis'i yeniden başlat
    if systemctl restart redis; then
        sleep 2
        if systemctl is-active --quiet redis; then
            print_success "Redis optimizasyonu tamamlandı!"
            echo -e "${GREEN}Uygulanan Ayarlar:${NC}"
            echo "  • maxmemory: ${max_memory_mb}mb"
            echo "  • maxmemory-policy: allkeys-lru"
            echo "  • maxclients: $maxclients"
        else
            print_error "Redis başlatılamadı! Yedek geri yükleniyor..."
            cp "$redis_backup" "$redis_conf"
            systemctl restart redis
            return 1
        fi
    else
        print_error "Redis yeniden başlatılamadı!"
        return 1
    fi
}

optimize_system_limits() {
    print_header "Sistem Limitleri Optimizasyonu"
    
    local specs=$(get_server_specs)
    local cpu_cores=$(echo "$specs" | cut -d'|' -f1)
    local total_ram_mb=$(echo "$specs" | cut -d'|' -f2)
    
    # Open files limit hesaplama
    local worker_connections=2048
    if [ $total_ram_mb -ge 4096 ]; then
        worker_connections=4096
    elif [ $total_ram_mb -ge 2048 ]; then
        worker_connections=2048
    else
        worker_connections=1024
    fi
    
    local open_files_limit=$((worker_connections * cpu_cores * 2))
    if [ $open_files_limit -lt 65536 ]; then
        open_files_limit=65536
    fi
    
    print_info "Önerilen Sistem Limitleri:"
    echo -e "  open files limit: ${GREEN}$open_files_limit${NC}"
    echo ""
    
    if ! ask_yes_no "Sistem limitlerini optimize etmek istiyor musunuz?"; then
        print_info "Optimizasyon iptal edildi"
        return 0
    fi
    
    # /etc/security/limits.conf güncelle
    local limits_conf="/etc/security/limits.conf"
    local limits_backup="$limits_conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$limits_conf" "$limits_backup"
    
    # Mevcut limitleri kaldır
    sed -i '/^www-data\|^nginx\|^\* soft nofile\|^\* hard nofile/d' "$limits_conf"
    
    # Yeni limitleri ekle
    cat >> "$limits_conf" <<EOF

# Optimized limits for web server
www-data soft nofile $open_files_limit
www-data hard nofile $open_files_limit
nginx soft nofile $open_files_limit
nginx hard nofile $open_files_limit
* soft nofile $open_files_limit
* hard nofile $open_files_limit
EOF
    
    # /etc/sysctl.conf optimizasyonları
    local sysctl_conf="/etc/sysctl.conf"
    local sysctl_backup="$sysctl_conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$sysctl_conf" "$sysctl_backup"
    
    # Mevcut ayarları kaldır
    sed -i '/^net.core.somaxconn\|^net.ipv4.tcp_max_syn_backlog\|^net.ipv4.ip_local_port_range/d' "$sysctl_conf"
    
    # Yeni ayarları ekle
    cat >> "$sysctl_conf" <<EOF

# Network optimizations
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
EOF
    
    # Sysctl ayarlarını uygula
    sysctl -p > /dev/null 2>&1
    
    print_success "Sistem limitleri optimizasyonu tamamlandı!"
    echo -e "${GREEN}Uygulanan Ayarlar:${NC}"
    echo "  • open files limit: $open_files_limit"
    echo "  • net.core.somaxconn: 65535"
    echo "  • net.ipv4.tcp_max_syn_backlog: 65535"
    echo ""
    print_warning "Değişikliklerin tam olarak etkili olması için oturum kapatıp açmanız gerekebilir"
}

optimize_services_menu() {
    while true; do
        clear
        print_header "Servis Optimizasyonu - Performans & Güvenlik"
        
        local specs=$(get_server_specs)
        local cpu_cores=$(echo "$specs" | cut -d'|' -f1)
        local total_ram_mb=$(echo "$specs" | cut -d'|' -f2)
        local cpu_model=$(echo "$specs" | cut -d'|' -f6)
        
        echo -e "${CYAN}Sunucu Donanım Bilgileri:${NC}"
        echo -e "  CPU: ${GREEN}$cpu_model${NC}"
        echo -e "  CPU Çekirdek: ${GREEN}$cpu_cores${NC}"
        echo -e "  Toplam RAM: ${GREEN}${total_ram_mb}MB${NC} ($(($total_ram_mb / 1024))GB)"
        echo ""
        
        echo -e "${CYAN}Optimizasyon Seçenekleri:${NC}"
        echo "1) Nginx Optimizasyonu"
        echo "2) PHP-FPM Optimizasyonu"
        echo "3) MySQL/MariaDB Optimizasyonu"
        echo "4) Redis Optimizasyonu"
        echo "5) Sistem Limitleri Optimizasyonu"
        echo "6) Tüm Servisleri Otomatik Optimize Et"
        echo "7) Geri Dön"
        echo ""
        
        read -p "Seçiminizi yapın (1-7): " opt_choice
        
        case $opt_choice in
            1)
                optimize_nginx
                read -p "Devam etmek için Enter'a basın..."
                ;;
            2)
                optimize_php_fpm
                read -p "Devam etmek için Enter'a basın..."
                ;;
            3)
                optimize_mysql
                read -p "Devam etmek için Enter'a basın..."
                ;;
            4)
                optimize_redis
                read -p "Devam etmek için Enter'a basın..."
                ;;
            5)
                optimize_system_limits
                read -p "Devam etmek için Enter'a basın..."
                ;;
            6)
                optimize_all_services
                read -p "Devam etmek için Enter'a basın..."
                ;;
            7)
                return 0
                ;;
            *)
                print_error "Geçersiz seçim"
                sleep 2
                ;;
        esac
    done
}

optimize_all_services() {
    print_header "Tüm Servisleri Otomatik Optimize Et"
    
    local specs=$(get_server_specs)
    local cpu_cores=$(echo "$specs" | cut -d'|' -f1)
    local total_ram_mb=$(echo "$specs" | cut -d'|' -f2)
    local cpu_model=$(echo "$specs" | cut -d'|' -f6)
    
    echo -e "${CYAN}Sunucu Özellikleri:${NC}"
    echo -e "  CPU: ${GREEN}$cpu_model${NC}"
    echo -e "  CPU Çekirdek: ${GREEN}$cpu_cores${NC}"
    echo -e "  Toplam RAM: ${GREEN}${total_ram_mb}MB${NC}"
    echo ""
    
    echo -e "${CYAN}Optimize Edilecek Servisler:${NC}"
    local services_to_optimize=""
    
    if command -v nginx &> /dev/null; then
        echo "  ✓ Nginx"
        services_to_optimize="$services_to_optimize nginx"
    fi
    
    if command -v php &> /dev/null; then
        echo "  ✓ PHP-FPM"
        services_to_optimize="$services_to_optimize php"
    fi
    
    if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
        echo "  ✓ MySQL/MariaDB"
        services_to_optimize="$services_to_optimize mysql"
    fi
    
    if systemctl is-active --quiet redis; then
        echo "  ✓ Redis"
        services_to_optimize="$services_to_optimize redis"
    fi
    
    echo "  ✓ Sistem Limitleri"
    echo ""
    
    if [ -z "$services_to_optimize" ]; then
        print_warning "Optimize edilecek servis bulunamadı!"
        return 1
    fi
    
    if ! ask_yes_no "Tüm servisleri optimize etmek istiyor musunuz?"; then
        print_info "Optimizasyon iptal edildi"
        return 0
    fi
    
    # Servisleri optimize et
    if echo "$services_to_optimize" | grep -q "nginx"; then
        optimize_nginx
        echo ""
    fi
    
    if echo "$services_to_optimize" | grep -q "php"; then
        optimize_php_fpm
        echo ""
    fi
    
    if echo "$services_to_optimize" | grep -q "mysql"; then
        optimize_mysql
        echo ""
    fi
    
    if echo "$services_to_optimize" | grep -q "redis"; then
        optimize_redis
        echo ""
    fi
    
    optimize_system_limits
    
    print_header "Optimizasyon Tamamlandı!"
    print_success "Tüm servisler donanımınıza göre optimize edildi"
    echo ""
    echo -e "${YELLOW}ÖNEMLİ:${NC}"
    echo "• Değişikliklerin tam etkili olması için servisler yeniden başlatıldı"
    echo "• Sistem limitleri için oturum kapatıp açmanız gerekebilir"
    echo "• Performansı izlemek için: htop, iotop, nginx -V"
}

install_openvpn() {
    print_header "OpenVPN Server Kurulumu"
    
    if systemctl is-active --quiet openvpn@server 2>/dev/null || systemctl is-active --quiet openvpn 2>/dev/null; then
        print_warning "OpenVPN zaten kurulu ve çalışıyor"
        if ! ask_yes_no "Yeniden kurmak istiyor musunuz?"; then
            return 0
        fi
    fi
    
    # OpenVPN ve Easy-RSA kurulumu
    print_info "OpenVPN ve gerekli paketler kuruluyor..."
    apt update
    apt install -y openvpn easy-rsa ufw
    
    # Easy-RSA dizinini oluştur
    local easyrsa_dir="/etc/openvpn/easy-rsa"
    mkdir -p $easyrsa_dir
    
    # Easy-RSA 3.x için
    if [ -d "/usr/share/easy-rsa" ]; then
        cp -r /usr/share/easy-rsa/* $easyrsa_dir/ 2>/dev/null || true
    fi
    
    # Easy-RSA paketini kur
    apt install -y easy-rsa
    
    # Easy-RSA'yı tekrar kopyala
    if [ -d "/usr/share/easy-rsa" ]; then
        cp -r /usr/share/easy-rsa/* $easyrsa_dir/ 2>/dev/null || true
    fi
    
    cd $easyrsa_dir
    
    # Easy-RSA 3.x için vars dosyası
    if [ ! -f "vars" ] && [ -f "vars.example" ]; then
        cp vars.example vars
    fi
    
    # Vars dosyasını düzenle
    if [ -f "vars" ]; then
        sed -i 's/^set_var EASYRSA_REQ_COUNTRY.*/set_var EASYRSA_REQ_COUNTRY\t"TR"/' vars 2>/dev/null || \
        echo 'set_var EASYRSA_REQ_COUNTRY     "TR"' >> vars
        sed -i 's/^set_var EASYRSA_REQ_PROVINCE.*/set_var EASYRSA_REQ_PROVINCE\t"Istanbul"/' vars 2>/dev/null || \
        echo 'set_var EASYRSA_REQ_PROVINCE    "Istanbul"' >> vars
        sed -i 's/^set_var EASYRSA_REQ_CITY.*/set_var EASYRSA_REQ_CITY\t\t"Istanbul"/' vars 2>/dev/null || \
        echo 'set_var EASYRSA_REQ_CITY         "Istanbul"' >> vars
        sed -i 's/^set_var EASYRSA_REQ_ORG.*/set_var EASYRSA_REQ_ORG\t\t"OpenVPN-CA"/' vars 2>/dev/null || \
        echo 'set_var EASYRSA_REQ_ORG          "OpenVPN-CA"' >> vars
        sed -i 's/^set_var EASYRSA_REQ_EMAIL.*/set_var EASYRSA_REQ_EMAIL\t"admin@example.com"/' vars 2>/dev/null || \
        echo 'set_var EASYRSA_REQ_EMAIL        "admin@example.com"' >> vars
        sed -i 's/^set_var EASYRSA_REQ_OU.*/set_var EASYRSA_REQ_OU\t\t"OpenVPN"/' vars 2>/dev/null || \
        echo 'set_var EASYRSA_REQ_OU           "OpenVPN"' >> vars
    else
        # Vars dosyası yoksa oluştur
        cat > vars <<'EOF'
set_var EASYRSA_REQ_COUNTRY     "TR"
set_var EASYRSA_REQ_PROVINCE    "Istanbul"
set_var EASYRSA_REQ_CITY         "Istanbul"
set_var EASYRSA_REQ_ORG          "OpenVPN-CA"
set_var EASYRSA_REQ_EMAIL        "admin@example.com"
set_var EASYRSA_REQ_OU           "OpenVPN"
set_var EASYRSA_KEY_SIZE         2048
set_var EASYRSA_ALGO             rsa
set_var EASYRSA_CA_EXPIRE        3650
set_var EASYRSA_CERT_EXPIRE      3650
EOF
    fi
    
    # PKI dizinini oluştur (eğer yoksa)
    if [ ! -d "pki" ]; then
        print_info "CA (Certificate Authority) oluşturuluyor..."
        ./easyrsa init-pki
        ./easyrsa build-ca nopass
    else
        print_info "Mevcut CA kullanılıyor"
    fi
    
    # Server sertifikası oluştur (eğer yoksa)
    if [ ! -f "pki/issued/server.crt" ]; then
        print_info "OpenVPN server sertifikası oluşturuluyor..."
        ./easyrsa gen-req server nopass
        ./easyrsa sign-req server server
    else
        print_info "Mevcut server sertifikası kullanılıyor"
    fi
    
    # Diffie-Hellman parametreleri oluştur (eğer yoksa)
    if [ ! -f "pki/dh.pem" ]; then
        print_info "Diffie-Hellman parametreleri oluşturuluyor (bu işlem birkaç dakika sürebilir)..."
        ./easyrsa gen-dh
    else
        print_info "Mevcut DH parametreleri kullanılıyor"
    fi
    
    # HMAC imza oluştur (eğer yoksa)
    if [ ! -f "pki/ta.key" ]; then
        openvpn --genkey --secret pki/ta.key
    else
        print_info "Mevcut HMAC imza kullanılıyor"
    fi
    
    # CRL (Certificate Revocation List) oluştur
    if [ ! -f "pki/crl.pem" ]; then
        ./easyrsa gen-crl
    fi
    cp pki/crl.pem /etc/openvpn/crl.pem 2>/dev/null || true
    
    # OpenVPN yapılandırma dosyası oluştur
    local server_ip=$(hostname -I | awk '{print $1}')
    local openvpn_port=1194
    local openvpn_proto="udp"
    
    read -p "OpenVPN port (varsayılan: 1194) [1194]: " input_port
    openvpn_port=${input_port:-1194}
    
    echo "Protokol seçin:"
    echo "1) UDP (Önerilen, daha hızlı)"
    echo "2) TCP (Daha güvenilir)"
    read -p "Seçiminiz (1-2) [1]: " proto_choice
    case $proto_choice in
        2) openvpn_proto="tcp";;
        *) openvpn_proto="udp";;
    esac
    
    # OpenVPN server yapılandırması
    local openvpn_conf="/etc/openvpn/server.conf"
    
    # Mevcut yapılandırma varsa yedekle
    if [ -f "$openvpn_conf" ]; then
        cp $openvpn_conf ${openvpn_conf}.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    cat > $openvpn_conf <<EOF
port $openvpn_port
proto $openvpn_proto
dev tun

ca $easyrsa_dir/pki/ca.crt
cert $easyrsa_dir/pki/issued/server.crt
key $easyrsa_dir/pki/private/server.key
dh $easyrsa_dir/pki/dh.pem
tls-auth $easyrsa_dir/pki/ta.key 0
crl-verify /etc/openvpn/crl.pem

server 10.8.0.0 255.255.255.0

ifconfig-pool-persist /var/log/openvpn/ipp.txt

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

keepalive 10 120
cipher AES-256-GCM
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
comp-lzo

status /var/log/openvpn/openvpn-status.log
log /var/log/openvpn/openvpn.log
verb 3

# Güvenlik ayarları
tls-version-min 1.2
EOF
    
    # Log dizinini oluştur
    mkdir -p /var/log/openvpn
    touch /var/log/openvpn/openvpn-status.log
    touch /var/log/openvpn/openvpn.log
    chown nobody:nogroup /var/log/openvpn/*
    
    # IP forwarding etkinleştir
    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    
    # Firewall kuralları
    if systemctl is-active --quiet ufw; then
        ufw allow $openvpn_port/$openvpn_proto comment 'OpenVPN'
        print_info "UFW firewall kuralı eklendi"
    fi
    
    # OpenVPN servisini başlat
    # Ubuntu 24.04'te systemd service adı
    if [ -f "/etc/systemd/system/multi-user.target.wants/openvpn.service" ] || \
       [ -f "/lib/systemd/system/openvpn.service" ]; then
        systemctl enable openvpn
        systemctl start openvpn
        sleep 2
        
        if systemctl is-active --quiet openvpn; then
            print_success "OpenVPN server başarıyla kuruldu ve başlatıldı"
            echo -e "${GREEN}OpenVPN Port:${NC} $openvpn_port/$openvpn_proto"
            echo -e "${GREEN}Server IP:${NC} $server_ip"
            echo -e "${GREEN}VPN Network:${NC} 10.8.0.0/24"
            echo ""
            print_info "İstemci sertifikaları oluşturmak için: Ana Menü > OpenVPN İstemci Yönetimi"
        else
            print_error "OpenVPN başlatılamadı!"
            print_info "Log kontrolü: journalctl -u openvpn -n 50"
            print_info "Yapılandırma kontrolü: openvpn --config $openvpn_conf --verb 4"
            return 1
        fi
    else
        # Alternatif: openvpn@server service
        systemctl enable openvpn@server
        systemctl start openvpn@server
        sleep 2
        
        if systemctl is-active --quiet openvpn@server; then
            print_success "OpenVPN server başarıyla kuruldu ve başlatıldı"
            echo -e "${GREEN}OpenVPN Port:${NC} $openvpn_port/$openvpn_proto"
            echo -e "${GREEN}Server IP:${NC} $server_ip"
            echo -e "${GREEN}VPN Network:${NC} 10.8.0.0/24"
            echo ""
            print_info "İstemci sertifikaları oluşturmak için: Ana Menü > OpenVPN İstemci Yönetimi"
        else
            print_error "OpenVPN başlatılamadı!"
            print_info "Log kontrolü: journalctl -u openvpn@server -n 50"
            print_info "Yapılandırma kontrolü: openvpn --config $openvpn_conf --verb 4"
            return 1
        fi
    fi
}

install_openvpn_web_admin() {
    print_header "OpenVPN Web Yönetim Paneli Kurulumu"
    
    # Web panel seçimi
    echo -e "${CYAN}Web Yönetim Paneli Seçenekleri:${NC}"
    echo "1) OpenVPN-Admin (PHP tabanlı, basit)"
    echo "2) Pritunl (Profesyonel, MongoDB gerekli)"
    echo "3) Pritunl için MongoDB Kurulumu/Yapılandırması (Pritunl zaten kuruluysa)"
    echo "4) Geri Dön"
    echo ""
    
    read -p "Seçiminiz (1-4) [1]: " panel_choice
    case $panel_choice in
        2)
            install_pritunl
            ;;
        3)
            install_mongodb_for_pritunl
            ;;
        4)
            return 0
            ;;
        *)
            install_openvpn_admin
            ;;
    esac
}

install_openvpn_admin() {
    print_info "OpenVPN-Admin kuruluyor..."
    
    # Gereksinimler kontrolü
    if ! command -v php &> /dev/null; then
        print_error "PHP kurulu değil! Önce PHP kurulumu yapın."
        return 1
    fi
    
    if ! command -v nginx &> /dev/null; then
        print_error "Nginx kurulu değil! Önce Nginx kurulumu yapın."
        return 1
    fi
    
    # Domain bilgisi
    local admin_domain=""
    ask_input "OpenVPN-Admin için domain/subdomain adını girin (örn: vpn.ornek.com)" admin_domain
    
    # Git ve Composer kontrolü
    if ! command -v git &> /dev/null; then
        apt install -y git
    fi
    
    if ! command -v composer &> /dev/null; then
        print_info "Composer kuruluyor..."
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi
    
    # OpenVPN-Admin dizini
    local admin_dir="/var/www/$admin_domain"
    mkdir -p $admin_dir
    
    # OpenVPN-Admin'i klonla
    print_info "OpenVPN-Admin indiriliyor..."
    if [ -d "$admin_dir/.git" ]; then
        cd $admin_dir
        git pull
    else
        git clone https://github.com/Chocobozzz/OpenVPN-Admin.git $admin_dir
    fi
    
    cd $admin_dir
    
    # Composer bağımlılıklarını kur
    print_info "Bağımlılıklar kuruluyor..."
    composer install --no-dev --optimize-autoloader
    
    # Yapılandırma dosyası
    if [ ! -f ".env" ]; then
        cp .env.example .env
        php artisan key:generate
    fi
    
    # Veritabanı yapılandırması
    if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
        if ask_yes_no "MySQL/MariaDB için veritabanı oluşturulsun mu?"; then
            local db_name="openvpn_admin"
            local db_user="openvpn_admin"
            local db_password=""
            
            ask_password "Veritabanı kullanıcı şifresini belirleyin" db_password
            
            if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                ask_password "MySQL root şifresini girin" MYSQL_ROOT_PASSWORD
            fi
            
            mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
CREATE DATABASE IF NOT EXISTS $db_name;
CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_password';
GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
EOF
            
            # .env dosyasını güncelle
            sed -i "s/DB_DATABASE=.*/DB_DATABASE=$db_name/" .env
            sed -i "s/DB_USERNAME=.*/DB_USERNAME=$db_user/" .env
            sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$db_password/" .env
            
            # Migration çalıştır
            php artisan migrate --force
        fi
    fi
    
    # Dosya izinleri
    chown -R www-data:www-data $admin_dir
    chmod -R 755 $admin_dir
    chmod -R 775 $admin_dir/storage
    chmod -R 775 $admin_dir/bootstrap/cache
    
    # Nginx yapılandırması
    local nginx_config="/etc/nginx/sites-available/$admin_domain"
    cat > $nginx_config <<EOF
server {
    listen 80;
    server_name $admin_domain;
    root $admin_dir/public;
    index index.php index.html;

    access_log /var/log/nginx/${admin_domain}_access.log;
    error_log /var/log/nginx/${admin_domain}_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$(php -v | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    
    ln -sf $nginx_config /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx
    
    # SSL sorusu
    if ask_yes_no "OpenVPN-Admin için SSL sertifikası kurulsun mu?"; then
        if [ -z "$EMAIL" ]; then
            ask_input "E-posta adresinizi girin" EMAIL
        fi
        
        if command -v certbot &> /dev/null; then
            certbot --nginx --agree-tos --redirect --hsts --staple-ocsp --email $EMAIL -d $admin_domain --non-interactive
        else
            print_warning "Certbot bulunamadı, SSL kurulumu atlandı"
        fi
    fi
    
    print_success "OpenVPN-Admin kurulumu tamamlandı!"
    echo -e "${GREEN}Erişim:${NC} http://$admin_domain"
    echo -e "${GREEN}Varsayılan Kullanıcı:${NC} admin"
    echo -e "${GREEN}Varsayılan Şifre:${NC} admin"
    echo -e "${YELLOW}UYARI:${NC} İlk girişte şifreyi değiştirin!"
}

install_pritunl() {
    print_header "Pritunl VPN Kurulumu"
    
    print_info "Pritunl, MongoDB gerektirir ve daha profesyonel bir çözümdür."
    
    if ! ask_yes_no "Pritunl kurulumuna devam etmek istiyor musunuz?"; then
        return 0
    fi
    
    # MongoDB kurulumu (Ubuntu 24.04 için resmi repository)
    print_info "MongoDB kurulumu başlatılıyor..."
    
    # MongoDB zaten kurulu mu kontrol et
    local mongodb_installed=false
    local mongodb_running=false
    
    if systemctl is-active --quiet mongod 2>/dev/null; then
        mongodb_installed=true
        mongodb_running=true
        print_success "MongoDB zaten kurulu ve çalışıyor (mongod)"
    elif systemctl is-active --quiet mongodb 2>/dev/null; then
        mongodb_installed=true
        mongodb_running=true
        print_success "MongoDB zaten kurulu ve çalışıyor (mongodb)"
    elif command -v mongod &>/dev/null || dpkg -l | grep -q mongodb-org; then
        mongodb_installed=true
        print_info "MongoDB kurulu görünüyor, servis başlatılıyor..."
        systemctl start mongod 2>/dev/null || systemctl start mongodb 2>/dev/null || true
        systemctl enable mongod 2>/dev/null || systemctl enable mongodb 2>/dev/null || true
        sleep 5
        if systemctl is-active --quiet mongod 2>/dev/null || systemctl is-active --quiet mongodb 2>/dev/null; then
            mongodb_running=true
            print_success "MongoDB servisi başlatıldı"
        else
            print_warning "MongoDB servisi başlatılamadı, yeniden kurulum yapılacak"
        fi
    fi
    
    # MongoDB kurulu değilse veya çalışmıyorsa kur
    if [ "$mongodb_installed" = false ] || [ "$mongodb_running" = false ]; then
        if [ "$mongodb_installed" = true ] && [ "$mongodb_running" = false ]; then
            print_info "MongoDB kurulu ancak çalışmıyor, yeniden kurulum yapılıyor..."
            # Eski MongoDB'yi kaldır
            systemctl stop mongod 2>/dev/null || systemctl stop mongodb 2>/dev/null || true
            apt remove --purge -y mongodb-org* mongodb* 2>/dev/null || true
            rm -rf /etc/apt/sources.list.d/mongodb*.list 2>/dev/null || true
            apt update
        fi
        
        print_info "MongoDB 8.0 resmi repository'sinden kuruluyor..."
        
        # Gerekli paketler
        if ! command -v gpg &>/dev/null; then
            apt install -y gnupg
        fi
        
        if ! command -v curl &>/dev/null; then
            apt install -y curl
        fi
        
        # GPG anahtarı ekle
        print_info "MongoDB GPG anahtarı ekleniyor..."
        mkdir -p /usr/share/keyrings
        
        if [ ! -f "/usr/share/keyrings/mongodb-server-8.0.gpg" ]; then
            if ! curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
                gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg 2>/dev/null; then
                print_error "MongoDB GPG anahtarı eklenemedi!"
                return 1
            fi
            print_success "MongoDB GPG anahtarı eklendi"
        else
            print_info "MongoDB GPG anahtarı zaten mevcut"
        fi
        
        # MongoDB repository ekle
        print_info "MongoDB repository ekleniyor..."
        local ubuntu_codename="noble"
        if command -v lsb_release &>/dev/null; then
            ubuntu_codename=$(lsb_release -cs)
        elif [ -f /etc/os-release ]; then
            ubuntu_codename=$(grep VERSION_CODENAME /etc/os-release | cut -d'=' -f2 | tr -d '"')
        fi
        
        # Ubuntu 24.04 için noble kullan
        if [ -z "$ubuntu_codename" ] || [ "$ubuntu_codename" = "" ]; then
            ubuntu_codename="noble"
        fi
        
        cat > /etc/apt/sources.list.d/mongodb-org.list <<EOF
deb [ signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${ubuntu_codename}/mongodb-org/8.0 multiverse
EOF
        
        # APT güncelle
        apt update
        
        # MongoDB kurulumu
        print_info "MongoDB-org paketleri kuruluyor..."
        if ! DEBIAN_FRONTEND=noninteractive apt install -y mongodb-org; then
            print_error "MongoDB kurulumu başarısız oldu!"
            return 1
        fi
        
        # MongoDB servisini başlat ve etkinleştir
        print_info "MongoDB servisi başlatılıyor..."
        systemctl daemon-reload
        systemctl enable mongod
        
        # MongoDB veri dizinini oluştur ve izinleri ayarla
        if [ ! -d "/var/lib/mongodb" ]; then
            mkdir -p /var/lib/mongodb
        fi
        if [ ! -d "/var/log/mongodb" ]; then
            mkdir -p /var/log/mongodb
        fi
        
        # MongoDB kullanıcısını kontrol et
        if ! id mongodb &>/dev/null; then
            useradd -r -s /bin/false mongodb 2>/dev/null || true
        fi
        
        # Dizin izinlerini ayarla
        chown -R mongodb:mongodb /var/lib/mongodb 2>/dev/null || true
        chown -R mongodb:mongodb /var/log/mongodb 2>/dev/null || true
        
        # Servisi başlat
        systemctl start mongod
        
        # Servis durumunu kontrol et (retry mekanizması)
        local mongodb_start_retry=0
        while [ $mongodb_start_retry -lt 15 ]; do
            if systemctl is-active --quiet mongod 2>/dev/null; then
                mongodb_running=true
                break
            fi
            sleep 2
            ((mongodb_start_retry++))
        done
        
        if [ "$mongodb_running" = false ]; then
            print_error "MongoDB servisi başlatılamadı!"
            print_info "Log kontrolü: journalctl -u mongod -n 50"
            print_info "Manuel başlatma: sudo systemctl start mongod"
            return 1
        fi
        
        print_success "MongoDB başarıyla kuruldu ve başlatıldı"
    fi
    
    # MongoDB yapılandırması (Pritunl için) - ZORUNLU
    print_info "MongoDB yapılandırması yapılıyor (Pritunl için)..."
    
    # MongoDB'nin çalıştığından kesinlikle emin ol
    if ! systemctl is-active --quiet mongod 2>/dev/null; then
        print_info "MongoDB servisi başlatılıyor..."
        systemctl start mongod
        sleep 5
    fi
    
    # MongoDB servis durumunu kontrol et (retry mekanizması)
    local mongodb_retry=0
    while [ $mongodb_retry -lt 15 ]; do
        if systemctl is-active --quiet mongod 2>/dev/null; then
            mongodb_running=true
            break
        fi
        sleep 2
        ((mongodb_retry++))
    done
    
    if ! systemctl is-active --quiet mongod 2>/dev/null; then
        print_error "MongoDB servisi başlatılamadı! Pritunl için MongoDB zorunludur!"
        print_info "Log kontrolü: journalctl -u mongod -n 50"
        print_info "Manuel başlatma: sudo systemctl start mongod"
        return 1
    fi
    
    print_success "MongoDB servisi çalışıyor"
    
    # MongoDB bağlantı testi
    print_info "MongoDB bağlantı testi yapılıyor..."
    local mongodb_connected=false
    
    # mongosh ile test (MongoDB 8.0 için)
    if command -v mongosh &>/dev/null; then
        if mongosh --eval "db.adminCommand('ping')" --quiet 2>/dev/null; then
            mongodb_connected=true
            print_success "MongoDB bağlantı testi başarılı (mongosh)"
        fi
    fi
    
    # mongo ile test (eski versiyonlar için)
    if [ "$mongodb_connected" = false ] && command -v mongo &>/dev/null; then
        if mongo --eval "db.adminCommand('ping')" --quiet 2>/dev/null; then
            mongodb_connected=true
            print_success "MongoDB bağlantı testi başarılı (mongo)"
        fi
    fi
    
    if [ "$mongodb_connected" = false ]; then
        print_warning "MongoDB bağlantı testi başarısız, ancak devam ediliyor..."
        print_info "MongoDB servisi çalışıyor, bağlantı zaman alabilir"
    fi
    
    # Pritunl için MongoDB veritabanı oluştur (opsiyonel)
    print_info "Pritunl için MongoDB veritabanı hazırlanıyor..."
    if command -v mongosh &>/dev/null; then
        mongosh --eval "use pritunl; db.createCollection('test'); db.test.drop();" --quiet 2>/dev/null || true
    elif command -v mongo &>/dev/null; then
        mongo --eval "use pritunl; db.createCollection('test'); db.test.drop();" --quiet 2>/dev/null || true
    fi
    
    # Pritunl repository ekle
    print_info "Pritunl repository ekleniyor..."
    
    # GPG anahtarı ekle
    if [ ! -f "/usr/share/keyrings/pritunl.gpg" ]; then
        print_info "Pritunl GPG anahtarı ekleniyor..."
        curl -fsSL https://raw.githubusercontent.com/pritunl/pgp/master/pritunl_repo_pub.asc | \
            gpg --dearmor -o /usr/share/keyrings/pritunl.gpg 2>/dev/null || {
            print_warning "Pritunl GPG anahtarı eklenemedi, alternatif yöntem deneniyor..."
            apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv-keys 7568D9BB55FF9E5287D586017AE645C0CF8E292A 2>/dev/null || true
        }
    fi
    
    # Repository ekle
    local ubuntu_codename="noble"
    if command -v lsb_release &>/dev/null; then
        ubuntu_codename=$(lsb_release -cs)
    elif [ -f /etc/os-release ]; then
        ubuntu_codename=$(grep VERSION_CODENAME /etc/os-release | cut -d'=' -f2 | tr -d '"')
    fi
    
    # Ubuntu 24.04 için noble kullan
    if [ -z "$ubuntu_codename" ] || [ "$ubuntu_codename" = "" ]; then
        ubuntu_codename="noble"
    fi
    
    cat > /etc/apt/sources.list.d/pritunl.list <<EOF
deb [ signed-by=/usr/share/keyrings/pritunl.gpg ] https://repo.pritunl.com/stable/apt ${ubuntu_codename} main
EOF
    
    # APT güncelle
    apt update
    
    # Pritunl kurulumu
    print_info "Pritunl paketleri kuruluyor..."
    if ! DEBIAN_FRONTEND=noninteractive apt install -y pritunl; then
        print_error "Pritunl kurulumu başarısız oldu!"
        return 1
    fi
    
    # Pritunl yapılandırması (MongoDB bağlantısı) - ZORUNLU
    print_info "Pritunl yapılandırması yapılıyor (MongoDB bağlantısı)..."
    
    # MongoDB bağlantı string'ini ayarla (varsayılan: mongodb://localhost:27017/pritunl)
    local pritunl_conf="/etc/pritunl.conf"
    local mongodb_uri="mongodb://localhost:27017/pritunl"
    
    # Yapılandırma dosyasını kontrol et ve düzelt
    if [ ! -f "$pritunl_conf" ]; then
        # Yeni JSON yapılandırma dosyası oluştur
        cat > "$pritunl_conf" <<EOF
{
  "mongodb_uri": "$mongodb_uri"
}
EOF
        chmod 644 "$pritunl_conf"
        print_success "Pritunl yapılandırma dosyası oluşturuldu (JSON formatında)"
    else
        # Mevcut dosyayı kontrol et - JSON formatında mı?
        local is_json=false
        if head -1 "$pritunl_conf" | grep -q "^{"; then
            is_json=true
        fi
        
        if [ "$is_json" = true ]; then
            # JSON formatında güncelle
            print_info "Mevcut yapılandırma JSON formatında, güncelleniyor..."
            
            # Python ile JSON güncelleme (eğer python3 varsa)
            if command -v python3 &>/dev/null; then
                python3 <<PYTHON_SCRIPT
import json
import sys

try:
    with open('$pritunl_conf', 'r') as f:
        config = json.load(f)
    
    config['mongodb_uri'] = '$mongodb_uri'
    
    with open('$pritunl_conf', 'w') as f:
        json.dump(config, f, indent=2)
    
    print("MongoDB URI güncellendi")
except Exception as e:
    print(f"Hata: {e}")
    sys.exit(1)
PYTHON_SCRIPT
                if [ $? -eq 0 ]; then
                    print_success "MongoDB URI JSON formatında güncellendi: $mongodb_uri"
                else
                    print_warning "Python ile güncelleme başarısız, manuel düzenleme gerekebilir"
                fi
            else
                # Python yoksa, dosyayı yedekle ve yeniden oluştur
                print_warning "Python3 bulunamadı, yapılandırma dosyası yeniden oluşturuluyor..."
                cp "$pritunl_conf" "${pritunl_conf}.backup.$(date +%Y%m%d_%H%M%S)"
                cat > "$pritunl_conf" <<EOF
{
  "mongodb_uri": "$mongodb_uri"
}
EOF
                print_success "Yapılandırma dosyası yeniden oluşturuldu (JSON formatında)"
            fi
        else
            # Python config formatında ise, JSON'a dönüştür
            print_info "Mevcut yapılandırma Python formatında, JSON'a dönüştürülüyor..."
            cp "$pritunl_conf" "${pritunl_conf}.backup.$(date +%Y%m%d_%H%M%S)"
            
            # Mevcut ayarları oku (varsa)
            local existing_uri=$(grep -E "^mongodb_uri" "$pritunl_conf" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
            if [ -z "$existing_uri" ]; then
                existing_uri="$mongodb_uri"
            fi
            
            # JSON formatında yeni dosya oluştur
            cat > "$pritunl_conf" <<EOF
{
  "mongodb_uri": "$existing_uri"
}
EOF
            print_success "Yapılandırma dosyası JSON formatına dönüştürüldü"
        fi
    fi
    
    # MongoDB bağlantı testi (Pritunl için)
    print_info "MongoDB bağlantı testi yapılıyor (Pritunl için)..."
    local mongodb_test_success=false
    
    # mongosh ile test
    if command -v mongosh &>/dev/null; then
        if mongosh --eval "db.adminCommand('ping')" --quiet 2>/dev/null; then
            mongodb_test_success=true
            print_success "MongoDB bağlantı testi başarılı (mongosh)"
        fi
    fi
    
    # mongo ile test
    if [ "$mongodb_test_success" = false ] && command -v mongo &>/dev/null; then
        if mongo --eval "db.adminCommand('ping')" --quiet 2>/dev/null; then
            mongodb_test_success=true
            print_success "MongoDB bağlantı testi başarılı (mongo)"
        fi
    fi
    
    if [ "$mongodb_test_success" = false ]; then
        print_warning "MongoDB bağlantı testi başarısız, ancak devam ediliyor..."
        print_info "MongoDB servisi çalışıyor, bağlantı zaman alabilir"
    fi
    
    # Pritunl için MongoDB veritabanı hazırla
    print_info "Pritunl için MongoDB veritabanı hazırlanıyor..."
    if command -v mongosh &>/dev/null; then
        mongosh --eval "use pritunl; db.createCollection('test'); db.test.drop();" --quiet 2>/dev/null || true
    elif command -v mongo &>/dev/null; then
        mongo --eval "use pritunl; db.createCollection('test'); db.test.drop();" --quiet 2>/dev/null || true
    fi
    
    print_success "Pritunl yapılandırması tamamlandı"
    
    # MongoDB'nin çalıştığından kesinlikle emin ol (Pritunl için zorunlu)
    print_info "MongoDB servis durumu kontrol ediliyor (Pritunl için zorunlu)..."
    if ! systemctl is-active --quiet mongod 2>/dev/null; then
        print_error "MongoDB servisi çalışmıyor! Pritunl için MongoDB zorunludur!"
        systemctl start mongod
        sleep 5
        if ! systemctl is-active --quiet mongod 2>/dev/null; then
            print_error "MongoDB servisi başlatılamadı!"
            return 1
        fi
    fi
    print_success "MongoDB servisi çalışıyor"
    
    # Pritunl servisini başlat
    print_info "Pritunl servisi başlatılıyor..."
    systemctl daemon-reload
    systemctl enable pritunl
    systemctl start pritunl
    
    # Servis durumunu kontrol et (retry mekanizması)
    local pritunl_start_retry=0
    while [ $pritunl_start_retry -lt 15 ]; do
        if systemctl is-active --quiet pritunl 2>/dev/null; then
            break
        fi
        sleep 2
        ((pritunl_start_retry++))
    done
    
    if systemctl is-active --quiet pritunl 2>/dev/null; then
        print_success "Pritunl başarıyla kuruldu ve başlatıldı!"
        
        # Setup key'i al
        local setup_key=""
        local retry_count=0
        while [ $retry_count -lt 10 ] && [ -z "$setup_key" ]; do
            setup_key=$(pritunl default-key 2>/dev/null | grep -oE '[a-f0-9]{32}' | head -1)
            if [ -z "$setup_key" ]; then
                sleep 2
                ((retry_count++))
            fi
        done
        
        local server_ip=$(hostname -I | awk '{print $1}')
        
        print_info "Pritunl kurulum bilgileri:"
        echo -e "${GREEN}MongoDB Durumu:${NC} $(systemctl is-active mongod)"
        echo -e "${GREEN}MongoDB URI:${NC} mongodb://localhost:27017/pritunl"
        if [ -n "$setup_key" ]; then
            echo -e "${GREEN}Setup Key:${NC} $setup_key"
        else
            echo -e "${YELLOW}Setup Key:${NC} Henüz oluşturulmadı, birkaç saniye bekleyin"
        fi
        echo -e "${GREEN}Web Arayüzü:${NC} https://$server_ip"
        echo ""
        echo -e "${YELLOW}ÖNEMLİ:${NC}"
        echo "1. Tarayıcıda https://$server_ip adresine gidin"
        if [ -n "$setup_key" ]; then
            echo "2. Setup Key'i girin: $setup_key"
        else
            echo "2. Setup Key'i almak için: pritunl default-key"
        fi
        echo "3. Admin kullanıcısı oluşturun"
    else
        print_error "Pritunl başlatılamadı!"
        print_info "Log kontrolü: journalctl -u pritunl -n 50"
        print_info "MongoDB durumu: systemctl status mongod"
        print_info "MongoDB log: journalctl -u mongod -n 50"
        print_info ""
        print_info "Pritunl yapılandırması kontrol ediliyor..."
        if [ -f "$pritunl_conf" ]; then
            echo "Mevcut yapılandırma:"
            cat "$pritunl_conf" | grep -E "mongodb_uri|mongodb_servers" || echo "MongoDB ayarları bulunamadı!"
        fi
        return 1
    fi
}

install_mongodb_for_pritunl() {
    print_header "Pritunl için MongoDB Kurulumu ve Yapılandırması"
    
    # Pritunl kurulu mu kontrol et
    if ! command -v pritunl &>/dev/null && ! systemctl list-units --type=service | grep -q pritunl; then
        print_error "Pritunl kurulu değil!"
        print_info "Önce Pritunl kurulumu yapmanız gerekiyor."
        if ask_yes_no "Pritunl kurulumuna devam etmek ister misiniz?"; then
            install_pritunl
            return $?
        else
            return 1
        fi
    fi
    
    print_info "Pritunl kurulu tespit edildi"
    
    # MongoDB zaten kurulu mu kontrol et
    local mongodb_installed=false
    local mongodb_running=false
    
    if systemctl is-active --quiet mongod 2>/dev/null; then
        mongodb_installed=true
        mongodb_running=true
        print_success "MongoDB zaten kurulu ve çalışıyor"
        
        # Pritunl yapılandırmasını kontrol et
        local pritunl_conf="/etc/pritunl.conf"
        if [ -f "$pritunl_conf" ]; then
            # JSON formatında mı kontrol et
            local is_json=false
            if head -1 "$pritunl_conf" | grep -q "^{"; then
                is_json=true
            fi
            
            if [ "$is_json" = true ]; then
                # JSON formatında kontrol
                if python3 -c "import json; json.load(open('$pritunl_conf'))" 2>/dev/null && \
                   python3 -c "import json; data=json.load(open('$pritunl_conf')); 'mongodb_uri' in data" 2>/dev/null; then
                    print_success "Pritunl MongoDB yapılandırması mevcut (JSON formatında)"
                    local existing_uri=$(python3 -c "import json; print(json.load(open('$pritunl_conf')).get('mongodb_uri', ''))" 2>/dev/null || echo "")
                    if [ -n "$existing_uri" ]; then
                        echo -e "${GREEN}MongoDB URI:${NC} $existing_uri"
                    fi
                else
                    print_warning "Pritunl yapılandırması bozuk, düzeltiliyor..."
                    # JSON formatında düzelt
                    if command -v python3 &>/dev/null; then
                        python3 <<PYTHON_SCRIPT
import json
config = {"mongodb_uri": "mongodb://localhost:27017/pritunl"}
with open('$pritunl_conf', 'w') as f:
    json.dump(config, f, indent=2)
PYTHON_SCRIPT
                        systemctl restart pritunl
                        print_success "Pritunl yapılandırması düzeltildi (JSON formatında)"
                    fi
                fi
            else
                # Python formatında ise JSON'a dönüştür
                print_warning "Pritunl yapılandırması eski formatta, JSON'a dönüştürülüyor..."
                cp "$pritunl_conf" "${pritunl_conf}.backup.$(date +%Y%m%d_%H%M%S)"
                if command -v python3 &>/dev/null; then
                    python3 <<PYTHON_SCRIPT
import json
config = {"mongodb_uri": "mongodb://localhost:27017/pritunl"}
with open('$pritunl_conf', 'w') as f:
    json.dump(config, f, indent=2)
PYTHON_SCRIPT
                    systemctl restart pritunl
                    print_success "Pritunl yapılandırması JSON formatına dönüştürüldü"
                fi
            fi
        fi
        
        return 0
    elif command -v mongod &>/dev/null || dpkg -l | grep -q mongodb-org; then
        mongodb_installed=true
        print_info "MongoDB kurulu görünüyor, servis başlatılıyor..."
        systemctl start mongod 2>/dev/null || true
        systemctl enable mongod 2>/dev/null || true
        sleep 5
        if systemctl is-active --quiet mongod 2>/dev/null; then
            mongodb_running=true
            print_success "MongoDB servisi başlatıldı"
        fi
    fi
    
    # MongoDB kurulu değilse veya çalışmıyorsa kur
    if [ "$mongodb_installed" = false ] || [ "$mongodb_running" = false ]; then
        print_info "MongoDB 8.0 resmi repository'sinden kuruluyor..."
        
        # Gerekli paketler
        if ! command -v gpg &>/dev/null; then
            apt install -y gnupg
        fi
        
        if ! command -v curl &>/dev/null; then
            apt install -y curl
        fi
        
        # GPG anahtarı ekle
        print_info "MongoDB GPG anahtarı ekleniyor..."
        mkdir -p /usr/share/keyrings
        
        if [ ! -f "/usr/share/keyrings/mongodb-server-8.0.gpg" ]; then
            if ! curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
                gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg 2>/dev/null; then
                print_error "MongoDB GPG anahtarı eklenemedi!"
                return 1
            fi
            print_success "MongoDB GPG anahtarı eklendi"
        fi
        
        # MongoDB repository ekle
        print_info "MongoDB repository ekleniyor..."
        local ubuntu_codename="noble"
        if command -v lsb_release &>/dev/null; then
            ubuntu_codename=$(lsb_release -cs)
        elif [ -f /etc/os-release ]; then
            ubuntu_codename=$(grep VERSION_CODENAME /etc/os-release | cut -d'=' -f2 | tr -d '"')
        fi
        
        if [ -z "$ubuntu_codename" ] || [ "$ubuntu_codename" = "" ]; then
            ubuntu_codename="noble"
        fi
        
        cat > /etc/apt/sources.list.d/mongodb-org.list <<EOF
deb [ signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${ubuntu_codename}/mongodb-org/8.0 multiverse
EOF
        
        # APT güncelle
        apt update
        
        # MongoDB kurulumu
        print_info "MongoDB-org paketleri kuruluyor..."
        if ! DEBIAN_FRONTEND=noninteractive apt install -y mongodb-org; then
            print_error "MongoDB kurulumu başarısız oldu!"
            return 1
        fi
        
        # MongoDB servisini başlat ve etkinleştir
        print_info "MongoDB servisi başlatılıyor..."
        systemctl daemon-reload
        systemctl enable mongod
        
        # MongoDB veri dizinini oluştur ve izinleri ayarla
        if [ ! -d "/var/lib/mongodb" ]; then
            mkdir -p /var/lib/mongodb
        fi
        if [ ! -d "/var/log/mongodb" ]; then
            mkdir -p /var/log/mongodb
        fi
        
        # MongoDB kullanıcısını kontrol et
        if ! id mongodb &>/dev/null; then
            useradd -r -s /bin/false mongodb 2>/dev/null || true
        fi
        
        # Dizin izinlerini ayarla
        chown -R mongodb:mongodb /var/lib/mongodb 2>/dev/null || true
        chown -R mongodb:mongodb /var/log/mongodb 2>/dev/null || true
        
        # Servisi başlat
        systemctl start mongod
        
        # Servis durumunu kontrol et
        local mongodb_start_retry=0
        while [ $mongodb_start_retry -lt 15 ]; do
            if systemctl is-active --quiet mongod 2>/dev/null; then
                mongodb_running=true
                break
            fi
            sleep 2
            ((mongodb_start_retry++))
        done
        
        if [ "$mongodb_running" = false ]; then
            print_error "MongoDB servisi başlatılamadı!"
            print_info "Log kontrolü: journalctl -u mongod -n 50"
            return 1
        fi
        
        print_success "MongoDB başarıyla kuruldu ve başlatıldı"
    fi
    
    # MongoDB bağlantı testi
    print_info "MongoDB bağlantı testi yapılıyor..."
    local mongodb_connected=false
    
    if command -v mongosh &>/dev/null; then
        if mongosh --eval "db.adminCommand('ping')" --quiet 2>/dev/null; then
            mongodb_connected=true
            print_success "MongoDB bağlantı testi başarılı"
        fi
    elif command -v mongo &>/dev/null; then
        if mongo --eval "db.adminCommand('ping')" --quiet 2>/dev/null; then
            mongodb_connected=true
            print_success "MongoDB bağlantı testi başarılı"
        fi
    fi
    
    # Pritunl yapılandırması (JSON formatında)
    print_info "Pritunl yapılandırması güncelleniyor (JSON formatında)..."
    local pritunl_conf="/etc/pritunl.conf"
    local mongodb_uri="mongodb://localhost:27017/pritunl"
    
    # Yapılandırma dosyasını kontrol et ve düzelt
    if [ ! -f "$pritunl_conf" ]; then
        # Yeni JSON yapılandırma dosyası oluştur
        if command -v python3 &>/dev/null; then
            python3 <<PYTHON_SCRIPT
import json
config = {"mongodb_uri": "$mongodb_uri"}
with open('$pritunl_conf', 'w') as f:
    json.dump(config, f, indent=2)
PYTHON_SCRIPT
            chmod 644 "$pritunl_conf"
            print_success "Pritunl yapılandırma dosyası oluşturuldu (JSON formatında)"
        else
            # Python yoksa basit JSON oluştur
            cat > "$pritunl_conf" <<EOF
{
  "mongodb_uri": "$mongodb_uri"
}
EOF
            chmod 644 "$pritunl_conf"
            print_success "Pritunl yapılandırma dosyası oluşturuldu (JSON formatında)"
        fi
    else
        # Mevcut dosyayı kontrol et - JSON formatında mı?
        local is_json=false
        if head -1 "$pritunl_conf" | grep -q "^{"; then
            is_json=true
        fi
        
        if [ "$is_json" = true ]; then
            # JSON formatında güncelle
            print_info "Mevcut yapılandırma JSON formatında, güncelleniyor..."
            
            if command -v python3 &>/dev/null; then
                python3 <<PYTHON_SCRIPT
import json
import sys

try:
    with open('$pritunl_conf', 'r') as f:
        config = json.load(f)
    
    config['mongodb_uri'] = '$mongodb_uri'
    
    with open('$pritunl_conf', 'w') as f:
        json.dump(config, f, indent=2)
    
    print("MongoDB URI güncellendi")
except json.JSONDecodeError as e:
    print(f"JSON hatası: {e}")
    # Bozuk JSON'u düzelt
    config = {"mongodb_uri": "$mongodb_uri"}
    with open('$pritunl_conf', 'w') as f:
        json.dump(config, f, indent=2)
    print("Yapılandırma dosyası düzeltildi")
except Exception as e:
    print(f"Hata: {e}")
    sys.exit(1)
PYTHON_SCRIPT
                if [ $? -eq 0 ]; then
                    print_success "MongoDB URI JSON formatında güncellendi: $mongodb_uri"
                else
                    print_warning "Python ile güncelleme başarısız, dosya yeniden oluşturuluyor..."
                    cp "$pritunl_conf" "${pritunl_conf}.backup.$(date +%Y%m%d_%H%M%S)"
                    cat > "$pritunl_conf" <<EOF
{
  "mongodb_uri": "$mongodb_uri"
}
EOF
                    print_success "Yapılandırma dosyası yeniden oluşturuldu (JSON formatında)"
                fi
            else
                # Python yoksa, dosyayı yedekle ve yeniden oluştur
                print_warning "Python3 bulunamadı, yapılandırma dosyası yeniden oluşturuluyor..."
                cp "$pritunl_conf" "${pritunl_conf}.backup.$(date +%Y%m%d_%H%M%S)"
                cat > "$pritunl_conf" <<EOF
{
  "mongodb_uri": "$mongodb_uri"
}
EOF
                print_success "Yapılandırma dosyası yeniden oluşturuldu (JSON formatında)"
            fi
        else
            # Python config formatında ise, JSON'a dönüştür
            print_info "Mevcut yapılandırma Python formatında, JSON'a dönüştürülüyor..."
            cp "$pritunl_conf" "${pritunl_conf}.backup.$(date +%Y%m%d_%H%M%S)"
            
            # Mevcut ayarları oku (varsa)
            local existing_uri=$(grep -E "^mongodb_uri" "$pritunl_conf" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
            if [ -z "$existing_uri" ]; then
                existing_uri="$mongodb_uri"
            fi
            
            # JSON formatında yeni dosya oluştur
            cat > "$pritunl_conf" <<EOF
{
  "mongodb_uri": "$existing_uri"
}
EOF
            print_success "Yapılandırma dosyası JSON formatına dönüştürüldü"
        fi
    fi
    
    # Pritunl için MongoDB veritabanı hazırla
    print_info "Pritunl için MongoDB veritabanı hazırlanıyor..."
    if command -v mongosh &>/dev/null; then
        mongosh --eval "use pritunl; db.createCollection('test'); db.test.drop();" --quiet 2>/dev/null || true
    elif command -v mongo &>/dev/null; then
        mongo --eval "use pritunl; db.createCollection('test'); db.test.drop();" --quiet 2>/dev/null || true
    fi
    
    # Pritunl servisini yeniden başlat
    print_info "Pritunl servisi yeniden başlatılıyor..."
    systemctl restart pritunl
    
    sleep 5
    
    # Servis durumunu kontrol et
    if systemctl is-active --quiet pritunl 2>/dev/null; then
        print_success "Pritunl MongoDB yapılandırması tamamlandı!"
        echo ""
        echo -e "${GREEN}MongoDB Durumu:${NC} $(systemctl is-active mongod)"
        echo -e "${GREEN}MongoDB URI:${NC} $mongodb_uri"
        echo -e "${GREEN}Pritunl Durumu:${NC} $(systemctl is-active pritunl)"
        echo ""
        print_info "Pritunl artık MongoDB'ye bağlı ve çalışıyor"
    else
        print_warning "Pritunl servisi başlatılamadı!"
        print_info "Log kontrolü: journalctl -u pritunl -n 50"
        print_info "MongoDB durumu: systemctl status mongod"
    fi
}

create_openvpn_client() {
    print_header "OpenVPN İstemci Sertifikası Oluşturma"
    
    # OpenVPN servis kontrolü
    local openvpn_running=false
    if systemctl is-active --quiet openvpn 2>/dev/null || systemctl is-active --quiet openvpn@server 2>/dev/null; then
        openvpn_running=true
    fi
    
    if [ "$openvpn_running" = false ]; then
        print_error "OpenVPN server çalışmıyor!"
        return 1
    fi
    
    local easyrsa_dir="/etc/openvpn/easy-rsa"
    if [ ! -d "$easyrsa_dir/pki" ]; then
        print_error "OpenVPN CA bulunamadı! Önce OpenVPN server kurulumu yapın."
        return 1
    fi
    
    cd $easyrsa_dir
    
    local client_name=""
    ask_input "İstemci adını girin (örn: kullanici1, laptop)" client_name
    
    if [ -z "$client_name" ]; then
        print_error "İstemci adı boş olamaz!"
        return 1
    fi
    
    # İstemci sertifikası oluştur
    print_info "İstemci sertifikası oluşturuluyor: $client_name"
    ./easyrsa gen-req $client_name nopass
    ./easyrsa sign-req client $client_name
    
    # İstemci yapılandırma dosyası oluştur
    local server_ip=$(hostname -I | awk '{print $1}')
    local openvpn_port=$(grep "^port" /etc/openvpn/server.conf 2>/dev/null | awk '{print $2}' || echo "1194")
    local openvpn_proto=$(grep "^proto" /etc/openvpn/server.conf 2>/dev/null | awk '{print $2}' || echo "udp")
    
    local client_config_dir="/etc/openvpn/clients"
    mkdir -p $client_config_dir
    
    local client_config="$client_config_dir/${client_name}.ovpn"
    cat > $client_config <<EOF
client
dev tun
proto $openvpn_proto
remote $server_ip $openvpn_port
resolv-retry infinite
nobind
persist-key
persist-tun
ca [inline]
cert [inline]
key [inline]
tls-auth [inline] 1
cipher AES-256-CBC
auth SHA256
verb 3
EOF
    
    # Sertifikaları dosyaya ekle
    echo "<ca>" >> $client_config
    cat $easyrsa_dir/pki/ca.crt >> $client_config
    echo "</ca>" >> $client_config
    
    echo "<cert>" >> $client_config
    cat $easyrsa_dir/pki/issued/${client_name}.crt >> $client_config
    echo "</cert>" >> $client_config
    
    echo "<key>" >> $client_config
    cat $easyrsa_dir/pki/private/${client_name}.key >> $client_config
    echo "</key>" >> $client_config
    
    echo "<tls-auth>" >> $client_config
    cat $easyrsa_dir/pki/ta.key >> $client_config
    echo "</tls-auth>" >> $client_config
    
    chmod 600 $client_config
    
    print_success "İstemci sertifikası oluşturuldu!"
    echo -e "${GREEN}İstemci Dosyası:${NC} $client_config"
    echo -e "${GREEN}İndirme:${NC} scp root@$server_ip:$client_config ./${client_name}.ovpn"
    echo ""
    print_info "Bu dosyayı OpenVPN istemcisine (Windows/Mac/Linux/Android/iOS) yükleyerek bağlanabilirsiniz"
}

list_openvpn_clients() {
    print_header "OpenVPN İstemci Listesi"
    
    local easyrsa_dir="/etc/openvpn/easy-rsa"
    local client_config_dir="/etc/openvpn/clients"
    
    if [ ! -d "$easyrsa_dir/pki/issued" ]; then
        print_warning "Henüz istemci sertifikası oluşturulmamış"
        return 0
    fi
    
    echo -e "${CYAN}Oluşturulan İstemci Sertifikaları:${NC}"
    echo ""
    
    local count=1
    for cert_file in $easyrsa_dir/pki/issued/*.crt; do
        if [ -f "$cert_file" ]; then
            local client_name=$(basename "$cert_file" .crt)
            if [ "$client_name" != "server" ]; then
                local client_ovpn="$client_config_dir/${client_name}.ovpn"
                local status=""
                if [ -f "$client_ovpn" ]; then
                    status="${GREEN}[Hazır]${NC}"
                else
                    status="${YELLOW}[Sertifika var, config yok]${NC}"
                fi
                
                echo "$count) $client_name $status"
                ((count++))
            fi
        fi
    done
    
    if [ $count -eq 1 ]; then
        print_info "Henüz istemci sertifikası oluşturulmamış"
    fi
}

revoke_openvpn_client() {
    print_header "OpenVPN İstemci Sertifikası İptal Etme"
    
    # OpenVPN servis kontrolü
    local openvpn_running=false
    if systemctl is-active --quiet openvpn 2>/dev/null || systemctl is-active --quiet openvpn@server 2>/dev/null; then
        openvpn_running=true
    fi
    
    if [ "$openvpn_running" = false ]; then
        print_error "OpenVPN server çalışmıyor!"
        return 1
    fi
    
    local easyrsa_dir="/etc/openvpn/easy-rsa"
    if [ ! -d "$easyrsa_dir/pki" ]; then
        print_error "OpenVPN CA bulunamadı!"
        return 1
    fi
    
    # İstemci listesi göster
    list_openvpn_clients
    echo ""
    
    local client_name=""
    ask_input "İptal edilecek istemci adını girin" client_name
    
    if [ -z "$client_name" ]; then
        print_error "İstemci adı boş olamaz!"
        return 1
    fi
    
    if [ ! -f "$easyrsa_dir/pki/issued/${client_name}.crt" ]; then
        print_error "İstemci sertifikası bulunamadı: $client_name"
        return 1
    fi
    
    echo -e "${YELLOW}UYARI:${NC} Bu işlem istemci sertifikasını iptal edecek ve bağlantıyı kesilecek!"
    if ! ask_yes_no "Devam etmek istiyor musunuz?"; then
        print_info "İşlem iptal edildi"
        return 0
    fi
    
    cd $easyrsa_dir
    ./easyrsa revoke $client_name
    
    # CRL'yi güncelle
    ./easyrsa gen-crl
    
    # CRL dosyasını OpenVPN dizinine kopyala
    cp $easyrsa_dir/pki/crl.pem /etc/openvpn/crl.pem 2>/dev/null || true
    
    # OpenVPN'i yeniden başlat
    if systemctl is-active --quiet openvpn 2>/dev/null; then
        systemctl restart openvpn
    elif systemctl is-active --quiet openvpn@server 2>/dev/null; then
        systemctl restart openvpn@server
    fi
    
    # İstemci dosyalarını sil
    rm -f /etc/openvpn/clients/${client_name}.ovpn
    
    print_success "İstemci sertifikası iptal edildi: $client_name"
}

openvpn_management_menu() {
    while true; do
        clear
        print_header "OpenVPN Yönetim Paneli"
        
        echo -e "${CYAN}OpenVPN Yönetim Seçenekleri:${NC}"
        echo "1) İstemci Sertifikası Oluştur"
        echo "2) İstemci Listesi"
        echo "3) İstemci Sertifikası İptal Et"
        echo "4) OpenVPN Durumu"
        echo "5) Geri Dön"
        echo ""
        
        read -p "Seçiminizi yapın (1-5): " choice
        
        case $choice in
            1)
                create_openvpn_client
                read -p "Devam etmek için Enter'a basın..."
                ;;
            2)
                list_openvpn_clients
                read -p "Devam etmek için Enter'a basın..."
                ;;
            3)
                revoke_openvpn_client
                read -p "Devam etmek için Enter'a basın..."
                ;;
            4)
                print_header "OpenVPN Durumu"
                local openvpn_running=false
                if systemctl is-active --quiet openvpn 2>/dev/null; then
                    openvpn_running=true
                    print_success "OpenVPN server çalışıyor (openvpn service)"
                elif systemctl is-active --quiet openvpn@server 2>/dev/null; then
                    openvpn_running=true
                    print_success "OpenVPN server çalışıyor (openvpn@server service)"
                fi
                
                if [ "$openvpn_running" = true ]; then
                    echo ""
                    echo -e "${CYAN}Servis Bilgileri:${NC}"
                    systemctl status openvpn 2>/dev/null | head -10 || systemctl status openvpn@server 2>/dev/null | head -10
                    echo ""
                    echo -e "${CYAN}Bağlı İstemciler:${NC}"
                    if [ -f "/var/log/openvpn/openvpn-status.log" ]; then
                        cat /var/log/openvpn/openvpn-status.log
                    elif [ -f "/etc/openvpn/openvpn-status.log" ]; then
                        cat /etc/openvpn/openvpn-status.log
                    else
                        echo "Henüz bağlı istemci yok veya log dosyası bulunamadı"
                    fi
                else
                    print_error "OpenVPN server çalışmıyor"
                fi
                read -p "Devam etmek için Enter'a basın..."
                ;;
            5)
                return 0
                ;;
            *)
                print_error "Geçersiz seçim"
                sleep 2
                ;;
        esac
    done
}

install_phpmyadmin() {
    print_info "phpMyAdmin kuruluyor..."
    
    # MySQL root şifresi kontrolü
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        print_error "MySQL root şifresi tanımlı değil!"
        ask_password "MySQL root şifresini girin" MYSQL_ROOT_PASSWORD
    fi
    
    debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect nginx"
    debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
    debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_ROOT_PASSWORD"
    debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password ''"
    
    apt install -y phpmyadmin
    print_success "phpMyAdmin kurulumu tamamlandı"
}

install_ssl() {
    print_info "Let's Encrypt SSL kuruluyor..."
    snap install core
    snap refresh core
    snap install --classic certbot
    ln -s /snap/bin/certbot /usr/bin/certbot
    
    certbot --nginx --agree-tos --redirect --hsts --staple-ocsp --email $EMAIL -d $ALAN_ADI -d www.$ALAN_ADI --non-interactive
    print_success "SSL kurulumu tamamlandı"
}

configure_nginx() {
    print_info "Nginx yapılandırması yapılıyor..."
    
    # Dizin yapısını oluştur
    mkdir -p /var/www/$ALAN_ADI/{logs,backups,storage,config}
    if [ -n "$WEB_ROOT" ]; then
        mkdir -p /var/www/$ALAN_ADI/$WEB_ROOT
    fi
    
    chown -R www-data:www-data /var/www/$ALAN_ADI
    chmod -R 755 /var/www/$ALAN_ADI
    
    # Framework'e özel Nginx konfigürasyonu
    case $FRAMEWORK in
        "laravel")
            cat > /etc/nginx/sites-available/$ALAN_ADI <<EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $ALAN_ADI www.$ALAN_ADI;
    root /var/www/$ALAN_ADI/$WEB_ROOT;
    index index.php index.html index.htm;

    access_log /var/www/$ALAN_ADI/logs/access.log;
    error_log /var/www/$ALAN_ADI/logs/error.log;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    location ~ ^/(storage|bootstrap)/ {
        deny all;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    location ~ /\.env {
        deny all;
    }
}
EOF
            ;;
        *)
            # Genel konfigürasyon
            cat > /etc/nginx/sites-available/$ALAN_ADI <<EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $ALAN_ADI www.$ALAN_ADI;
    root /var/www/$ALAN_ADI/$WEB_ROOT;
    index index.php index.html index.htm;

    access_log /var/www/$ALAN_ADI/logs/access.log;
    error_log /var/www/$ALAN_ADI/logs/error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
            ;;
    esac
    
    # VHost'u etkinleştir
    ln -sf /etc/nginx/sites-available/$ALAN_ADI /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # phpMyAdmin konfigürasyonu
    if [ "$INSTALL_PHPMYADMIN" = true ]; then
        cat >> /etc/nginx/sites-available/$ALAN_ADI <<'EOF'

    # phpMyAdmin Configuration
    location /phpmyadmin {
        root /usr/share/;
        index index.php index.html index.htm;

        location ~ ^/phpmyadmin/(.+\.php)$ {
            try_files $uri =404;
            root /usr/share/;
            fastcgi_pass unix:/var/run/php/phpEOF
        echo -n "$PHP_VERSION" >> /etc/nginx/sites-available/$ALAN_ADI
        cat >> /etc/nginx/sites-available/$ALAN_ADI <<'EOF'-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            include fastcgi_params;
        }

        location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
            root /usr/share/;
        }
    }
EOF
    fi
    
    print_success "Nginx yapılandırması tamamlandı"
}

create_sample_files() {
    print_info "Örnek dosyalar oluşturuluyor..."
    
    # Web root'u belirle
    local web_root_path="/var/www/$ALAN_ADI"
    if [ -n "$WEB_ROOT" ]; then
        web_root_path="/var/www/$ALAN_ADI/$WEB_ROOT"
    fi
    
    # Örnek index dosyası
    cat > $web_root_path/index.html <<EOF
<html>
<head>
    <title>$ALAN_ADI - Kurulum Başarılı</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; line-height: 1.6; }
        .container { max-width: 800px; margin: 0 auto; }
        .success { background: #d4edda; color: #155724; padding: 15px; border-radius: 5px; }
        .info { background: #d1ecf1; color: #0c5460; padding: 15px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class='container'>
        <h1>🚀 Kurulum Başarılı!</h1>
        <div class='success'>
            <strong>$ALAN_ADI</strong> için sunucu kurulumu tamamlandı.
        </div>
        
        <div class='info' style='margin-top: 20px;'>
            <h3>Kurulan Servisler:</h3>
            <ul>
                $([ "$INSTALL_NGINX" = true ] && echo "<li>✓ Nginx</li>")
                $([ "$INSTALL_PHP" = true ] && echo "<li>✓ PHP $PHP_VERSION</li>")
                $([ "$INSTALL_MYSQL" = true ] && echo "<li>✓ MySQL/MariaDB</li>")
                $([ "$INSTALL_NODEJS" = true ] && echo "<li>✓ Node.js</li>")
                $([ "$INSTALL_REDIS" = true ] && echo "<li>✓ Redis</li>")
                $([ "$INSTALL_COMPOSER" = true ] && echo "<li>✓ Composer</li>")
                $([ "$INSTALL_PHPMYADMIN" = true ] && echo "<li>✓ phpMyAdmin</li>")
                $([ "$INSTALL_SSL" = true ] && echo "<li>✓ SSL Sertifikası</li>")
            </ul>
        </div>
        
        <div style='margin-top: 20px;'>
            <p><strong>Framework:</strong> $FRAMEWORK</p>
            <p><strong>Web Root:</strong> $web_root_path</p>
            <p><strong>Ortam:</strong> $APP_ENV</p>
        </div>
    </div>
</body>
</html>
EOF

    # PHP test dosyası (sadece PHP kurulduysa)
    if [ "$INSTALL_PHP" = true ]; then
        cat > $web_root_path/info.php <<'EOF'
<?php
echo "<html><body>";
echo "<h1>PHP Çalışıyor!</h1>";
echo "<p>PHP Version: " . phpversion() . "</p>";
echo "<p>Server: " . $_SERVER['SERVER_SOFTWARE'] . "</p>";
echo "<p>Bu dosyayı üretim ortamında silmeyi unutmayın!</p>";
echo "</body></html>";
?>
EOF
    fi
    
    chown -R www-data:www-data /var/www/$ALAN_ADI
    print_success "Örnek dosyalar oluşturuldu"
}

# Yeni eklenen yönetim fonksiyonları
list_domains() {
    print_header "Mevcut Domain ve Subdomain'ler"
    
    if [ ! -d "/etc/nginx/sites-available" ]; then
        print_error "Nginx kurulu değil veya sites-available dizini bulunamadı."
        return 1
    fi
    
    local domains=$(ls /etc/nginx/sites-available/ 2>/dev/null | grep -v default)
    
    if [ -z "$domains" ]; then
        print_warning "Henüz yapılandırılmış domain bulunamadı."
        return 1
    fi
    
    echo -e "${CYAN}Yapılandırılmış Domain/Subdomain'ler:${NC}"
    echo ""
    local count=1
    for domain in $domains; do
        local enabled=""
        if [ -L "/etc/nginx/sites-enabled/$domain" ]; then
            enabled="${GREEN}[Aktif]${NC}"
        else
            enabled="${RED}[Pasif]${NC}"
        fi
        
        local root_dir=$(grep -E "^\s*root\s+" /etc/nginx/sites-available/$domain 2>/dev/null | head -1 | awk '{print $2}' | tr -d ';')
        local server_names=$(grep -E "^\s*server_name\s+" /etc/nginx/sites-available/$domain 2>/dev/null | head -1 | sed 's/server_name//' | sed 's/;//')
        
        echo -e "${count}) ${GREEN}$domain${NC} $enabled"
        echo "   Server Names: $server_names"
        echo "   Root: $root_dir"
        echo ""
        ((count++))
    done
}

add_subdomain() {
    print_header "Subdomain Ekleme"
    
    if ! command -v nginx &> /dev/null; then
        print_error "Nginx kurulu değil. Önce Nginx kurulumu yapın."
        return 1
    fi
    
    local subdomain=""
    local main_domain=""
    local subdomain_dir=""
    local php_version=""
    local use_ssl=false
    
    # Ana domain seçimi
    ask_input "Ana domain adını girin (örn: ornek.com)" main_domain
    
    # Subdomain adı
    ask_input "Subdomain adını girin (örn: api, blog, test)" subdomain
    
    # Dizin seçimi
    echo -e "${CYAN}Dizin seçimi:${NC}"
    echo "1) Ana domain ile aynı dizin (/var/www/$main_domain)"
    echo "2) Ayrı dizin (/var/www/$subdomain.$main_domain)"
    echo "3) Özel dizin belirt"
    
    read -p "Seçiminiz (1-3) [2]: " dir_choice
    case $dir_choice in
        1)
            subdomain_dir="/var/www/$main_domain"
            ;;
        3)
            read -p "Özel dizin yolunu girin: " subdomain_dir
            ;;
        *)
            subdomain_dir="/var/www/$subdomain.$main_domain"
            ;;
    esac
    
    # PHP versiyonu kontrolü
    if systemctl list-units --type=service | grep -q "php.*-fpm"; then
        echo "PHP versiyonu seçin:"
        echo "1) PHP 8.3"
        echo "2) PHP 8.4"
        read -p "Seçiminiz (1-2) [1]: " php_choice
        case $php_choice in
            2) php_version="8.4";;
            *) php_version="8.3";;
        esac
        
        # PHP-FPM servisinin gerçekten var olup olmadığını kontrol et
        if ! systemctl list-units --type=service | grep -q "php${php_version}-fpm"; then
            # Mevcut PHP versiyonunu bul
            local installed_php=$(systemctl list-units --type=service | grep "php.*-fpm" | head -1 | sed 's/.*php\([0-9.]*\)-fpm.*/\1/')
            if [ -n "$installed_php" ]; then
                php_version="$installed_php"
                print_info "PHP $php_version kullanılıyor"
            else
                print_warning "PHP bulunamadı. PHP olmadan devam ediliyor."
                php_version=""
            fi
        fi
    else
        print_warning "PHP bulunamadı. PHP olmadan devam ediliyor."
        php_version=""
    fi
    
    # SSL sorusu
    if ask_yes_no "Bu subdomain için SSL sertifikası oluşturulsun mu?"; then
        use_ssl=true
        if [ -z "$EMAIL" ]; then
            ask_input "E-posta adresinizi girin (SSL için gerekli)" EMAIL
        fi
    fi
    
    # Dizin oluştur
    print_info "Dizin oluşturuluyor: $subdomain_dir"
    mkdir -p $subdomain_dir
    mkdir -p /var/www/$main_domain/logs
    chown -R www-data:www-data $subdomain_dir
    chown -R www-data:www-data /var/www/$main_domain/logs
    chmod -R 755 $subdomain_dir
    chmod -R 755 /var/www/$main_domain/logs
    
    # Örnek index dosyası
    cat > $subdomain_dir/index.html <<EOF
<html>
<head>
    <title>$subdomain.$main_domain</title>
</head>
<body>
    <h1>Subdomain: $subdomain.$main_domain</h1>
    <p>Kurulum başarılı!</p>
</body>
</html>
EOF
    
    # Nginx konfigürasyonu
    local config_file="/etc/nginx/sites-available/$subdomain.$main_domain"
    local server_name="$subdomain.$main_domain"
    
    if [ -n "$php_version" ]; then
        cat > $config_file <<EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $server_name;
    root $subdomain_dir;
    index index.php index.html index.htm;

    access_log /var/www/$main_domain/logs/${subdomain}_access.log;
    error_log /var/www/$main_domain/logs/${subdomain}_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${php_version}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    else
        cat > $config_file <<EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $server_name;
    root $subdomain_dir;
    index index.html index.htm;

    access_log /var/www/$main_domain/logs/${subdomain}_access.log;
    error_log /var/www/$main_domain/logs/${subdomain}_error.log;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    fi
    
    # VHost'u etkinleştir
    ln -sf $config_file /etc/nginx/sites-enabled/
    
    # Nginx test ve reload
    if nginx -t; then
        systemctl reload nginx
        print_success "Nginx yapılandırması başarılı"
    else
        print_error "Nginx yapılandırma hatası!"
        rm -f /etc/nginx/sites-enabled/$subdomain.$main_domain
        return 1
    fi
    
    # SSL kurulumu
    if [ "$use_ssl" = true ]; then
        print_info "SSL sertifikası oluşturuluyor..."
        if command -v certbot &> /dev/null; then
            certbot --nginx --agree-tos --redirect --hsts --staple-ocsp --email $EMAIL -d $server_name --non-interactive
            print_success "SSL sertifikası oluşturuldu"
        else
            print_warning "Certbot bulunamadı. SSL kurulumu atlandı."
        fi
    fi
    
    print_success "Subdomain başarıyla eklendi: $server_name"
    echo -e "${GREEN}Erişim:${NC} http://$server_name"
    if [ "$use_ssl" = true ]; then
        echo -e "${GREEN}HTTPS:${NC} https://$server_name"
    fi
}

change_directory() {
    print_header "Domain Dizin Değiştirme"
    
    if ! command -v nginx &> /dev/null; then
        print_error "Nginx kurulu değil."
        return 1
    fi
    
    local domain=""
    ask_input "Dizinini değiştirmek istediğiniz domain/subdomain adını girin" domain
    
    if [ ! -f "/etc/nginx/sites-available/$domain" ]; then
        print_error "Domain bulunamadı: $domain"
        return 1
    fi
    
    local current_dir=$(grep -E "^\s*root\s+" /etc/nginx/sites-available/$domain 2>/dev/null | head -1 | awk '{print $2}' | tr -d ';')
    echo -e "${CYAN}Mevcut dizin:${NC} $current_dir"
    
    local new_dir=""
    ask_input "Yeni dizin yolunu girin" new_dir
    
    if [ ! -d "$new_dir" ]; then
        if ask_yes_no "Dizin mevcut değil. Oluşturulsun mu?"; then
            mkdir -p $new_dir
            chown -R www-data:www-data $new_dir
            chmod -R 755 $new_dir
            print_success "Dizin oluşturuldu"
        else
            print_error "İşlem iptal edildi."
            return 1
        fi
    fi
    
    # Nginx konfigürasyonunu güncelle
    sed -i "s|^\s*root\s\+.*;|    root $new_dir;|g" /etc/nginx/sites-available/$domain
    
    # Nginx test ve reload
    if nginx -t; then
        systemctl reload nginx
        print_success "Dizin başarıyla değiştirildi"
        echo -e "${GREEN}Yeni dizin:${NC} $new_dir"
    else
        print_error "Nginx yapılandırma hatası! Değişiklik geri alınıyor..."
        sed -i "s|^\s*root\s\+.*;|    root $current_dir;|g" /etc/nginx/sites-available/$domain
        return 1
    fi
}

renew_ssl() {
    print_header "SSL Sertifikası Yenileme"
    
    if ! command -v certbot &> /dev/null; then
        print_error "Certbot kurulu değil. Önce SSL kurulumu yapın."
        return 1
    fi
    
    echo -e "${CYAN}SSL Yenileme Seçenekleri:${NC}"
    echo "1) Tüm sertifikaları yenile"
    echo "2) Belirli bir domain için yenile"
    echo "3) Test yenileme (dry-run)"
    
    read -p "Seçiminiz (1-3) [1]: " choice
    case $choice in
        2)
            local domain=""
            ask_input "Yenilenecek domain adını girin" domain
            print_info "SSL sertifikası yenileniyor: $domain"
            certbot renew --cert-name $domain --force-renewal
            ;;
        3)
            print_info "Test yenileme yapılıyor..."
            certbot renew --dry-run
            ;;
        *)
            print_info "Tüm SSL sertifikaları yenileniyor..."
            certbot renew --force-renewal
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        print_success "SSL sertifikaları başarıyla yenilendi"
        systemctl reload nginx
    else
        print_error "SSL yenileme sırasında hata oluştu"
        return 1
    fi
}

create_ssl() {
    print_header "SSL Sertifikası Oluşturma"
    
    if ! command -v certbot &> /dev/null; then
        print_info "Certbot kuruluyor..."
        snap install core
        snap refresh core
        snap install --classic certbot
        ln -s /snap/bin/certbot /usr/bin/certbot
    fi
    
    if ! command -v nginx &> /dev/null; then
        print_error "Nginx kurulu değil. SSL için Nginx gerekli."
        return 1
    fi
    
    local domain=""
    ask_input "SSL oluşturulacak domain/subdomain adını girin" domain
    
    if [ ! -f "/etc/nginx/sites-available/$domain" ]; then
        print_error "Domain bulunamadı: $domain"
        return 1
    fi
    
    if [ -z "$EMAIL" ]; then
        ask_input "E-posta adresinizi girin (SSL için gerekli)" EMAIL
    fi
    
    local server_names=$(grep -E "^\s*server_name\s+" /etc/nginx/sites-available/$domain 2>/dev/null | head -1 | sed 's/server_name//' | sed 's/;//' | xargs)
    
    if [ -z "$server_names" ]; then
        print_error "Domain yapılandırmasında server_name bulunamadı."
        return 1
    fi
    
    print_info "SSL sertifikası oluşturuluyor: $server_names"
    
    # Domain listesini oluştur (-d parametreleri için)
    local certbot_domains=""
    for d in $server_names; do
        certbot_domains="$certbot_domains -d $d"
    done
    
    certbot --nginx --agree-tos --redirect --hsts --staple-ocsp --email $EMAIL $certbot_domains --non-interactive
    
    if [ $? -eq 0 ]; then
        print_success "SSL sertifikası başarıyla oluşturuldu"
        systemctl reload nginx
    else
        print_error "SSL oluşturma sırasında hata oluştu"
        return 1
    fi
}

delete_domain() {
    print_header "Domain/Subdomain Silme"
    
    if ! command -v nginx &> /dev/null; then
        print_error "Nginx kurulu değil."
        return 1
    fi
    
    local domain=""
    ask_input "Silinecek domain/subdomain adını girin" domain
    
    if [ ! -f "/etc/nginx/sites-available/$domain" ]; then
        print_error "Domain bulunamadı: $domain"
        return 1
    fi
    
    echo -e "${YELLOW}UYARI:${NC} Bu işlem domain yapılandırmasını silecek."
    if ! ask_yes_no "Devam etmek istiyor musunuz?"; then
        print_info "İşlem iptal edildi."
        return 1
    fi
    
    # SSL sertifikasını sil
    if certbot certificates 2>/dev/null | grep -q "$domain"; then
        if ask_yes_no "SSL sertifikası da silinsin mi?"; then
            certbot delete --cert-name $domain --non-interactive
        fi
    fi
    
    # Nginx yapılandırmasını sil
    rm -f /etc/nginx/sites-enabled/$domain
    rm -f /etc/nginx/sites-available/$domain
    
    # Nginx test ve reload
    if nginx -t; then
        systemctl reload nginx
        print_success "Domain başarıyla silindi: $domain"
    else
        print_error "Nginx yapılandırma hatası!"
        return 1
    fi
}

install_gitlab() {
    print_header "GitLab Kurulumu"
    
    local gitlab_domain=""
    local gitlab_email=""
    local gitlab_edition="ce"
    local install_ssl_gitlab=false
    
    # GitLab domain bilgisi
    ask_input "GitLab için domain adını girin (örn: gitlab.ornek.com)" gitlab_domain
    
    # E-posta bilgisi
    if [ -z "$EMAIL" ]; then
        ask_input "E-posta adresinizi girin (SSL ve bildirimler için)" gitlab_email
        EMAIL="$gitlab_email"
    else
        gitlab_email="$EMAIL"
    fi
    
    # GitLab Edition seçimi
    echo -e "${CYAN}GitLab Edition Seçimi:${NC}"
    echo "1) GitLab CE (Community Edition) - Ücretsiz"
    echo "2) GitLab EE (Enterprise Edition) - Ücretli"
    read -p "Seçiminiz (1-2) [1]: " edition_choice
    case $edition_choice in
        2) gitlab_edition="ee";;
        *) gitlab_edition="ce";;
    esac
    
    # SSL sorusu
    if ask_yes_no "GitLab için SSL sertifikası kurulsun mu?"; then
        install_ssl_gitlab=true
    fi
    
    # Sistem gereksinimleri kontrolü
    print_info "Sistem gereksinimleri kontrol ediliyor..."
    
    local total_ram=$(free -g | awk '/^Mem:/{print $2}')
    local available_disk=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ "$total_ram" -lt 4 ]; then
        print_warning "GitLab için en az 4GB RAM önerilir. Mevcut RAM: ${total_ram}GB"
        if ! ask_yes_no "Yine de devam etmek istiyor musunuz?"; then
            print_error "Kurulum iptal edildi."
            return 1
        fi
    fi
    
    if [ "$available_disk" -lt 10 ]; then
        print_warning "GitLab için en az 10GB boş disk alanı önerilir. Mevcut: ${available_disk}GB"
        if ! ask_yes_no "Yine de devam etmek istiyor musunuz?"; then
            print_error "Kurulum iptal edildi."
            return 1
        fi
    fi
    
    # Kurulum özeti
    print_header "GitLab Kurulum Özeti"
    echo -e "${GREEN}Domain:${NC} $gitlab_domain"
    echo -e "${GREEN}Edition:${NC} GitLab ${gitlab_edition^^}"
    echo -e "${GREEN}E-posta:${NC} $gitlab_email"
    echo -e "${GREEN}SSL:${NC} $([ "$install_ssl_gitlab" = true ] && echo "Evet" || echo "Hayır")"
    echo ""
    
    if ! ask_yes_no "GitLab kurulumunu başlatmak istiyor musunuz?"; then
        print_error "Kurulum iptal edildi."
        return 1
    fi
    
    # KURULUM BAŞLANGICI
    print_header "GitLab Kurulumu Başlatılıyor..."
    
    # Sistem güncellemeleri
    print_info "Sistem güncellemeleri yapılıyor..."
    apt update && apt upgrade -y
    
    # Gerekli paketler
    print_info "Gerekli paketler kuruluyor..."
    apt install -y curl openssh-server ca-certificates tzdata perl postfix lsb-release
    
    # Postfix yapılandırması (eğer kurulu değilse)
    if ! command -v postfix &> /dev/null; then
        print_info "Postfix yapılandırılıyor..."
        debconf-set-selections <<< "postfix postfix/mailname string $gitlab_domain"
        debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
    fi
    
    # GitLab repository ekleme
    print_info "GitLab repository ekleniyor..."
    curl -fsSL https://packages.gitlab.com/gitlab/gitlab-${gitlab_edition}/gpgkey | gpg --dearmor > /usr/share/keyrings/gitlab-${gitlab_edition}.gpg
    
    # Repository kaynağını ekle
    cat > /etc/apt/sources.list.d/gitlab_${gitlab_edition}.list <<EOF
deb [signed-by=/usr/share/keyrings/gitlab-${gitlab_edition}.gpg] https://packages.gitlab.com/gitlab/gitlab-${gitlab_edition}/ubuntu/ $(lsb_release -cs) main
EOF
    
    # Paket listesini güncelle
    apt update
    
    # GitLab kurulumu
    print_info "GitLab ${gitlab_edition^^} kuruluyor (bu işlem birkaç dakika sürebilir)..."
    EXTERNAL_URL="http://$gitlab_domain" apt install -y gitlab-${gitlab_edition}
    
    if [ $? -ne 0 ]; then
        print_error "GitLab kurulumu başarısız oldu."
        return 1
    fi
    
    # GitLab yapılandırması
    print_info "GitLab yapılandırılıyor..."
    
    # GitLab yapılandırma dosyasını düzenle
    local gitlab_config="/etc/gitlab/gitlab.rb"
    
    # Domain yapılandırması
    if grep -q "external_url" $gitlab_config; then
        sed -i "s|external_url.*|external_url 'http://$gitlab_domain'|g" $gitlab_config
    else
        echo "external_url 'http://$gitlab_domain'" >> $gitlab_config
    fi
    
    # E-posta yapılandırması
    if ask_yes_no "SMTP e-posta yapılandırması yapılsın mı?"; then
        configure_gitlab_smtp $gitlab_config $gitlab_email
    fi
    
    # GitLab yapılandırmasını uygula
    print_info "GitLab yapılandırması uygulanıyor (bu işlem 5-10 dakika sürebilir)..."
    gitlab-ctl reconfigure
    
    if [ $? -ne 0 ]; then
        print_error "GitLab yapılandırması başarısız oldu."
        return 1
    fi
    
    # SSL kurulumu
    if [ "$install_ssl_gitlab" = true ]; then
        print_info "GitLab için SSL sertifikası oluşturuluyor..."
        
        # Certbot kurulumu (eğer yoksa)
        if ! command -v certbot &> /dev/null; then
            snap install core
            snap refresh core
            snap install --classic certbot
            ln -s /snap/bin/certbot /usr/bin/certbot
        fi
        
        # GitLab'ı geçici olarak durdur (port 80'i serbest bırakmak için)
        print_info "GitLab geçici olarak durduruluyor (SSL kurulumu için)..."
        gitlab-ctl stop nginx
        
        # Certbot ile SSL ekle (standalone mod)
        certbot certonly --standalone --agree-tos --email $gitlab_email -d $gitlab_domain --non-interactive
        
        if [ $? -eq 0 ]; then
            # GitLab yapılandırmasını HTTPS'e güncelle
            sed -i "s|external_url 'http://$gitlab_domain'|external_url 'https://$gitlab_domain'|g" $gitlab_config
            
            # Let's Encrypt sertifikalarını GitLab'a bağla
            # Mevcut nginx ayarlarını temizle
            sed -i "/^nginx\['redirect_http_to_https'\]/d" $gitlab_config
            sed -i "/^nginx\['ssl_certificate'\]/d" $gitlab_config
            sed -i "/^nginx\['ssl_certificate_key'\]/d" $gitlab_config
            
            # Yeni SSL ayarlarını ekle
            cat >> $gitlab_config <<EOF

# SSL Configuration
nginx['redirect_http_to_https'] = true
nginx['ssl_certificate'] = "/etc/letsencrypt/live/$gitlab_domain/fullchain.pem"
nginx['ssl_certificate_key'] = "/etc/letsencrypt/live/$gitlab_domain/privkey.pem"
EOF
            
            # Yapılandırmayı uygula
            print_info "GitLab SSL yapılandırması uygulanıyor..."
            gitlab-ctl reconfigure
            
            if [ $? -eq 0 ]; then
                print_success "SSL sertifikası başarıyla eklendi"
            else
                print_warning "SSL yapılandırması uygulanamadı. GitLab HTTP üzerinden çalışmaya devam edecek."
                # HTTP'ye geri dön
                sed -i "s|external_url 'https://$gitlab_domain'|external_url 'http://$gitlab_domain'|g" $gitlab_config
                gitlab-ctl reconfigure
            fi
        else
            print_warning "SSL sertifikası oluşturulamadı. GitLab HTTP üzerinden çalışmaya devam edecek."
        fi
        
        # GitLab'ı tekrar başlat
        gitlab-ctl start
    fi
    
    # GitLab servislerini başlat
    print_info "GitLab servisleri başlatılıyor..."
    gitlab-ctl start
    
    # İlk root şifresini göster
    print_header "GitLab Kurulumu Tamamlandı!"
    echo -e "${GREEN}✓ Domain:${NC} $([ "$install_ssl_gitlab" = true ] && echo "https://" || echo "http://")$gitlab_domain"
    echo -e "${GREEN}✓ Edition:${NC} GitLab ${gitlab_edition^^}"
    echo ""
    echo -e "${YELLOW}ÖNEMLİ:${NC}"
    echo "GitLab ilk kurulumda otomatik bir root şifresi oluşturur."
    
    # Şifre dosyasını kontrol et
    local password_file="/etc/gitlab/initial_root_password"
    if [ -f "$password_file" ]; then
        echo ""
        echo -e "${CYAN}İlk giriş bilgileri:${NC}"
        echo -e "${CYAN}Kullanıcı adı:${NC} root"
        echo -e "${CYAN}Şifre:${NC} $(grep 'Password:' $password_file | cut -d' ' -f2)"
        echo ""
        echo -e "${YELLOW}UYARI:${NC} Bu şifre dosyası 24 saat sonra otomatik olarak silinir!"
        echo "Şifreyi güvenli bir yere kaydedin ve ilk girişte değiştirin."
    else
        echo "Şifre dosyası henüz oluşturulmadı. Birkaç dakika bekleyip tekrar kontrol edin:"
        echo -e "${CYAN}sudo cat /etc/gitlab/initial_root_password${NC}"
    fi
    echo ""
    echo -e "${CYAN}GitLab Yönetim Komutları:${NC}"
    echo "• Durum kontrolü: ${GREEN}sudo gitlab-ctl status${NC}"
    echo "• Yeniden başlatma: ${GREEN}sudo gitlab-ctl restart${NC}"
    echo "• Yapılandırma uygulama: ${GREEN}sudo gitlab-ctl reconfigure${NC}"
    echo "• Log görüntüleme: ${GREEN}sudo gitlab-ctl tail${NC}"
    echo ""
    print_success "GitLab kurulumu başarıyla tamamlandı!"
}

configure_gitlab_smtp() {
    local gitlab_config=$1
    local email=$2
    
    print_info "SMTP yapılandırması yapılıyor..."
    
    echo ""
    echo -e "${CYAN}SMTP Yapılandırması:${NC}"
    echo "1) Gmail"
    echo "2) Outlook/Hotmail"
    echo "3) Özel SMTP"
    read -p "Seçiminiz (1-3) [3]: " smtp_choice
    
    local smtp_host=""
    local smtp_port=""
    local smtp_user=""
    local smtp_password=""
    local smtp_domain=""
    
    case $smtp_choice in
        1)
            smtp_host="smtp.gmail.com"
            smtp_port="587"
            ask_input "Gmail e-posta adresiniz" smtp_user
            ask_password "Gmail uygulama şifreniz (2FA aktifse)" smtp_password
            smtp_domain="gmail.com"
            ;;
        2)
            smtp_host="smtp-mail.outlook.com"
            smtp_port="587"
            ask_input "Outlook e-posta adresiniz" smtp_user
            ask_password "Outlook şifreniz" smtp_password
            smtp_domain="outlook.com"
            ;;
        *)
            ask_input "SMTP sunucu adresi (örn: smtp.example.com)" smtp_host
            ask_input "SMTP port (örn: 587, 465, 25)" smtp_port "587"
            ask_input "SMTP kullanıcı adı" smtp_user
            ask_password "SMTP şifresi" smtp_password
            read -p "SMTP domain (opsiyonel): " smtp_domain
            ;;
    esac
    
    # GitLab SMTP yapılandırmasını ekle
    cat >> $gitlab_config <<EOF

# SMTP Configuration
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = "$smtp_host"
gitlab_rails['smtp_port'] = $smtp_port
gitlab_rails['smtp_user_name'] = "$smtp_user"
gitlab_rails['smtp_password'] = "$smtp_password"
gitlab_rails['smtp_domain'] = "$smtp_domain"
gitlab_rails['smtp_authentication'] = "login"
gitlab_rails['smtp_enable_starttls_auto'] = true
gitlab_rails['smtp_tls'] = false
gitlab_rails['gitlab_email_from'] = "$email"
gitlab_rails['gitlab_email_reply_to'] = "$email"
EOF
    
    print_success "SMTP yapılandırması eklendi"
}

# Yeni eklenen yardımcı fonksiyonlar
show_server_info() {
    print_header "Sunucu Bilgileri"
    
    echo -e "${CYAN}Sistem Bilgileri:${NC}"
    if command -v lsb_release &> /dev/null; then
        echo -e "İşletim Sistemi: ${GREEN}$(lsb_release -d | cut -f2)${NC}"
    else
        echo -e "İşletim Sistemi: ${GREEN}$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)${NC}"
    fi
    echo -e "Kernel: ${GREEN}$(uname -r)${NC}"
    echo -e "Hostname: ${GREEN}$(hostname)${NC}"
    echo -e "Uptime: ${GREEN}$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')${NC}"
    echo ""
    
    echo -e "${CYAN}Donanım Bilgileri:${NC}"
    local total_ram=$(free -h | awk '/^Mem:/{print $2}')
    local used_ram=$(free -h | awk '/^Mem:/{print $3}')
    local total_disk=$(df -h / | awk 'NR==2 {print $2}')
    local used_disk=$(df -h / | awk 'NR==2 {print $3}')
    local cpu_cores=$(nproc)
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
    
    echo -e "CPU: ${GREEN}$cpu_model${NC}"
    echo -e "CPU Çekirdek: ${GREEN}$cpu_cores${NC}"
    echo -e "RAM: ${GREEN}$used_ram / $total_ram${NC}"
    echo -e "Disk: ${GREEN}$used_disk / $total_disk${NC}"
    echo ""
    
    echo -e "${CYAN}Ağ Bilgileri:${NC}"
    local ip_address=$(hostname -I | awk '{print $1}')
    echo -e "IP Adresi: ${GREEN}$ip_address${NC}"
    echo ""
    
    echo -e "${CYAN}Kurulu Servisler:${NC}"
    [ -f /usr/sbin/nginx ] && echo -e "✓ ${GREEN}Nginx${NC} - $(nginx -v 2>&1 | cut -d' ' -f3)"
    [ -f /usr/bin/php ] && echo -e "✓ ${GREEN}PHP${NC} - $(php -v | head -1 | cut -d' ' -f2)"
    [ -f /usr/bin/mysql ] && echo -e "✓ ${GREEN}MySQL${NC} - $(mysql --version | cut -d' ' -f5-6)"
    [ -f /usr/bin/node ] && echo -e "✓ ${GREEN}Node.js${NC} - $(node --version)"
    [ -f /usr/local/bin/composer ] && echo -e "✓ ${GREEN}Composer${NC} - $(composer --version 2>/dev/null | head -1 | cut -d' ' -f3)"
    [ -f /usr/bin/redis-cli ] && echo -e "✓ ${GREEN}Redis${NC} - $(redis-server --version | cut -d' ' -f3)"
    [ -f /usr/bin/gitlab-ctl ] && echo -e "✓ ${GREEN}GitLab${NC}"
    [ -f /usr/bin/docker ] && echo -e "✓ ${GREEN}Docker${NC} - $(docker --version | cut -d' ' -f3 | tr -d ',')"
    echo ""
    
    echo -e "${CYAN}Servis Durumları:${NC}"
    systemctl is-active --quiet nginx && echo -e "Nginx: ${GREEN}Çalışıyor${NC}" || echo -e "Nginx: ${RED}Durdurulmuş${NC}"
    systemctl is-active --quiet mariadb && echo -e "MariaDB: ${GREEN}Çalışıyor${NC}" || echo -e "MariaDB: ${RED}Durdurulmuş${NC}"
    systemctl is-active --quiet redis && echo -e "Redis: ${GREEN}Çalışıyor${NC}" || echo -e "Redis: ${RED}Durdurulmuş${NC}"
    systemctl is-active --quiet ufw && echo -e "UFW: ${GREEN}Aktif${NC}" || echo -e "UFW: ${RED}Pasif${NC}"
    systemctl is-active --quiet fail2ban && echo -e "Fail2ban: ${GREEN}Çalışıyor${NC}" || echo -e "Fail2ban: ${RED}Durdurulmuş${NC}"
}

install_firewall() {
    print_header "UFW Firewall Kurulumu"
    
    if ! command -v ufw &> /dev/null; then
        print_info "UFW kuruluyor..."
        apt update
        apt install -y ufw
    fi
    
    print_info "UFW yapılandırılıyor..."
    
    # Varsayılan politikalar
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH portunu aç (mevcut bağlantıyı kesmemek için)
    local ssh_port=$(grep -E "^Port\s+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    ufw allow $ssh_port/tcp comment 'SSH'
    
    # Yaygın servis portları
    if ask_yes_no "HTTP (80) portunu açmak istiyor musunuz?"; then
        ufw allow 80/tcp comment 'HTTP'
    fi
    
    if ask_yes_no "HTTPS (443) portunu açmak istiyor musunuz?"; then
        ufw allow 443/tcp comment 'HTTPS'
    fi
    
    if systemctl is-active --quiet mariadb; then
        if ask_yes_no "MySQL (3306) portunu açmak istiyor musunuz? (Sadece güvenli ağlardan)"; then
            read -p "MySQL için IP adresi veya subnet (örn: 192.168.1.0/24) [Tümü]: " mysql_network
            mysql_network=${mysql_network:-"0.0.0.0/0"}
            ufw allow from $mysql_network to any port 3306 comment 'MySQL'
        fi
    fi
    
    if systemctl is-active --quiet redis; then
        if ask_yes_no "Redis (6379) portunu açmak istiyor musunuz? (Sadece localhost önerilir)"; then
            ufw allow 127.0.0.1 comment 'Redis Localhost'
        fi
    fi
    
    # UFW'yi etkinleştir
    if ask_yes_no "UFW'yi etkinleştirmek istiyor musunuz?"; then
        ufw --force enable
        systemctl enable ufw
        print_success "UFW başarıyla etkinleştirildi"
        ufw status verbose
    else
        print_info "UFW yapılandırıldı ancak etkinleştirilmedi"
    fi
}

install_fail2ban() {
    print_header "Fail2ban Kurulumu"
    
    if ! command -v fail2ban-server &> /dev/null; then
        print_info "Fail2ban kuruluyor..."
        apt update
        apt install -y fail2ban
    fi
    
    print_info "Fail2ban yapılandırılıyor..."
    
    # Fail2ban yapılandırma dosyası
    local jail_local="/etc/fail2ban/jail.local"
    
    cat > $jail_local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_)s

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10

[nginx-botsearch]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2
EOF
    
    # E-posta adresi güncelle
    if [ -n "$EMAIL" ]; then
        sed -i "s|destemail = root@localhost|destemail = $EMAIL|g" $jail_local
    fi
    
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    print_success "Fail2ban başarıyla kuruldu ve yapılandırıldı"
    echo ""
    echo -e "${CYAN}Fail2ban Durumu:${NC}"
    fail2ban-client status
}

backup_database() {
    print_header "Database Yedekleme"
    
    if ! systemctl is-active --quiet mariadb && ! systemctl is-active --quiet mysql; then
        print_error "MySQL/MariaDB çalışmıyor veya kurulu değil."
        return 1
    fi
    
    # MySQL root şifresini al
    local mysql_password=""
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        ask_password "MySQL root şifresini girin" mysql_password
    else
        mysql_password="$MYSQL_ROOT_PASSWORD"
    fi
    
    local backup_dir="/var/backups/mysql"
    mkdir -p $backup_dir
    
    echo -e "${CYAN}Yedekleme Seçenekleri:${NC}"
    echo "1) Tüm veritabanlarını yedekle"
    echo "2) Belirli bir veritabanını yedekle"
    read -p "Seçiminiz (1-2) [1]: " backup_choice
    
    local db_name=""
    local backup_file=""
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    case $backup_choice in
        2)
            # Veritabanı listesi
            echo ""
            echo -e "${CYAN}Mevcut Veritabanları:${NC}"
            mysql -u root -p"$mysql_password" -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$"
            echo ""
            ask_input "Yedeklenecek veritabanı adını girin" db_name
            
            backup_file="$backup_dir/${db_name}_${timestamp}.sql.gz"
            print_info "Veritabanı yedekleniyor: $db_name"
            mysqldump -u root -p"$mysql_password" $db_name 2>/dev/null | gzip > $backup_file
            ;;
        *)
            backup_file="$backup_dir/all_databases_${timestamp}.sql.gz"
            print_info "Tüm veritabanları yedekleniyor..."
            mysqldump -u root -p"$mysql_password" --all-databases 2>/dev/null | gzip > $backup_file
            ;;
    esac
    
    if [ $? -eq 0 ] && [ -f "$backup_file" ]; then
        local file_size=$(du -h "$backup_file" | cut -f1)
        print_success "Yedekleme tamamlandı!"
        echo -e "${GREEN}Yedek Dosyası:${NC} $backup_file"
        echo -e "${GREEN}Boyut:${NC} $file_size"
    else
        print_error "Yedekleme başarısız oldu!"
        return 1
    fi
}

restore_database() {
    print_header "Database Geri Yükleme"
    
    if ! systemctl is-active --quiet mariadb && ! systemctl is-active --quiet mysql; then
        print_error "MySQL/MariaDB çalışmıyor veya kurulu değil."
        return 1
    fi
    
    # MySQL root şifresini al
    local mysql_password=""
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        ask_password "MySQL root şifresini girin" mysql_password
    else
        mysql_password="$MYSQL_ROOT_PASSWORD"
    fi
    
    local backup_dir="/var/backups/mysql"
    
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A $backup_dir 2>/dev/null)" ]; then
        print_error "Yedek dosyası bulunamadı: $backup_dir"
        return 1
    fi
    
    echo -e "${CYAN}Mevcut Yedekler:${NC}"
    ls -lh $backup_dir/*.sql.gz 2>/dev/null | nl
    echo ""
    
    read -p "Geri yüklenecek yedek dosyasının numarasını girin: " file_num
    local backup_file=$(ls -1 $backup_dir/*.sql.gz 2>/dev/null | sed -n "${file_num}p")
    
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        print_error "Geçersiz dosya seçimi!"
        return 1
    fi
    
    echo -e "${YELLOW}UYARI:${NC} Bu işlem mevcut veritabanını silecek!"
    if ! ask_yes_no "Devam etmek istiyor musunuz?"; then
        print_info "İşlem iptal edildi."
        return 1
    fi
    
    print_info "Veritabanı geri yükleniyor: $backup_file"
    gunzip < $backup_file | mysql -u root -p"$mysql_password" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_success "Geri yükleme tamamlandı!"
    else
        print_error "Geri yükleme başarısız oldu!"
        return 1
    fi
}

install_docker() {
    print_header "Docker Kurulumu"
    
    if command -v docker &> /dev/null; then
        print_warning "Docker zaten kurulu: $(docker --version)"
        if ! ask_yes_no "Yeniden kurmak istiyor musunuz?"; then
            return 0
        fi
    fi
    
    print_info "Docker kuruluyor..."
    
    # Eski Docker sürümlerini kaldır
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null
    
    # Gerekli paketler
    apt update
    apt install -y ca-certificates curl gnupg lsb-release
    
    # Docker GPG key ekle
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Repository ekle
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Docker kur
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Docker servisini başlat
    systemctl start docker
    systemctl enable docker
    
    # Docker Compose kurulumu
    if ! command -v docker-compose &> /dev/null; then
        print_info "Docker Compose kuruluyor..."
        apt install -y docker-compose
    fi
    
    print_success "Docker başarıyla kuruldu!"
    echo -e "${GREEN}Docker Version:${NC} $(docker --version)"
    echo -e "${GREEN}Docker Compose Version:${NC} $(docker compose version 2>/dev/null || docker-compose --version)"
    echo ""
    echo -e "${CYAN}Docker Yönetim Komutları:${NC}"
    echo "• Durum: ${GREEN}sudo systemctl status docker${NC}"
    echo "• Başlat: ${GREEN}sudo systemctl start docker${NC}"
    echo "• Durdur: ${GREEN}sudo systemctl stop docker${NC}"
}

install_individual_service() {
    print_header "Tekil Servis Kurulumu"
    
    echo -e "${CYAN}Kurulabilecek Servisler:${NC}"
    echo "1) Nginx"
    echo "2) PHP (8.3 veya 8.4)"
    echo "3) MySQL/MariaDB"
    echo "4) Node.js"
    echo "5) Redis (Sunucu)"
    echo "6) Composer"
    echo "7) phpMyAdmin"
    echo "8) PHP Eklentileri (Redis, Memcached, vb.)"
    echo "9) Geri Dön"
    echo ""
    
    read -p "Kurulacak servisi seçin (1-9): " service_choice
    
    case $service_choice in
        1)
            # PHP kurulu mu kontrol et (birden fazla yöntem dene)
            local php_installed=false
            local php_version=""
            
            # Yöntem 1: php -v komutundan versiyon al
            if command -v php &> /dev/null; then
                php_version=$(php -v 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
                if [ -n "$php_version" ]; then
                    php_installed=true
                    print_info "Kurulu PHP versiyonu tespit edildi: $php_version"
                fi
            fi
            
            # Yöntem 2: /usr/bin/php* dosyalarından versiyon bul
            if [ -z "$php_version" ]; then
                for php_bin in /usr/bin/php[0-9]* /usr/bin/php[0-9]*.[0-9]*; do
                    if [ -f "$php_bin" ] && [ -x "$php_bin" ]; then
                        php_version=$(basename "$php_bin" | sed 's/php//' | grep -oE "^[0-9]+\.[0-9]+")
                        if [ -n "$php_version" ]; then
                            php_installed=true
                            print_info "Kurulu PHP versiyonu tespit edildi: $php_version"
                            break
                        fi
                    fi
                done
            fi
            
            # Yöntem 3: PHP-FPM servislerinden versiyon bul
            if [ -z "$php_version" ]; then
                local php_fpm_version=$(systemctl list-units --type=service --all 2>/dev/null | grep "php.*-fpm" | head -1 | sed 's/.*php\([0-9.]*\)-fpm.*/\1/' | grep -E "^[0-9]+\.[0-9]+" || echo "")
                if [ -n "$php_fpm_version" ]; then
                    php_version="$php_fpm_version"
                    php_installed=true
                    print_info "Kurulu PHP versiyonu tespit edildi: $php_version"
                fi
            fi
            
            if [ "$php_installed" = true ]; then
                print_info "Nginx kurulumundan sonra PHP yapılandırmaları otomatik olarak eklenecek"
            fi
            
            if command -v nginx &> /dev/null; then
                print_warning "Nginx zaten kurulu: $(nginx -v 2>&1)"
                if ask_yes_no "Yeniden kurmak istiyor musunuz?"; then
                    install_nginx
                elif [ "$php_installed" = true ] && [ -n "$php_version" ]; then
                    # Nginx zaten kurulu, sadece PHP yapılandırmalarını güncelle
                    if ask_yes_no "Mevcut Nginx yapılandırmalarını PHP için güncellemek ister misiniz?"; then
                        update_nginx_for_php $php_version
                    fi
                fi
            else
                install_nginx
            fi
            ;;
        2)
            # PHP versiyonu seçimi
            echo ""
            echo "PHP versiyonu seçin:"
            echo "1) PHP 8.3 (Önerilen)"
            echo "2) PHP 8.4"
            read -p "Seçiminiz (1-2) [1]: " php_choice
            local php_version="8.3"
            case $php_choice in
                2) php_version="8.4";;
                *) php_version="8.3";;
            esac
            
            # Framework seçimi (opsiyonel)
            echo ""
            echo "Framework seçimi (opsiyonel, ek paketler için):"
            echo "1) Laravel"
            echo "2) Symfony"
            echo "3) CodeIgniter"
            echo "4) Genel (Framework yok)"
            read -p "Seçiminiz (1-4) [4]: " framework_choice
            local temp_framework=""
            case $framework_choice in
                1) temp_framework="laravel";;
                2) temp_framework="symfony";;
                3) temp_framework="codeigniter";;
                *) temp_framework="";;
            esac
            
            # Geçici olarak FRAMEWORK değişkenini ayarla
            local old_framework="$FRAMEWORK"
            FRAMEWORK="$temp_framework"
            
            # Mevcut PHP kurulumunu kontrol et
            local has_php_cli=false
            local has_php_fpm=false
            
            if command -v php &> /dev/null; then
                has_php_cli=true
                local current_version=$(php -v | head -1 | cut -d' ' -f2 | cut -d'.' -f1,2)
                print_info "PHP CLI kurulu: $current_version"
            fi
            
            # PHP-FPM servislerini kontrol et
            local php_fpm_services=$(systemctl list-units --type=service --all 2>/dev/null | grep "php.*-fpm" | awk '{print $1}' || echo "")
            if [ -n "$php_fpm_services" ]; then
                has_php_fpm=true
                print_info "PHP-FPM servisleri tespit edildi"
            fi
            
            # Eğer sadece PHP-CLI varsa ve PHP-FPM yoksa
            if [ "$has_php_cli" = true ] && [ "$has_php_fpm" = false ]; then
                print_warning "Sadece PHP-CLI kurulu, PHP-FPM bulunamadı!"
                print_info "Nginx ile çalışmak için PHP-FPM gereklidir."
                if ask_yes_no "PHP-FPM kurulumuna devam etmek ister misiniz?"; then
                    install_php $php_version
                    FRAMEWORK="$old_framework"
                else
                    print_info "PHP kurulumu iptal edildi"
                    FRAMEWORK="$old_framework"
                fi
            elif [ "$has_php_cli" = true ] && [ "$has_php_fpm" = true ]; then
                print_warning "PHP zaten kurulu (CLI ve FPM)"
                if ask_yes_no "PHP $php_version kurulumuna devam etmek istiyor musunuz?"; then
                    install_php $php_version
                    FRAMEWORK="$old_framework"
                else
                    FRAMEWORK="$old_framework"
                fi
            else
                # PHP kurulu değil, normal kurulum
                print_info "PHP-FPM kurulumu başlatılıyor..."
                install_php $php_version
                FRAMEWORK="$old_framework"
            fi
            ;;
        3)
            # MySQL/MariaDB durum kontrolü
            local mysql_running=false
            local mysql_error=false
            
            if systemctl is-active --quiet mariadb 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null; then
                mysql_running=true
                print_info "MySQL/MariaDB servisi çalışıyor"
                
                # Şifre ile bağlantı testi
                if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
                    if ! mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
                        mysql_error=true
                        print_error "MySQL root şifresi hatalı veya bağlantı hatası!"
                        print_info "Hata: Access denied veya servis hatası tespit edildi"
                    fi
                else
                    # Şifresiz bağlantı testi
                    if ! mysql -u root -e "SELECT 1;" 2>/dev/null && ! sudo mysql -u root -e "SELECT 1;" 2>/dev/null; then
                        mysql_error=true
                        print_error "MySQL bağlantı hatası tespit edildi!"
                    fi
                fi
            else
                # Servis çalışmıyor ama kurulu olabilir
                if command -v mysql &> /dev/null || command -v mariadb &> /dev/null; then
                    print_warning "MySQL/MariaDB kurulu görünüyor ancak servis çalışmıyor"
                    mysql_error=true
                fi
            fi
            
            # Hata durumunda temizleme seçeneği
            if [ "$mysql_error" = true ]; then
                print_warning "MySQL/MariaDB'de sorun tespit edildi!"
                echo ""
                echo "Seçenekler:"
                echo "1) Mevcut kurulumu kaldırıp yeniden kur (Önerilen)"
                echo "2) Şifreyi manuel olarak ayarla ve tekrar dene"
                echo "3) İptal et"
                echo ""
                read -p "Seçiminiz (1-3) [1]: " fix_choice
                
                case $fix_choice in
                    2)
                        print_info "Manuel şifre ayarlama..."
                        if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                            ask_password "MySQL root şifresini belirleyin" MYSQL_ROOT_PASSWORD
                        fi
                        
                        # Servisi başlatmayı dene
                        systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null
                        sleep 3
                        
                        # Servisin başladığından emin ol
                        local retry_count=0
                        while [ $retry_count -lt 10 ]; do
                            if systemctl is-active --quiet mariadb 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null; then
                                break
                            fi
                            sleep 1
                            ((retry_count++))
                        done
                        
                        # Şifre ayarlamayı dene (birden fazla yöntem)
                        local manual_password_set=false
                        local max_attempts=3
                        local attempt=0
                        
                        while [ $attempt -lt $max_attempts ] && [ "$manual_password_set" = false ]; do
                            ((attempt++))
                            print_info "Şifre ayarlama denemesi $attempt/$max_attempts..."
                            
                            # Yöntem 1: sudo mysql (MariaDB 10.4+ için en güvenilir)
                            if sudo mysql <<EOF 2>/dev/null; then
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
ALTER USER 'root'@'::1' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF
                                manual_password_set=true
                                print_success "Şifre sudo mysql ile ayarlandı"
                                break
                            # Yöntem 2: Normal mysql (eğer şifresiz erişim varsa)
                            elif mysql -u root <<EOF 2>/dev/null; then
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF
                                manual_password_set=true
                                print_success "Şifre normal mysql ile ayarlandı"
                                break
                            # Yöntem 3: mysqladmin
                            elif mysqladmin -u root password "$MYSQL_ROOT_PASSWORD" 2>/dev/null; then
                                manual_password_set=true
                                print_success "Şifre mysqladmin ile ayarlandı"
                                break
                            else
                                sleep 2
                            fi
                        done
                        
                        if [ "$manual_password_set" = true ]; then
                            # Şifre ile bağlantı testi
                            sleep 2
                            local verify_count=0
                            local verify_success=false
                            
                            while [ $verify_count -lt 5 ] && [ "$verify_success" = false ]; do
                                if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
                                    verify_success=true
                                    print_success "MySQL bağlantısı başarılı!"
                                    break
                                fi
                                sleep 1
                                ((verify_count++))
                            done
                            
                            if [ "$verify_success" = false ]; then
                                print_warning "Şifre ayarlandı ancak bağlantı testi başarısız"
                                print_info "Manuel test için: mysql -u root -p"
                            fi
                        else
                            print_error "Manuel şifre ayarlama başarısız, temizleme önerilir"
                        fi
                        ;;
                    3)
                        print_info "İşlem iptal edildi"
                        ;;
                    *)
                        # Temizleme ve yeniden kurulum
                        print_info "MySQL/MariaDB kapsamlı temizleme yapılıyor..."
                        
                        # Önce çalışan tüm MySQL/MariaDB process'lerini zorla durdur
                        print_info "Çalışan MySQL/MariaDB process'leri durduruluyor..."
                        pkill -9 mysqld 2>/dev/null || true
                        pkill -9 mariadbd 2>/dev/null || true
                        pkill -9 mysqld_safe 2>/dev/null || true
                        pkill -9 mariadb 2>/dev/null || true
                        sleep 3
                        
                        # Servisleri durdur (systemd varsa)
                        systemctl stop mariadb 2>/dev/null || true
                        systemctl stop mysql 2>/dev/null || true
                        systemctl disable mariadb 2>/dev/null || true
                        systemctl disable mysql 2>/dev/null || true
                        sleep 2
                        
                        # Broken dependencies'i düzelt
                        print_info "Broken dependencies düzeltiliyor..."
                        apt --fix-broken install -y 2>/dev/null || true
                        
                        # Tüm MariaDB/MySQL paketlerini kaldır
                        print_info "MariaDB/MySQL paketleri kaldırılıyor..."
                        
                        # Önce kısmi kurulumları temizle
                        dpkg --remove --force-remove-reinstreq mariadb-server mariadb-client mariadb-common 2>/dev/null || true
                        dpkg --remove --force-remove-reinstreq mysql-server mysql-client mysql-common 2>/dev/null || true
                        
                        # Sonra normal kaldırma
                        apt remove --purge -y \
                            mariadb-server mariadb-client mariadb-common \
                            mysql-server mysql-client mysql-common \
                            mariadb-server-* mariadb-client-* \
                            mysql-server-* mysql-client-* \
                            galera-* 2>/dev/null || true
                        
                        # update-alternatives temizliği
                        print_info "update-alternatives temizleniyor..."
                        update-alternatives --remove-all mysql 2>/dev/null || true
                        update-alternatives --remove-all mysqldump 2>/dev/null || true
                        update-alternatives --remove-all mysqladmin 2>/dev/null || true
                        update-alternatives --remove-all mysqlcheck 2>/dev/null || true
                        
                        # Eksik dosyaları oluştur (dpkg hatasını önlemek için)
                        if [ ! -d "/etc/mysql" ]; then
                            mkdir -p /etc/mysql
                        fi
                        if [ ! -f "/etc/mysql/mariadb.cnf" ]; then
                            touch /etc/mysql/mariadb.cnf
                        fi
                        
                        # dpkg yapılandırmasını düzelt
                        print_info "dpkg yapılandırması düzeltiliyor..."
                        dpkg --configure -a 2>/dev/null || true
                        
                        # Broken dependencies'i tekrar düzelt
                        apt --fix-broken install -y 2>/dev/null || true
                        
                        # Kalan paketleri temizle
                        apt autoremove -y
                        apt autoclean
                        
                        # Eksik bağımlılıkları kur
                        apt-get -f install -y 2>/dev/null || true
                        
                        # dpkg durumunu kontrol et ve düzelt
                        print_info "dpkg durumu kontrol ediliyor..."
                        dpkg --configure -a 2>/dev/null || true
                        
                        # Veri ve yapılandırma dizinlerini temizle
                        print_info "Veri ve yapılandırma dizinleri temizleniyor..."
                        rm -rf /var/lib/mysql
                        rm -rf /etc/mysql
                        rm -rf /var/log/mysql
                        rm -rf /run/mysqld
                        rm -f /etc/init.d/mysql
                        rm -f /etc/init.d/mariadb
                        
                        # Systemd servis dosyalarını temizle
                        rm -f /etc/systemd/system/mariadb.service
                        rm -f /etc/systemd/system/mysql.service
                        rm -f /lib/systemd/system/mariadb.service
                        rm -f /lib/systemd/system/mysql.service
                        systemctl daemon-reload
                        
                        print_success "Kapsamlı temizleme tamamlandı"
                        sleep 2
                        
                        if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                            ask_password "MySQL root şifresini belirleyin" MYSQL_ROOT_PASSWORD
                        fi
                        
                        install_mysql
                        ;;
                esac
            elif [ "$mysql_running" = true ]; then
                # MySQL çalışıyor, yeniden kurulum seçeneği
                print_warning "MySQL/MariaDB zaten kurulu ve çalışıyor"
                if ask_yes_no "Yeniden kurmak istiyor musunuz? (UYARI: Veriler silinebilir!)"; then
                    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                        ask_password "MySQL root şifresini belirleyin" MYSQL_ROOT_PASSWORD
                    fi
                    install_mysql
                fi
            else
                # MySQL kurulu değil, normal kurulum
                if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                    ask_password "MySQL root şifresini belirleyin" MYSQL_ROOT_PASSWORD
                fi
                install_mysql
            fi
            ;;
        4)
            if command -v node &> /dev/null; then
                print_warning "Node.js zaten kurulu: $(node --version)"
                if ask_yes_no "Yeniden kurmak istiyor musunuz?"; then
                    install_nodejs
                fi
            else
                install_nodejs
            fi
            ;;
        5)
            if systemctl is-active --quiet redis; then
                print_warning "Redis zaten kurulu ve çalışıyor"
                if ask_yes_no "Yeniden kurmak istiyor musunuz?"; then
                    install_redis
                fi
            else
                install_redis
            fi
            ;;
        6)
            if command -v composer &> /dev/null; then
                print_warning "Composer zaten kurulu: $(composer --version 2>/dev/null | head -1)"
                if ask_yes_no "Yeniden kurmak istiyor musunuz?"; then
                    install_composer
                fi
            else
                install_composer
            fi
            ;;
        7)
            # phpMyAdmin için MySQL ve PHP kontrolü
            if ! systemctl is-active --quiet mariadb && ! systemctl is-active --quiet mysql; then
                print_error "phpMyAdmin için MySQL/MariaDB kurulu olmalıdır."
                if ask_yes_no "MySQL/MariaDB kurmak ister misiniz?"; then
                    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                        ask_password "MySQL root şifresini belirleyin" MYSQL_ROOT_PASSWORD
                    fi
                    install_mysql
                else
                    print_error "phpMyAdmin kurulumu iptal edildi."
                    return 1
                fi
            fi
            
            if ! command -v php &> /dev/null; then
                print_error "phpMyAdmin için PHP kurulu olmalıdır."
                if ask_yes_no "PHP kurmak ister misiniz?"; then
                    echo "PHP versiyonu seçin:"
                    echo "1) PHP 8.3"
                    echo "2) PHP 8.4"
                    read -p "Seçiminiz (1-2) [1]: " php_choice
                    local php_version="8.3"
                    case $php_choice in
                        2) php_version="8.4";;
                        *) php_version="8.3";;
                    esac
                    install_php $php_version
                else
                    print_error "phpMyAdmin kurulumu iptal edildi."
                    return 1
                fi
            fi
            
            if dpkg -l | grep -q phpmyadmin; then
                print_warning "phpMyAdmin zaten kurulu"
                if ask_yes_no "Yeniden kurmak istiyor musunuz?"; then
                    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                        ask_password "MySQL root şifresini girin" MYSQL_ROOT_PASSWORD
                    fi
                    install_phpmyadmin
                fi
            else
                if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                    ask_password "MySQL root şifresini girin" MYSQL_ROOT_PASSWORD
                fi
                install_phpmyadmin
            fi
            ;;
        8)
            install_php_extensions
            ;;
        9)
            return 0
            ;;
        *)
            print_error "Geçersiz seçim"
            return 1
            ;;
    esac
    
    print_success "Servis kurulumu tamamlandı!"
}

view_logs() {
    print_header "Log Dosyaları Görüntüleme"
    
    echo -e "${CYAN}Log Seçenekleri:${NC}"
    echo "1) Nginx Access Log"
    echo "2) Nginx Error Log"
    echo "3) PHP-FPM Log"
    echo "4) MySQL/MariaDB Log"
    echo "5) System Log (journalctl)"
    echo "6) Fail2ban Log"
    echo "7) Özel Log Dosyası"
    read -p "Seçiminiz (1-7): " log_choice
    
    local log_file=""
    local lines=50
    
    read -p "Kaç satır gösterilsin? [50]: " lines_input
    lines=${lines_input:-50}
    
    case $log_choice in
        1)
            log_file="/var/log/nginx/access.log"
            ;;
        2)
            log_file="/var/log/nginx/error.log"
            ;;
        3)
            local php_version=$(systemctl list-units --type=service | grep "php.*-fpm" | head -1 | sed 's/.*php\([0-9.]*\)-fpm.*/\1/')
            if [ -n "$php_version" ]; then
                log_file="/var/log/php${php_version}-fpm.log"
            else
                print_error "PHP-FPM bulunamadı"
                return 1
            fi
            ;;
        4)
            log_file="/var/log/mysql/error.log"
            ;;
        5)
            print_info "System log gösteriliyor..."
            journalctl -n $lines --no-pager
            return 0
            ;;
        6)
            log_file="/var/log/fail2ban.log"
            ;;
        7)
            read -p "Log dosyası yolunu girin: " log_file
            ;;
        *)
            print_error "Geçersiz seçim"
            return 1
            ;;
    esac
    
    if [ -f "$log_file" ]; then
        print_info "Son $lines satır gösteriliyor: $log_file"
        echo ""
        tail -n $lines "$log_file"
    else
        print_error "Log dosyası bulunamadı: $log_file"
        return 1
    fi
}

# Nginx'teki domain'leri tespit et
get_nginx_domains() {
    local domains=()
    
    if [ ! -d "/etc/nginx/sites-available" ]; then
        return 1
    fi
    
    # Nginx yapılandırma dosyalarından server_name'leri çıkar
    for config_file in /etc/nginx/sites-available/*; do
        if [ -f "$config_file" ] && [ "$(basename "$config_file")" != "default" ]; then
            # server_name direktiflerini bul
            local server_names=$(grep -E "^\s*server_name\s+" "$config_file" 2>/dev/null | \
                sed 's/server_name//' | sed 's/;//' | tr -s ' ' | tr ' ' '\n' | \
                grep -v "^$" | grep -v "default_server" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            
            if [ -n "$server_names" ]; then
                while IFS= read -r domain; do
                    if [ -n "$domain" ] && [[ ! " ${domains[@]} " =~ " ${domain} " ]]; then
                        domains+=("$domain")
                    fi
                done <<< "$server_names"
            fi
        fi
    done
    
    # Domain'leri yazdır
    printf '%s\n' "${domains[@]}"
}

# Nginx domain'lerini DNS kayıtlarına ekle (BIND9)
add_nginx_domains_to_bind9() {
    local forward_zone=$1
    local server_ip=$2
    
    if [ ! -f "$forward_zone" ]; then
        return 1
    fi
    
    print_info "Nginx'teki domain'ler DNS kayıtlarına ekleniyor..."
    
    local nginx_domains=($(get_nginx_domains))
    local added_count=0
    
    if [ ${#nginx_domains[@]} -eq 0 ]; then
        print_warning "Nginx'te yapılandırılmış domain bulunamadı"
        return 0
    fi
    
    # Zone dosyasını yedekle
    cp "$forward_zone" "${forward_zone}.backup.$(date +%Y%m%d_%H%M%S)"
    
    for domain in "${nginx_domains[@]}"; do
        # Domain'i parse et (subdomain ve ana domain)
        local subdomain=""
        local main_domain=""
        
        if [[ "$domain" =~ ^([^.]+)\.(.+)$ ]]; then
            subdomain="${BASH_REMATCH[1]}"
            main_domain="${BASH_REMATCH[2]}"
        else
            main_domain="$domain"
        fi
        
        # Zone dosyasının domain'i ile eşleşiyor mu kontrol et
        local zone_domain=$(basename "$forward_zone" | sed 's/^db\.//')
        
        if [ "$main_domain" = "$zone_domain" ]; then
            # Subdomain kaydı ekle
            if [ -n "$subdomain" ] && [ "$subdomain" != "www" ]; then
                if ! grep -q "^$subdomain[[:space:]]" "$forward_zone" 2>/dev/null; then
                    # Zone dosyasının sonuna ekle (SOA kaydından önce değil)
                    sed -i "/^@[[:space:]]*IN[[:space:]]*MX/a\\$subdomain     IN      A       $server_ip" "$forward_zone"
                    print_success "DNS kaydı eklendi: $subdomain.$main_domain -> $server_ip"
                    ((added_count++))
                fi
            fi
        fi
    done
    
    if [ $added_count -gt 0 ]; then
        # Serial numarasını güncelle
        local current_serial=$(grep -E "^\s*[0-9]+\s*;" "$forward_zone" | head -1 | awk '{print $1}')
        local new_serial=$(date +%Y%m%d01)
        if [ -n "$current_serial" ] && [ "$new_serial" -gt "$current_serial" ]; then
            sed -i "s/^[[:space:]]*$current_serial[[:space:]]*;/$new_serial        ;/" "$forward_zone"
        fi
        
        print_success "$added_count Nginx domain'i DNS kayıtlarına eklendi"
        
        # Zone dosyasını kontrol et
        local zone_domain=$(basename "$forward_zone" | sed 's/^db\.//')
        if named-checkzone "$zone_domain" "$forward_zone" 2>/dev/null; then
            print_success "Zone dosyası geçerli"
            systemctl reload named 2>/dev/null || systemctl restart named
        else
            print_warning "Zone dosyasında hata olabilir, kontrol edin: named-checkzone $zone_domain $forward_zone"
        fi
    else
        print_info "Eklenmesi gereken yeni domain bulunamadı"
    fi
}

# Nginx domain'lerini DNS kayıtlarına ekle (dnsmasq)
add_nginx_domains_to_dnsmasq() {
    local dnsmasq_hosts=$1
    local server_ip=$2
    
    if [ ! -f "$dnsmasq_hosts" ]; then
        return 1
    fi
    
    print_info "Nginx'teki domain'ler DNS kayıtlarına ekleniyor..."
    
    local nginx_domains=($(get_nginx_domains))
    local added_count=0
    
    if [ ${#nginx_domains[@]} -eq 0 ]; then
        print_warning "Nginx'te yapılandırılmış domain bulunamadı"
        return 0
    fi
    
    # Hosts dosyasını yedekle
    cp "$dnsmasq_hosts" "${dnsmasq_hosts}.backup.$(date +%Y%m%d_%H%M%S)"
    
    for domain in "${nginx_domains[@]}"; do
        # Domain kaydı var mı kontrol et
        if ! grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+$domain" "$dnsmasq_hosts" 2>/dev/null; then
            echo "$server_ip    $domain" >> "$dnsmasq_hosts"
            print_success "DNS kaydı eklendi: $domain -> $server_ip"
            ((added_count++))
        fi
    done
    
    if [ $added_count -gt 0 ]; then
        print_success "$added_count Nginx domain'i DNS kayıtlarına eklendi"
        systemctl restart dnsmasq
        print_success "dnsmasq servisi yeniden başlatıldı"
    else
        print_info "Eklenmesi gereken yeni domain bulunamadı"
    fi
}

add_nginx_domains_to_dns() {
    print_header "Nginx Domain'lerini DNS'e Ekleme"
    
    # Nginx kontrolü
    if ! command -v nginx &>/dev/null || [ ! -d "/etc/nginx/sites-available" ]; then
        print_error "Nginx kurulu değil veya yapılandırma dizini bulunamadı!"
        return 1
    fi
    
    # Nginx domain'lerini tespit et
    local nginx_domains=($(get_nginx_domains))
    
    if [ ${#nginx_domains[@]} -eq 0 ]; then
        print_warning "Nginx'te yapılandırılmış domain bulunamadı!"
        return 1
    fi
    
    print_info "Nginx'te tespit edilen domain'ler:"
    for domain in "${nginx_domains[@]}"; do
        echo "  - $domain"
    done
    echo ""
    
    # DNS sunucusu kontrolü
    local dns_type=""
    local server_ip=$(hostname -I | awk '{print $1}')
    
    if systemctl is-active --quiet named 2>/dev/null; then
        dns_type="bind9"
        print_success "BIND9 DNS sunucusu aktif"
    elif systemctl is-active --quiet dnsmasq 2>/dev/null; then
        dns_type="dnsmasq"
        print_success "dnsmasq DNS sunucusu aktif"
    else
        print_error "Aktif DNS sunucusu bulunamadı!"
        print_info "Önce DNS sunucusu kurulumu yapmanız gerekiyor."
        if ask_yes_no "DNS sunucusu kurulumuna gitmek ister misiniz?"; then
            install_dns_server
            return $?
        else
            return 1
        fi
    fi
    
    # Sunucu IP'sini al
    ask_input "DNS sunucusu IP adresi" server_ip "$server_ip"
    
    # BIND9 için
    if [ "$dns_type" = "bind9" ]; then
        print_info "BIND9 için domain'ler ekleniyor..."
        
        # Domain'leri grupla (ana domain'e göre)
        declare -A domain_groups
        for domain in "${nginx_domains[@]}"; do
            local main_domain=""
            if [[ "$domain" =~ ^([^.]+)\.(.+)$ ]]; then
                main_domain="${BASH_REMATCH[2]}"
            else
                main_domain="$domain"
            fi
            
            if [ -z "${domain_groups[$main_domain]}" ]; then
                domain_groups[$main_domain]="$domain"
            else
                domain_groups[$main_domain]="${domain_groups[$main_domain]} $domain"
            fi
        done
        
        # Her ana domain için zone dosyası bul ve ekle
        local added_count=0
        for main_domain in "${!domain_groups[@]}"; do
            local forward_zone="/etc/bind/db.$main_domain"
            
            if [ -f "$forward_zone" ]; then
                print_info "Zone dosyası bulundu: $forward_zone"
                add_nginx_domains_to_bind9 "$forward_zone" "$server_ip"
                ((added_count++))
            else
                print_warning "Zone dosyası bulunamadı: $forward_zone"
                print_info "Bu domain için önce BIND9 zone oluşturmanız gerekiyor."
            fi
        done
        
        if [ $added_count -gt 0 ]; then
            print_success "Nginx domain'leri BIND9 DNS kayıtlarına eklendi!"
        fi
        
    # dnsmasq için
    elif [ "$dns_type" = "dnsmasq" ]; then
        print_info "dnsmasq için domain'ler ekleniyor..."
        
        local dnsmasq_hosts="/etc/dnsmasq.hosts"
        
        if [ ! -f "$dnsmasq_hosts" ]; then
            print_warning "dnsmasq hosts dosyası bulunamadı: $dnsmasq_hosts"
            print_info "dnsmasq yapılandırmasını kontrol edin."
            return 1
        fi
        
        add_nginx_domains_to_dnsmasq "$dnsmasq_hosts" "$server_ip"
        print_success "Nginx domain'leri dnsmasq DNS kayıtlarına eklendi!"
    fi
}

# Mevcut zone dosyalarını RFC uyumlu hale getir
update_zone_soa_values() {
    print_header "Zone Dosyalarını RFC Uyumlu Hale Getirme"
    
    # Zone dosyalarını bul (sadece domain zone dosyaları, sistem zone dosyaları değil)
    local zone_files=$(find /etc/bind -name "db.*" -type f 2>/dev/null | grep -v ".backup" | grep -vE "(db\.127|db\.0|db\.255|db\.empty|db\.local|db\.root)")
    
    if [ -z "$zone_files" ]; then
        print_warning "Domain zone dosyası bulunamadı!"
        print_info "Sistem zone dosyaları (db.127, db.local, vb.) atlanıyor."
        return 1
    fi
    
    print_info "Domain zone dosyaları güncelleniyor..."
    
    for zone_file in $zone_files; do
        if [ ! -f "$zone_file" ]; then
            continue
        fi
        
        # Sistem zone dosyalarını atla
        local zone_basename=$(basename "$zone_file")
        if [[ "$zone_basename" =~ ^db\.(127|0|255|empty|local|root)$ ]]; then
            print_info "Sistem zone dosyası atlanıyor: $zone_file"
            continue
        fi
        
        print_info "Güncelleniyor: $zone_file"
        
        # Yedekleme
        cp "$zone_file" "${zone_file}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Python ile güvenli güncelleme - satır satır işleme
        if command -v python3 &>/dev/null; then
            python3 <<PYTHON_UPDATE
import re
import sys
from datetime import datetime

zone_file = '$zone_file'

try:
    with open(zone_file, 'r') as f:
        lines = f.readlines()
    
    updated_lines = []
    has_www = False
    server_ip = None
    last_ns_index = -1
    
    for i, line in enumerate(lines):
        original = line
        
        # TTL değerini güncelle
        if line.strip().startswith('$TTL'):
            line = line.replace('604800', '3600')
            line = line.replace('10800', '3600')
    
        # REFRESH: 604800 -> 3600
        if 'Refresh' in line and '604800' in line:
            line = line.replace('604800', '3600')
        
        # RETRY: 86400 -> 600
        if 'Retry' in line:
            if '86400' in line:
                line = line.replace('86400', '600')
            else:
                # Diğer yüksek değerleri kontrol et
                match = re.search(r'(\s+)(\d+)(\s*;\s*Retry)', line)
                if match:
                    try:
                        if int(match.group(2)) > 600:
                            line = re.sub(r'\d+(\s*;\s*Retry)', '600\\1', line)
                    except:
                        pass
        
        # EXPIRE: 2419200 -> 604800
        if 'Expire' in line:
            if '2419200' in line:
                line = line.replace('2419200', '604800')
            else:
                # Diğer yüksek değerleri kontrol et
                match = re.search(r'(\s+)(\d+)(\s*;\s*Expire)', line)
                if match:
                    try:
                        if int(match.group(2)) > 604800:
                            line = re.sub(r'\d+(\s*;\s*Expire)', '604800\\1', line)
                    except:
                        pass
        
        # MINIMUM TTL: 604800 -> 3600
        if 'Negative Cache TTL' in line or 'Minimum TTL' in line:
            if '604800' in line:
                line = line.replace('604800', '3600')
            else:
                # Diğer yüksek değerleri kontrol et
                match = re.search(r'(\s+)(\d+)(\s*\)\s*;\s*(?:Negative|Minimum))', line)
                if match:
                    try:
                        if int(match.group(2)) > 3600:
                            line = re.sub(r'\d+(\s*\)\s*;\s*(?:Negative|Minimum))', '3600\\1', line)
                    except:
                        pass
        
        # Serial numarasını güncelle
        if 'Serial' in line:
            today_serial = datetime.now().strftime('%Y%m%d') + '01'
            line = re.sub(r'(\d{8})\d{2}(\s*;\s*Serial)', today_serial + '\\2', line)
        
        # IP adresini al
        if '@' in line and 'IN' in line and 'A' in line:
            match = re.search(r'@\s+IN\s+A\s+([0-9.]+)', line)
            if match:
                server_ip = match.group(1)
        
        # NS kayıtlarını bul
        if '@' in line and 'IN' in line and 'NS' in line:
            last_ns_index = len(updated_lines)
        
        # www kaydını kontrol et
        if 'www' in line and 'IN' in line and 'A' in line:
            has_www = True
        
        updated_lines.append(line)
    
    # www kaydı yoksa ekle
    if not has_www and server_ip and last_ns_index >= 0:
        www_line = f'www     IN      A       {server_ip}\n'
        updated_lines.insert(last_ns_index + 1, www_line)
        domain_name = zone_file.split('/')[-1].replace('db.', '')
        print(f"www kaydı eklendi: www.{domain_name} -> {server_ip}")
    
    # Dosyayı yaz
    with open(zone_file, 'w') as f:
        f.writelines(updated_lines)
    
    print("Zone dosyası güncellendi")
    sys.exit(0)
except Exception as e:
    print(f"Hata: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYTHON_UPDATE
            
            if [ $? -eq 0 ]; then
                print_success "Zone dosyası güncellendi: $zone_file"
                
                # Zone dosyasını kontrol et
                local zone_name=$(basename "$zone_file" | sed 's/^db\.//')
                if named-checkzone "$zone_name" "$zone_file" 2>/dev/null; then
                    print_success "Zone dosyası geçerli: $zone_name"
                else
                    print_warning "Zone dosyasında hata olabilir: named-checkzone $zone_name $zone_file"
                fi
            else
                print_warning "Python ile güncelleme başarısız: $zone_file"
            fi
        else
            # Python yoksa sed ile basit güncelleme
            print_warning "Python3 bulunamadı, basit güncelleme yapılıyor..."
            
            # TTL güncelle
            sed -i 's/^\$TTL[[:space:]]*604800/\$TTL    3600/' "$zone_file"
            sed -i 's/^\$TTL[[:space:]]*10800/\$TTL    3600/' "$zone_file"
            
            # SOA REFRESH güncelle
            sed -i 's/^[[:space:]]*604800[[:space:]]*;[[:space:]]*Refresh/                          3600         ; Refresh/' "$zone_file"
            
            # SOA RETRY güncelle
            sed -i 's/^[[:space:]]*86400[[:space:]]*;[[:space:]]*Retry/                          600           ; Retry/' "$zone_file"
            
            # SOA EXPIRE güncelle
            sed -i 's/^[[:space:]]*2419200[[:space:]]*;[[:space:]]*Expire/                          604800        ; Expire/' "$zone_file"
            
            # SOA MINIMUM TTL güncelle
            sed -i 's/^[[:space:]]*604800[[:space:]]*)[[:space:]]*;[[:space:]]*Negative Cache TTL/                          3600 )        ; Minimum TTL/' "$zone_file"
            sed -i 's/^[[:space:]]*604800[[:space:]]*)[[:space:]]*;[[:space:]]*Minimum TTL/                          3600 )        ; Minimum TTL/' "$zone_file"
            
            # www kaydını kontrol et ve ekle
            if ! grep -qE "^www[[:space:]]+IN[[:space:]]+A" "$zone_file" 2>/dev/null; then
                # IP adresini al
                local server_ip=$(grep -E "^@[[:space:]]+IN[[:space:]]+A" "$zone_file" | head -1 | awk '{print $4}')
                if [ -n "$server_ip" ]; then
                    # NS kayıtlarından sonra www ekle
                    sed -i "/^@[[:space:]]*IN[[:space:]]*NS/a\\www     IN      A       $server_ip" "$zone_file"
                    print_success "www kaydı eklendi: www -> $server_ip"
                fi
            fi
            
            print_success "Zone dosyası güncellendi (basit yöntem): $zone_file"
        fi
    done
    
    # BIND9 servisini yeniden yükle
    print_info "BIND9 servisi yeniden yükleniyor..."
    systemctl reload named 2>/dev/null || systemctl restart named
    
    sleep 2
    
    if systemctl is-active --quiet named; then
        print_success "BIND9 servisi başarıyla yeniden yüklendi"
        print_success "Zone dosyaları RFC uyumlu hale getirildi!"
    else
        print_error "BIND9 servisi yeniden yüklenemedi!"
        print_info "Log kontrolü: journalctl -u named -n 50"
        return 1
    fi
}

# BIND9 yapılandırma hatasını düzelt
fix_bind9_config() {
    print_header "BIND9 Yapılandırma Hatası Düzeltme"
    
    local named_conf_options="/etc/bind/named.conf.options"
    
    if [ ! -f "$named_conf_options" ]; then
        print_error "named.conf.options dosyası bulunamadı!"
        return 1
    fi
    
    print_info "Duplicate kayıtlar temizleniyor..."
    
    # Yedekleme
    cp "$named_conf_options" "${named_conf_options}.backup.fix.$(date +%Y%m%d_%H%M%S)"
    
    if command -v python3 &>/dev/null; then
        python3 <<PYTHON_FIX
import re
import sys

config_file = '$named_conf_options'

try:
    with open(config_file, 'r') as f:
        content = f.read()
    
    # allow-recursion duplicate'lerini temizle (sadece ilkini tut)
    lines = content.split('\n')
    cleaned_lines = []
    seen_forwarders_block = False
    seen_recursion = False
    in_forwarders = False
    in_recursion = False
    brace_count = 0
    
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        
        # forwarders bloğunu tespit et
        if 'forwarders' in stripped and '{' in stripped:
            if seen_forwarders_block:
                # Duplicate forwarders bloğunu atla
                in_forwarders = True
                brace_count = stripped.count('{') - stripped.count('}')
                i += 1
                while i < len(lines) and (brace_count > 0 or '};' not in lines[i]):
                    brace_count += lines[i].count('{') - lines[i].count('}')
                    i += 1
                in_forwarders = False
                continue
            else:
                seen_forwarders_block = True
                in_forwarders = True
                brace_count = stripped.count('{') - stripped.count('}')
        
        # allow-recursion satırını tespit et
        if 'allow-recursion' in stripped:
            if seen_recursion:
                # Duplicate allow-recursion'ı atla
                i += 1
                continue
            else:
                seen_recursion = True
        
        # forwarders bloğu içindeysek brace sayısını takip et
        if in_forwarders:
            brace_count += line.count('{') - line.count('}')
            if brace_count <= 0 and '};' in line:
                in_forwarders = False
        
        cleaned_lines.append(line)
        i += 1
    
    # Dosyayı yaz
    with open(config_file, 'w') as f:
        f.write('\n'.join(cleaned_lines))
    
    print("Duplicate kayıtlar temizlendi")
    sys.exit(0)
except Exception as e:
    print(f"Hata: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYTHON_FIX
        
        if [ $? -eq 0 ]; then
            print_success "Yapılandırma dosyası düzeltildi"
            
            # Yapılandırmayı kontrol et
            if named-checkconf 2>/dev/null; then
                print_success "BIND9 yapılandırması geçerli"
                
                # Servisi yeniden başlat
                systemctl restart named
                sleep 2
                
                if systemctl is-active --quiet named; then
                    print_success "BIND9 servisi başarıyla başlatıldı"
                else
                    print_error "BIND9 servisi başlatılamadı!"
                    print_info "Log kontrolü: journalctl -u named -n 50"
                    return 1
                fi
            else
                print_error "Yapılandırma hala geçersiz!"
                print_info "Kontrol edin: named-checkconf"
                return 1
            fi
        else
            print_error "Python ile düzeltme başarısız!"
            return 1
        fi
    else
        print_error "Python3 bulunamadı! Lütfen manuel olarak düzeltin."
        print_info "Dosya: $named_conf_options"
        print_info "Hata: 'allow-recursion' duplicate tanımlanmış"
        return 1
    fi
}

install_dns_server() {
    print_header "DNS Sunucusu Kurulumu"
    
    echo -e "${CYAN}DNS Sunucusu Seçenekleri:${NC}"
    echo "1) BIND9 (Profesyonel, tam özellikli DNS sunucusu)"
    echo "2) dnsmasq (Hafif, küçük ağlar için)"
    echo "3) BIND9 Yapılandırma Hatası Düzelt"
    echo "4) Zone Dosyalarını RFC Uyumlu Hale Getir (SOA değerleri güncelle)"
    echo "5) Geri Dön"
    echo ""
    
    read -p "Seçiminiz (1-5) [1]: " dns_choice
    dns_choice=${dns_choice:-1}
    
    case $dns_choice in
        1)
            install_bind9
            ;;
        2)
            install_dnsmasq
            ;;
        3)
            fix_bind9_config
            read -p "Devam etmek için Enter'a basın..."
            ;;
        4)
            update_zone_soa_values
            read -p "Devam etmek için Enter'a basın..."
            ;;
        5)
            return 0
            ;;
        *)
            print_error "Geçersiz seçim!"
            return 1
            ;;
    esac
}

install_bind9() {
    print_header "BIND9 DNS Sunucusu Kurulumu"
    
    # BIND9 zaten kurulu mu?
    if command -v named &>/dev/null || systemctl list-units --type=service | grep -q "bind9\|named"; then
        print_warning "BIND9 zaten kurulu görünüyor"
        if ! ask_yes_no "Yeniden kurmak istiyor musunuz?"; then
            return 0
        fi
    fi
    
    print_info "BIND9 kuruluyor..."
    apt update
    apt install -y bind9 bind9utils bind9-doc dnsutils
    
    if [ $? -ne 0 ]; then
        print_error "BIND9 kurulumu başarısız!"
        return 1
    fi
    
    print_success "BIND9 başarıyla kuruldu"
    
    # BIND9 yapılandırması
    print_info "BIND9 yapılandırması yapılıyor..."
    
    # Ana domain bilgisi
    local domain_name=""
    local server_ip=""
    
    ask_input "DNS sunucusu için ana domain adını girin (örn: example.com)" domain_name
    
    # Sunucu IP'sini otomatik tespit et
    server_ip=$(hostname -I | awk '{print $1}')
    ask_input "DNS sunucusu IP adresi" server_ip "$server_ip"
    
    # Forward zone dosyası oluştur
    local forward_zone="/etc/bind/db.$domain_name"
    local reverse_zone=""
    
    # Reverse zone için IP'yi parse et
    local ip_octets=($(echo $server_ip | tr '.' ' '))
    if [ ${#ip_octets[@]} -eq 4 ]; then
        reverse_zone="/etc/bind/db.${ip_octets[2]}.${ip_octets[1]}.${ip_octets[0]}"
    fi
    
    # Forward zone dosyası oluştur (RFC2308 uyumlu SOA değerleri)
    print_info "Forward zone dosyası oluşturuluyor (RFC2308 uyumlu)..."
    cat > "$forward_zone" <<EOF
\$TTL    3600
@       IN      SOA     ns1.$domain_name. admin.$domain_name. (
                          $(date +%Y%m%d01)        ; Serial
                          3600          ; Refresh (1 saat - RFC önerisi)
                          600           ; Retry (10 dakika - RFC önerisi)
                          604800        ; Expire (7 gün)
                          3600 )        ; Minimum TTL (1 saat - RFC2308 önerisi)
;
@       IN      NS      ns1.$domain_name.
@       IN      NS      ns2.$domain_name.
@       IN      A       $server_ip
ns1     IN      A       $server_ip
ns2     IN      A       $server_ip
www     IN      A       $server_ip
mail    IN      A       $server_ip
@       IN      MX      10 mail.$domain_name.
EOF
    
    chmod 644 "$forward_zone"
    print_success "Forward zone dosyası oluşturuldu: $forward_zone"
    
    # Reverse zone dosyası oluştur (opsiyonel)
    if [ -n "$reverse_zone" ] && ask_yes_no "Reverse DNS zone dosyası oluşturulsun mu?"; then
        print_info "Reverse zone dosyası oluşturuluyor..."
        local reverse_network="${ip_octets[0]}.${ip_octets[1]}.${ip_octets[2]}.0"
        local reverse_ptr="${ip_octets[3]}.${ip_octets[2]}.${ip_octets[1]}.${ip_octets[0]}.in-addr.arpa"
        
        cat > "$reverse_zone" <<EOF
\$TTL    3600
@       IN      SOA     ns1.$domain_name. admin.$domain_name. (
                          $(date +%Y%m%d01)        ; Serial
                          3600          ; Refresh (1 saat - RFC önerisi)
                          600           ; Retry (10 dakika - RFC önerisi)
                          604800        ; Expire (7 gün)
                          3600 )        ; Minimum TTL (1 saat - RFC2308 önerisi)
;
@       IN      NS      ns1.$domain_name.
@       IN      NS      ns2.$domain_name.
${ip_octets[3]}      IN      PTR     ns1.$domain_name.
${ip_octets[3]}      IN      PTR     $domain_name.
${ip_octets[3]}      IN      PTR     www.$domain_name.
EOF
        
        chmod 644 "$reverse_zone"
        print_success "Reverse zone dosyası oluşturuldu: $reverse_zone"
    fi
    
    # named.conf.local yapılandırması
    print_info "BIND9 named.conf.local yapılandırması yapılıyor..."
    
    local named_conf_local="/etc/bind/named.conf.local"
    
    # Forward zone tanımı
    if ! grep -q "zone \"$domain_name\"" "$named_conf_local" 2>/dev/null; then
        cat >> "$named_conf_local" <<EOF

// Forward zone for $domain_name
zone "$domain_name" {
    type master;
    file "$forward_zone";
    allow-update { none; };
};
EOF
        print_success "Forward zone tanımı eklendi"
    fi
    
    # Reverse zone tanımı (varsa)
    if [ -n "$reverse_zone" ] && [ -f "$reverse_zone" ]; then
        local reverse_network="${ip_octets[0]}.${ip_octets[1]}.${ip_octets[2]}.0"
        if ! grep -q "zone \"${ip_octets[2]}.${ip_octets[1]}.${ip_octets[0]}.in-addr.arpa\"" "$named_conf_local" 2>/dev/null; then
            cat >> "$named_conf_local" <<EOF

// Reverse zone for $reverse_network
zone "${ip_octets[2]}.${ip_octets[1]}.${ip_octets[0]}.in-addr.arpa" {
    type master;
    file "$reverse_zone";
    allow-update { none; };
};
EOF
            print_success "Reverse zone tanımı eklendi"
        fi
    fi
    
    # named.conf.options yapılandırması
    print_info "BIND9 named.conf.options yapılandırması yapılıyor..."
    
    local named_conf_options="/etc/bind/named.conf.options"
    
    # Yedekleme
    cp "$named_conf_options" "${named_conf_options}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Önce duplicate kayıtları temizle
    print_info "Duplicate kayıtlar temizleniyor..."
    if command -v python3 &>/dev/null; then
        python3 <<PYTHON_CLEANUP
import re
import sys

config_file = '$named_conf_options'

try:
    with open(config_file, 'r') as f:
        lines = f.readlines()
    
    # allow-recursion ve forwarders duplicate'lerini temizle
    seen_forwarders = False
    seen_recursion = False
    cleaned_lines = []
    skip_forwarders = False
    skip_recursion = False
    brace_count = 0
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        # forwarders bloğunu tespit et
        if 'forwarders' in line and '{' in line:
            if seen_forwarders:
                skip_forwarders = True
                brace_count = line.count('{') - line.count('}')
                i += 1
                while i < len(lines) and (brace_count > 0 or '};' not in lines[i]):
                    brace_count += lines[i].count('{') - lines[i].count('}')
                    i += 1
                skip_forwarders = False
                continue
            else:
                seen_forwarders = True
        
        # allow-recursion satırını tespit et
        if 'allow-recursion' in line:
            if seen_recursion:
                # Bu satırı atla
                i += 1
                continue
            else:
                seen_recursion = True
        
        cleaned_lines.append(line)
        i += 1
    
    with open(config_file, 'w') as f:
        f.writelines(cleaned_lines)
    
    print("Duplicate kayıtlar temizlendi")
    sys.exit(0)
except Exception as e:
    print(f"Hata: {e}")
    sys.exit(1)
PYTHON_CLEANUP
        if [ $? -ne 0 ]; then
            print_warning "Python ile temizleme başarısız, manuel temizleme yapılıyor..."
        fi
    fi
    
    # Forwarders ve recursion ayarlarını kontrol et
    local has_forwarders=false
    local has_recursion=false
    
    if grep -qE "forwarders\s*{" "$named_conf_options" 2>/dev/null; then
        has_forwarders=true
    fi
    
    if grep -qE "allow-recursion\s*{" "$named_conf_options" 2>/dev/null; then
        has_recursion=true
    fi
    
    local local_network=$(echo $server_ip | cut -d'.' -f1-3)
    
    # Python ile güvenli ekleme
    if command -v python3 &>/dev/null; then
        python3 <<PYTHON_SCRIPT
import re
import sys

local_network = '$local_network'
config_file = '$named_conf_options'
has_forwarders = '$has_forwarders' == 'true'
has_recursion = '$has_recursion' == 'true'

try:
    with open(config_file, 'r') as f:
        content = f.read()
    
    # options bloğunu bul
    if 'options {' in content:
        # options bloğunun sonunu bul (}; den önce)
        pattern = r'(options \{)(.*?)(\};)'
        
        def add_missing_settings(match):
            options_start = match.group(1)
            options_content = match.group(2)
            options_end = match.group(3)
            
            additions = ""
            
            # Forwarders ekle (yoksa)
            if not has_forwarders:
                additions += '''
        forwarders {
                8.8.8.8;
                8.8.4.4;
                1.1.1.1;
                1.0.0.1;
        };'''
            
            # Recursion ekle (yoksa)
            if not has_recursion:
                additions += '''
        allow-recursion { localhost; ''' + local_network + '''.0/24; };'''
            
            return options_start + options_content + additions + options_end
        
        content = re.sub(pattern, add_missing_settings, content, flags=re.DOTALL)
        
        with open(config_file, 'w') as f:
            f.write(content)
        
        if not has_forwarders or not has_recursion:
            print("Eksik ayarlar eklendi")
        else:
            print("Tüm ayarlar mevcut")
        sys.exit(0)
    else:
        print("options bloğu bulunamadı")
        sys.exit(1)
except Exception as e:
    print(f"Hata: {e}")
    sys.exit(1)
PYTHON_SCRIPT
        if [ $? -eq 0 ]; then
            if [ "$has_forwarders" = false ]; then
                print_success "Forwarders eklendi (Google DNS, Cloudflare DNS)"
            fi
            if [ "$has_recursion" = false ]; then
                print_success "Recursion izni eklendi"
            fi
            if [ "$has_forwarders" = true ] && [ "$has_recursion" = true ]; then
                print_info "Forwarders ve recursion zaten yapılandırılmış"
            fi
        else
            # Python başarısız olursa basit awk ile ekleme
            print_warning "Python ile ekleme başarısız, basit yöntem deneniyor..."
            if [ "$has_forwarders" = false ] || [ "$has_recursion" = false ]; then
                # options bloğunun sonuna ekle
                awk -v local_net="$local_network" -v add_fwd="$has_forwarders" -v add_rec="$has_recursion" '
                /options \{/ { in_options=1; print; next }
                in_options && /^[[:space:]]*\};/ {
                    if (add_fwd == "false") {
                        print "        forwarders {"
                        print "                8.8.8.8;"
                        print "                8.8.4.4;"
                        print "                1.1.1.1;"
                        print "                1.0.0.1;"
                        print "        };"
                    }
                    if (add_rec == "false") {
                        print "        allow-recursion { localhost; " local_net ".0/24; };"
                    }
                    in_options=0
                }
                { print }
                ' "$named_conf_options" > "${named_conf_options}.tmp" && mv "${named_conf_options}.tmp" "$named_conf_options"
                
                if [ "$has_forwarders" = false ]; then
                    print_success "Forwarders eklendi"
                fi
                if [ "$has_recursion" = false ]; then
                    print_success "Recursion izni eklendi"
                fi
            fi
        fi
    else
        # Python yoksa basit awk ile ekleme
        if [ "$has_forwarders" = false ] || [ "$has_recursion" = false ]; then
            awk -v local_net="$local_network" -v add_fwd="$has_forwarders" -v add_rec="$has_recursion" '
            /options \{/ { in_options=1; print; next }
            in_options && /^[[:space:]]*\};/ {
                if (add_fwd == "false") {
                    print "        forwarders {"
                    print "                8.8.8.8;"
                    print "                8.8.4.4;"
                    print "                1.1.1.1;"
                    print "                1.0.0.1;"
                    print "        };"
                }
                if (add_rec == "false") {
                    print "        allow-recursion { localhost; " local_net ".0/24; };"
                }
                in_options=0
            }
            { print }
            ' "$named_conf_options" > "${named_conf_options}.tmp" && mv "${named_conf_options}.tmp" "$named_conf_options"
            
            if [ "$has_forwarders" = false ]; then
                print_success "Forwarders eklendi"
            fi
            if [ "$has_recursion" = false ]; then
                print_success "Recursion izni eklendi"
            fi
        else
            print_info "Forwarders ve recursion zaten yapılandırılmış"
        fi
    fi
    
    # Yapılandırma kontrolü
    print_info "BIND9 yapılandırması kontrol ediliyor..."
    if named-checkconf 2>/dev/null; then
        print_success "BIND9 yapılandırması geçerli"
    else
        print_warning "BIND9 yapılandırmasında hata olabilir, kontrol edin: named-checkconf"
    fi
    
    # Zone dosyalarını kontrol et
    if named-checkzone "$domain_name" "$forward_zone" 2>/dev/null; then
        print_success "Forward zone dosyası geçerli"
    else
        print_warning "Forward zone dosyasında hata olabilir: named-checkzone $domain_name $forward_zone"
    fi
    
    # BIND9 servisini başlat
    print_info "BIND9 servisi başlatılıyor..."
    systemctl enable named
    
    # Yapılandırma kontrolü (duplicate hataları için)
    if ! named-checkconf 2>/dev/null; then
        print_warning "BIND9 yapılandırmasında hata tespit edildi, düzeltiliyor..."
        if command -v python3 &>/dev/null; then
            python3 <<PYTHON_FIX
import re
import sys

config_file = '$named_conf_options'

try:
    with open(config_file, 'r') as f:
        content = f.read()
    
    # allow-recursion duplicate'lerini temizle
    lines = content.split('\n')
    cleaned_lines = []
    seen_recursion = False
    
    for line in lines:
        stripped = line.strip()
        
        # allow-recursion satırını tespit et
        if 'allow-recursion' in stripped:
            if seen_recursion:
                # Duplicate allow-recursion'ı atla
                continue
            else:
                seen_recursion = True
        
        cleaned_lines.append(line)
    
    # Dosyayı yaz
    with open(config_file, 'w') as f:
        f.write('\n'.join(cleaned_lines))
    
    print("Duplicate allow-recursion temizlendi")
    sys.exit(0)
except Exception as e:
    print(f"Hata: {e}")
    sys.exit(1)
PYTHON_FIX
            if [ $? -eq 0 ]; then
                print_success "Yapılandırma düzeltildi"
            fi
        fi
    fi
    
    systemctl restart named
    
    sleep 2
    
    if systemctl is-active --quiet named; then
        print_success "BIND9 servisi başarıyla başlatıldı"
    else
        print_error "BIND9 servisi başlatılamadı!"
        print_warning "Yapılandırma hatası olabilir, otomatik düzeltme deneniyor..."
        
        # Otomatik düzeltme dene
        if fix_bind9_config; then
            print_success "BIND9 servisi düzeltme sonrası başlatıldı"
        else
            print_error "BIND9 servisi başlatılamadı!"
            print_info "Log kontrolü: journalctl -u named -n 50"
            print_info "Yapılandırma kontrolü: named-checkconf"
            print_info "Manuel düzeltme için: DNS Sunucusu Kurulumu > BIND9 Yapılandırma Hatası Düzelt"
            return 1
        fi
    fi
    
    # Firewall kuralları
    if command -v ufw &>/dev/null; then
        if ask_yes_no "UFW firewall için DNS portlarını (53) açmak ister misiniz?"; then
            ufw allow 53/tcp
            ufw allow 53/udp
            print_success "DNS portları firewall'da açıldı"
        fi
    fi
    
    # Test
    print_info "DNS çözümleme testi yapılıyor..."
    if dig @127.0.0.1 $domain_name +short 2>/dev/null | grep -q "$server_ip"; then
        print_success "DNS çözümleme testi başarılı!"
    else
        print_warning "DNS çözümleme testi başarısız, yapılandırmayı kontrol edin"
    fi
    
    # Nginx'teki domain'leri otomatik ekle
    if command -v nginx &>/dev/null && [ -d "/etc/nginx/sites-available" ]; then
        local nginx_domains=($(get_nginx_domains))
        if [ ${#nginx_domains[@]} -gt 0 ]; then
            echo ""
            print_info "Nginx'te yapılandırılmış domain'ler tespit edildi:"
            for domain in "${nginx_domains[@]}"; do
                echo "  - $domain"
            done
            
            if ask_yes_no "Nginx'teki domain'leri DNS kayıtlarına otomatik eklemek ister misiniz?"; then
                add_nginx_domains_to_bind9 "$forward_zone" "$server_ip"
            fi
        fi
    fi
    
    print_header "BIND9 Kurulumu Tamamlandı!"
    echo -e "${GREEN}Domain:${NC} $domain_name"
    echo -e "${GREEN}DNS Server IP:${NC} $server_ip"
    echo -e "${GREEN}Forward Zone:${NC} $forward_zone"
    [ -f "$reverse_zone" ] && echo -e "${GREEN}Reverse Zone:${NC} $reverse_zone"
    echo ""
    echo -e "${CYAN}Yararlı Komutlar:${NC}"
    echo "• DNS test: ${GREEN}dig @$server_ip $domain_name${NC}"
    echo "• Reverse DNS test: ${GREEN}dig @$server_ip -x $server_ip${NC}"
    echo "• Zone dosyası düzenle: ${GREEN}nano $forward_zone${NC}"
    echo "• Yapılandırma kontrolü: ${GREEN}named-checkconf${NC}"
    echo "• Servis durumu: ${GREEN}systemctl status named${NC}"
    echo "• Servis yeniden başlat: ${GREEN}systemctl restart named${NC}"
    echo "• Log görüntüle: ${GREEN}journalctl -u named -f${NC}"
    echo ""
    echo -e "${YELLOW}NOT:${NC} Nginx'te yeni domain eklediğinizde, DNS kayıtlarını manuel olarak eklemeniz gerekebilir."
    echo "   Veya 'Nginx Domain'lerini DNS'e Ekle' seçeneğini kullanabilirsiniz."
}

install_dnsmasq() {
    print_header "dnsmasq DNS Sunucusu Kurulumu"
    
    # dnsmasq zaten kurulu mu?
    if command -v dnsmasq &>/dev/null || systemctl list-units --type=service | grep -q dnsmasq; then
        print_warning "dnsmasq zaten kurulu görünüyor"
        if ! ask_yes_no "Yeniden kurmak istiyor musunuz?"; then
            return 0
        fi
    fi
    
    print_info "dnsmasq kuruluyor..."
    apt update
    apt install -y dnsmasq
    
    if [ $? -ne 0 ]; then
        print_error "dnsmasq kurulumu başarısız!"
        return 1
    fi
    
    print_success "dnsmasq başarıyla kuruldu"
    
    # dnsmasq yapılandırması
    print_info "dnsmasq yapılandırması yapılıyor..."
    
    local dnsmasq_conf="/etc/dnsmasq.conf"
    
    # Yedekleme
    cp "$dnsmasq_conf" "${dnsmasq_conf}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Domain bilgisi
    local domain_name=""
    local server_ip=""
    
    ask_input "DNS sunucusu için ana domain adını girin (örn: example.com)" domain_name
    
    # Sunucu IP'sini otomatik tespit et
    server_ip=$(hostname -I | awk '{print $1}')
    ask_input "DNS sunucusu IP adresi" server_ip "$server_ip"
    
    # dnsmasq yapılandırması
    print_info "dnsmasq yapılandırma dosyası düzenleniyor..."
    
    # Temel ayarlar
    if ! grep -q "^domain=" "$dnsmasq_conf" 2>/dev/null; then
        echo "domain=$domain_name" >> "$dnsmasq_conf"
    fi
    
    if ! grep -q "^listen-address=" "$dnsmasq_conf" 2>/dev/null; then
        echo "listen-address=127.0.0.1,$server_ip" >> "$dnsmasq_conf"
    fi
    
    # DNS kayıtları için hosts dosyası kullan
    if ! grep -q "^addn-hosts=" "$dnsmasq_conf" 2>/dev/null; then
        echo "addn-hosts=/etc/dnsmasq.hosts" >> "$dnsmasq_conf"
    fi
    
    # DNS kayıtları dosyası oluştur
    local dnsmasq_hosts="/etc/dnsmasq.hosts"
    if [ ! -f "$dnsmasq_hosts" ]; then
        cat > "$dnsmasq_hosts" <<EOF
$server_ip    $domain_name
$server_ip    www.$domain_name
$server_ip    ns1.$domain_name
$server_ip    mail.$domain_name
EOF
        chmod 644 "$dnsmasq_hosts"
        print_success "DNS kayıtları dosyası oluşturuldu: $dnsmasq_hosts"
    fi
    
    # Yapılandırma kontrolü
    print_info "dnsmasq yapılandırması kontrol ediliyor..."
    if dnsmasq --test 2>/dev/null; then
        print_success "dnsmasq yapılandırması geçerli"
    else
        print_warning "dnsmasq yapılandırmasında hata olabilir"
    fi
    
    # dnsmasq servisini başlat
    print_info "dnsmasq servisi başlatılıyor..."
    systemctl enable dnsmasq
    systemctl restart dnsmasq
    
    sleep 2
    
    if systemctl is-active --quiet dnsmasq; then
        print_success "dnsmasq servisi başarıyla başlatıldı"
    else
        print_error "dnsmasq servisi başlatılamadı!"
        print_info "Log kontrolü: journalctl -u dnsmasq -n 50"
        return 1
    fi
    
    # Firewall kuralları
    if command -v ufw &>/dev/null; then
        if ask_yes_no "UFW firewall için DNS portlarını (53) açmak ister misiniz?"; then
            ufw allow 53/tcp
            ufw allow 53/udp
            print_success "DNS portları firewall'da açıldı"
        fi
    fi
    
    # Test
    print_info "DNS çözümleme testi yapılıyor..."
    if dig @127.0.0.1 $domain_name +short 2>/dev/null | grep -q "$server_ip"; then
        print_success "DNS çözümleme testi başarılı!"
    else
        print_warning "DNS çözümleme testi başarısız, yapılandırmayı kontrol edin"
    fi
    
    # Nginx'teki domain'leri otomatik ekle
    if command -v nginx &>/dev/null && [ -d "/etc/nginx/sites-available" ]; then
        local nginx_domains=($(get_nginx_domains))
        if [ ${#nginx_domains[@]} -gt 0 ]; then
            echo ""
            print_info "Nginx'te yapılandırılmış domain'ler tespit edildi:"
            for domain in "${nginx_domains[@]}"; do
                echo "  - $domain"
            done
            
            if ask_yes_no "Nginx'teki domain'leri DNS kayıtlarına otomatik eklemek ister misiniz?"; then
                add_nginx_domains_to_dnsmasq "$dnsmasq_hosts" "$server_ip"
            fi
        fi
    fi
    
    print_header "dnsmasq Kurulumu Tamamlandı!"
    echo -e "${GREEN}Domain:${NC} $domain_name"
    echo -e "${GREEN}DNS Server IP:${NC} $server_ip"
    echo -e "${GREEN}Hosts Dosyası:${NC} $dnsmasq_hosts"
    echo ""
    echo -e "${CYAN}Yararlı Komutlar:${NC}"
    echo "• DNS test: ${GREEN}dig @$server_ip $domain_name${NC}"
    echo "• Hosts dosyası düzenle: ${GREEN}nano $dnsmasq_hosts${NC}"
    echo "• Yapılandırma düzenle: ${GREEN}nano $dnsmasq_conf${NC}"
    echo "• Servis durumu: ${GREEN}systemctl status dnsmasq${NC}"
    echo "• Servis yeniden başlat: ${GREEN}systemctl restart dnsmasq${NC}"
    echo "• Log görüntüle: ${GREEN}journalctl -u dnsmasq -f${NC}"
    echo ""
    echo -e "${YELLOW}NOT:${NC} Nginx'te yeni domain eklediğinizde, DNS kayıtlarını manuel olarak eklemeniz gerekebilir."
    echo "   Veya 'Nginx Domain'lerini DNS'e Ekle' seçeneğini kullanabilirsiniz."
}

main_menu() {
    while true; do
        clear
        print_header "Ubuntu 24.04 Sunucu Yönetim Paneli"
        echo ""
        echo -e "${CYAN}Ana Menü:${NC}"
        echo "1) Yeni Domain Kurulumu"
        echo "2) Subdomain Ekle"
        echo "3) Domain Dizinini Değiştir"
        echo "4) Nginx Yapılandırmalarını PHP için Güncelle"
        echo "5) SSL Sertifikası Oluştur"
        echo "6) SSL Sertifikası Yenile"
        echo "7) Domain/Subdomain Listesi"
        echo "8) Domain/Subdomain Sil"
        echo "9) GitLab Kurulumu"
        echo "10) Tekil Servis Kurulumu"
        echo "11) Sunucu Bilgileri"
        echo "12) UFW Firewall Kurulumu"
        echo "13) Fail2ban Kurulumu"
        echo "14) Database Yedekleme"
        echo "15) Database Geri Yükleme"
        echo "16) Docker Kurulumu"
        echo "17) Log Dosyaları Görüntüle"
        echo "18) OpenVPN Server Kurulumu"
        echo "19) OpenVPN Web Yönetim Paneli"
        echo "20) OpenVPN İstemci Yönetimi"
        echo "21) Servis Optimizasyonu (Performans & Güvenlik)"
        echo "22) DNS Sunucusu Kurulumu"
        echo "23) Nginx Domain'lerini DNS'e Ekle"
        echo "24) PHP Eklentileri Hızlı Düzeltme (Composer için)"
        echo "25) PHP Çift Yükleme Sorunu Düzelt (dom, xml)"
        echo "26) Redis Bağlantı Sorunu Düzelt"
        echo "27) Çıkış"
        echo ""
        
        read -p "Seçiminizi yapın (1-27): " choice
        
        case $choice in
            1)
                run_new_installation
                read -p "Devam etmek için Enter'a basın..."
                ;;
            2)
                add_subdomain
                read -p "Devam etmek için Enter'a basın..."
                ;;
            3)
                change_directory
                read -p "Devam etmek için Enter'a basın..."
                ;;
            4)
                update_nginx_configs_for_php
                read -p "Devam etmek için Enter'a basın..."
                ;;
            5)
                create_ssl
                read -p "Devam etmek için Enter'a basın..."
                ;;
            6)
                renew_ssl
                read -p "Devam etmek için Enter'a basın..."
                ;;
            7)
                list_domains
                read -p "Devam etmek için Enter'a basın..."
                ;;
            8)
                delete_domain
                read -p "Devam etmek için Enter'a basın..."
                ;;
            9)
                install_gitlab
                read -p "Devam etmek için Enter'a basın..."
                ;;
            10)
                install_individual_service
                read -p "Devam etmek için Enter'a basın..."
                ;;
            11)
                show_server_info
                read -p "Devam etmek için Enter'a basın..."
                ;;
            12)
                install_firewall
                read -p "Devam etmek için Enter'a basın..."
                ;;
            13)
                install_fail2ban
                read -p "Devam etmek için Enter'a basın..."
                ;;
            14)
                backup_database
                read -p "Devam etmek için Enter'a basın..."
                ;;
            15)
                restore_database
                read -p "Devam etmek için Enter'a basın..."
                ;;
            16)
                install_docker
                read -p "Devam etmek için Enter'a basın..."
                ;;
            17)
                view_logs
                read -p "Devam etmek için Enter'a basın..."
                ;;
            18)
                install_openvpn
                read -p "Devam etmek için Enter'a basın..."
                ;;
            19)
                install_openvpn_web_admin
                read -p "Devam etmek için Enter'a basın..."
                ;;
            20)
                openvpn_management_menu
                ;;
            21)
                optimize_services_menu
                read -p "Devam etmek için Enter'a basın..."
                ;;
            22)
                install_dns_server
                read -p "Devam etmek için Enter'a basın..."
                ;;
            23)
                add_nginx_domains_to_dns
                read -p "Devam etmek için Enter'a basın..."
                ;;
            24)
                quick_fix_php_extensions
                read -p "Devam etmek için Enter'a basın..."
                ;;
            25)
                # PHP versiyonunu tespit et
                local menu_php_version=""
                if command -v php &> /dev/null; then
                    menu_php_version=$(php -v 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
                fi
                
                if [ -z "$menu_php_version" ]; then
                    # PHP-FPM'den tespit et
                    menu_php_version=$(systemctl list-units --type=service --all 2>/dev/null | grep "php.*-fpm" | head -1 | sed 's/.*php\([0-9.]*\)-fpm.*/\1/' | grep -E "^[0-9]+\.[0-9]+" || echo "")
                fi
                
                fix_php_duplicate_modules "$menu_php_version"
                read -p "Devam etmek için Enter'a basın..."
                ;;
            26)
                fix_redis_connection
                read -p "Devam etmek için Enter'a basın..."
                ;;
            27)
                print_success "Çıkılıyor..."
                exit 0
                ;;
            *)
                print_error "Geçersiz seçim. Lütfen 1-27 arasında bir sayı girin."
                sleep 2
                ;;
        esac
    done
}

run_new_installation() {
    print_header "Yeni Domain Kurulumu"
    
    # Değişkenleri sıfırla
    MYSQL_ROOT_PASSWORD=""
    ALAN_ADI=""
    EMAIL=""
    PHP_VERSION="8.3"
    FRAMEWORK="laravel"
    WEB_ROOT="public"
    APP_ENV="production"
    
    # Servis bayrakları
    INSTALL_NGINX=false
    INSTALL_PHP=false
    INSTALL_MYSQL=false
    INSTALL_NODEJS=false
    INSTALL_REDIS=false
    INSTALL_COMPOSER=false
    INSTALL_PHPMYADMIN=false
    INSTALL_SSL=false
    
    # Temel bilgiler
    print_header "Temel Yapılandırma"
    ask_input "Lütfen alan adınızı girin (örn: ornek.com)" ALAN_ADI
    ask_input "Lütfen e-posta adresinizi girin" EMAIL
    
    print_header "Framework Seçimi"
    select_framework
    
    read -p "Uygulama ortamı (production/development) [production]: " env_input
    APP_ENV="${env_input:-production}"
    
    # Servis seçimleri
    print_header "Servis Seçimleri"
    echo -e "${YELLOW}Hangi servisleri kurmak istediğinizi seçin:${NC}"
    
    if ask_yes_no "Nginx kurulsun mu?"; then
        INSTALL_NGINX=true
    fi
    
    if ask_yes_no "PHP kurulsun mu?"; then
        INSTALL_PHP=true
        echo "PHP sürüm seçin:"
        echo "1) PHP 8.3 (Önerilen)"
        echo "2) PHP 8.4 (Geliştirme)"
        read -p "Seçiminiz (1-2) [1]: " php_choice
        case $php_choice in
            2) PHP_VERSION="8.4";;
            *) PHP_VERSION="8.3";;
        esac
    fi
    
    if ask_yes_no "MySQL/MariaDB kurulsun mu?"; then
        INSTALL_MYSQL=true
        ask_password "MySQL root şifresini belirleyin" MYSQL_ROOT_PASSWORD
    fi
    
    if ask_yes_no "Node.js kurulsun mu?"; then
        INSTALL_NODEJS=true
    fi
    
    if ask_yes_no "Redis kurulsun mu?"; then
        INSTALL_REDIS=true
    fi
    
    if ask_yes_no "Composer kurulsun mu?"; then
        INSTALL_COMPOSER=true
    fi
    
    if ask_yes_no "phpMyAdmin kurulsun mu?"; then
        if [ "$INSTALL_MYSQL" = true ] && [ "$INSTALL_PHP" = true ]; then
            INSTALL_PHPMYADMIN=true
        else
            print_warning "phpMyAdmin için MySQL ve PHP kurulu olmalıdır."
            INSTALL_PHPMYADMIN=false
        fi
    fi
    
    if ask_yes_no "Let's Encrypt SSL sertifikası kurulsun mu?"; then
        if [ "$INSTALL_NGINX" = true ]; then
            INSTALL_SSL=true
        else
            print_warning "SSL için Nginx kurulu olmalıdır."
            INSTALL_SSL=false
        fi
    fi
    
    # Bağımlılık kontrolleri
    if [ "$INSTALL_PHPMYADMIN" = true ] && [ "$INSTALL_MYSQL" = false ]; then
        print_error "phpMyAdmin için MySQL kurulu olmalıdır."
        if ask_yes_no "MySQL kurulumunu etkinleştirmek ister misiniz?"; then
            INSTALL_MYSQL=true
            ask_password "MySQL root şifresini belirleyin" MYSQL_ROOT_PASSWORD
        else
            INSTALL_PHPMYADMIN=false
        fi
    fi
    
    # Kurulum özeti
    print_header "Kurulum Özeti"
    echo -e "${GREEN}Alan Adı:${NC} $ALAN_ADI"
    echo -e "${GREEN}Framework:${NC} $FRAMEWORK"
    echo -e "${GREEN}Ortam:${NC} $APP_ENV"
    echo ""
    
    echo -e "${CYAN}Seçilen Servisler:${NC}"
    [ "$INSTALL_NGINX" = true ] && echo "✓ Nginx"
    [ "$INSTALL_PHP" = true ] && echo "✓ PHP $PHP_VERSION"
    [ "$INSTALL_MYSQL" = true ] && echo "✓ MySQL/MariaDB"
    [ "$INSTALL_NODEJS" = true ] && echo "✓ Node.js"
    [ "$INSTALL_REDIS" = true ] && echo "✓ Redis"
    [ "$INSTALL_COMPOSER" = true ] && echo "✓ Composer"
    [ "$INSTALL_PHPMYADMIN" = true ] && echo "✓ phpMyAdmin"
    [ "$INSTALL_SSL" = true ] && echo "✓ SSL Sertifikası"
    
    echo ""
    
    if ! ask_yes_no "Kurulumu başlatmak istiyor musunuz?"; then
        print_error "Kurulum iptal edildi."
        return 1
    fi
    
    # KURULUM BAŞLANGICI
    print_header "Kurulum Başlatılıyor..."
    
    # Sistem güncellemeleri
    print_info "Sistem güncellemeleri yapılıyor..."
    apt update && apt upgrade -y
    apt install -y curl wget gnupg software-properties-common
    
    # Seçilen servisleri kur
    [ "$INSTALL_NGINX" = true ] && install_nginx
    [ "$INSTALL_PHP" = true ] && install_php $PHP_VERSION
    [ "$INSTALL_MYSQL" = true ] && install_mysql
    [ "$INSTALL_NODEJS" = true ] && install_nodejs
    [ "$INSTALL_REDIS" = true ] && install_redis
    [ "$INSTALL_COMPOSER" = true ] && install_composer
    
    # Nginx yapılandırması (Nginx kurulduysa)
    if [ "$INSTALL_NGINX" = true ]; then
        configure_nginx
        create_sample_files
    fi
    
    # phpMyAdmin kurulumu
    [ "$INSTALL_PHPMYADMIN" = true ] && install_phpmyadmin
    
    # SSL kurulumu
    [ "$INSTALL_SSL" = true ] && install_ssl
    
    # Servisleri başlat
    print_info "Servisler başlatılıyor..."
    [ "$INSTALL_NGINX" = true ] && systemctl restart nginx
    [ "$INSTALL_PHP" = true ] && systemctl restart php$PHP_VERSION-fpm
    [ "$INSTALL_MYSQL" = true ] && systemctl restart mariadb
    [ "$INSTALL_REDIS" = true ] && systemctl restart redis
    
    # SSL yenileme kontrolü
    [ "$INSTALL_SSL" = true ] && certbot renew --dry-run
    
    # KURULUM TAMAMLANDI
    print_header "KURULUM TAMAMLANDI"
    echo -e "${GREEN}✓ Alan Adı:${NC} $ALAN_ADI"
    echo -e "${GREEN}✓ Framework:${NC} $FRAMEWORK"
    echo -e "${GREEN}✓ Web Dizini:${NC} /var/www/$ALAN_ADI/$WEB_ROOT"
    
    echo ""
    echo -e "${CYAN}Kurulan Servisler:${NC}"
    [ "$INSTALL_NGINX" = true ] && echo "✓ Nginx - http://$ALAN_ADI"
    [ "$INSTALL_PHP" = true ] && echo "✓ PHP $PHP_VERSION - http://$ALAN_ADI/info.php"
    [ "$INSTALL_MYSQL" = true ] && echo "✓ MySQL - Port: 3306"
    [ "$INSTALL_NODEJS" = true ] && echo "✓ Node.js - $(node --version)"
    [ "$INSTALL_REDIS" = true ] && echo "✓ Redis - Port: 6379"
    [ "$INSTALL_COMPOSER" = true ] && echo "✓ Composer - $(composer --version 2>/dev/null | head -1)"
    [ "$INSTALL_PHPMYADMIN" = true ] && echo "✓ phpMyAdmin - http://$ALAN_ADI/phpmyadmin"
    [ "$INSTALL_SSL" = true ] && echo "✓ SSL - https://$ALAN_ADI"
    
    echo ""
    echo -e "${YELLOW}ÖNEMLİ NOTLAR:${NC}"
    [ "$INSTALL_PHP" = true ] && echo "• /var/www/$ALAN_ADI/info.php dosyasını üretimde silin"
    [ "$INSTALL_PHPMYADMIN" = true ] && echo "• phpMyAdmin erişimini güvence altına alın"
    [ "$INSTALL_SSL" = true ] && echo "• SSL sertifikası otomatik yenilenecek"
    
    print_success "Modüler kurulum başarıyla tamamlandı!"
}

# Ana program başlangıcı
# Ana menüyü başlat
main_menu

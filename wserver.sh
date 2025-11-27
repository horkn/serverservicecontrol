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
    apt install -y php$version-cli php$version-common \
        php$version-mysql php$version-zip php$version-gd php$version-mbstring \
        php$version-curl php$version-xml php$version-bcmath php$version-json \
        php$version-opcache php$version-intl
    
    # PHP-FPM'in düzgün kurulduğunu doğrula
    if ! systemctl list-unit-files | grep -q "php$version-fpm.service"; then
        print_error "PHP-FPM servisi bulunamadı! Kurulum başarısız olmuş olabilir."
        return 1
    fi
    
    print_success "PHP-FPM başarıyla kuruldu"
    
    # Imagick paketi (opsiyonel, hata olsa bile devam et)
    if apt-cache search php$version-imagick | grep -q "php$version-imagick"; then
        apt install -y php$version-imagick 2>/dev/null || print_warning "php$version-imagick kurulamadı (opsiyonel)"
    fi
    
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
    apt install -y mariadb-server
    
    # MySQL güvenlik yapılandırması
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD'; FLUSH PRIVILEGES;"
    
    mysql_secure_installation <<EOF
y
0
y
y
y
y
EOF
    
    print_success "MySQL kurulumu tamamlandı"
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
    apt install -y redis-server
    systemctl enable redis
    print_success "Redis kurulumu tamamlandı"
}

install_composer() {
    print_info "Composer kuruluyor..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    chmod +x /usr/local/bin/composer
    print_success "Composer kurulumu tamamlandı"
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
    
    # Kurulabilecek eklentileri listele
    echo -e "${CYAN}Kurulabilecek PHP Eklentileri:${NC}"
    echo "1) php$php_version-redis (Redis desteği)"
    echo "2) php$php_version-memcached (Memcached desteği)"
    echo "3) php$php_version-pcntl (Process Control)"
    echo "4) php$php_version-sqlite3 (SQLite3 desteği)"
    echo "5) php$php_version-pdo (PDO desteği)"
    echo "6) php$php_version-pdo-mysql (PDO MySQL desteği)"
    echo "7) php$php_version-imagick (ImageMagick desteği)"
    echo "8) php$php_version-xdebug (Xdebug - Debugging)"
    echo "9) php$php_version-mongodb (MongoDB desteği)"
    echo "10) Tümü (Yukarıdaki tüm eklentiler)"
    echo "11) Geri Dön"
    echo ""
    
    read -p "Kurulacak eklentiyi seçin (1-11): " ext_choice
    
    case $ext_choice in
        1)
            print_info "php$php_version-redis kuruluyor..."
            apt install -y php$php_version-redis
            ;;
        2)
            print_info "php$php_version-memcached kuruluyor..."
            apt install -y php$php_version-memcached
            ;;
        3)
            print_info "php$php_version-pcntl kuruluyor..."
            apt install -y php$php_version-pcntl
            ;;
        4)
            print_info "php$php_version-sqlite3 kuruluyor..."
            apt install -y php$php_version-sqlite3
            ;;
        5)
            print_info "php$php_version-pdo kuruluyor..."
            apt install -y php$php_version-pdo
            ;;
        6)
            print_info "php$php_version-pdo-mysql kuruluyor..."
            apt install -y php$php_version-pdo-mysql || apt install -y php$php_version-pdo_mysql
            ;;
        7)
            print_info "php$php_version-imagick kuruluyor..."
            apt install -y php$php_version-imagick
            ;;
        8)
            print_info "php$php_version-xdebug kuruluyor..."
            apt install -y php$php_version-xdebug
            ;;
        9)
            print_info "php$php_version-mongodb kuruluyor..."
            apt install -y php$php_version-mongodb
            ;;
        10)
            print_info "Tüm PHP eklentileri kuruluyor..."
            apt install -y php$php_version-redis php$php_version-memcached \
                php$php_version-pcntl php$php_version-sqlite3 php$php_version-pdo \
                php$php_version-imagick php$php_version-xdebug php$php_version-mongodb
            
            # PDO MySQL için alternatif isim denemesi
            apt install -y php$php_version-pdo-mysql 2>/dev/null || \
            apt install -y php$php_version-pdo_mysql 2>/dev/null || \
            print_warning "php$php_version-pdo-mysql kurulamadı"
            ;;
        11)
            return 0
            ;;
        *)
            print_error "Geçersiz seçim"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        # PHP-FPM servisini yeniden başlat (eklentilerin yüklenmesi için)
        if systemctl is-active --quiet php$php_version-fpm 2>/dev/null; then
            print_info "PHP-FPM servisi yeniden başlatılıyor (eklentilerin yüklenmesi için)..."
            systemctl restart php$php_version-fpm
            print_success "PHP eklentisi başarıyla kuruldu ve PHP-FPM yeniden başlatıldı"
        else
            print_success "PHP eklentisi başarıyla kuruldu"
            print_warning "PHP-FPM servisi çalışmıyor, eklentilerin aktif olması için servisi başlatın"
        fi
        
        # Kurulu eklentileri göster
        echo ""
        print_info "Kurulu PHP eklentileri:"
        php -m | grep -E "redis|memcached|pcntl|sqlite3|pdo|imagick|xdebug|mongodb" | sort
    else
        print_error "PHP eklentisi kurulumu başarısız oldu!"
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
            if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
                print_warning "MySQL/MariaDB zaten kurulu ve çalışıyor"
                if ask_yes_no "Yeniden kurmak istiyor musunuz? (UYARI: Veriler silinebilir!)"; then
                    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                        ask_password "MySQL root şifresini belirleyin" MYSQL_ROOT_PASSWORD
                    fi
                    install_mysql
                fi
            else
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
        echo "18) Servis Optimizasyonu (Performans & Güvenlik)"
        echo "19) Çıkış"
        echo ""
        
        read -p "Seçiminizi yapın (1-19): " choice
        
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
                optimize_services_menu
                read -p "Devam etmek için Enter'a basın..."
                ;;
            19)
                print_success "Çıkılıyor..."
                exit 0
                ;;
            *)
                print_error "Geçersiz seçim. Lütfen 1-19 arasında bir sayı girin."
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

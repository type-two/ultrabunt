# 🚀 UltraBunt - Ultimate Ubuntu Setup Script

*Because life's too short for manual installations and broken dependencies*

## 🎭 What is This Magnificent Beast?

UltraBunt is the **ULTIMATE** Ubuntu setup script that transforms your fresh Ubuntu installation into a powerhouse development machine faster than you can say "sudo apt update". 

Think of it as a whole bunch of blu-tac'd together bash scripts that:
- 🧙‍♂️ Install up to 560+ essential applications
- 🎪 Organized into 25+ magnificent categories  
- 🚀 Handles APT, Snap, Flatpak, and custom installations
- 🎨 Makes your terminal look absolutely gorgeous
- 🔒 Set up a native LAMP wordpress site that works without all the ball-ache
- ☕ Saves you pissfarting around in terminal for hours every frikkin time you install it

## 🎪 THE MAGNIFICENT BUNTAGE CATEGORIES 🎪

### 🔧 Core Utilities - The Foundation of Greatness
Essential command-line tools that every developer needs:

**Git** - Version control system [APT]  
**Curl** - Command line tool for transferring data [APT]  
**Wget** - Network downloader [APT]  
**Build Essential** - Compilation tools (gcc, make, etc) [APT]  
**Tree** - Directory structure visualizer [APT]  
**Ncdu** - NCurses disk usage analyzer [APT]  
**Jq** - JSON processor [APT]  
**Tmux** - Terminal multiplexer [APT]  
**Fzf** - Fuzzy finder [APT]  
**Ripgrep** - Fast text search [APT]  
**Bat** - Cat with syntax highlighting [APT]  
**Eza** - Modern ls replacement [APT]  
**Tldr** - Simplified man pages [APT]  

### 💻 Development Tools - Code Like a Pro
Programming languages, frameworks, and development utilities:

**Git** - Version control [APT]  
**GitHub CLI** - GitHub command line [APT]  
**GitLab CLI** - GitLab command line [SCRIPT]  
**Gitea** - Self-hosted Git service [SCRIPT]  
**Forgejo** - Self-hosted Git service [SCRIPT]  
**Node.js** - JavaScript runtime [APT]  
**NPM** - Node package manager [APT]  
**Yarn** - Package manager [APT]  
**PNPM** - Fast package manager [SCRIPT]  
**Bun** - JavaScript runtime [SCRIPT]  
**Deno** - Secure JavaScript runtime [SCRIPT]  
**Python3** - Python interpreter [APT]  
**Python3-pip** - Python package manager [APT]  
**Pipx** - Python app installer [APT]  
**Poetry** - Python dependency manager [SCRIPT]  
**Pyenv** - Python version manager [SCRIPT]  
**Go** - Go programming language [APT]  
**Rust** - Rust programming language [SCRIPT]  
**Cargo** - Rust package manager [SCRIPT]  
**Java (OpenJDK)** - Java development kit [APT]  
**Maven** - Java build tool [APT]  
**Gradle** - Build automation [APT]  
**PHP** - PHP interpreter [APT]  
**Composer** - PHP dependency manager [APT]  
**Ruby** - Ruby interpreter [APT]  
**RubyGems** - Ruby package manager [APT]  
**Bundler** - Ruby dependency manager [APT]  
**C/C++ Build Tools** - GCC compiler [APT]  
**Make** - Build automation [APT]  
**CMake** - Cross-platform build system [APT]  
**Ninja** - Small build system [APT]  
**Meson** - Build system [APT]  
**Bazel** - Build tool [SCRIPT]  
**Docker** - Containerization [SCRIPT]  
**Docker Compose** - Multi-container apps [APT]  
**Podman** - Daemonless containers [APT]  
**Kubernetes CLI (kubectl)** - Kubernetes control [SCRIPT]  
**Helm** - Kubernetes package manager [SCRIPT]  
**Terraform** - Infrastructure as code [SCRIPT]  
**Ansible** - Configuration management [APT]  
**Vagrant** - Development environments [SCRIPT]  
**VirtualBox** - Virtualization [SCRIPT]  
**QEMU** - Machine emulator [APT]  
**Neovim** - Modern Vim editor [APT]  
**MkDocs** - Documentation generator [SCRIPT]  
**Insomnia** - API testing tool [SCRIPT]  
**Zed** - High-performance code editor [SCRIPT]  
**Postman** - API development platform [SCRIPT]  
**Bruno** - Open-source API client [SCRIPT]  
**Bruno (Snap)** - Bruno via Snap [SNAP]  
**Bruno (Flatpak)** - Bruno via Flatpak [FLATPAK]  
**Yaak** - API testing tool [SCRIPT]  
**N8N** - Workflow automation [SCRIPT]  
**HTTPie** - Modern HTTP client [APT]  
**Lazygit** - Simple terminal UI for git [SCRIPT]  
**Legit** - Generate Open Source licences [CUSTOM]  
**Mklicense** - Create a custom LICENSE file painlessly [CUSTOM]  
**Rebound** - Fetch Stack Overflow results on compiler error [CUSTOM]  
**Foy** - Lightweight general purpose task runner/build tool [CUSTOM]  
**Just** - A handy way to save and run project-specific commands [CUSTOM]  
**Bcal** - Byte CALculator for storage conversions and calculations [CUSTOM]  
**Bitwise** - Terminal based bitwise calculator [CUSTOM]  
**Cgasm** - x86 assembly documentation [CUSTOM]  
**Grex** - Generate regular expressions from user-provided test cases [CUSTOM]  
**Iola** - Socket client with REST API [CUSTOM]  
**Add-gitignore** - Interactively generate a .gitignore for your project [CUSTOM]  
**Is-up-cli** - Check if a domain is up [CUSTOM]  
**Reachable** - Check if a domain is up [CUSTOM]  
**Diff2html-cli** - Create pretty HTML from diffs [CUSTOM]  
**Caniuse-cmd** - Search caniuse.com about browser support [CUSTOM]  
**Strip-css-comments-cli** - Strip comments from CSS [CUSTOM]  
**Viewport-list-cli** - Return a list of devices and their viewports [CUSTOM]  
**Surge** - Publish static websites for free [CUSTOM]  
**Localtunnel** - Expose localhost to the world for easy testing [CUSTOM]  
**Tunnelmole** - Connect to local servers from anywhere [CUSTOM]  
**Ngrok** - Secure introspectable tunnels to localhost [CUSTOM]  
**Mobicon-cli** - Mobile app icon generator [CUSTOM]  
**Mobisplash-cli** - Mobile app splash screen generator [CUSTOM]  
**Deviceframe** - Put device frames around your mobile/web/progressive app screenshots [CUSTOM]  
**Htconvert** - Convert .htaccess redirects to nginx.conf redirects [CUSTOM]  
**Saws** - A supercharged AWS command line interface [CUSTOM]  
**S3cmd** - Command line tool for managing Amazon S3 and CloudFront [CUSTOM]  
**Pm2** - Advanced, production process manager for Node.js [CUSTOM]  
**Ops** - Build and run nanos unikernels [CUSTOM]  
**Flog** - A fake log generator for common log formats [CUSTOM]  
**Pingme** - Send messages/alerts to multiple messaging platforms [CUSTOM]  
**Ipfs-deploy** - Deploy static websites to IPFS [CUSTOM]  
**Discharge** - Deploy static websites to Amazon S3 [CUSTOM]  
**Updatecli** - A declarative dependency management tool [CUSTOM]  
**Telert** - Multi-channel alerts for long-running commands [CUSTOM]  
**Logdy** - Supercharge terminal logs with web UI [CUSTOM]  
**S5cmd** - Blazing fast S3 and local filesystem execution tool [CUSTOM]  
**Release-it** - Automate releases for Git repositories and/or npm packages [CUSTOM]  
**Clog** - A conventional changelog for the rest of us [CUSTOM]  
**Np** - A better npm publish [CUSTOM]  
**Release** - Generate changelogs with a single command [CUSTOM]  
**Semantic-release** - Fully automated version management and package publishing [CUSTOM]  
**Npm-name-cli** - Check whether a package name is available on npm [CUSTOM]  
**Npm-user-cli** - Get user info of a npm user [CUSTOM]  
**Npm-home** - Open the npm page of the package in the current directory [CUSTOM]  
**Pkg-dir-cli** - Find the root directory of a npm package [CUSTOM]  
**Npm-check-updates** - Find newer versions of package dependencies [CUSTOM]  
**Updates** - Flexible npm dependency update tool [CUSTOM]  
**Wipe-modules** - Remove node_modules of inactive projects [CUSTOM]  
**Doctoc** - Generates table of contents for markdown files [CUSTOM]  
**Grip** - Preview markdown files as GitHub would render them [CUSTOM]  
**Mdv** - Styled terminal markdown viewer [CUSTOM]  
**Gtree** - Use markdown to generate directory trees [CUSTOM]  
**Cmdchallenge** - Presents small shell challenge with user submitted solutions [CUSTOM]  
**Explainshell** - Type a snippet to see the help text for each argument [CUSTOM]  
**Howdoi** - Instant coding answers [CUSTOM]  
**How2** - Node.js implementation of howdoi [CUSTOM]  
**Wat** - Instant, central, community-built docs [CUSTOM]  
**Teachcode** - Guide for the earliest lessons of coding [CUSTOM]  
**Navi** - Interactive cheatsheet tool [CUSTOM]  
**Jp** - JSON parser [CUSTOM]  
**Fx** - Command-line JSON viewer [CUSTOM]  
**Vj** - Makes JSON human readable [CUSTOM]  
**Underscore-cli** - Utility-belt for hacking JSON and Javascript [CUSTOM]  
**Strip-json-comments-cli** - Strip comments from JSON [CUSTOM]  
**Groq** - JSON processor with queries and projections [CUSTOM]  
**Gron** - Make JSON greppable [CUSTOM]  
**Config-file-validator** - Validate configuration files [CUSTOM]  
**Dyff** - YAML diff tool [CUSTOM]  
**Parse-columns-cli** - Parse text columns to JSON [CUSTOM]  
**Q** - Execution of SQL-like queries on CSV/TSV/tabular text file [CUSTOM]  
**Scc** - Count lines of code, blank lines, comment lines, and physical lines [CUSTOM]  
**Release-it** - Automate releases for Git repositories and/or npm packages [CUSTOM]  
**Clog** - A conventional changelog for the rest of us [CUSTOM]  
**Np** - A better npm publish [CUSTOM]  
**Release** - Generate changelogs with a single command [CUSTOM]  
**Semantic-release** - Fully automated version management and package publishing [CUSTOM]  
**Npm-name-cli** - Check whether a package name is available on npm [CUSTOM]  
**Npm-user-cli** - Get user info of a npm user [CUSTOM]  
**Npm-home** - Open the npm page of the package in the current directory [CUSTOM]  
**Pkg-dir-cli** - Find the root directory of a npm package [CUSTOM]  
**Npm-check-updates** - Find newer versions of package dependencies [CUSTOM]  
**Updates** - Flexible npm dependency update tool [CUSTOM]  
**Wipe-modules** - Remove node_modules of inactive projects [CUSTOM]  

### 🐳 Containers & Orchestration - Virtualization Mastery
Container and orchestration tools:

**Docker** - Container platform [SCRIPT]  
**Docker Compose** - Multi-container applications [APT]  
**Podman** - Daemonless containers [APT]  
**Minikube** - Local Kubernetes [SCRIPT]  
**Kind** - Kubernetes in Docker [SCRIPT]  
**Ctop** - Container monitoring [SCRIPT]  
**Lazydocker** - Docker terminal UI [SCRIPT]  
**K9s** - Kubernetes CLI To Manage Your Clusters In Style [CUSTOM]  
**Lstags** - Synchronize images across registries [CUSTOM]  
**Dockly** - Interactively manage containers [CUSTOM]  
**Docker-pushrm** - Push a readme to container registries [CUSTOM]  

### 🌐 Web Stack - The Internet's Backbone
Web development and server tools:

**Nginx** - High-performance web server [APT]  
**Apache2** - The classic web server [APT]  
**PHP-FPM** - FastCGI Process Manager [APT]  
**LibApache2-mod-php** - Apache PHP module [APT]  
**PHP-MySQL** - PHP MySQL extension [APT]  
**PHP-Curl** - PHP cURL extension [APT]  
**PHP-GD** - PHP graphics library [APT]  
**PHP-XML** - PHP XML extension [APT]  
**PHP-Mbstring** - PHP multibyte string [APT]  
**PHP-Zip** - PHP ZIP extension [APT]  
**MariaDB** - MySQL-compatible database [APT]  
**Certbot** - SSL certificate management [APT]  
**Python3-certbot-nginx** - Certbot Nginx plugin [APT]  
**Python3-certbot-apache** - Certbot Apache plugin [APT]  
**Redis** - In-memory data store [APT]  
**Caddy** - Modern web server [SCRIPT]  
**PM2** - Node.js process manager [SCRIPT]  
**Ngrok** - Secure tunneling [SCRIPT]  
**MailHog** - Email testing tool [SCRIPT]  
**AdminMongo** - MongoDB admin interface [SCRIPT]  
**SQLiteStudio** - SQLite database manager [SCRIPT]  
**LocalWP** - Local WordPress development [SCRIPT]  
**DevKinsta** - Local WordPress development [SCRIPT]  
**Lando** - Local development environment [SCRIPT]  
**DDEV** - Docker-based development [SCRIPT]  
**XAMPP** - Cross-platform web server [SCRIPT]  

### 🐚 Shells & Customization - Terminal Beauty
Shell environments and customization:

**Zsh** - Z shell [APT]  
**Fonts-powerline** - Powerline fonts [APT]  
**Oh-my-zsh** - Zsh framework [SCRIPT]  
**Starship** - Cross-shell prompt [SCRIPT]  
**Zoxide** - Smart directory jumper [SCRIPT]  
**Zsh-autosuggestions** - Command suggestions [APT]  

### 🎪 Fun & Entertainment - Hacker Playground
Terminal entertainment and fun tools:

**Cmatrix** - Matrix-style terminal [APT]  
**Hollywood** - Hacker terminal simulator [APT]  
**SL** - Steam locomotive animation [APT]  
**Lolcat** - Rainbow text output [APT]  
**Toilet** - ASCII art text [APT]  
**Figlet** - ASCII art text generator [APT]  
**Boxes** - Text box drawing [APT]  
**Asciiquarium** - ASCII aquarium [APT]  
**Cowsay** - Talking cow [APT]  
**Fortune** - Random quotes [APT]  
**Newsboat** - RSS/Atom feed reader for text terminals [APT]  
**Mal-cli** - MyAnimeList command line client [CUSTOM]  
**Moviemon** - Everything about your movies within the command line [CUSTOM]  
**Movie** - Get movie info or compare movies in terminal [CUSTOM]  
**Pokete** - A terminal based Pokemon like game [CUSTOM]  

### ✏️ Editors & IDEs - Code Creation Stations
Text editors and integrated development environments:

**Visual Studio Code** - Microsoft's editor [SCRIPT]  
**Sublime Text** - Sophisticated text editor [SCRIPT]  
**VSCode (Snap)** - VS Code via Snap [SNAP]  
**VSCode (Flatpak)** - VS Code via Flatpak [FLATPAK]  
**Vim** - Vi IMproved - enhanced vi editor [APT]  
**Emacs** - GNU Emacs editor [APT]  
**Kakoune** - Modal editor inspired by vim [APT]  
**O** - Configuration-free text editor and IDE [CUSTOM]  
**Helix** - A post-modern modal text editor [CUSTOM]  

### 🌍 Web Browsers - Windows to the Web
Web browsers for every need:

**Brave** - Privacy-focused browser [SCRIPT]  
**Firefox** - Mozilla's browser [APT]  
**Chromium** - Open-source Chrome [APT]  
**Firefox (Snap)** - Firefox via Snap [SNAP]  
**Firefox (Flatpak)** - Firefox via Flatpak [FLATPAK]  
**Chromium (Snap)** - Chromium via Snap [SNAP]  
**Chromium (Flatpak)** - Chromium via Flatpak [FLATPAK]  

### 📊 System Monitoring - Keep Watch
System monitoring and analysis tools:

**Htop** - Interactive process viewer [APT]  
**Btop** - Modern system monitor [APT]  
**Glances** - System monitoring [APT]  
**Iotop** - I/O monitoring [APT]  
**Bpytop** - Python-based system monitor [APT]  
**Bashtop** - Bash-based system monitor [APT]  
**Bottom** - Cross-platform system monitor [APT]  
**Gotop** - Terminal-based activity monitor [APT]  
**Vtop** - Visual top [APT]  
**Zenith** - System monitor [APT]  
**Nmon** - System performance monitor [APT]  
**Atop** - Advanced system monitor [APT]  
**Iostat** - I/O statistics [APT]  
**Vmstat** - Virtual memory statistics [APT]  
**Free** - Memory usage display [APT]  
**Lsof** - List open files [APT]  
**Sar** - System activity reporter [APT]  
**Mpstat** - Multiprocessor statistics [APT]  
**Pidstat** - Process statistics [APT]  
**Nvtop** - NVIDIA GPU monitor [APT]  
**Radeontop** - AMD GPU monitor [APT]  
**Ps** - Process status [APT]  
**Qmasa** - System monitor [APT]  
**Gtop** - System monitoring dashboard [APT]  
**Procs** - Modern ps replacement [APT]  

### 🌐 Network Monitoring - Network Ninja Tools
Network analysis and monitoring:

**Nethogs** - Network usage by process [APT]  
**Iftop** - Network bandwidth monitor [APT]  
**Nload** - Network load monitor [APT]  
**Bmon** - Bandwidth monitor [APT]  
**Iptraf-ng** - Network statistics [APT]  
**SS** - Socket statistics [APT]  
**Bandwhich** - Network utilization [APT]  
**Nmap** - Network discovery and security auditing [APT]  
**Dog** - DNS lookup tool [SCRIPT]  
**Speedtest-net** - Test internet connection speed using speedtest.net [CUSTOM]  
**Speed-test** - speedtest-net wrapper with different UI [CUSTOM]  
**Speedtest-cli** - Test internet bandwidth using speedtest.net [APT]  

### ⚡ Performance Tools - Speed Demons
Performance analysis and benchmarking:

**Tokei** - Code statistics [APT]  
**Hyperfine** - Command-line benchmarking [APT]  

### 🛠️ Utilities - Essential Command-Line Tools
Handy utilities for daily tasks:

**PV** - Pipe viewer with progress [APT]  
**Duf** - Disk usage analyzer [APT]  
**Dust** - Directory size analyzer [APT]  
**Fd-find** - Fast file finder [APT]  
**Exa** - Modern ls replacement [APT]  
**Batcat** - Cat with syntax highlighting [APT]  
**Micro** - Modern terminal editor [APT]  
**Atool** - Archive tool wrapper [APT]  
**MirrorSelect** - Tool to select the fastest Ubuntu mirror for optimal download speeds [SNAP]  
**Apt-mirror** - Create and maintain local Ubuntu mirror repositories for offline installations [APT]  
**Fastfetch** - System information tool [APT]  
**Battery-level-cli** - Get current battery level [CUSTOM]  
**Brightness-cli** - Change screen brightness [CUSTOM]  
**Clipboard** - Cut, copy, and paste anything, anywhere [CUSTOM]  
**Yank** - Yank terminal output to clipboard [CUSTOM]  
**Screensaver** - Start the screensaver [CUSTOM]  
**Google-font-installer** - Download and install Google Web Fonts [CUSTOM]  
**Tiptop** - System monitor [CUSTOM]  
**Gzip-size-cli** - Get the gzipped size of a file [CUSTOM]  
**Mdlt** - Do quick math right from the command line [CUSTOM]  
**Qalculate** - Calculate non-trivial math expressions [APT]  
**Visidata** - Spreadsheet multitool for data discovery and arrangement [CUSTOM]  
**Wttr-in** - Weather information from wttr.in [CUSTOM]  
**Wego** - Weather app for the terminal [CUSTOM]  
**Weather-cli** - Get weather information from command line [CUSTOM]  
**S** - Open a web search in your terminal [CUSTOM]  
**Hget** - Render websites in plain text from your terminal [CUSTOM]  
**Mapscii** - Terminal Map Viewer [CUSTOM]  
**Nasa-cli** - Download NASA Picture of the Day [CUSTOM]  
**Getnews-tech** - Fetch news headlines from various news outlets [CUSTOM]  
**Trino** - Translation of words and phrases [CUSTOM]  
**Translate-shell** - Google Translate interface [APT]  
**Vifm** - VI influenced file manager [APT]  
**Nnn** - File browser and disk usage analyzer [APT]  
**Lf** - Fast, extensively customizable file manager [CUSTOM]  
**Clifm** - The command line file manager [CUSTOM]  
**Far2l** - Orthodox file manager [CUSTOM]  
**Yazi** - Blazing fast file manager [CUSTOM]  
**Xplr** - A hackable, minimal, fast TUI file explorer [CUSTOM]  
**Trash-cli** - Move files and directories to the trash [APT]  
**Empty-trash-cli** - Empty the trash [CUSTOM]  
**Del-cli** - Delete files and folders [CUSTOM]  
**Cpy-cli** - Copies files [CUSTOM]  
**Rename-cli** - Rename files quickly [CUSTOM]  
**Renameutils** - Mass renaming in your editor [APT]  
**Diskonaut** - Disk space navigator [CUSTOM]  
**Dua-cli** - Disk usage analyzer [CUSTOM]  
**Dutree** - A tool to analyze file system usage written in Rust [CUSTOM]  
**Chokidar-cli** - CLI to watch file system changes [CUSTOM]  
**File-type-cli** - Detect the file type of a file or stdin [CUSTOM]  
**Unix-permissions** - Swiss Army knife for Unix permissions [CUSTOM]  
**Transmission-cli** - Torrent client for your command line [APT]  
**Webtorrent-cli** - Streaming torrent client [CUSTOM]  
**Entr** - Run an arbitrary command when files change [APT]  
**Organize-cli** - Organize your files automatically [CUSTOM]  
**Organize-rt** - organize-cli in Rust with more customization [CUSTOM]  
**Recoverpy** - Recover overwritten or deleted files [CUSTOM]  
**F2** - A cross-platform tool for fast, safe, and flexible batch renaming [CUSTOM]  
**Ffsend** - Quick file share [CUSTOM]  
**Share-cli** - Share files with your local network [CUSTOM]  
**Google-drive-upload** - Upload/sync with Google Drive [CUSTOM]  
**Gdrive-downloader** - Download files/folders from Google Drive [CUSTOM]  
**Portal** - Send files between computers [CUSTOM]  
**Shbin** - Turn a Github repo into a pastebin [CUSTOM]  
**Sharing** - Send and receive files on your mobile device [CUSTOM]  
**Ncp** - Transfer files and folders, to and from NFS servers [CUSTOM]  
**Alder** - Minimal tree with colors [CUSTOM]  
**Tre** - tree with git awareness, editor aliasing, and more [CUSTOM]  
**Plocate** - Fast file locator [APT]  
**Silversearcher-ag** - Fast text search [APT]  
**YQ** - YAML processor [APT]  
**Delta** - Git diff viewer [APT]  
**Ranger** - Console file manager [APT]  
**MC** - Midnight Commander file manager [APT]  
**AG** - The Silver Searcher [APT]  
**Thefuck** - Command correction tool [PIP]  
**Glow** - Markdown renderer [SCRIPT]  
**Cheat** - Interactive cheatsheets [SCRIPT]  
**Broot** - Tree view file manager [SCRIPT]  

### 🗄️ Database Management - Data Wranglers
Database servers and management tools:

**PHPMyAdmin** - MySQL web interface [SCRIPT]  
**Adminer** - Web database management [SCRIPT]  
**DBeaver CE** - Universal database tool [SCRIPT]  
**DBeaver CE (Flatpak)** - DBeaver via Flatpak [FLATPAK]  
**MySQL Workbench Community** - MySQL GUI [SCRIPT]  
**PgAdmin4** - PostgreSQL GUI [SCRIPT]  
**SQLiteBrowser** - SQLite database browser [APT]  
**MyCLI** - MySQL command-line client [APT]  
**PgCLI** - PostgreSQL command-line client [APT]  
**LiteCLI** - SQLite command-line client [APT]  
**Redis-tools** - Redis command-line tools [APT]  
**MongoDB Compass** - MongoDB GUI [SCRIPT]  
**Postbird** - PostgreSQL GUI client [SCRIPT]  
**Beekeeper Studio** - Modern database client [SCRIPT]  
**TablePlus** - Database management tool [SCRIPT]  
**Sqlline** - Shell for issuing SQL via JDBC [CUSTOM]  
**Iredis** - Redis client with autocompletion and syntax highlighting [CUSTOM]  
**Usql** - Universal SQL client with autocompletion [CUSTOM]  

### 🔒 Security Tools - Digital Guardians
Security and penetration testing tools:

**UFW** - Uncomplicated firewall [APT]  
**Fail2ban** - Intrusion prevention [APT]  
**Pass** - Password manager [APT]  
**Gopass** - Fully-featured password manager [CUSTOM]  
**Xiringuito** - SSH-based VPN [CUSTOM]  
**Hasha-cli** - Get the hash of text or stdin [CUSTOM]  
**Ots** - Share secrets with others via a one-time URL [CUSTOM]  
**Stegcloak** - Hide secrets with invisible characters in plain text [CUSTOM]  

### ⚙️ System Tools - System Mastery
System administration and management:

**Flatpak** - Universal package system [APT]  
**Samba** - File sharing protocol [APT]  
**NFS-kernel-server** - Network file system [APT]  
**Dysk** - Disk usage analyzer [SCRIPT]  
**LVM2** - Logical volume manager [APT]  
**SnapRAID** - Snapshot RAID [SCRIPT]  
**Greyhole** - Storage pooling [SCRIPT]  
**MergerFS** - Union filesystem [SCRIPT]  

### 💬 Communication - Stay Connected
Communication and messaging applications:

**LocalSend** - Local file sharing [SCRIPT]  
**Discord** - Gaming communication [SCRIPT]  
**Telegram Desktop** - Secure messaging [APT]  
**Zoom** - Video conferencing [SCRIPT]  
**Discord (DEB)** - Discord via DEB package [DEB]  
**Discord (Flatpak)** - Discord via Flatpak [FLATPAK]  
**Weechat** - Fast, light and extensible chat client [APT]  
**Irssi** - Terminal based IRC client [APT]  
**Kirc** - A tiny IRC client written in POSIX C99 [CUSTOM]  

### 🎵 Audio & Music - Sound Engineering
Audio editing and music production:

**Spotify** - Music streaming [SCRIPT]  
**Audacity** - Audio editor [APT]  
**Ardour** - Digital audio workstation [APT]  
**LMMS** - Music production [APT]  
**Mixxx** - DJ software [APT]  
**Audacity (Snap)** - Audacity via Snap [SNAP]  
**Audacity (Flatpak)** - Audacity via Flatpak [FLATPAK]  
**Cmus** - Small, fast and powerful console music player [APT]  
**Pianobar** - Console-based Pandora client [APT]  
**Somafm-cli** - Listen to SomaFM in your terminal [CUSTOM]  
**Mpd** - Music Player Daemon [APT]  
**Ncmpcpp** - NCurses Music Player Client (Plus Plus) [APT]  
**Moc** - Console audio player for Linux/UNIX [APT]  
**Musikcube** - Cross-platform terminal-based music player [CUSTOM]  
**Beets** - Music library manager and MusicBrainz tagger [APT]  
**Spotify-tui** - Spotify for the terminal written in Rust [CUSTOM]  
**Swaglyrics-for-spotify** - Spotify lyrics in your terminal [CUSTOM]  
**Dzr** - Command line Deezer player [CUSTOM]  
**Radio-active** - Internet radio player with 40k+ stations [CUSTOM]  
**Mpvc** - Music player interfacing mpv [CUSTOM]  

### 🎬 Video & Media - Motion Pictures
Video editing and media production:

**OBS Studio** - Streaming/recording [APT]  
**VLC** - Media player [APT]  
**FFmpeg** - Media processing [APT]  
**YT-DLP** - YouTube downloader [APT]  
**FreeTube** - Privacy-focused YouTube client [FLATPAK]  
**Invidious** - Alternative YouTube frontend [SCRIPT]  
**MPV** - Minimalist media player [APT]  
**VLC (Snap)** - VLC via Snap [SNAP]  
**VLC (Flatpak)** - VLC via Flatpak [FLATPAK]  
**OBS Studio (Flatpak)** - OBS via Flatpak [FLATPAK]  
**Streamlink** - Extract streams from various websites [APT]  
**Mps-youtube** - Terminal based YouTube player and downloader [CUSTOM]  
**Editly** - Declarative command line video editing [CUSTOM]  

### 📺 Media Servers & Streaming - Entertainment Central
Media servers and streaming platforms:

**Kodi** - Media center [APT]  
**Stremio** - Modern media center with streaming [FLATPAK]  
**Plex** - Media streaming platform [SCRIPT]  
**Jellyfin** - Open source media server [SCRIPT]  
**UMS** - Universal Media Server [SCRIPT]  

### ☁️ Cloud & Sync - Sky Storage
Cloud storage and synchronization:

**Rclone** - Cloud storage sync [SCRIPT]  
**Dropbox** - Cloud storage [SCRIPT]  
**Nextcloud Desktop** - Self-hosted cloud [APT]  
**Syncthing** - Peer-to-peer sync [APT]  
**Google Drive OCamlFUSE** - Google Drive filesystem [APT]  
**Nextcloud Server** - Self-hosted cloud storage server [SCRIPT]  
**Seafile** - Lightweight cloud storage with sync [SCRIPT]  

### 💻 Terminals - Command Central
Terminal emulators and command-line tools:

**Warp Terminal** - Modern terminal [SCRIPT]  
**Alacritty** - GPU-accelerated terminal [APT]  
**Terminator** - Multiple terminal panes [APT]  
**Tilix** - Tiling terminal [APT]  
**Ghostty** - Fast, feature-rich terminal emulator [SCRIPT]  

### 🎮 Gaming Platforms - Game On
Gaming platforms and game launchers:

**Steam** - Gaming platform [APT]  
**Heroic Launcher** - Epic Games/GOG launcher [FLATPAK]  
**Lutris** - Gaming manager [APT]  
**GameMode** - Gaming performance optimizer [APT]  
**Wine** - Windows API compatibility layer [APT]  
**Wine (Snap)** - Wine via Snap [SNAP]  
**Wine (Flatpak)** - Wine via Flatpak [FLATPAK]  
**Dwarf-fortress** - Roguelike construction and management simulation [CUSTOM]  
**Cataclysm-dda** - Turn-based survival game set in a post-apocalyptic world [CUSTOM]  

### 🎨 Graphics & Design - Visual Creativity
Graphics editing and design applications:

**GIMP** - Image manipulation [APT]  
**Blender** - 3D creation suite [APT]  
**Inkscape** - Vector graphics [APT]  
**GIMP (Snap)** - GIMP via Snap [SNAP]  
**GIMP (Flatpak)** - GIMP via Flatpak [FLATPAK]  
**Inkscape (Snap)** - Inkscape via Snap [SNAP]  
**Inkscape (Flatpak)** - Inkscape via Flatpak [FLATPAK]  
**Webcamize** - Webcam utility [SCRIPT]  
**Durdraw** - ASCII art editor [SCRIPT]  
**Pastel** - Color manipulation tool [SCRIPT]  

### 📄 Office & Productivity - Get Things Done
Office suites and productivity applications:

**LibreOffice** - Complete office suite [APT]  
**Thunderbird** - Email client [APT]  
**Calibre** - E-book management [APT]  
**Obsidian** - Knowledge management [SCRIPT]  
**Epr** - Terminal EPUB reader [APT]  
**Bible.js** - Read the Holy Bible via the command line [CUSTOM]  
**SpeedRead** - A simple terminal-based open source Spritz-alike [CUSTOM]  
**Medium-cli** - Read medium.com stories within terminal [CUSTOM]  
**Hygg** - Minimal document reader [CUSTOM]  
**Papis** - Extensible document and bibliography manager [CUSTOM]  
**Pubs** - Scientific bibliography manager [CUSTOM]  

### 🤖 AI & LLM Tools - The Future is Now
Cutting-edge AI and machine learning tools:

**Ollama** - Run LLMs locally [SCRIPT]  
**Gollama** - Ollama GUI client [SCRIPT]  
**LM Studio** - Local LLM interface [SCRIPT]  
**Text Generation WebUI** - Local text generation [SCRIPT]  
**Whisper-cpp** - Speech recognition [SCRIPT]  
**ComfyUI** - Node-based AI interface [SCRIPT]  
**InvokeAI** - Professional AI art [SCRIPT]  
**LMDeploy** - LLM deployment toolkit [SCRIPT]  
**KoboldCpp** - AI storytelling backend [SCRIPT]  
**Automatic1111** - Popular SD interface [SCRIPT]  
**Fooocus** - Simplified Stable Diffusion [SCRIPT]  
**SD-Next** - Advanced Stable Diffusion [SCRIPT]  
**Kohya SS GUI** - LoRA training interface [SCRIPT]  
**Faster-Whisper** - Optimized speech recognition [SCRIPT]  
**WhisperX** - Enhanced Whisper with alignment [SCRIPT]  
**Coqui-STT** - Speech-to-text engine [SCRIPT]  
**Piper-TTS** - Text-to-speech synthesis [SCRIPT]  
**Mimic3** - Neural text-to-speech [SCRIPT]  
**Coqui-TTS** - Advanced text-to-speech [SCRIPT]  
**Yai** - AI powered terminal assistant [CUSTOM]  

### 🕹️ Gaming Emulators - Retro Gaming
Gaming emulators for classic systems:

**RetroArch** - Multi-system emulator [APT]  
**RetroArch (Snap)** - RetroArch via Snap [SNAP]  
**RetroArch (Flatpak)** - RetroArch via Flatpak [FLATPAK]  
**MAME** - Arcade machine emulator [APT]  
**MAME (Flatpak)** - MAME via Flatpak [FLATPAK]  
**Dolphin Emulator** - GameCube/Wii emulator [APT]  
**Dolphin Emulator (Flatpak)** - Dolphin via Flatpak [FLATPAK]  
**PCSX2** - PlayStation 2 emulator [APT]  
**PCSX2 (Flatpak)** - PCSX2 via Flatpak [FLATPAK]  
**RPCS3** - PlayStation 3 emulator [FLATPAK]  
**Yuzu** - Nintendo Switch emulator [FLATPAK]  
**Cemu** - Wii U emulator [FLATPAK]  
**Mednafen** - Multi-system accurate emulator [APT]  
**DuckStation** - PlayStation 1 emulator [FLATPAK]  
**BSNES** - Super Nintendo emulator [APT]  
**mGBA** - Game Boy Advance emulator [APT]  
**mGBA (Snap)** - mGBA via Snap [SNAP]  
**mGBA (Flatpak)** - mGBA via Flatpak [FLATPAK]  
**DeSmuME** - Nintendo DS emulator [APT]  
**DeSmuME (Flatpak)** - DeSmuME via Flatpak [FLATPAK]  
**Citra** - Nintendo 3DS emulator [APT]  
**Citra (Flatpak)** - Citra via Flatpak [FLATPAK]  
**DOSBox** - DOS emulator [APT]  
**DOSBox (Snap)** - DOSBox via Snap [SNAP]  
**DOSBox (Flatpak)** - DOSBox via Flatpak [FLATPAK]  
**Mupen64Plus** - Nintendo 64 emulator [APT]  
**ScummVM** - Adventure game engine [APT]  
**ScummVM (Snap)** - ScummVM via Snap [SNAP]  
**ScummVM (Flatpak)** - ScummVM via Flatpak [FLATPAK]  
**QEMU** - System hardware emulator [APT]  
**Stella** - Atari 2600 emulator [APT]  
**DOSBox Staging** - DOS emulator for retro PC games [APT]  

# 🚀 INSTALLATION INSTRUCTIONS 🚀
Because Even Sublime Scripts Need Setup

## 📋 Prerequisites
- Ubuntu 20.04+ or Linux Mint 20+ (Fresh install or existing)
- Internet Connection (Obviously!)
- Sudo Access (You're the boss!)
- Terminal Access (Command line courage!)

## 🎯 Quick Start Guide

### Update Your System First (This is CRUCIAL!)

```bash
sudo apt update && sudo apt upgrade -y
```

### Download the Ultimate Buntstaller

```bash
git clone https://github.com/type-two/ultrabunt.git
cd ultrabunt
```

### Make It Executable (The Magic Incantation!)

```bash
chmod +x ultrabunt.sh
```

### Launch the Beast!

```bash
./ultrabunt.sh
```

## 🎪 Alternative Installation Methods

### One-Liner for the Brave:

```bash
curl -sSL https://raw.githubusercontent.com/type-two/ultrabunt/main/ultrabunt.sh | bash
```

### Download and Run:

```bash
wget https://raw.githubusercontent.com/type-two/ultrabunt/main/ultrabunt.sh
chmod +x ultrabunt.sh
./ultrabunt.sh
```
# 🎮 USAGE GUIDE 🎮
Navigate Like a Pro

## 🎯 Main Menu Navigation
- Use Arrow Keys or Tab to navigate
- Press Enter to select
- Press Esc or select "Back" to go back
- Press Ctrl+C to exit (if you must!)

## 🎪 Menu Structure

### 🏠 Main Menu
```
├── 📦 Browse Buntages by Category (A-Z Hotkeys Available!)
│   ├── (A) 🔧 Core Utilities
│   ├── (B) 💻 Development Tools
│   ├── (C) 🤖 AI & Modern Tools
│   ├── (D) 🐳 Containers
│   ├── (E) 🌐 Web Stack
│   ├── (F) 🐚 Shell Tools
│   ├── (G) 🎪 Hacker Playground
│   ├── (H) ✏️ Editors & IDEs
│   ├── (I) 🌍 Web Browsers
│   ├── (J) 📊 System Monitoring
│   ├── (K) 🌐 Network Monitoring
│   ├── (L) ⚡ Performance Tools
│   ├── (M) 🔧 Utilities
│   ├── (N) 🗄️ Database Management
│   ├── (O) 🛡️ Security Tools
│   ├── (P) ⚙️ System Tools
│   ├── (Q) 📄 Office & Productivity
│   ├── (R) 💬 Communication
│   ├── (S) 🎨 Graphics & Design
│   ├── (T) 🎵 Audio & Music
│   ├── (U) 🎬 Video & Media
│   ├── (V) 📺 Media Servers & Streaming
│   ├── (W) ☁️ Cloud & Sync
│   ├── (X) 💻 Terminal Emulators
│   ├── (Y) 🎮 Gaming Platforms
│   └── (Z) 🎮 Gaming Emulators
├── 🔍 Search Buntages
├── ℹ️ System Information
├── 🪞 Mirror Management
│   ├── 🌐 Display Current Mirror
│   ├── ⚡ Scan & Set Fastest Mirror
│   ├── 🔧 Advanced MirrorSelect Options
│   ├── 📦 Install/Setup apt-mirror
│   ├── 🏗️ Setup Local Mirror Storage
│   ├── 🔄 Update Local Mirror
│   └── 🏠 Use Local Mirror
├── ⌨️ Keyboard Layout Configuration
├── 🌐 WordPress Setup
│   ├── 🆕 Install New WordPress Site
│   ├── 📋 Manage Existing Sites
│   ├── 🔧 WP-CLI Management
│   └── 🛠️ Individual Site Management
├── 🐘 PHP Settings
├── 🗄️ Database Management
│   ├── 🔑 Show MariaDB Credentials
│   └── 🛠️ MariaDB Management
├── 📋 Bulk Operations
│   ├── Install All in Category
│   ├── Remove All in Category
│   ├── Update All Installed
│   └── Clean Cache & Orphans
├── 📊 Log Viewer
│   ├── 📋 System Logs
│   ├── 🌐 Web Server Logs
│   ├── 🗄️ Database Logs
│   ├── 🐘 PHP Logs
│   └── 🔒 Security Logs
└── 🚪 Exit
```

## 🎨 Status Icons Guide
- ✓ = Installed and ready to rock!
- ✗ = Not installed (yet!)
- (*) = bumhole
- (.Y.) = bewbs

# 🖥️ SYSTEM COMPATIBILITY 🖥️

## ✅ Fully Supported Systems
- Ubuntu 20.04 LTS (Focal Fossa)
- Ubuntu 22.04 LTS (Jammy Jellyfish)
- Ubuntu 23.04 (Lunar Lobster)
- Ubuntu 24.04 LTS (Noble Numbat)
- Linux Mint 20.x (All variants)
- Linux Mint 21.x (All variants)

## 🎯 Recommended Scenarios
- Fresh Installation - Perfect for setting up a new system
- Existing Installation - Great for adding new tools
- Development Workstation - Ideal for programmers
- Content Creation - Perfect for creators and artists
- Gaming Setup - Excellent for Linux gamers
- AI/ML Development - Complete AI toolkit included

## ⚡ System Requirements
- RAM: 4GB minimum (8GB+ recommended for AI tools)
- Storage: 20GB free space (for all buntages)
- Network: Broadband internet connection
- Processor: Any 64-bit x86 processor

# 🎭 ADVANCED FEATURES 🎭

## 🪞 Mirror Management & Optimization
- **Smart Mirror Selection** - Automatically find and set the fastest Ubuntu mirror
- **Local Mirror Creation** - Set up offline repositories with apt-mirror for air-gapped systems
- **Mirror Status Display** - View current mirror configuration and local storage paths
- **One-Click Optimization** - Scan and switch to optimal mirrors with automatic backups
- **Enterprise Ready** - Perfect for corporate environments and offline installations

## ⌨️ Enhanced Navigation
- **A-Z Hotkey Shortcuts** - Press any letter A-Z to jump directly to package categories
- **Double-Q Exit Protection** - Prevents accidental exits with confirmation system
- **Reorganized Menu Structure** - System tools prioritized at the top for quick access
- **Smart Status Indicators** - Real-time installation counts and refresh status

## 🔧 Bulk Operations
- Install Entire Categories - One click, dozens of apps!
- Remove Categories - Clean house efficiently
- Update Everything - Keep all buntages current
- Export Lists - Share your setup with friends

## 📊 Smart Features
- Dependency Resolution - Installs prerequisites automatically
- Installation Verification - Confirms successful installations
- Rollback Support - Undo problematic installations
- Comprehensive Logging - Track everything that happens

## 🎨 Customization Options
- Category Filtering - Show only what you need
- Installation Methods - Choose APT, Snap, Flatpak, or Custom
- Batch Processing - Queue multiple installations
- Export Formats - Multiple list export options

# 🐛 TROUBLESHOOTING 🐛

## 🚨 Common Issues & Solutions

### Script Won't Run:

```bash
# Make sure it's executable
chmod +x ultrabunt.sh

# Check if bash is available
which bash
```

### Permission Denied:

```bash
# Run with proper permissions
sudo ./ultrabunt.sh
```

### Package Installation Fails:

```bash
# Update package lists first
sudo apt update

# Fix broken dependencies
sudo apt --fix-broken install
```

### Snap/Flatpak Issues:

```bash
# Install snap support
sudo apt install snapd

# Install flatpak support
sudo apt install flatpak
```

### AI Tools Installation Issues:

```bash
# Ensure Python and pip are installed
sudo apt install python3 python3-pip python3-venv

# Install required system dependencies
sudo apt install build-essential git curl wget
```

# 📝 LOGS & DEBUGGING 📝

All operations are logged to: `/tmp/ultrabunt_YYYYMMDD_HHMMSS.log`

## View Current Log:

```bash
tail -f /tmp/ultrabunt_*.log
```

## Debug Mode:

```bash
DEBUG=1 ./ultrabunt.sh
```

# 🎉 CONTRIBUTING 🎉

Want to make this even more ridiculously sublime?

1. Fork the Repository
2. Add Your Favorite Buntages
3. Test Everything Thoroughly
4. Submit a Pull Request
5. Become a Buntage Legend!

## 🎯 Adding New Applications
1. Add package definition in the appropriate category section
2. Create custom installation/removal functions if needed
3. Add to installation/removal dispatchers
4. Update this README with the new application
5. Test thoroughly on a clean system

# 📜 LICENSE 📜

This project is licensed under the MIT License - because sharing is caring! seriously its just a bunch of bash stickytaped together go nuts.

# 🏆 CREDITS & ACKNOWLEDGMENTS 🏆

## 🎭 MONSTERROBOTSOFT a subsidiary of MONSTERROBOTCORP 
- Created with emoticons by developers who believe software installation should be bunt
- Inspired by the need for a better Ubuntu setup experience
- Powered by hallucinations and debugging

## 🌟 Special Thanks
- Ubuntu Community - For creating an OS for lazy ppl who hate windows
- Open Source Developers - For the free shit
- Tata Besters - For flinding all our blugs
- Methylphenidate - For making this possible

# 🚀 FINAL WORDS 🚀

The Ultimate Buntstaller isn't just a script - it's a statement. A statement that says "I refuse to manually install packages like a caveman!" It's a declaration of independence from boring, repetitive setup tasks. It's a celebration of the ridiculous, the sublime, and the absolutely bonkers world of Linux package management.

So go forth, brave user, and BUNTAGE ALL THE THINGS! 🎉

╔══════════════════════════════════════════════════════════════╗
║  "In a world of packages, dare to be a BUNTAGE!"             ║
║                                                              ║
║  - The Ultimate Buntstaller Philosophy                       ║
╚══════════════════════════════════════════════════════════════╝
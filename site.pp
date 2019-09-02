node '<UPLOAD_SERVER_URL>' {
    include apache, tcpwrappers

    # BOINC upload server

    file {'/storage' :
        ensure  => directory,
        group   => 'boinc',
        owner   => 'boinc',
        mode    => '0775',
    }

    # Setup ssh allow and deny
    tcpwrappers::allow { '<SERVER_NAME>':
      service  => 'sshd',
      address  => '<SERVER_IP_ADDRESS>',
    }->
    tcpwrappers::allow { 'all_sendmail':
      service  => 'sendmail',
      address  => 'ALL',
    }->
    tcpwrappers::allow { 'localhost':
      service  => 'ALL',
      address  => '127.0.0.1',
    }->
    tcpwrappers::deny { 'deny all':
      service  => 'ALL',
      address  => 'ALL',
    }

    # Setup the required users
    user { '<USERNAME>':
      ensure     => present,
      home       => '/var/empty',
      shell      => '/sbin/nologin',
      managehome => true,
      uid        => 1001,
      gid        => 1001,
    }

    # Setup the firewall
    resources { 'firewall':
        purge => true,
    }->
    firewall { '999 drop all':
      proto  => 'all',
      action => 'drop',
      before => undef,
    }->
    firewall { '000 accept all icmp':
      proto  => 'icmp',
      action => 'accept',
    }->
    firewall { '001 accept all to lo interface':
      proto   => 'all',
      iniface => 'lo',
      action  => 'accept',
    }->
    firewall { '002 reject local traffic not on loopback interface':
      iniface     => '! lo',
      proto       => 'all',
      destination => '127.0.0.1/8',
      action      => 'reject',
    }->
    firewall { '003 accept related established rules':
      proto  => 'all',
      state  => ['RELATED', 'ESTABLISHED'],
      action => 'accept',
    }->
    firewall { '004 Allow SSH':
        dport      => '22',
        proto      => 'tcp',
        action     => 'accept',
    }->
    firewall { '005 Allow http':
        dport      => '80',
        proto      => 'tcp',
        action     => 'accept',
    }->
    firewall { '006 Allow Puppet Master':
        dport      => '8140',
        proto      => 'tcp',
        action     => 'accept',
    }

    apache::vhost { '<UPLOAD_MACHINE_URL> non-ssl':
        servername      => '<UPLOAD_MACHINE_URL>',
        port            => '80',
        docroot         => '/var/www/html',
        redirect_status => 'permanent',
        redirect_dest   => 'https://<UPLOAD_MACHINE_URL>/',
        keepalive       => 'on',
        keepalive_timeout => '300',
    }
    apache::vhost { '<UPLOAD_MACHINE_URL> ssl':
        servername => '<UPLOAD_MACHINE_URL>',
        port       => '443',
        docroot    => '/var/www/html',
        ssl        => true,
        keepalive  => 'on',
        keepalive_timeout => '300',
    }

    $username = '<USERNAME>'
    $group = $username

    # Setup the folder structure
    file { '<PATH_TO_BOINC_FOLDER>' :
        ensure  => directory,
        group   => $group,
        owner   => $username,
        mode    => '0755',
    }->
    file { '<PATH_TO_SCRIPTS>' :
        ensure  => directory,
        group   => $group,
        owner   => $username,
        mode    => '0755',
    }

    file { '<PATH_TO_STORAGE_FOLDER>' :
        ensure  => directory,
        group   => '$group,
        owner   => $username,
        mode    => '0755',
    }->
    file { '<INCOMING_FOLDER_PATH>' :
        ensure  => directory,
        group   => $group,
        owner   => $username,
        mode    => '0775',
    }->
    file { '<PATH_TO_BOINC_STORAGE_FOLDER>' :
        ensure  => directory,
        group   => $group,
        owner   => $username,
        mode    => '0775',
    }->
    file { '<PROJECT_RESULTS_PATH>' :
        ensure  => directory,
        group   => $group,
        owner   => $username,
        mode    => '0775',
    }->
    file { '<UPLOADER_FOLDER_PATH>' :
        ensure  => directory,
        group   => $group,
        owner   => $username,
        mode    => '0775',
    }

    file {'<PROJECT_PATH>' :
        ensure  => directory,
        group   => $group,
        owner   => $username,
        mode    => '0700',
    }->
    file {'<PROJECT_PATH>/cgi-bin' :
        ensure  => directory,
        group   => $group,
        owner   => $username,
        mode    => '0755',
    }->
    file { '<PROJECT_PATH>/log':
        ensure => 'directory',
        owner  => $username,
        group  => $group,
        mode   => '0770',
    }->
    file { '<KEYS_DIRECTORY_PATH>':
        ensure => 'directory',
        owner  => $username,
        group  => $group',
        mode   => '0700',
    }

    # Install the required packages
    package { 'git':
        ensure => installed,
    }->
    package { 'libnotify-devel':
        ensure => installed,
    }->
    package { 'libcurl-devel':
        ensure => installed,
    }->
    package { 'libtool':
        ensure => installed,
    }->
    package { 'autoconf':
        ensure => installed,
    }->
    package { 'automake':
        ensure => installed,
    }->
    package { 'gcc-c++':
        ensure => installed,
    }->
    package { 'mysql-devel':
        ensure => installed,
    }

    # Pull down the BOINC repository and build
    vcsrepo { "<PATH_TO_BOINC_HOME>":
        ensure   => latest,
        owner    => $username,
        group    => $group,
        provider => git,
        require  => [ Package["git"] ],
        source   => "https://github.com/BOINC/boinc.git",
        revision => 'master',
    }->
    exec { 'build_boinc':
        cwd     => '<PATH_TO_BOINC_HOME>',
        subscribe   => Vcsrepo['<PATH_TO_BOINC_HOME>'],
        require  => [ Package["libnotify-devel"],Package["libcurl-devel"],Package["autoconf"],Package["automake"],Package["libtool"],Package["gcc-c++"],Package["mysql-devel"] ],
        refreshonly => true,
        path =>  '/bin/:/sbin/:/usr/bin/:/usr/sbin/:<PATH_TO_BOINC_HOME>',
        command => "./_autosetup >/tmp/boinc_install;./configure --disable-client --disable-manager>>/tmp/boinc_install;make>>/tmp/boinc_install",
    }->
    exec { 'file_upload_handler':
        cwd    => '<PATH_TO_BOINC_HOME>/sched',
        subscribe   => Exec['build_boinc'],
        refreshonly => true,
        path =>  '/bin/:/sbin/:/usr/bin/:/usr/sbin/:<PATH_TO_BOINC_HOME>',
        command => "make >>/tmp/boinc_install;/bin/cp file_upload_handler <PROJECT_PATH>/cgi-bin",
    }

    # Copy the upload keys to the correct place
    file { 'upload_public':
        owner  => 'apache',
        group  => 'root',
        mode   => '0664',
        path    => '<PATH_TO_KEYS>/upload_public',
        source  => "puppet:///modules/upload_server/upload_public",
        replace => false,
    }

    # Copy over the config.xml file
    file { 'config_xml':
        owner  => 'root',
        group  => 'root',
        mode   => '0644',
        path    => '<PROJECT_PATH>/config.xml',
        source  => "puppet:///modules/upload_server/config.xml",
        replace => false,
    }

    # Setup batch sorting
    cron{'pull_repo':
        command => '/bin/sh -c "cd $SCRIPTS_DIR && /usr/bin/git pull origin master" 2>/dev/null',
        user    => 'boinc',
        hour    => 0,
        minute  => 55,
    }->
    cron{'run_batch_script1':
        command => '$SCRIPTS_DIR/batch_sorting_phase1.py >> $LOG_DIR/batch_sorting_phase1.log',
        user    => 'boinc',
        hour    => 0,
        minute  => 0,
    }->
    cron{'run_batch_script2':
        command => '$SCRIPTS_DIR/batch_sorting_phase2.py >> $LOG_DIR/batch_sorting_phase2.log',
        user    => 'boinc',
        hour    => 7,
        minute  => 15,
    }

    # Environment Variables for batch sorting scripts
    exec { 'BATCH_LISTS_URLS' :
       command => "/bin/bash -c \"export BATCH_LISTS_URLS=<BATCH_LIST_URLS>\"",
    }->
    exec { 'RESULTS_FOLDER' :
       command => "/bin/bash -c \"export RESULTS_FOLDER=<PROJECT_RESULTS_LOCATION>\"",
    }->
    exec { 'INCOMING_FOLDER' :
       command => "/bin/bash -c \"export INCOMING_FOLDER=<UPLOADER_FOLDER_LOCATION>\"",
    }->
    exec { 'TMPDIR' :
       command => "/bin/bash -c \"export TMPDIR=<PATH_TO_BOINC_HOME>../\"",
    }->
    exec { 'UPLOAD_BASE_URL' :
       command => "/bin/bash -c \"export UPLOAD_BASE_URL=<LOCATION_OF_PROJECT_RESULTS>\"",
    }->
    exec { 'SCRIPTS_DIR' :
       command => "/bin/bash -c \"export SCRIPTS_DIR=<SCRIPTS_LOCATION>\"",
    }->
    exec { 'LOG_DIR' :
       command => "/bin/bash -c \"export LOG_DIR=/<LOG_DIRECTORY_LOCATION>\"",
    }->
    exec { 'CLEANUP_CLOSED_BATCHES' :
       command => "/bin/bash -c \"export CLEANUP_CLOSED_BATCHES=TRUE\"",
    }->
    exec { 'SORT_BY_PROJECT' :
       command => "/bin/bash -c \"export SORT_BY_PROJECT=TRUE\"",
    }

}

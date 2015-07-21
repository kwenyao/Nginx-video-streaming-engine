#!/bin/sh

BUILD_DIRECTORY=/usr/build
CURR_USER=`whoami`
NGINX_VER=1.7.10

sudo apt-get update
sudo apt-get install -y build-essential libpcre3 libpcre3-dev libssl-dev git
sudo mkdir "$BUILD_DIRECTORY"
sudo chown "$CURR_USER":"$CURR_USER" "$BUILD_DIRECTORY" -R
cd "$BUILD_DIRECTORY"
sudo git clone git://github.com/arut/nginx-rtmp-module.git
sudo git clone git://github.com/openresty/redis2-nginx-module.git
sudo git clone git://github.com/openresty/set-misc-nginx-module.git
sudo git clone git://github.com/simpl/ngx_devel_kit.git
sudo git clone git://github.com/openresty/lua-nginx-module.git
sudo git clone git://github.com/openresty/echo-nginx-module.git
sudo git clone git://github.com/calio/form-input-nginx-module.git
sudo git clone http://luajit.org/git/luajit-2.0.git

cd "$BUILD_DIRECTORY"/luajit-2.0
sudo make
sudo make install
echo export LUAJIT_LIB=/usr/local/lib >> ~/.bashrc
echo export LUAJIT_INC=/usr/local/include/luajit-2.0 >> ~/.bashrc
echo export LD_LIBRARY_PATH=/usr/local/lib/:/opt/drizzle/lib/:$LD_LIBRARY_PATH >> ~/.bashrc
sudo apt-get install -y lua5.1 liblua5.1-0 liblua5.1-0-dev
sudo ln -s /usr/lib/x86_64-linux-gnu/liblua5.1.so /usr/lib/liblua.so

wget http://nginx.org/download/nginx-"$NGINX_VER".tar.gz
tar xzf nginx-"$NGINX_VER".tar.gz
cd "$BUILD_DIRECTORY"/nginx-"$NGINX_VER"

sudo ./configure --add-module="$BUILD_DIRECTORY"/nginx-rtmp-module \
--add-module="$BUILD_DIRECTORY"/redis2-nginx-module \
--add-module="$BUILD_DIRECTORY"/ngx_devel_kit \
--add-module="$BUILD_DIRECTORY"/set-misc-nginx-module \
--add-module="$BUILD_DIRECTORY"/lua-nginx-module \
--add-module="$BUILD_DIRECTORY"/echo-nginx-module \
--add-module="$BUILD_DIRECTORY"/form-input-nginx-module \
--with-ld-opt="-Wl,-rpath,/path/to/luajit-or-lua/lib" \
--with-http_ssl_module \
--with-http_auth_request_module

sudo make -j2
sudo make install

sudo wget https://raw.github.com/JasonGiedymin/nginx-init-ubuntu/master/nginx -O /etc/init.d/nginx
sudo chmod +x /etc/init.d/nginx
sudo update-rc.d nginx defaults
sudo service nginx start
sudo service nginx stop

sudo apt-get install software-properties-common
sudo add-apt-repository ppa:kirillshkrogalev/ffmpeg-next
sudo apt-get update
sudo apt-get install ffmpeg

cat <<'EOF' |sudo tee /usr/local/nginx/conf/nginx.conf 

#user  nobody;
worker_processes  1;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

#pid        logs/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    #log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
    #                  '$status $body_bytes_sent "$http_referer" '
    #                  '"$http_user_agent" "$http_x_forwarded_for"';

    #access_log  logs/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    #keepalive_timeout  0;
    keepalive_timeout  65;

    #gzip  on;

    server {
        listen       80;
        server_name  localhost;

        #charset koi8-r;

        #access_log  logs/host.access.log  main;

        location / {
            root   html;
            index  index.html index.htm;
        }

        #error_page  404              /404.html;

        # redirect server error pages to the static page /50x.html
        #
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }

        # proxy the PHP scripts to Apache listening on 127.0.0.1:80
        #
        #location ~ \.php$ {
        #    proxy_pass   http://127.0.0.1;
        #}

        # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
        #
        #location ~ \.php$ {
        #    root           html;
        #    fastcgi_pass   127.0.0.1:9000;
        #    fastcgi_index  index.php;
        #    fastcgi_param  SCRIPT_FILENAME  /scripts$fastcgi_script_name;
        #    include        fastcgi_params;
        #}

        # deny access to .htaccess files, if Apache's document root
        # concurs with nginx's one
        #
        #location ~ /\.ht {
        #    deny  all;
        #}
    }


    # another virtual host using mix of IP-, name-, and port-based configuration
    #
    #server {
    #    listen       8000;
    #    listen       somename:8080;
    #    server_name  somename  alias  another.alias;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}


    # HTTPS server
    #
    #server {
    #    listen       443;
    #    server_name  localhost;

    #    ssl                  on;
    #    ssl_certificate      cert.pem;
    #    ssl_certificate_key  cert.key;

    #    ssl_session_timeout  5m;

    #    ssl_protocols  SSLv2 SSLv3 TLSv1;
    #    ssl_ciphers  HIGH:!aNULL:!MD5;
    #    ssl_prefer_server_ciphers   on;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}
    server {

        listen      8080;

        location /redis {
            internal;
            set_unescape_uri $query $arg_query;
            redis2_query get $query;
            redis2_pass 127.0.0.1:6379;
        }

        location /auth {
            set_form_input $name;
            content_by_lua '
            local res = ngx.location.capture("/redis",
                { args = { query = ngx.var.name } }
            )
            if string.len(res.body) > 5 then 
                ngx.exit(200)
            else
                ngx.exit(400)
            end
        ';
        }

        location /hls {
            # Serve HLS fragments
            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }
            root /tmp;
            add_header Cache-Control no-cache;
        }

        location /360p {
            # Serve HLS fragments
            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }
            root /tmp;
            add_header Cache-Control no-cache;
        }
    }
}

rtmp {
    server {
        listen 1935;
        chunk_size 4000;
        
        application hls {
            on_publish http://localhost:8080/auth;
            live on;
            hls on;
            hls_path /tmp/hls;
        }
        application live {
            live on;
            record off;
            exec ffmpeg -i rtmp://localhost/live/$name -threads 1 -c:v libx264 -profile:v main -b:v 350K -vf scale=-1:360 -f flv -c:a aac -ac 1 -strict -2 -b:a 56k rtmp://localhost/live360p/$name;
        }
        application live360p {
            live on;
            hls on;
            hls_path /tmp/360p;
        }
    }
}

EOF

echo export PATH=$PATH:/usr/local/nginx/sbin >> ~/.bashrc
sudo service nginx restart

sudo apt-get install -y tcl8.5
cd "$BUILD_DIRECTORY"
wget http://download.redis.io/releases/redis-stable.tar.gz
tar xzf redis-stable.tar.gz
cd "$BUILD_DIRECTORY"/redis-stable
make
make test
sudo make install
cd utils
sudo ./install_server.sh

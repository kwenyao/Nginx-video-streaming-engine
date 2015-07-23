#!/bin/sh

CURR_USER=`whoami`

MYSQL_SCRIPT_DIRECTORY=/usr/build
MYSQL_SCRIPT_NAME=dbconfig.py
MYSQL_HOST=localhost
MYSQL_USER=root
MYSQL_PASSWORD=root
DATABASE_NAME=auth

API_DIRECTORY=~/authapi
API_FILE_NAME=authapi
UWSGI_FILE_NAME=authapi
WSGI_ENTRY_POINT=wsgi

sudo apt-get update
sudo apt-get -y install python-dev libmysqlclient-dev build-essential libffi-dev
sudo apt-get -y install python-pip mysql-server
sudo apt-get -y install python-mysql.connector
sudo pip install flask-restful
sudo pip install flask-mysql
sudo pip install MySQL-python
sudo pip install redis
sudo pip install bcrypt

cat <<EOF |sudo tee "$MYSQL_SCRIPT_DIRECTORY"/"$MYSQL_SCRIPT_NAME"

__author__ = 'Wen Yao'

import sys
import mysql.connector
import MySQLdb
from warnings import filterwarnings
from collections import OrderedDict

TABLE_NAME = 'credentials'
TABLE_ATTR = OrderedDict([('username', 'VARCHAR(32)'),
                          ('password', 'CHAR(60)')
                          ])
PRIMARY_KEY = 'username'


def connect_to_mysql_server(host, user, password, dbname):
    create_database(host, user, password, dbname)
    connection = mysql.connector.connect(user=user,
                                         password=password,
                                         host=host,
                                         database=dbname)
    return connection

def create_database(host, user, password, dbname):
    statement = ("CREATE DATABASE IF NOT EXISTS {0}".format(dbname))
    filterwarnings('ignore', category=MySQLdb.Warning)
    connection = MySQLdb.connect(host=host, user=user, passwd=password)
    cursor = connection.cursor()
    try:
        cursor.execute(statement)
    except MySQLdb.Error as err:
        print("MYSQL Error: {}".format(err))
    cursor.close()
    connection.close()

def alter_password_field(cursor):
    statement = """ALTER TABLE {tableName}
                MODIFY password {passwdType}
                CHARACTER SET latin1 COLLATE latin1_danish_ci
                """.format(tableName=TABLE_NAME,
                           passwdType=TABLE_ATTR.get('password'))
    try:
        cursor.execute(statement)
    except mysql.connector.Error as err:
        print("MYSQL Error: {}".format(err))


def create_table(dbname, cursor):
    statement1 =  "CREATE TABLE IF NOT EXISTS {0}.{1}(".format(dbname, TABLE_NAME)
    statement2 = ""
    for column, type in TABLE_ATTR.iteritems():
        statement2 += column
        statement2 += " " + type + ","
    statement3 = "PRIMARY KEY({0}))".format(PRIMARY_KEY)
    sqlstatement = statement1 + statement2 + statement3
    try:
        cursor.execute(sqlstatement)
    except mysql.connector.Error as err:
        print("MYSQL Error: {}".format(err))
    alter_password_field(cursor)
    return

def procedure_create_user(cursor):
    procedureName = 'CreateUser'
    cursor.execute("DROP procedure IF EXISTS {0};".format(procedureName))
    statement = """CREATE PROCEDURE {procedureName} (
                IN p_username {userType},
                IN p_password {passwordType}
                )
                BEGIN
                    if ( select exists (select 1 from {tableName} where username = p_username) ) THEN
                        select 'Username Exists!!';
                    ELSE
                        insert into {tableName}(username,password) values(p_username, p_password);
                    END IF;
                END""".format(procedureName=procedureName,
                              tableName=TABLE_NAME,
                              userType=TABLE_ATTR.get('username'),
                              passwordType=TABLE_ATTR.get('password'))
    try:
        cursor.execute(statement)
    except MySQLdb.Error as err:
        print("MYSQL Error: {}".format(err))
    return

def procedure_authenticate_user(cursor):
    procedureName = 'AuthenticateUser'
    cursor.execute("DROP procedure IF EXISTS {0};".format(procedureName))
    statement = """CREATE PROCEDURE {procedureName} (
                IN p_username {userType}
                )
                BEGIN
                     select * from {tableName} where username = p_username;
                END""".format(procedureName=procedureName,
                              userType=TABLE_ATTR.get('username'),
                              tableName=TABLE_NAME)
    try:
        cursor.execute(statement)
    except MySQLdb.Error as err:
        print("MYSQL Error: {}".format(err))
    return

def create_procedures(cursor):
    procedure_create_user(cursor)
    procedure_authenticate_user(cursor)
    return

def execute():
    MYSQL_HOST = sys.argv[1]
    MYSQL_USER = sys.argv[2]
    MYSQL_PASSWORD = sys.argv[3]
    DATABASE_NAME = sys.argv[4]
    mysqlConn = connect_to_mysql_server(MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD, DATABASE_NAME)
    cursor = mysqlConn.cursor()
    create_table(DATABASE_NAME, cursor)
    create_procedures(cursor)
    cursor.close()
    mysqlConn.close()

if __name__ == '__main__':
    if len(sys.argv) > 4:
        execute()
    else:
        print 'Missing argument(s). Please enter <MySQL host> <MySQL user> <MySQL password> <Database name>'

EOF

cd "$MYSQL_SCRIPT_DIRECTORY"
python "$MYSQL_SCRIPT_NAME" "$MYSQL_HOST" "$MYSQL_USER" "$MYSQL_PASSWORD" "$DATABASE_NAME"

sudo apt-get install uwsgi uwsgi-plugin-python
sudo pip install uwsgi flask
mkdir "$API_DIRECTORY"
cd "$API_DIRECTORY"

cat <<EOF |tee "$API_DIRECTORY"/"$API_FILE_NAME".py

__author__ = 'Wen Yao'

import bcrypt
import hashlib
import redis
import time
from flask import Flask
from flask.ext.mysql import MySQL
from flask_restful import Api
from flask_restful import Resource
from flask_restful import reqparse

mysql = MySQL()
app = Flask(__name__)

# MySQL configurations
app.config['MYSQL_DATABASE_USER'] = 'root'
app.config['MYSQL_DATABASE_PASSWORD'] = 'root'
app.config['MYSQL_DATABASE_DB'] = 'auth'
app.config['MYSQL_DATABASE_HOST'] = 'localhost'

REDIS_HOST = '127.0.0.1'
REDIS_PORT = 6379

redispool = redis.ConnectionPool(host=REDIS_HOST, port=REDIS_PORT, db=0)

mysql.init_app(app)
api = Api(app)

class CreateUser(Resource):
    def hash_passwd(self, passwd):
        hashed_passwd = bcrypt.hashpw(passwd, bcrypt.gensalt(rounds=12))
        return hashed_passwd

    def post(self):
        try:
            # Parse the arguments
            parser = reqparse.RequestParser()
            parser.add_argument('user', type=str, help='Username to create user')
            parser.add_argument('password', type=str, help='Password to create user')
            args = parser.parse_args()

            _userEmail = args['user']
            _userPassword = self.hash_passwd(args['password'])

            conn = mysql.connect()
            cursor = conn.cursor()
            cursor.callproc('CreateUser',(_userEmail,_userPassword))
            data = cursor.fetchall()

            if len(data) is 0:
                conn.commit()
                content = {'message': 'User Created!'}
                statuscode = 200
            else:
                content = {'Message': str(data[0][0])}
                statuscode = 200
            return content, statuscode

        except Exception as e:
            return {'error': str(e)}

class Auth(Resource):
    def hash_password(self, passwd, hashedpw):
        return bcrypt.hashpw(passwd, hashedpw)

    def add_stream_key_to_redis(self, key):
        redis_server = redis.Redis(connection_pool=redispool)
        redis_server.set(key, 'true')
        return

    def generate_stream_key(self, username):
        hash = hashlib.md5()
        hash.update(str(time.time()))
        hash.update(username)
        streamkey = hash.hexdigest()
        self.add_stream_key_to_redis(streamkey)
        return streamkey

    def post(self):
        try:
            # Parse the arguments
            parser = reqparse.RequestParser()
            parser.add_argument('user', type=str, help='Username for Authentication')
            parser.add_argument('password', type=str, help='Password for Authentication')
            args = parser.parse_args()

            _userName = args['user']
            _userPassword = args['password']

            conn = mysql.connect()
            cursor = conn.cursor()
            cursor.callproc('AuthenticateUser',(_userName,))
            data = cursor.fetchall()
            if(len(data)>0):
                hashedpasswd = self.hash_password(_userPassword, str(data[0][1]))
                if(str(data[0][1])==hashedpasswd): # Authenticated
                    streamkey = self.generate_stream_key(_userName)
                    content = {'message': 'Authentication success!', 'stream key': streamkey}
                    statuscode = 200
                else:
                    content = {'message':'Authentication failure'}
                    statuscode = 401
                return content, statuscode

        except Exception as e:
            return {'error': str(e)}

api.add_resource(Auth, '/auth')
api.add_resource(CreateUser, '/createuser')

if __name__ == '__main__':
    app.run(host='0.0.0.0')

EOF

cat <<EOF |tee "$API_DIRECTORY"/"$WSGI_ENTRY_POINT".py

from $API_FILE_NAME import app

if __name__ == "__main__":
    app.run()

EOF

cat <<EOF |tee "$API_DIRECTORY"/"$UWSGI_FILE_NAME".ini
[uwsgi]
module = $WSGI_ENTRY_POINT
callable = app

master = true
processes = 5

socket = 127.0.0.1:3031
chmod-socket = 660
vacuum = true

die-on-term = true

EOF

cat <<EOF |sudo tee /etc/init/"$API_FILE_NAME".conf
description "uWSGI server instance configured to serve $API_FILE_NAME"

start on runlevel [2345]
stop on runlevel [!2345]

setuid $CURR_USER
setgid www-data

chdir $API_DIRECTORY
exec uwsgi --ini $UWSGI_FILE_NAME.ini

EOF

sudo start "$API_FILE_NAME"

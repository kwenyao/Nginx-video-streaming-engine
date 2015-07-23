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
    app.run(debug=True, host='0.0.0.0')

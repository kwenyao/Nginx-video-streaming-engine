__author__ = 'Wen Yao'

import bcrypt
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

mysql.init_app(app)
api = Api(app)

class CreateUser(Resource):
    def hash_passwd(self, passwd):
        hashed_passwd = bcrypt.hashpw(passwd, bcrypt.gensalt())
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
                return {'StatusCode':'200','passwd length': str(len(_userPassword))}
            else:
                return {'StatusCode':'1000','Message': str(data[0])}

        except Exception as e:
            return {'error': str(e)}

class Auth(Resource):
    def hash_password(self, passwd, hashedpw):
        return bcrypt.hashpw(passwd, hashedpw)

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
                    return {'status':200,'Password':str(data[0][1])}
                else:
                    return {'status':100,'message':'Authentication failure'}

        except Exception as e:
            return {'error': str(e)}

api.add_resource(Auth, '/auth')
api.add_resource(CreateUser, '/createuser')

if __name__ == '__main__':
    app.run(debug=True)
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

"""
Charge PyMySQL comme backend MySQLdb pour Django (simple sur Windows + WAMP).
Sans PyMySQL, utilisez PostgreSQL ou SQLite.
"""
try:
    import pymysql

    pymysql.install_as_MySQLdb()
except ImportError:
    pass

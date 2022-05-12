db = db.getSiblingDB('admin');
db.createUser(
	{
	user: "[ADMIN_REPLACE_ME]",
	pwd: "[PWD_REPLACE_ME]",
	roles:[
		{ role: "dbOwner" , db:"admin"},
		{ role: 'userAdminAnyDatabase', db: 'admin' },
		{ role: 'readWriteAnyDatabase', db: 'admin' },
		{ role: 'dbAdminAnyDatabase', db: 'admin'},
	]
}	
);
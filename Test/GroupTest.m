/*
 Copyright (c) 2009 copyright@de-co-de.com
 
 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 */
#import "GTMSenTestCase.h"
#import "GTMUnitTestDevLog.h"
#import "Lite3DB.h"
#import "Lite3Table.h"
#import "Lite3LinkTable.h"

@interface GroupTest : SenTestCase {
    Lite3DB * db;
    Lite3Table * groupsTable;
    Lite3Table * usersTable;
}

@end

static const char * ddl = 
"create table \"users\" ("
"\"id\" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,"
"\"name\" varchar(255)"
");"
"create table \"groups\" ("
"\"id\" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,"
"\"name\" varchar(255) "
");"
"create table \"groups_users\" ("
"  group_id integer,"
"  user_id integer"
");"
;



@implementation GroupTest
- (void)setUp {
    db = [Lite3DB alloc];        
    db = [db initWithDbName: @"user_test" andSql:[NSString stringWithCString:ddl]];
        usersTable = [[Lite3Table lite3TableName: @"users" withDb: db forClassName:@"User"] retain];
    groupsTable = [[Lite3Table lite3TableName: @"groups" withDb: db forClassName:@"Group"] retain];
    // need to traverse all the tables and fix the references 
    [db checkConsistency];
    
}

- (void) testDDL {
    // we expect two tables to be created
    NSArray * tables  =[db listTables];
    STAssertNotNil( tables, @"No tables", nil );
    STAssertEquals( (int)[tables count], 3, @"Wrong number of tables, got %d", [tables count]);
}

- (void)testGroupsTableSetup {
    STAssertNotNil( groupsTable, @"Valid groupsTable", nil );
    STAssertTrue( [groupsTable tableExists], @"Table regions does not exist", nil );
    STAssertNotNil( groupsTable.linkedTables, nil, @"No linked tables", nil );
    STAssertEquals( (int)[groupsTable.linkedTables count],1,@"Bad number of linkedTables %d", [groupsTable.linkedTables count]);
}

-(void)testUsersTableSetup {
    STAssertNotNil( usersTable, @"Valid usersTable", nil );
    STAssertTrue( [usersTable tableExists], @"Table places does not exist", nil );    
    STAssertNotNil( usersTable.arguments, @"Bad arguments in usersTable", nil );
}

- (void)testGroupsLinkedTableSetup {
    Lite3LinkTable * groupsUsers = [groupsTable.linkedTables objectAtIndex: 0];
    STAssertNotNil( groupsUsers, @"Empty linkedTables", nil );
    STAssertNotNil( groupsUsers.ownTable, @"LinkedTable does not have its own table", nil );
    STAssertTrue( [groupsUsers.ownTable tableExists], @"LinkedTable not in the database %@", groupsUsers.ownTable.tableName );
}

- (void) testImport {
    
    id input = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects: @"1", @"group1", [NSArray arrayWithObjects: @"1", @"2", @"3",nil],nil] forKeys:[NSArray arrayWithObjects: @"id", @"name", @"user_ids", nil]];
    NSArray * data = [NSArray arrayWithObjects: input, nil];
    STAssertNotNil ( data, @"data not nil", data );
    STAssertGreaterThan( (int)[data count], 0, @"data is empty", nil );
    Lite3LinkTable * groupsUsers = [groupsTable.linkedTables objectAtIndex: 0];
    
    [groupsTable truncate];
    STAssertEquals( 0, [groupsTable count], @"Groups table not empty after truncate, instead %d", [groupsTable count] );
    STAssertEquals( (int)[groupsUsers.ownTable count], 0, @"Linked table is not empty %d",  [groupsUsers.ownTable count] );

    [groupsTable updateAll: data];
    STAssertEquals ( 1, [groupsTable count], @"Groups table does not have proper count of rows %d", [groupsTable count] );
    
    int linksCount = [groupsUsers.ownTable count];
    STAssertGreaterThan( linksCount, 0, @"Linked table is empty", nil);
    STAssertEquals( linksCount, 3, @"Bad number of links %d", linksCount );


    // truncate one more time
    [groupsTable truncate];
    STAssertEquals( 0, [groupsTable count], @"Groups table not empty after truncate, instead %d", [groupsTable count] );
    STAssertEquals( (int)[groupsUsers.ownTable count], 0, @"Linked table is not empty %d",  [groupsUsers.ownTable count] );
    
}

- (void)tearDown {
    [usersTable release];
    [groupsTable release];
    [db release];
    
}

@end

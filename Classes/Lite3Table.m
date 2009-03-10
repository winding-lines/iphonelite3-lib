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

#import "Lite3Arg.h"
#import "Lite3Table.h"
#import "Lite3DB.h"
#import "Lite3LinkTable.h"

#pragma mark "-- Lite3Table private --"
@interface Lite3Table(Private)

- (BOOL)mapToClass: (NSString*)clsName;

- (int)updateOwnTable:(id)data;

- (NSMutableArray*)selectOwn:(NSString *)whereClause start: (int)start count:(int)count withAggregate:(NSString*)aggregate orderBy:(NSString*)orderBy;

- (NSMutableArray*)selectOwn:(NSString *)whereClause expr:(NSString*)expr groupBy:(NSString*)groupBy;

- (void)truncateOwn;

-(void) setProperty:(NSString *) name inObject: (id) object toInt:(int) value;

-(void) setProperty:(NSString *) name inObject: (id) object toValue: (const char *) value;

@end

/**
 * SQLite3 callbacks
 */
static int singleRowCallback(void *helperP, int columnCount, char **values, char **columnNames);

static int multipleRowCallback(void *helperP, int columnCount, char **values, char **columnNames);


/**
 * Class used in the communication to the sqlite3 multipleRowCallback.
 */
struct _SqlOutputHelper {
    Lite3Table * preparedTable;
    NSMutableArray * output;
    Class cls;
};

typedef struct _SqlOuputHelper SqlOutputHelper;

@implementation Lite3Table
@synthesize tableName;
@synthesize className;
@synthesize arguments;

-(void)setClassName:(NSString*)_className {
    [className release];
    self->className = _className;
    [className retain];
    [classNameLowerCase release];
    classNameLowerCase = [[className lowercaseString] retain];
    [db addLite3Table: self];
    [self mapToClass: _className];
}




#pragma mark "--- Lite3Table init/factory ---"
-(Lite3Table*)initWithDB:(Lite3DB*)dp{
    db = dp;
    updateStmt = NULL;
    countStmt = NULL;
    dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss Z"];
    return self;
}

- (void)dealloc {
    [dateFormatter release];
    [tableName release];
    [arguments release];
    [className release];
    [classNameLowerCase release];
    if (
        updateStmt != NULL ) {
        sqlite3_finalize(updateStmt);
    }
    if ( countStmt != NULL ) {
        sqlite3_finalize(countStmt);
    }
    [super dealloc];
}

+ (Lite3Table*)lite3TableName:(NSString*)name withDb:(Lite3DB*)_db {

    Lite3Table * pt = [[[Lite3Table alloc] initWithDB: _db ] autorelease];
    pt.tableName = name;
    return pt;

}

+ (Lite3Table*)lite3TableName:(NSString*)name withDb:(Lite3DB*)_db forClassName:(NSString*)_clsName {
    Lite3Table * pt = [Lite3Table lite3TableName:name withDb:_db];
    if ( pt != nil ) {
        pt.className = _clsName;
        [pt compileStatements];
    }
    return pt;
}

- (BOOL)isValid {
    return arguments!=nil && updateStmt != NULL;
}

- (BOOL)compileStatements {
    if ( ! [db compileUpdateStatement: &updateStmt tableName: tableName arguments: arguments] ) {
        return FALSE;
    }
    if ( ![db compileCountStatement: &countStmt tableName: tableName ] ) {
        return FALSE;
    }
    return TRUE;
}


-(Lite3LinkTable*)linkTableFor:(NSString*)propertyName {
    Lite3Arg * arg = [Lite3Arg findByName: propertyName inArray: arguments];
    if ( arg != nil ) {
        return arg.link;
    }
    return nil;
}
#pragma mark "--- Lite3Table database functions ---"
-(BOOL)tableExists {
    NSArray * existing = [db listTables];

    for( NSString * one in existing ) {
        if ( [one compare: tableName] == NSOrderedSame ) {
            return TRUE;
        }
    }
    return FALSE;
}


- (int)updateNoTransaction:(id)data {
    int rc = [self updateOwnTable: data];
    for ( Lite3Arg * arg in arguments ) {
        if ( arg.preparedType == _LITE3_LINK ) {
            [arg.link  updateNoTransaction: data];
        }
    }
    return rc;
}

- (int)update:(id)data {
    [db startTransaction: @"update"];
    int rc = [self updateNoTransaction: data];
    [db endTransaction];
    return rc;
}


-(int)count {
    if ( countStmt == NULL ) {
        return -1;
    }
    int count;
    int rc = sqlite3_step(countStmt);
    [db checkError: rc message: @"Stepping count statement"];
    count =  sqlite3_column_int(countStmt,0);
    rc = sqlite3_reset(countStmt);
    [db checkError: rc message: @"Resetting count statement"];
    return count;

}

- (int) count: (NSString*)whereClause {
    NSArray * result = [self selectOwn:whereClause start: -1 count: -1 withAggregate: @"count" orderBy: nil ];
    NSMutableDictionary * dict = (NSMutableDictionary*)[result objectAtIndex:0];
    return [[dict objectForKey:@"count(*)"] intValue];
}

- (NSArray*) count: (NSString*)whereClause groupBy:(NSString*) property1, ... {
    if ( property1 != nil ) {
        va_list propertyList;
        va_start( propertyList, property1 );
        NSMutableString * groupByClause = [[NSMutableString alloc] initWithFormat: @" group by %@", property1] ;
        NSMutableString * columns = [[NSMutableString alloc] initWithFormat: @"count(*) as count, %@", property1];
        NSString * property;
        while (property = va_arg(propertyList, id)) {
            [columns appendFormat: @", %@", property];
            [groupByClause appendFormat:@", %@", property];

        }
        va_end( propertyList );
        NSArray * ret = [self selectOwn:whereClause expr:columns groupBy:groupByClause];
        [groupByClause release];
        [columns release];
        return ret;
    }
    return nil;

}

- (int)updateAll:(NSArray*)objects {
    NSDate * start = [NSDate date];
    [db startTransaction: @"updateAll"];
    for ( int i=0; i < [objects count]; i++ ) {
        NSDictionary * d = [objects objectAtIndex: i];
        NSDictionary * embedded = [d valueForKey: classNameLowerCase];
        if ( embedded != nil ) {
            d = embedded;
        }
        [self updateNoTransaction: d];
    }
    [db endTransaction];
    NSTimeInterval elapsed = [start timeIntervalSinceNow];
    DLog(@"updateAll %@ duration %f", tableName, -elapsed);
    return [objects count];
}

- (NSMutableArray*)select:(NSString *)whereClause start: (int)start count:(int)count orderBy: (NSString*)orderBy {
    NSMutableArray * rows = [self selectOwn: whereClause start: start count: count withAggregate:nil orderBy: orderBy];
    return rows;
}

-(NSMutableArray*)loadProperty: (NSString*)propertyName forOwner:(id)owner withCache:(NSMutableArray*)cache {
    Lite3Arg * arg = [Lite3Arg findByName: propertyName inArray: arguments];
    NSMutableArray * links = [arg.link selectLinksFor:classNameLowerCase andId: [[owner valueForKey: @"_id"] intValue]];
    //ALog( @"---- main %@ ---- id %d ------ links %@", main, [[main valueForKey: @"_id"] intValue], links );
    if ( links == nil ) {
        return nil;
    }
    NSMutableArray * output = [NSMutableArray array];
    NSString * secondaryIdName = [NSString stringWithFormat: @"%@_id", arg.link.secondaryTable->classNameLowerCase];
    for( id linkEntry in links ) {
        int linkId = [[linkEntry valueForKey:secondaryIdName ] intValue];
        BOOL existing = FALSE;
        if ( cache != nil ) {
            for ( id one in cache ) {
                if ( [[one valueForKey:@"_id" ] intValue] ==  linkId ) {
                    [output addObject: one];
                    existing = TRUE;
                    break;
                }
            }
        }
        if ( !existing ) {
            id one = [arg.link.secondaryTable selectFirst: @"id=%d", linkId];
            if ( one != nil ) {
                [output addObject: one];
            }
            if ( cache != nil ) {
                [cache addObject: one];
            }
        }
    }
    return output;
}

- (NSMutableArray*)filterArray: (NSArray*)pool forOwner:(id)owner andProperty: (NSString*)name {
    Lite3Arg * arg = [Lite3Arg findByName: name inArray: arguments];
    NSMutableArray * links = [arg.link selectLinksFor:classNameLowerCase andId: [[owner valueForKey: @"_id"] intValue]];
    //ALog( @"---- main %@ ---- id %d ------ links %@", main, [[main valueForKey: @"_id"] intValue], links );
    if ( links == nil ) {
        return nil;
    }
    NSMutableArray * output = [NSMutableArray array];
    NSString * secondaryIdName = [NSString stringWithFormat: @"%@_id", arg.link.secondaryTable->classNameLowerCase];
    for( id linkEntry in links ) {
        int linkId = [[linkEntry valueForKey:secondaryIdName ] intValue];
        for ( id one in pool ) {
            if ( [[one valueForKey:@"_id" ] intValue] ==  linkId ) {
                [output addObject: one];
                break;
            }
        }
    }
    return output;

}


- (NSMutableArray*)select:(NSString*)whereClause {
    return [self select: whereClause start: -1 count: -1 orderBy:nil ];
}

- (id)selectFirstOrderBy:(NSString*) orderBy withFormat: (NSString*)whereFormat, ... {
    NSString * whereClause = nil;
    if ( whereFormat != nil ) {
        va_list argumentList;
        va_start( argumentList, whereFormat );
        whereClause = [[[NSString alloc] initWithFormat:whereFormat arguments:argumentList] autorelease];
        va_end( argumentList );
    }
    NSArray * matches = [self select: whereClause start: -1 count: 1 orderBy: orderBy];
    if ( matches == nil || [matches count] == 0 ) {
        return nil;
    }
    return [matches objectAtIndex: 0];

}

/**
 * Allow the user to use a predicate during the search to avoid over-allocating memory.
 * This implementation moves away from using a callback.
 */
-(NSArray*)selectWithPredicate:(id<Lite3Predicate>) predicate sortBy:(NSString*)optionalSort withFormat: (NSString*)whereFormat, ... {
    NSString * whereClause = nil;
    if ( whereFormat != nil ) {
        va_list argumentList;
        va_start( argumentList, whereFormat );
        whereClause = [[NSString alloc] initWithFormat:whereFormat arguments:argumentList];
        va_end( argumentList );
    }
    NSMutableString * sql = [[NSMutableString alloc] initWithFormat:  @"select * from %@", tableName ];
    if ( whereClause != nil ) {
        [sql appendString: @" where " ];
        [sql appendString: whereClause ];
    }
    if ( optionalSort != nil ) {
        [sql appendString: @" order by "];
        [sql appendString: optionalSort ];
    }

    sqlite3_stmt * stmt = NULL;
    NSMutableArray * ret = nil;
    if ( [db compileStatement: &stmt sql: sql] )  {
        ret = [[[NSMutableArray alloc] init] autorelease];
        Class cls = objc_getClass([className cStringUsingEncoding: NSASCIIStringEncoding]);
        while( true ) {
            int rc = sqlite3_step(stmt);
            if ( ![db checkError: rc message: @"Cannot step in the stmt for selectWithPredicate"] ) {
                DLog( @"----Error" );
                break;
            }
            if ( rc != SQLITE_ROW ) {
                DLog( @"Exiting with rc %d", rc );
                break;
            }
            id object  = class_createInstance(cls, 0 );
            int count = sqlite3_column_count(stmt);
            for( int i=0;i<count;i++) {
                const char * name = sqlite3_column_name(stmt,i);
                NSString * nameAsString = [[NSString alloc] initWithCString: name];
                const char * value = (const char *)sqlite3_column_text(stmt,i);
                [self setProperty: nameAsString inObject: object toValue: value ];
                [nameAsString release];
            }
            if ( [predicate matches: object data: ret] ) {
                [ret addObject: object];
            }
            [object release];
            if ( [predicate shouldBreak]) {
                break;
            }

        }
    } else {
        ALog( @"Failed compiling %@.", sql);
    }

    if ( stmt != NULL ) {
        sqlite3_finalize(stmt);
    }

    [whereClause release];
    [sql release];
    return ret;
}


- (id)selectFirst:(NSString*)whereFormat, ... {
    NSString * whereClause = nil;
    if ( whereFormat != nil ) {
        va_list argumentList;
        va_start( argumentList, whereFormat );
        whereClause = [[[NSString alloc] initWithFormat:whereFormat arguments:argumentList] autorelease];
        va_end( argumentList );
    }
    NSArray * matches = [self select: whereClause start: -1 count: 1 orderBy: nil];
    if ( matches == nil || [matches count] == 0 ) {
        return nil;
    }
    return [matches objectAtIndex: 0];

}

-(void)truncate {
    [db startTransaction: @"truncate"];
    for( Lite3Arg * arg in arguments ) {
        if ( arg.preparedType == _LITE3_LINK ) {
            [arg.link.ownTable truncateOwn];
        }
    }
    [self truncateOwn];
    [db endTransaction];
}

- (int)countAssociations:(id)owner forProperty:(NSString*)name {
    Lite3Arg * arg = [Lite3Arg findByName: name inArray: arguments];
    int linkCount = [arg.link countLinksFor:classNameLowerCase andId: [[owner valueForKey: @"_id"] intValue]];
    return linkCount;
}

- (NSArray*)countAssociationsMultiple:(NSArray*)primary forProperty:(NSString*)name {
    // work in progress
    return nil;
}



#pragma mark "-- private implementation --"
- (BOOL)mapToClass: (NSString*)clsName {
    NSMutableArray * _arguments = [[NSMutableArray alloc] init];
    const char * _c = [clsName cStringUsingEncoding: NSASCIIStringEncoding];
    Class cls = objc_getClass(_c);
    if ( cls == nil ) {
        ALog( @"Cannot class '%s'", _c );
        return FALSE;
    }
    objc_property_t * properties = NULL;
    unsigned int outCount;
    properties = class_copyPropertyList( cls, &outCount);
    if ( outCount != 0 ) {
        for( int i=0; i<outCount;i++ ) {
            Lite3Arg * pa = [[Lite3Arg alloc] init];
            const char * propertyName =  property_getName(properties[i]);
            pa.ivar = class_getInstanceVariable( cls, propertyName );
            // by convention bypass initial _
            if ( propertyName[0] == '_' ) {
                propertyName = propertyName+1;
            }
            pa.name = [[NSString alloc] initWithCString: propertyName encoding: NSASCIIStringEncoding];


            const char *attributes = property_getAttributes(properties[i]);
            if ( attributes != NULL ) {
                if ( strncmp(attributes,"Ti",2) == 0 ) {
                    pa.preparedType = _LITE3_INT;
                } else if ( strncmp(attributes,"Td",2) == 0 ) {
                    pa.preparedType = _LITE3_DOUBLE;
                } else if ( strncmp(attributes,"T@\"NSString\"",12) == 0 ) {
                    pa.preparedType = _LITE3_STRING;
                } else if ( strncmp(attributes,"T@\"NSDate\"",10) == 0 ) {
                    pa.preparedType = _LITE3_TIMESTAMP;
                } else if ( strncmp(attributes,"T^@\"", 4 ) == 0 ) {
                    // assume this is a many-to-many relationship and extract the class name
                    const char * comma = strchr( attributes, ',' );
                    comma = comma - 5;
                    NSString * linkedClassName = [NSString stringWithCString: attributes+4 length:(comma-attributes)];
                    Lite3LinkTable * linkTable = [[Lite3LinkTable alloc] initWithDb: db];
                    linkTable.primaryTable = self;
                    linkTable.secondaryClassName = linkedClassName;
                    pa.preparedType = _LITE3_LINK;
                    pa.link = linkTable;
                } else {
                    ALog( @"Need to decode %s in class %@", attributes, clsName );
                }
            }
            if( pa != nil ) {
                [_arguments addObject:pa];
            }
        }
    }
    if ( properties != NULL ) {
        free( properties );
    }
    arguments = _arguments;

    return TRUE;
}

/**
 * Update from the object or dictionary using Key Value access.
 */
- (int)updateOwnTable:(id)data {
    if ( updateStmt == NULL ) {
        ALog( @"No update statement" );
        return -1;
    }
    int rc = sqlite3_clear_bindings(updateStmt);
    [db checkError: rc message: @"Clearing statement bindings"];
    int bindCount = 0;
    BOOL isCreate = FALSE; // track create operations to save the ID back in the object
    for( Lite3Arg * pa in arguments ) {
        if ( pa.preparedType == _LITE3_LINK ) {
            continue;
        }
        bindCount ++;
        id toBind = [data valueForKey:pa.name];
        if ( toBind != nil && toBind != [NSNull null] ) {
            switch (pa.preparedType) {
                case _LITE3_INT: {
                    // check to see if this is an id of 0 and then set the stored proc to null
                    // your database should be created with
                    // "id" INTEGER PRIMARY KEY NOT NULL AUTOINCREMENT
                    int value = [toBind intValue];
                    if ( [pa.name isEqualToString: @"id"]  && value == 0 ) {
                        rc = sqlite3_bind_null( updateStmt, bindCount );
                        isCreate = TRUE;
                    } else {
                        rc = sqlite3_bind_int(updateStmt, bindCount, value);
                    }
                    [db checkError: rc message: @"Binding int"];
                }
                    break;
                case _LITE3_DOUBLE:
                    rc = sqlite3_bind_double(updateStmt, bindCount, [toBind floatValue]);
                    [db checkError: rc message: @"Binding float"];
                    break;
                case _LITE3_STRING:
                {
                    const char * cString = [toBind UTF8String];
                    rc = sqlite3_bind_text(updateStmt, bindCount, cString, strlen(cString), NULL);
                    [db checkError: rc message: @"Binding string"];
                }
                    break;
                case _LITE3_TIMESTAMP: {
                    const char * cString = [[toBind description] UTF8String];
                    rc = sqlite3_bind_text(updateStmt, bindCount, cString, strlen(cString), NULL );
                    [db checkError: rc message: @"Binding timestamp"];
                }
                    break;
                default:
                    break;
            }
        }
    }
    rc = sqlite3_step(updateStmt);
    sqlite_int64 lastId = sqlite3_last_insert_rowid(db.dbHandle);
    //ALog( @"last id: %d", lastId );
    if ( lastId == 0 ) {
        ALog( @"No value inserted" );
    }
    if ( isCreate ) {
        [self setProperty:@"id" inObject: data toInt: (int)lastId];
    }

    [db checkError: rc message: @"Getting last insert row"];
    rc = sqlite3_reset(updateStmt);
    [db checkError: rc message: @"Resetting statement" ];
    return lastId;
}

/**
 * Do a select in our own table (as opposed to the link tables).
 */
- (NSMutableArray*)selectOwn:(NSString *)whereClause start: (int)start count:(int)count withAggregate:(NSString*)aggregate orderBy:(NSString*) orderBy {
    struct _SqlOutputHelper outputHelper;
    outputHelper.output = [NSMutableArray array];
    if ( aggregate == nil ) {
        outputHelper.cls = objc_getClass([className cStringUsingEncoding: NSASCIIStringEncoding]);
    } else {
        // passing a class does not make sense when aggregate functions are passed in.
        outputHelper.cls = NULL;
    }
    outputHelper.preparedTable = self;
    char *zErrMsg = NULL;
    NSString * sql;
    NSMutableString * limit = [[NSMutableString alloc] init];
    if ( orderBy != nil && [orderBy length] > 0 ) {
        [limit appendFormat : @" order by %@", orderBy];
    }
    if ( count > -1 ) {
        [limit appendFormat: @" limit %d", count ];
    }
    if ( start > -1 ) {
        [limit appendFormat: @" offset %d", start ];
    }
    NSString * selectExpr = @"*";
    if ( aggregate != nil ) {
        selectExpr = [NSString stringWithFormat: @"%@(*)", aggregate];
    }
    if ( whereClause == nil ) {
        sql = [NSString stringWithFormat: @"select %@ from %@%@", selectExpr, tableName, limit];
    } else {
        sql = [NSString stringWithFormat: @"select %@ from %@ where %@%@", selectExpr, tableName, whereClause, limit];
    }
    [limit release];
    //ALog( @"SQL SQL SQL %@", sql );
    int rc = sqlite3_exec(db.dbHandle, [sql UTF8String], multipleRowCallback, (void*)&outputHelper, &zErrMsg);
    if ( zErrMsg != NULL ) {
        sqlite3_free(zErrMsg);
    }
    [db checkError: rc message: @"Executing select statement"];
    return outputHelper.output;
}

- (NSMutableArray*)selectOwn:(NSString *)whereClause expr:(NSString*)expr groupBy:(NSString*)groupBy {
    struct _SqlOutputHelper outputHelper;
    outputHelper.output = [NSMutableArray array];
    outputHelper.cls = NULL;
    outputHelper.preparedTable = self;
    char *zErrMsg = NULL;
    NSString * sql;
    if ( whereClause == nil ) {
        sql = [NSString stringWithFormat: @"select %@ from %@%@", expr, tableName, groupBy];
    } else {
        sql = [NSString stringWithFormat: @"select %@ from %@ where %@%@", expr, tableName, whereClause, groupBy];
    }
    //ALog( @"SQL SQL SQL %@", sql );
    int rc = sqlite3_exec(db.dbHandle, [sql UTF8String], multipleRowCallback, (void*)&outputHelper, &zErrMsg);
    if ( zErrMsg != NULL ) {
        sqlite3_free(zErrMsg);
    }
    [db checkError: rc message: @"Executing select statement"];
    return outputHelper.output;
}

- (void)truncateOwn {
    char *zErrMsg = NULL;
    NSString * sql = [NSString stringWithFormat: @"delete from %@", tableName];
    int rc = sqlite3_exec(db.dbHandle, [sql UTF8String], multipleRowCallback, NULL, &zErrMsg);
    if ( zErrMsg != NULL ) {
        sqlite3_free(zErrMsg);
    }
    [db checkError: rc message: @"Truncating table"];

}

-(void) setProperty:(NSString *) name inObject: (id) object toInt:(int) value  {
    Lite3Arg * pa = [Lite3Arg findByName:name inArray: arguments];
    void ** varIndex = (void **)((char *)object + ivar_getOffset(pa.ivar));
    *(long*)varIndex = value;
}

-(void) setProperty:(NSString *) name inObject: (id) object toValue: (const char *) value  {
    Lite3Arg * pa = [Lite3Arg findByName:name inArray: arguments];
    if ( pa == nil ) {
        return;
    }
    if ( [name isEqualToString: @"id"]) {
        name = @"_id";
    }

    void ** varIndex = (void **)((char *)object + ivar_getOffset(pa.ivar));
    if ( varIndex == NULL ) {
        ALog( @"----VAR INDEX IS NULL for %@ object %p", name, object );
        return;
    }
    switch ( pa.preparedType ) {
        case _LITE3_INT: {
            long extracted = value == NULL? 0: atol( value );
            *(long*)varIndex = extracted;
        }
            break;
        case _LITE3_DOUBLE: {
            double extracted = value == NULL ? 0.0: atof( value );
            *(double*)varIndex = extracted;
        }
            break;
        case _LITE3_STRING: {
            if ( value != NULL ) {
                NSString * extracted = [[NSString stringWithCString:value encoding:NSUTF8StringEncoding] retain];
                object_setInstanceVariable( object, [name UTF8String], extracted );
            }
        } break;
        case _LITE3_TIMESTAMP: {
            if ( value != nil ) {
                NSDate * extracted = [[dateFormatter dateFromString:[NSString stringWithCString:value encoding:NSUTF8StringEncoding]] retain];
                object_setInstanceVariable( object, [name UTF8String], extracted );
            }
        } break;
    }
}


static int multipleRowCallback(void *helperP, int columnCount, char **values, char **columnNames) {
    if ( helperP == NULL ) {
        return 0;
    }
    struct _SqlOutputHelper * helper = (struct _SqlOutputHelper*)helperP;

    id object;
    if ( helper->cls != nil ) {
        object = class_createInstance(helper->cls, 0 );
    } else {
        object = [[NSMutableDictionary alloc] init];
    }
    int i;
    for(i=0; i<columnCount; i++) {

        const char * name = columnNames[i];
        const char * value = values[i];
        if ( value == NULL ) {
            continue;
        }
        NSString * nameAsString = [[NSString alloc] initWithCString: name];
        if (helper->cls == nil ) {
            // we don't have an user class backing this table
            [object setValue: [[NSString alloc] initWithCString: value] forKey: nameAsString];
        } else {
            [helper->preparedTable setProperty: nameAsString inObject: object toValue: value ];
        }
        [nameAsString release];
    }
    [helper->output addObject: object];
    return 0;
}




@end

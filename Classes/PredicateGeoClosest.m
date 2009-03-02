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
#import "PredicateGeoClosest.h"
#import "De_co_de_Utils.h"

@implementation PredicateGeoClosest
@synthesize lat;
@synthesize lon;
@synthesize maxDistance;
@synthesize maxCount;

- (bool)matches: (id)object data:(NSArray*)_data {
    if ( [_data count] > maxCount ) {
        _shouldBreak = true;
        return false;
    }
    if ( maxDistance > calculateDistance( [object lat], [object lon], lat, lon ) ) {
        return true;
    }
    return false;
}

- (bool)shouldBreak {
    return _shouldBreak;
}
@end

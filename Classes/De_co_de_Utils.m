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

#import "De_co_de_Utils.h"


@implementation De_co_de_Utils



/**
 * Helper function for base63 coding, assumes input and memory has been setup properly.
 */
int base64_block( unsigned char * in3, int in_len, unsigned char * data_out, int out_len ) {
    static unsigned char alphabet[64] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    unsigned char out4[4];
    for(int i=in_len; i < 3; i++) {
        in3[i] = '\0';
    }
    
    out4[0] = (in3[0] & 0xfc) >> 2;
    out4[1] = ((in3[0] & 0x03) << 4) + ((in3[1] & 0xf0) >> 4);
    out4[2] = ((in3[1] & 0x0f) << 2) + ((in3[2] & 0xc0) >> 6);
    out4[3] = in3[2] & 0x3f;
    
    for(int i = 0; (i <in_len+1) ; i++) {
        data_out[out_len++] = alphabet[out4[i]];
    }
    while ( in_len++ < 3 ) {
        data_out[out_len++] = '=';        
    }
    return out_len;
}

/**
 * Encode a string in base64
 */
+(NSString*) base64_encode:(const char *) data_in length: (int) len {
    
    int i = 0;
    unsigned char in3[3];
    unsigned char * data_out = alloca(len);
    int out_len=0;
    
    while (len--) {
        in3[i++] = *(data_in++);
        if (i == 3) {
            out_len = base64_block( in3, i, data_out, out_len );
            i = 0;
        }
    }
    
    if (i) {
        out_len = base64_block( in3, i, data_out, out_len );
    }
    data_out[out_len]=0;
    
    return [NSString stringWithCString: (const char*)data_out length: out_len];
    
}

+(NSString*) basicAuthorizationUser: (NSString*) username password: (NSString*) password {
    NSString *tmp = [NSString stringWithFormat:@"%@:%@", username, password];
    NSString *data64 = [De_co_de_Utils base64_encode:[tmp cStringUsingEncoding: NSASCIIStringEncoding ] length:[tmp length]];
    return [NSString stringWithFormat:@"Basic %@", data64];
}

@end

/**
 * Transform from degrees to radians.
 */
double toRad(double degrees) {
    return degrees * M_PI / 180;
};

/**
 * Compute (approximate) the distance between the two points.
 */
double calculateDistance( double nLat1, double nLon1, double nLat2, double nLon2 ) {
    double nRadius = 3958.7; // Earth radius miles
    // Get the difference between our two points 
    // then convert the difference into radians
    double nDLat = toRad(nLat2 - nLat1);  
    double nDLon = toRad(nLon2 - nLon1); 
    
    nLat1 =  toRad(nLat1);
    nLat2 =  toRad(nLat2);
    double nA = pow ( sin(nDLat/2), 2 ) + cos(nLat1) * cos(nLat2) * pow ( sin(nDLon/2), 2 );
    
    double nC = 2 * atan2( sqrt(nA), sqrt( 1 - nA ));
    
    double nD = nRadius * nC;
    
    return nD; 
}

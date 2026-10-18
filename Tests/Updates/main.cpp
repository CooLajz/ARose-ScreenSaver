#include "../../Windows/Updates/UpdatePolicy.h"
#include <cstdlib>
int main() {
    if(!updates::due(0,1) || updates::due(100,100) || updates::due(100,604899) || !updates::due(100,604900) || !updates::due(100,99))return EXIT_FAILURE;
}

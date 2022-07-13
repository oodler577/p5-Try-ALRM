use strict;
use warnings;

use Try::ALRM;

alarm { 5 }
try {
  local $|=1;
  print qq{ doing something that might timeout ...\n};
  sleep 6;
}
ALRM {
  print qq{ Alarm Clock!!!!\n};
};

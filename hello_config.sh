# Basic configuration

# Public key to copy over
ID='/home/elana/.ssh/id_slack'

# IP addresses for the hosts you wish to configure
HOSTS='REDACTED1 REDACTED2'

# Working directory
WORKING_DIRECTORY='/tmp/config'

# Packages to be installed with aptitude
APTITUDE_PACKAGES='apache2 php5'

# Remote directories to create. Note path names cannot contain spaces
REMOTE_DIRECTORIES=('/srv/hello-web')

# Configuration files to copy to remote locations. Note paths cannot contain
# spaces.
# FIXME: I'd like to use pairs or something here but associative arrays are a 
# bash 4.0 thing, which means I wouldn't be able to claim bash was a good 
# choice for "portability", hence this convention.
REMOTE_CONFIGURATIONS=('index.php /srv/hello-web' 'hello.conf /etc/apache2/sites-available')

# Commands to run on the remote hosts, in order
REMOTE_COMMANDS=('a2dissite 000-default' 'a2ensite hello' 'service apache2 reload')

# Optional test commands to run post-configuration.
TEST_COMMANDS=('[[ "`curl -s http://$host`" == "Hello, world!" ]]')

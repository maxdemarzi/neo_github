neo_github
==========

A look at the github archive


Installation
----------------

    git clone git@github.com:maxdemarzi/neo_github.git
    bundle install
    rake neo4j:install
    rake neo4j:start
    rake neo4j:create
    rackup

On Heroku
---------

    git clone git@github.com:maxdemarzi/neo_hubway.git
    heroku apps:create neohubway
    heroku addons:add neo4j
    heroku rake neo4j:create
    git push heroku master

See it running live at http://neogithub.heroku.com

![Screenshot](https://raw.github.com/maxdemarzi/neo_github/master/neo_github.png)
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd">

    <servers>
        <server>
            <id>releases</id>
            <username>{ARTIFACTORY_USERNAME}</username>
            <password>{ARTIFACTORY_PASSWORD}</password>
        </server>
        <server>
            <id>snapshots</id>
            <username>{ARTIFACTORY_USERNAME}</username>
            <password>{ARTIFACTORY_PASSWORD}</password>
        </server>
    </servers>

    <profiles>
        <profile>
            <repositories>
                <repository>
                    <snapshots>
                        <enabled>false</enabled>
                    </snapshots>
                    <releases>
                        <enabled>true</enabled>
                    </releases>
                    <id>releases</id>
                    <name>libs-release</name>
                    <url>https://{ARTIFACTORY_HOST}/artifactory/libs-release</url>
                </repository>
                <repository>
                    <snapshots>
                        <enabled>true</enabled>
                    </snapshots>
                    <releases>
                        <enabled>false</enabled>
                    </releases>
                    <id>snapshots</id>
                    <name>libs-snapshot</name>
                    <url>https://{ARTIFACTORY_HOST}/artifactory/libs-snapshot</url>
                </repository>
            </repositories>

            <pluginRepositories>
                <pluginRepository>
                    <snapshots>
                        <enabled>false</enabled>
                    </snapshots>
                    <releases>
                        <enabled>true</enabled>
                    </releases>
                    <id>releases</id>
                    <name>libs-release</name>
                    <url>https://{ARTIFACTORY_HOST}/artifactory/libs-release</url>
                </pluginRepository>
                <pluginRepository>
                    <snapshots>
                        <enabled>true</enabled>
                    </snapshots>
                    <releases>
                        <enabled>false</enabled>
                    </releases>
                    <id>snapshots</id>
                    <name>libs-snapshot</name>
                    <url>https://{ARTIFACTORY_HOST}/artifactory/libs-snapshot</url>
                </pluginRepository>
            </pluginRepositories>

            <id>artifactory-ibk</id>
        </profile>
    </profiles>

    <activeProfiles>
        <activeProfile>artifactory-ibk</activeProfile>
    </activeProfiles>
</settings>
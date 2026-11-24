/**
 * Tibia GIMUD Server - a free and open-source MMORPG server emulator
 * Copyright (C) 2017  Alejandro Mujica <alejandrodemujica@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include "otpch.h"

#include "configmanager.h"
#include "databasemanager.h"
#include "luascript.h"
#include "sqlidentifier.h"

extern ConfigManager g_config;

bool DatabaseManager::optimizeTables()
{
	Database* db = Database::getInstance();
	std::ostringstream query;

	std::string escapedDatabase;
	if (!db->escapeString(g_config.getString(ConfigManager::MYSQL_DB), escapedDatabase)) return false;
	query << "SELECT `TABLE_NAME` FROM `information_schema`.`TABLES` WHERE `TABLE_SCHEMA` = " << escapedDatabase << " AND `DATA_FREE` > 0";
	DBResult_ptr result = db->storeQuery(query.str());
	if (!result) {
		return false;
	}

	do {
		std::string tableName = result->getString("TABLE_NAME");
		std::cout << "> Optimizing table " << tableName << "..." << std::flush;

		query.str(std::string());
		query << "OPTIMIZE TABLE " << quoteSqlIdentifier(tableName);

		if (db->executeQuery(query.str())) {
			std::cout << " [success]" << std::endl;
		} else {
			std::cout << " [failed]" << std::endl;
		}
	} while (result->next());
	return true;
}

bool DatabaseManager::tableExists(const std::string& tableName, bool* querySucceeded)
{
	if (querySucceeded) *querySucceeded = false;
	Database* db = Database::getInstance();

	std::string escapedDatabase;
	std::string escapedTable;
	if (!db->escapeString(g_config.getString(ConfigManager::MYSQL_DB), escapedDatabase)
		|| !db->escapeString(tableName, escapedTable)) return false;

	std::ostringstream query;
	query << "SELECT `TABLE_NAME` FROM `information_schema`.`tables` WHERE `TABLE_SCHEMA` = " << escapedDatabase << " AND `TABLE_NAME` = " << escapedTable << " LIMIT 1";
	bool succeeded = false;
	DBResult_ptr result = db->storeQuery(query.str(), &succeeded);
	if (querySucceeded) *querySucceeded = succeeded;
	return result != nullptr;
}

bool DatabaseManager::isDatabaseSetup(bool* querySucceeded)
{
	if (querySucceeded) *querySucceeded = false;
	Database* db = Database::getInstance();
	std::string escapedDatabase;
	if (!db->escapeString(g_config.getString(ConfigManager::MYSQL_DB), escapedDatabase)) return false;
	std::ostringstream query;
	query << "SELECT `TABLE_NAME` FROM `information_schema`.`tables` WHERE `TABLE_SCHEMA` = " << escapedDatabase;
	bool succeeded = false;
	DBResult_ptr result = db->storeQuery(query.str(), &succeeded);
	if (querySucceeded) *querySucceeded = succeeded;
	return result != nullptr;
}


#include "otpch.h"

#include "npcambient.h"
#include "tools.h"

#include <fstream>
#include <sstream>

std::unordered_map<std::string, NpcAmbientLines> NpcAmbient::table;
std::unordered_map<uint32_t, int64_t> NpcAmbient::areaLast;

namespace {

void trimLine(std::string& s)
{
	while (!s.empty() && (s.back() == '\r' || s.back() == '\n' || s.back() == ' ' || s.back() == '\t')) {
		s.pop_back();
	}
	size_t start = 0;
	while (start < s.size() && (s[start] == ' ' || s[start] == '\t')) {
		++start;
	}
	s.erase(0, start);
}

bool startsWith(const std::string& s, const char* prefix, size_t len)
{
	return s.size() >= len && s.compare(0, len, prefix) == 0;
}

}

bool NpcAmbient::parse(const std::string& text, std::unordered_map<std::string, NpcAmbientLines>& out)
{
	std::istringstream in(text);
	std::string line;
	NpcAmbientLines* current = nullptr;
	while (std::getline(in, line)) {
		trimLine(line);
		if (line.empty() || line[0] == '#') {
			continue;
		}

		if (line[0] == '[') {
			size_t end = line.find(']');
			if (end == std::string::npos || end < 2) {
				current = nullptr;
				continue;
			}
			std::string key = asLowerCaseString(line.substr(1, end - 1));
			trimLine(key);
			current = &out[key];
			continue;
		}

		if (!current) {
			continue;
		}

		if (startsWith(line, "night:", 6)) {
			std::string t = line.substr(6);
			trimLine(t);
			if (!t.empty()) {
				current->night.push_back(t);
			}
		} else if (startsWith(line, "day:", 4)) {
			std::string t = line.substr(4);
			trimLine(t);
			if (!t.empty()) {
				current->day.push_back(t);
			}
		} else {
			current->any.push_back(line);
		}
	}
	return true;
}

bool NpcAmbient::load(const std::string& filename)
{
	std::ifstream file(filename, std::ios::binary);
	if (!file) {
		table.clear();
		return false;
	}

	std::ostringstream buffer;
	buffer << file.rdbuf();

	std::unordered_map<std::string, NpcAmbientLines> fresh;
	parse(buffer.str(), fresh);
	table.swap(fresh);
	areaLast.clear();
	return true;
}

const NpcAmbientLines* NpcAmbient::get(const std::string& key)
{
	auto it = table.find(key);
	if (it == table.end()) {
		return nullptr;
	}
	return &it->second;
}

const std::string* NpcAmbient::pick(const NpcAmbientLines& lines, bool night, int32_t& lastIndex)
{
	const std::vector<std::string>& timed = night ? lines.night : lines.day;
	const size_t total = lines.any.size() + timed.size();
	if (total == 0) {
		return nullptr;
	}

	int32_t index = uniform_random(0, static_cast<int32_t>(total) - 1);
	if (total > 1 && index == lastIndex) {
		index = (index + 1 + uniform_random(0, static_cast<int32_t>(total) - 2)) % static_cast<int32_t>(total);
	}
	lastIndex = index;

	if (static_cast<size_t>(index) < lines.any.size()) {
		return &lines.any[index];
	}
	return &timed[index - lines.any.size()];
}

bool NpcAmbient::claimArea(uint16_t x, uint16_t y, uint8_t z, int64_t now)
{
	const uint32_t key = (static_cast<uint32_t>(x >> 4) << 16) | (static_cast<uint32_t>(y >> 4) << 4) | (z & 0x0F);
	auto it = areaLast.find(key);
	if (it != areaLast.end() && now - it->second < AREA_GAP) {
		return false;
	}
	areaLast[key] = now;
	return true;
}

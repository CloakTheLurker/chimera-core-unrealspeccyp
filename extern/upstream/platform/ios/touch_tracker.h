/*
Portable ZX-Spectrum emulator.
Copyright (C) 2001-2016 SMT, Dexus, Alone Coder, deathsoft, djdron, scor

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef __TOUCH_TRACKER_H__
#define __TOUCH_TRACKER_H__

#pragma once

#include <vector>

#pragma once

namespace xPlatform
{

class eTouchTracker
{
public:
	int Process(const void* touch, bool on);
private:
	typedef std::vector<const void*> eTouches;
	eTouches touches;
};

}
//namespace xPlatform

#endif//__TOUCH_TRACKER_H__

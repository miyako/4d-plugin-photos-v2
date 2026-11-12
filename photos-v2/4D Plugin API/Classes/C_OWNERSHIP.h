#ifndef C_OWNERSHIP_H
#define C_OWNERSHIP_H

#include "4DPluginAPI.h"
#include <stdexcept>

template<size_t N> class C_VariableArguments
{
	PA_Variable _values[N];
	C_VariableArguments(const C_VariableArguments&);
	C_VariableArguments& operator=(const C_VariableArguments&);
public:
	C_VariableArguments()
	{
		for(size_t i = 0; i < N; ++i)
			_values[i] = PA_CreateVariable(eVK_Undefined);
	}
	~C_VariableArguments()
	{
		for(size_t i = 0; i < N; ++i)
			PA_ClearVariable(&_values[i]);
	}
	PA_Variable& operator[](size_t i) { return _values[i]; }
	PA_Variable* data() { return _values; }
};

inline void C_ExecuteCommand(PA_long32 command, PA_Variable* args, short count)
{
	PA_Variable result = PA_ExecuteCommandByID(command, args, count);
	const PA_ErrorCode error = PA_GetLastError();
	if(error != eER_NoErr)
		throw std::runtime_error("4D command failed");
	PA_ClearVariable(&result);
}

inline void C_ResizeArray(PA_Variable& array, PA_long32 count, bool ownsArray = false)
{
	if(!array.uValue.fArray.fData)
		throw std::runtime_error("4D array allocation failed");
	const PA_long32 oldCount = array.uValue.fArray.fNbElements;
	if(count == oldCount)
		return;
	PA_ResizeArray(&array, count);
	const PA_ErrorCode error = PA_GetLastError();
	if(error != eER_NoErr)
	{
		// The SDK changes the count even when the handle allocation fails.
		array.uValue.fArray.fNbElements = oldCount;
		if(ownsArray)
			PA_ClearVariable(&array);
		throw std::runtime_error("4D array resize failed");
	}
}

#endif

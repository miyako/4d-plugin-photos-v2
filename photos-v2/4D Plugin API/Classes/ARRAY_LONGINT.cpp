/*
 *  ARRAY_LONGINT.cpp
 *  4D Plugin
 *
 *  Created by miyako on 11/01/03.
 *
 */

#include "ARRAY_LONGINT.h"
#include "C_OWNERSHIP.h"

void ARRAY_LONGINT::fromParamAtIndex(PackagePtr pParams, uint32_t index)
{	
	if(index)		
	{
		PA_Variable arr = *((PA_Variable*) pParams[index - 1]);

		this->setSize(0);
		
		if(arr.fType == eVK_ArrayLongint && arr.uValue.fArray.fData)
		{
			uint32_t i;
			
			int intValue;
			
			for(i = 0; i <= (unsigned int)arr.uValue.fArray.fNbElements; i++)
			{
				intValue = ( * (int**) (arr.uValue.fArray.fData) )[i];
				this->_CIntArray->push_back(intValue);				
			}
			
		}
		
	}
			
}

void ARRAY_LONGINT::toParamAtIndex(PackagePtr pParams, uint32_t index)
{
	if(index)		
	{
		PA_Variable arr = *((PA_Variable*) pParams[index - 1]);
		PA_Variable *param = ((PA_Variable *)pParams[index - 1]);
		const bool ownsArray = arr.fType == eVK_Undefined;
		
		switch (arr.fType) 
		{
			case eVK_ArrayLongint:
				break;
			case eVK_Undefined:
				PA_ClearVariable(&arr);
				arr = PA_CreateVariable(eVK_ArrayLongint);
				break;				
				
			default:
				break;
		}		
		
		if(arr.fType == eVK_ArrayLongint)
		{
			
			C_ResizeArray(arr, this->_CIntArray->empty() ? 0 : (uint32_t)(this->_CIntArray->size() - 1), ownsArray);
			
			uint32_t i;
			
			for(i = 0; i < this->_CIntArray->size(); i++)
			{
				PA_SetLongintInArray(arr, i, this->_CIntArray->at(i));	
			}
			
			param->fType = arr.fType;
			param->fFiller = 0;
			param->uValue.fArray.fCurrent = arr.uValue.fArray.fCurrent;
			param->uValue.fArray.fNbElements = arr.uValue.fArray.fNbElements;
			param->uValue.fArray.fData = arr.uValue.fArray.fData;	
			
		}
		
	}
				
}

void ARRAY_LONGINT::appendIntValue(int intValue)
{
	this->_CIntArray->push_back(intValue);	
}

void ARRAY_LONGINT::setIntValueAtIndex(int intValue, uint32_t index)
{
	if(index < this->_CIntArray->size())
	{
		
		std::vector<int>::iterator it = this->_CIntArray->begin();
		it += index;
		
		this->_CIntArray->insert(this->_CIntArray->erase(it), intValue);
		
	}
}

int ARRAY_LONGINT::getIntValueAtIndex(uint32_t index)	
{
	
	int intValue = 0;
	
	if(index < this->_CIntArray->size())
	{
		
		intValue = this->_CIntArray->at(index);
	}
	
	return intValue;
	
}

uint32_t ARRAY_LONGINT::getSize()
{
	return (uint32_t)this->_CIntArray->size();
}

void ARRAY_LONGINT::setSize(uint32_t size)
{
	this->_CIntArray->resize(size);
}

ARRAY_LONGINT::ARRAY_LONGINT() : _CIntArray(new CIntArray)
{
	
}

ARRAY_LONGINT::~ARRAY_LONGINT()
{ 
	delete _CIntArray; 
}
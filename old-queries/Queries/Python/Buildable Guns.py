# -*- coding: utf-8 -*-
"""
Program to Take the Master BOM File and build out a lit of every part that goes into every gun at the indent level
"""
# %% Import Libraries

import pandas as pd
import numpy as np

# %% Get Data Functions

def import_data():
    df = pd.read_csv('C:/Users/tylerw.CARMS/Desktop/MASTER BOM.csv', dtype={'INDENT_LEVEL':int})
    return df

def import_part_data():
    part_df = pd.read_excel('C:/Users/tylerw.CARMS/Desktop/Part Quantities.xlsx')
    return part_df
    

# %% This Merges the Data and Creates the datasets
df = import_data()
part_df = import_part_data()
part_df2 = import_part_data()

df = pd.merge(df, part_df, how ='inner', left_on='SUBORD_PART_ID', right_on='ID')
df = df.rename(columns={'PRODUCT_CODE':'PRODUCT_CODE_SUB'})

part_df = part_df.drop(['QTY_ON_HAND'], axis=1)

df = pd.merge(df, part_df, how ='inner', left_on='PARENT_PART_ID', right_on='ID')
df = df.rename(columns={'PRODUCT_CODE':'PRODUCT_CODE_PAR'})

df['Difference'] = df['QTY_ON_HAND'] - df['QTY_PER']

df['Status'] = np.where(df['Difference'] > 0,0,1)

Level_1 = df[df['LEVEL_INDICATOR']==1 & df['PRODUCT_CODE_PAR'].isin (['RANGER 22','MESA','MESA TI','MESA FFT','MESA-LR','MPR','MPR-STEEL','BA TACTICAL','TFM','RIDGELINE','RIDGELINE TI','RIDGELINE SCOUT','RIDGELINE FFT','ELR','SUMMIT','CA-15 G2','CA-10 DMR','TRAVERSE'])] 
Level_1 = Level_1.drop(['INDENT_LEVEL','LEVEL_INDICATOR','ID_x','ID_y'], axis = 1)

guns = Level_1[['PARENT_PART_ID','PARENT_PART_DESCRIPTION','Status']]
guns['Descriptor'] = guns['PARENT_PART_ID']+' - '+guns['PARENT_PART_DESCRIPTION']
n_guns = pd.pivot_table(guns, values='Status', index= 'Descriptor', columns=None,aggfunc=sum)

n_guns=n_guns.rename(columns={'Status':'Parts Missing'})
buildable_guns = n_guns[n_guns['Parts Missing'] ==0]
guns_missing_pieces = n_guns[n_guns['Parts Missing'] > 0]

#%% Write the information to an Excel file

writer = pd.ExcelWriter('C:/Users/tylerw.CARMS/Desktop/Buildable Guns.xlsx', engine ='xlsxwriter')

buildable_guns.to_excel(writer, sheet_name='Buildable Guns')
guns_missing_pieces.to_excel(writer, sheet_name='Missing Pieces')
Level_1.to_excel(writer, sheet_name='Level 1')
part_df2.to_excel(writer, sheet_name='Parts_On_Hand')

writer.save()



import pandas as pd
import numpy as np
import matplotlib.pyplot as pyplot
import seaborn as sns

def import_data():
    df = pd.read_excel('C:/Users/tylerw.CARMS/Desktop/Forecasting 2022/Weekly Orders.xlsx', 'Sheet2')
    df['Period'] = df['Year'].astype(str)+"-"+df['Week'].astype(str).str.zfill(2)
    df = df.set_index(['Period'], drop=True)
    df = df.drop(['Year'],axis =1)
    df = df.drop(['Week'],axis =1)
    df1 = df.transpose()
    return df, df1

df, df1 = import_data()

import pickle
model = pickle.load(open('C:/Users/tylerw.CARMS/Desktop/Forecasting 2022/13 week predictor model.sav', 'rb'))

result = model.predict(df1)
print(result)

# -*- coding: utf-8 -*-
"""
Created on Mon May  2 17:31:58 2022

@author: TylerW
"""
#Functions

#This function runs SQL queries on VECA
def run_sql(sql):
    server = '3CARMS\CAPROD'
    database = 'VECA'
    username = 'TYLWHI'
    password = 'Whit123#'

    cnxn = pyodbc.connect('DRIVER={ODBC Driver 17 for SQL Server};SERVER='+server+';DATABASE='+database+';UID='+username+';PWD='+ password)
    #cursor = cnxn.cursor()
    data = pd.read_sql(sql,cnxn)
    return data

#This function creates the excel files for the open order reports
def create_files(send_list):
    for i in send_list:
        cust_order = open_orders.loc[open_orders['Customer_ID'] == i]
        cust_order.to_excel('V:/018 - FP&A/Queries/Open Order Mailings/Excel Reports/'+i+'.xlsx', index=False)

# This function reads the SQL files in as strings to search
def get_sql():
    customer_sql = open('V:/018 - FP&A/Queries/Open Order Mailings/SQL/Mailing Customer IDs.sql','r').read()
    order_sql = open('V:/018 - FP&A/Queries/Open Order Mailings/SQL/Open Order Report for Mailings.sql','r').read()
    return customer_sql, order_sql



#%% Get The Data from the server

#import libraries
import pyodbc 
import pandas as pd

#get the customer data
customer_sql, order_sql = get_sql()
open_orders = run_sql(order_sql)
customer_list = run_sql(customer_sql)

#create a list of sendors
send_list = customer_list['CUSTOMER_ID'].values.tolist()
#Create the excel files
create_files(send_list)



#%% send the emails out to the right people.
import win32com.client as win32

for i in send_list:
    outlook = win32.Dispatch('outlook.application')
    mail = outlook.CreateItem(0)
    mail.To = customer_list['CONTACT_EMAIL'].loc[customer_list['CUSTOMER_ID'] == i].to_string(index = False)
    mail.Subject = 'Christensen Arms Open Order Report'
    mail.Body = 'Christensen Arms Open Order Report'
    mail.HTMLBody = '<h2>Christensen Arms Open Order Report</h2>' #this field is optional

    # To attach a file to the email (optional):
    attachment  = "V:/018 - FP&A/Queries/Open Order Mailings/Excel Reports/"+i+".xlsx"
    mail.Attachments.Add(attachment)

    mail.Send()
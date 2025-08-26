import csv, random, uuid, datetime as dt
random.seed(42)

N_CUSTOMERS=400; N_PRODUCTS=300; N_ORDERS=1000; N_ITEMS=3000
today = dt.date.today()

# customers
cust=[]
with open('ecommerce_customers.csv','w',newline='') as f:
    w=csv.writer(f); w.writerow(['customer_id','first_name','last_name','email','signup_date','country','state_province','city'])
    for i in range(1,N_CUSTOMERS+1):
        fn=random.choice(['Sam','Jamie','Avery','Jordan','Riley','Taylor','Alex','Casey','Morgan','Cameron'])
        ln=random.choice(['Souza','Costa','Miller','Brown','Silva','Santos','Oliveira','Williams','Johnson','Lee'])
        email=f"{fn.lower()}.{ln.lower()}{i}@example.com"
        d = today - dt.timedelta(days=random.randint(30,1200))
        country=random.choice(['US','CA','BR'])
        state=random.choice(['CA','NY','TX','WA','ON','BC','SP','RJ','PR'])
        city=random.choice(['SF','NYC','Austin','Seattle','Toronto','Vancouver','Sao Paulo','Rio','Curitiba'])
        w.writerow([i,fn,ln,email,d.isoformat(),country,state,city]); cust.append(i)

# products
pro=[]
with open('ecommerce_products.csv','w',newline='') as f:
    w=csv.writer(f); w.writerow(['product_id','product_name','category','brand','unit_price','is_active'])
    for i in range(1,N_PRODUCTS+1):
        cat=random.choice(['Electronics','Books','Home','Clothing','Beauty'])
        brand=random.choice(['Acme','Globex','Umbrella','Initech','Soylent'])
        price=round(random.uniform(5,500),2)
        w.writerow([i,f'Product {i}',cat,brand,price,random.choice([True,True,True,False])]); pro.append(i)

# orders
orders=[]
with open('ecommerce_orders.csv','w',newline='') as f:
    w=csv.writer(f); w.writerow(['order_id','customer_id','order_date','status','payment_method','gross_amount','discount_amount','net_amount','currency'])
    for i in range(1,N_ORDERS+1):
        cid=random.choice(cust)
        date = today - dt.timedelta(days=random.randint(0,365))
        status=random.choice(['completed','completed','completed','pending','canceled'])
        pay=random.choice(['card','pix','paypal','boleto'])
        gross=round(random.uniform(20,800),2)
        disc=round(gross*random.choice([0,0,0.05,0.1]),2)
        net=round(gross-disc,2)
        w.writerow([i,cid,date.isoformat(),status,pay,gross,disc,net,'USD'])
        orders.append(i)

# order_items (consistentes com orders/products)
with open('ecommerce_order_items.csv','w',newline='') as f:
    w=csv.writer(f); w.writerow(['order_item_id','order_id','product_id','quantity','unit_price','total_price'])
    oid=1
    for _ in range(N_ITEMS):
        o=random.choice(orders); p=random.choice(pro)
        q=random.randint(1,4); up=round(random.uniform(5,500),2)
        w.writerow([oid,o,p,q,up,round(q*up,2)]); oid+=1

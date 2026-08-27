import json, os, time, uuid
import boto3
from decimal import Decimal

ddb=boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
cognito=boto3.client("cognito-idp")
CLIENT_ID=os.environ["CLIENT_ID"]

def out(code, body):
    return {"statusCode":code,"headers":{"content-type":"application/json","access-control-allow-origin":"https://proudpops.denduluru.com","access-control-allow-headers":"authorization,content-type","access-control-allow-methods":"GET,POST,PUT,DELETE,OPTIONS"},"body":json.dumps(body,default=str)}

def body(e):
    try:return json.loads(e.get("body") or "{}")
    except:return {}

def handler(e,c):
    route=e.get("routeKey","")
    if route=="OPTIONS /{proxy+}": return out(204,{})
    if route=="POST /login":
        b=body(e)
        try:
            a=cognito.initiate_auth(AuthFlow="USER_PASSWORD_AUTH",ClientId=CLIENT_ID,AuthParameters={"USERNAME":b.get("username",""),"PASSWORD":b.get("password","")})["AuthenticationResult"]
            return out(200,{"idToken":a["IdToken"],"expiresIn":a["ExpiresIn"]})
        except Exception:return out(401,{"message":"Invalid username or password"})
    now=int(time.time())
    if route=="GET /announcements":
        items=ddb.scan().get("Items",[])
        active=[x for x in items if x.get("status")=="PUBLISHED" and int(x.get("startEpoch",0))<=now and int(x.get("endEpoch",4102444800))>=now]
        active.sort(key=lambda x:int(x.get("startEpoch",0)),reverse=True)
        return out(200,active)
    if route=="GET /admin/announcements":
        return out(200,ddb.scan().get("Items",[]))
    if route=="POST /admin/announcements":
        b=body(e); aid=str(uuid.uuid4()); item={"id":aid,"title":b.get("title","")[:100],"message":b.get("message","")[:500],"type":b.get("type","INFO"),"status":b.get("status","DRAFT"),"startEpoch":int(b.get("startEpoch") or now),"endEpoch":int(b.get("endEpoch") or 4102444800),"updatedEpoch":now}
        ddb.put_item(Item=item); return out(201,item)
    if route.startswith("PUT /admin/announcements/"):
        aid=e["pathParameters"]["id"]; b=body(e); item={"id":aid,"title":b.get("title","")[:100],"message":b.get("message","")[:500],"type":b.get("type","INFO"),"status":b.get("status","DRAFT"),"startEpoch":int(b.get("startEpoch") or now),"endEpoch":int(b.get("endEpoch") or 4102444800),"updatedEpoch":now}
        ddb.put_item(Item=item); return out(200,item)
    if route.startswith("DELETE /admin/announcements/"):
        ddb.delete_item(Key={"id":e["pathParameters"]["id"]}); return out(200,{"deleted":True})
    return out(404,{"message":"Not found"})

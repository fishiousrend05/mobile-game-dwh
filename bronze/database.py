from pymongo import MongoClient
from config import Config

def get_collection():
    client = MongoClient(Config.MONGO_URI)
    db = client[Config.DB_NAME]
    return db[Config.COLLECTION_NAME]
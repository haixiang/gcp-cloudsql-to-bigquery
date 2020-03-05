def datatype_to_bq(datatype):
    """
    Simple attempt to do some basic datatypes.
    Fallback to String for unknowns and then you can fix it later in bigquery.
    """
    if "DATETIME" in datatype:
        return "DATETIME"
    if "DATE" in datatype:
        return "DATE"
    if "INT" in datatype:
        return "INTEGER"
    if "FLOAT" in datatype or "DOUBLE" in datatype or "DECIMAL" in datatype:
        return "FLOAT"
    return "STRING"

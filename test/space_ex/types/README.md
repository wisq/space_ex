Type usage breakdown¹ as of 0.4.3 kRPC API:

```
   1430 CLASS
    681 DOUBLE
    260 BOOL
    219 FLOAT
    190 TUPLE
    135 STRING
     80 LIST
     51 ENUMERATION
     34 SINT32
      6 DICTIONARY
      3 UINT64
      3 UINT32
      2 SET
      2 PROCEDURE_CALL
      2 BYTES
      1 STREAM
      1 STATUS
      1 SERVICES
      1 EVENT
```

Breaking those 19 codes down by class:

* Raw      (8): DOUBLE, BOOL, FLOAT, STRING, SINT32, UINT64, UINT32, BYTES
* Nested   (4): TUPLE, LIST, DICTIONARY, SET
* Special  (3): CLASS, ENUMERATION, PROCEDURE_CALL
* Protobuf (4): STREAM, STATUS, SERVICES, EVENT

We've got one test covering one of the protobuf types, but the rest are fully covered.


¹ `grep -h '"code"' *.json | cut -d\" -f4 | sort | uniq -c | sort -rn`

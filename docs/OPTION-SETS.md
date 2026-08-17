# Phase 1 - Option set reference

The Dataverse Web API returns these columns as integers. FetchXML returns labels.
Any flow or Power Fx formula that filters or writes one of these must use the integer.

## `mserp_inventqualityorderheaderentity`

### `mserp_isbatchattributevaluedefaultedwithtestmeasurement`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_isbatchdispositionstatusdefaultedwithtestmeasurement`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_isdestructivetest`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_isinventorystatusdefaultedwithtestmeasurement`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_isqualityorderfailurecreatingquantineorder`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_qmssampleinspectionmethod`

| Value | Label |
|---|---|
| `200000000` | None |
| `200000001` | Inline process |
| `200000002` | Continuous process |
| `200000003` | Both |

### `mserp_qmsuseforcertificateofanalysis`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_qualityorderpolicytype`

| Value | Label |
|---|---|
| `200000000` | Inventory |
| `200000001` | Sales |
| `200000002` | Purchase |
| `200000003` | Production |
| `200000004` | Quarantine |
| `200000005` | Route operation |
| `200000006` | Co-product production |
| `200000007` | Goods in transit order |
| `200000008` | Inbound shipment order |
| `200000009` | Sales return |
| `200000010` | Transfer |

### `mserp_qualityorderstatus`

| Value | Label |
|---|---|
| `200000000` | Open |
| `200000001` | Fail |
| `200000002` | Pass |

### `mserp_referencetype`

| Value | Label |
|---|---|
| `200000000` | Inventory |
| `200000001` | Sales |
| `200000002` | Purchase |
| `200000003` | Production |
| `200000004` | Quarantine |
| `200000005` | Route operation |
| `200000006` | Co-product production |
| `200000007` | Goods in transit order |
| `200000008` | Inbound shipment order |
| `200000009` | Sales return |
| `200000010` | Transfer |

## `mserp_inventqualityorderlineresultentity`

### `mserp_istestvalidationincludingresult`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_qmstestresultsexist`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_testresult`

| Value | Label |
|---|---|
| `200000000` | Fail |
| `200000001` | Pass |

## `mserp_inventnonconformancetableentity`

### `mserp_closed`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_inventnonconformanceapproval`

| Value | Label |
|---|---|
| `200000000` | New |
| `200000001` | Approved |
| `200000002` | Refused |

### `mserp_inventnonconformancetype`

| Value | Label |
|---|---|
| `200000000` | Internal |
| `200000001` | Customer |
| `200000002` | Vendor |
| `200000003` | Service request |
| `200000004` | Production |
| `200000005` | Co-product production |

### `mserp_inventtestinfostat`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_inventtestquarantinetype`

| Value | Label |
|---|---|
| `200000000` | Restricted usage |
| `200000001` | Unusable |

### `mserp_inventtranstype`

| Value | Label |
|---|---|
| `200000000` | Sales order |
| `200000001` | Production |
| `200000002` | Purchase order |
| `200000003` | Transaction |
| `200000004` | Inventory adjustment |
| `200000005` | Transfer |
| `200000006` | Weighted average inventory closing |
| `200000007` | Production line |
| `200000008` | BOM line |
| `200000009` | BOM |
| `200000010` | Output order |
| `200000011` | Project |
| `200000012` | Counting |
| `200000013` | Pallet transport |
| `200000014` | Quarantine order |
| `200000015` | Fixed assets |
| `200000016` | Transfer order shipment |
| `200000017` | Transfer order receive |
| `200000018` | Transfer order scrap |
| `200000019` | Quotation |
| `200000020` | Quality order |
| `200000021` | Inventory blocking |
| `200000022` | Kanban process job |
| `200000023` | Kanban transfer job receipt |
| `200000024` | Kanban job transfer issue |
| `200000025` | Kanban job consumption |
| `200000026` | Kanban job work in process |
| `200000027` | Kanban emptied |
| `200000028` | Co-product production |
| `200000029` | By-product |
| `200000030` | Fixed assets |
| `200000031` | Statement |
| `200000032` | Components |
| `200000033` | Work |
| `200000034` | Inventory status change |
| `200000035` | Container |
| `200000036` | Consignment replenishment order |
| `200000037` | Ownership change |
| `200000038` | Order-committed reservation |
| `200000039` | Archived inventory transactions |
| `200000040` | Archived warehouse transaction type only affects location and below |
| `200000041` | Goods in transit |
| `200000042` | none |
| `200000043` | Outbound shipment order |
| `200000044` | Inbound shipment order |
| `200000045` | Outbound shipment order update |
| `200000046` | Warehouse order |
| `200000047` | Warehouse receipt |
| `200000048` | Warehouse order reservation |
| `200000049` | Warehouse inventory adjustment |
| `200000050` | Warehouse inventory blocking |

### `mserp_rush`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

## `mserp_inventqualityorderlineentitypowerapp`

### `mserp_failureaction`

| Value | Label |
|---|---|
| `200000000` | Fail |
| `200000001` | Accept |

### `mserp_isbatchattributevaluedefaultedwithtestmeasurement`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_iscertificateofanalysisreportincludingtestmeasurement`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_isitembatchattributevalueoverridden`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_istestresultvalidationincludingline`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_pdsbatchattribtype`

| Value | Label |
|---|---|
| `200000000` | String |
| `200000001` | Integer |
| `200000002` | Fraction |
| `200000003` | Enumerate |
| `200000004` | Date |

### `mserp_qualitytestoutcomestatus`

| Value | Label |
|---|---|
| `200000000` | Fail |
| `200000001` | Pass |

## `mserp_inventqualitytestgroupentity`

### `mserp_isbatchattributevaluedefaultedwithtestmeasurement`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_isbatchdispositionstatusdefaultedwithtestmeasurement`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_isdestructivetest`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |

### `mserp_isinventorystatusdefaultedwithtestmeasurement`

| Value | Label |
|---|---|
| `200000000` | No |
| `200000001` | Yes |



WITH orders AS (
    SELECT so.order_id
  	 , so.order_cr_dt AS order_created_date
  	 , do.dim_orders_id
  	 , dc.dim_customer_id
  	 , dp.dim_product_id
  	 , CAST(GETDATE() AS DATE) AS snapshot_date
  	 , so.order_uom
  	 , so.order_qty
  	 , so.currency_code
  	 , so.order_amount
    FROM staging.orders AS so
    INNER JOIN dm_sales.dim_orders AS do ON so.order_id = do.order_id
    INNER JOIN dm_common.dim_customer_sdc2 AS dc ON so.customer_id = dc.customer_id 
	  AND so.order_created_date BETWEEN dc.record_start_date AND dc.record_end_date
    INNER JOIN dm_common.dim_product AS dp ON dp.product_id = sd.product_id
    WHERE so.order_created_date >= DATEADD(MONTH, - 3, GETDATE()))
  , billing AS (
    SELECT *
  	 , ROW_NUMBER() (PARTITION BY so.sap_order_id ORDER BY bill.billing_date DESC) AS rn
    FROM staging.billing AS bill
    INNER JOIN staging.orders AS so ON so.order_id = bill.order_id)
  , orders_final AS (
    SELECT orders.*
  	 , billing.billing_number
  	 , CONVERT(VARBINARY(32), HASHBYTES('SHA2_256', CONCAT (
  		COALESCE(orders.order_created_date, '')                                                              , '|'
  		, COALESCE(orders.dim_orders_id, CAST('00000000-0000-0000-0000-000000000000' AS UNIQUEIDENTIFIER))   , '|'
  		, COALESCE(orders.dim_customer_id, CAST('00000000-0000-0000-0000-000000000000' AS UNIQUEIDENTIFIER)) , '|'
  		, COALESCE(orders.dim_product_id, CAST('00000000-0000-0000-0000-000000000000' AS UNIQUEIDENTIFIER))  , '|'
  		, COALESCE(orders.order_uom, '')                                                                     , '|'
  		, COALESCE(orders.order_qty, 0)                                                                      , '|'
  		, COALESCE(orders.currency_code, '')                                                                 , '|'
  		, COALESCE(orders.order_amount, 0)                                                                   , '|'
  		, COALESCE(billing.billing_number, 0)))) AS row_hash
    FROM orders
    LEFT JOIN billing ON orders.sap_order_id = billing.sap_order_id 
         AND billing.rn = 1)
MERGE INTO dm_sales.fact_orders AS tgt
USING orders_final AS src
	ON tgt.order_id = src.order_id AND tgt.snapshot_date = src.snapshot_date
WHEN MATCHED AND src.row_hash <> tgt.row_hash
	THEN UPDATE
		  SET tgt.order_created_date = src.order_created_date
			    , tgt.dim_orders_id = src.dim_orders_id
			    , tgt.dim_customer_id = src.dim_customer_id
			    , tgt.dim_product_id = src.dim_product_id
			    , tgt.snapshot_date = src.snapshot_date
			    , tgt.order_uom = src.order_uom
			    , tgt.order_qty = src.order_qty
			    , tgt.currency_code = src.currency_code
			    , tgt.order_amount = src.order_amount
			    , tgt.billing_number = src.billing_number
WHEN NOT MATCHED BY TARGET
	THEN INSERT (order_id
			           , order_created_date
				   , dim_orders_id
			           , dim_customer_id
			           , dim_product_id
			           , snapshot_date
			           , order_uom
			           , order_qty
			           , currency_code
			           , order_amount)
		VALUES (src.order_id
			      , src.order_created_date
			      , src.dim_orders_id
			      , src.dim_customer_id
			      , src.dim_product_id
			      , src.snapshot_date
			      , src.order_uom
			      , src.order_qty
			      , src.currency_code
			      , src.order_amount);

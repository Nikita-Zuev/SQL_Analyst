# Analysis of a Company's Tax Depreciation of Fixed Assets

## The Purpose of the Query
SQL query for a detailed calculation and analysis of a company's tax depreciation of fixed assets. It considers different scenarios for asset use (full period, partial period, and decommissioning).


## Key Stages

1.  **Data Collection:** Combining information about assets, their value, service life, and depreciation method using a `LEFT JOIN`.

2.  **Depreciation Calculation:** Using the `CASE WHEN` statement to calculate depreciation, considering different situations:
      * Full operating period.
      * Commissioning during the period.
      * Decommissioning or improvement.

3.  **Summary Formation:** Aggregating data using `SUM` and `AVG`. Adding a "TOTAL" summary row with `UNION ALL`.



## **Error Handling and Optimization**

* **Error Handling:** Using `COALESCE()` to replace `NULL` with default values (`0` or `1`). `CASE WHEN` conditions check for data presence and whether they match business logic.

* **Optimization**:
      * Breaking down the logic into several `CTE`s to improve readability and maintenance.
      * Using `:selection_start_date` and `:selection_end_date` parameters for flexibility.
      * Optimizing `JOIN` operations by moving the selection of main fields to the final `CTE`.



* ## Technical Requirements
     * DBMS: Oracle
     * Parameters: Mandatory start and end date parameters for the period

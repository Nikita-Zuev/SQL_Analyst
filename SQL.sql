-- CTE 1: ASSET - Extracting basic information about assets

WITH Asset AS (
  SELECT
    t0.ID AS "ID",
    t0.ASSETID AS "Asset_ID",
    t0.ACCOUNTID AS "AccountID",
    t1.ACCOUNT_DESCRIPTION AS "AccountDescription",
    t0.DESCRIPTION AS "Description",
    t0.DATE_OF_AQUISITION AS "DateOfAquisition",
    t0.START_UP_DATE AS "StartUpDate",                    -- Start Date of Use
    t0.DECOMMISSION_DATE AS "DecommissionDate",          -- Date of Decommissioning
    t0.ASSET_DISPOSAL_DATE AS "AssetDisposalDate",       -- Date of Sale/Write-off
    t0.RESIDUAL_VALUE AS "ResidualValue"                 -- Residual Value
  FROM MASTER_ASSET t0
  LEFT JOIN DOC_ASSET_TRANSACTION t1 ON t0.ASSETID = t1.ASSETID
),


-- CTE 2: VALUATION - Getting data on asset valuation and depreciation

Valuation AS (
  SELECT
    t0.ID AS "ID",
    t0.ASSET_ID AS "Asset_ID",
    t0.ASSET_VALUATION_TYPE AS "AssetValuationType",
    t0.VALUATION_CLASS AS "ValuationClass",         -- Classification for Tax Purposes

    -- Cost Indicators
    t0.ACQUISITION_AND_PRODUCTION_COSTS_BEGIN AS "AcquisitionAndProductionCostsBegin",
    t0.ACQUISITION_AND_PRODUCTION_COSTS_END AS "AcquisitionAndProductionCostsEnd",
    t0.INVESTMENT_SUPPORT AS "InvestmentSupport",      -- Investment support

    -- Parameters of service life
    t0.ASSET_LIFE_YEAR AS "AssetLifeYear",            -- Service life in years
    t0.ASSET_LIFE_MONTH AS "AssetLifeMonth",          -- Service life in months

    -- Asset movements
    t0.ASSET_ADDITION AS "AssetAddition",             -- Asset Receipt
    t0.TRANSFERS AS "Transfers",                     -- Asset transfer
    t0.ASSET_DISPOSAL AS "AssetDisposal",            -- Asset Disposal

    -- Book value and depreciation
    t0.BOOK_VALUE_BEGIN AS "BookValueBegin",            -- Book value at the beginning
    t0.DEPRECIATION_METHOD AS "DepreciationMethod",       -- Depreciation method
    t0.DEPRECIATION_PERCENTAGE AS "DepreciationPercentage", -- Depreciation percentage
    t0.DEPRECIATION_FOR_PERIOD AS "DepreciationForPeriod", -- Depreciation for the period

    -- Asset revaluation
    t0.APPRECIATION_METHOD AS "AppreciationMethod",
    t0.APPRECIATION_FOR_PERIOD AS "AppreciationForPeriod",

    -- Extraordinary depreciation
    t1.EXTRAORDINARY_DEPRECIATION_METHOD AS "ExtraordinaryDepreciationMethod",
    t1.EXTRAORDINARY_DEPRECIATION_FOR_PERIOD AS "ExtraordinaryDepreciationForPeriod",

    t0.ACCUMULATED_DEPRECIATION AS "AccumulatedDepreciation", -- Accumulated depreciation
    t0.BOOK_VALUE_END AS "BookValueEnd"              -- Book value at the end

  FROM ASSET_VALUATION t0
  LEFT JOIN ASSET_VALUATION_PERIOD t1 ON t0.ID = t1.ASSET_VALUATION_ID
  WHERE
    t0.ASSET_VALUATION_TYPE = 2                      -- Only tax valuation
    AND t0.VALUATION_CLASS IN (                      -- Filter by asset classes
      'Д2', 'Д3', 'Д3.1', 'Д4', 'Д4.1', 'Д5', 'Д5.1',
      'Д6', 'Д7', 'Д8', 'Д9', 'Д9.1', 'Д12', 'Д14',
      'Д15', 'Д16', 'Д1', 'Д2', 'Д3', 'Д4', 'Д5', 'Д6'
    )
    AND t0.DEPRECIATION_METHOD = 1                     -- Straight-line depreciation method
),


-- CTE 3: FORWARD_METHOD - Розрахунок податкової амортизації різними способами

ForwardMethod AS (
  SELECT
    -- Basic asset information
    a."Asset_ID",
    a."AccountID",
    a."AccountDescription",
    a."Description",
    a."DateOfAquisition",
    a."StartUpDate",
    a."DecommissionDate",
    a."AssetDisposalDate",

    -- Valuation data
    v."AssetValuationType",
    v."ValuationClass",
    v."AcquisitionAndProductionCostsBegin",
    v."AcquisitionAndProductionCostsEnd",
    v."InvestmentSupport",
    v."AssetLifeYear",
    v."AssetLifeMonth",
    v."AssetAddition",
    v."Transfers",
    v."AssetDisposal",
    v."BookValueBegin",
    v."DepreciationMethod",
    v."DepreciationPercentage",
    v."DepreciationForPeriod",
    v."AppreciationMethod",
    v."AppreciationForPeriod",
    v."ExtraordinaryDepreciationMethod",
    v."ExtraordinaryDepreciationForPeriod",
    v."AccumulatedDepreciation",
    v."BookValueEnd",
    a."ResidualValue",


    -- CALCULATION 1: Depreciation of assets used during the period

    CASE
      WHEN v."AcquisitionAndProductionCostsBegin" > 0
        AND v."AcquisitionAndProductionCostsEnd" > 0
        AND a."StartUpDate" < DATE :startdate              -- Asset was put into use before the start of the period
        AND a."DecommissionDate" IS NULL                   -- Asset has not been decommissioned
        AND a."AssetDisposalDate" IS NULL                  -- Asset has not been written off
      THEN
        CASE
          -- Calculation based on years
          WHEN v."AssetLifeYear" <> 0 THEN
            (v."AcquisitionAndProductionCostsBegin" - a."ResidualValue")
            / (v."AssetLifeYear" * 12)
            * (MONTHS_BETWEEN(DATE :enddate, DATE :startdate) + 1)
          -- Calculation based on months
          ELSE
            (v."AcquisitionAndProductionCostsBegin" - a."ResidualValue")
            / v."AssetLifeMonth"
            * (MONTHS_BETWEEN(DATE :enddate, DATE :startdate) + 1)
        END
      ELSE 0
    END AS "CalculatedDepreciation",


    -- CALCULATION 2: Depreciation of assets received during the period

    CASE
      WHEN v."AssetAddition" > 0
        AND a."StartUpDate" > DATE :startdate              -- Asset was put into use during the period
        AND a."DecommissionDate" IS NULL
        AND a."AssetDisposalDate" IS NULL
      THEN
        CASE
          -- Calculation based on years
          WHEN v."AssetLifeYear" <> 0 THEN
            (v."AssetAddition" - a."ResidualValue")
            / (v."AssetLifeYear" * 12)
            * MONTHS_BETWEEN(DATE :enddate, ADD_MONTHS(a."StartUpDate", 1))
          -- Calculation based on months
          ELSE
            (v."AssetAddition" - a."ResidualValue")
            / v."AssetLifeMonth"
            * MONTHS_BETWEEN(DATE :enddate, ADD_MONTHS(a."StartUpDate", 1))
        END
    ELSE 0
    END AS "CalculatedDepreciation_Addition",


    -- CALCULATION 3: Depreciation of assets that were disposed of/decommissioned during the period

    CASE
      WHEN
        (v."Transfers" < 0 OR v."AssetDisposal" > 0)     -- There is asset disposal
        AND (a."DecommissionDate" >= DATE :startdate OR a."DecommissionDate" IS NULL)
        AND (a."AssetDisposalDate" >= DATE :startdate OR a."AssetDisposalDate" IS NULL)
        AND (a."DecommissionDate" IS NOT NULL OR a."AssetDisposalDate" IS NOT NULL)
      THEN
        CASE
          -- Calculation based on years
          WHEN v."AssetLifeYear" <> 0 THEN
            (v."AcquisitionAndProductionCostsBegin" - a."ResidualValue")
            / (v."AssetLifeYear" * 12) *
          CASE
            -- We select the earlier of the two dates
            WHEN a."DecommissionDate" >= DATE :startdate
                     AND (a."DecommissionDate" <= a."AssetDisposalDate" OR a."AssetDisposalDate" IS NULL) THEN
              MONTHS_BETWEEN(ADD_MONTHS(a."DecommissionDate",1), DATE :startdate) + 1
            ELSE
              MONTHS_BETWEEN(ADD_MONTHS(a."AssetDisposalDate",1), DATE :startdate) + 1
          END
        ELSE
          -- Calculation based on months
            (v."AcquisitionAndProductionCostsBegin" - a."ResidualValue")
            / v."AssetLifeMonth"
            * CASE
            WHEN a."DecommissionDate" >= DATE :startdate
                     AND (a."DecommissionDate" <= a."AssetDisposalDate" OR a."AssetDisposalDate" IS NULL) THEN
              MONTHS_BETWEEN(ADD_MONTHS(a."DecommissionDate",1), DATE :startdate) + 1
            ELSE
              MONTHS_BETWEEN(ADD_MONTHS(a."AssetDisposalDate",1), DATE :startdate) + 1
          END
        END
    ELSE 0
    END AS "CalculatedDepreciation_Disposal",


    -- CALCULATION 4: Depreciation of investment support (improvements) of assets

    CASE
      WHEN v."InvestmentSupport" > 0
        AND a."StartUpDate" < DATE :startdate
      THEN
        CASE
          -- Calculation based on years
          WHEN v."AssetLifeYear" <> 0 THEN
            (v."InvestmentSupport")
            / (v."AssetLifeYear" * 12)
            * (MONTHS_BETWEEN(DATE :enddate, DATE :startdate) + 1)
          -- Calculation based on months
          ELSE
            (v."InvestmentSupport")
            / v."AssetLifeMonth"
            * (MONTHS_BETWEEN(DATE :enddate, DATE :startdate) + 1)
        END
      ELSE 0
    END AS "CalculatedDepreciation_Investment"

  FROM Asset a
  LEFT JOIN Valuation v ON a."ID" = v."Asset_ID"
),

-- CTE 4: TOTAL_CALCULATED - Total calculation of depreciation for the period

TotalCalculated AS (
  SELECT f.*,
        -- Sum of all types of calculated depreciation
        COALESCE(f."CalculatedDepreciation", 0)
      + COALESCE(f."CalculatedDepreciation_Addition",0)
      + COALESCE(f."CalculatedDepreciation_Disposal",0)
      + COALESCE(f."CalculatedDepreciation_Investment",0) AS "TotalCalculatedDepreciation"
  FROM ForwardMethod f
)


-- MAIN QUERY: Calculation of corporate income tax

SELECT t.*,
        -- Calculation of 18% corporate tax from the depreciation difference
        CASE
          WHEN (COALESCE(t."DepreciationForPeriod", 0) - t."TotalCalculatedDepreciation") > 100 THEN
            (COALESCE(t."DepreciationForPeriod", 0) - t."TotalCalculatedDepreciation") * 0.18
          ELSE 0
        END AS "CorporateIncomeTax18%"
FROM TotalCalculated t


-- SUMMARY ROWS: Aggregation of all indicators

UNION ALL

SELECT
    NULL AS "Asset_ID",
    NULL AS "AccountID",
    NULL AS "AccountDescription",
    NULL AS "Description",
    NULL AS "DateOfAquisition",
    NULL AS "StartUpDate",
    NULL AS "DecommissionDate",
    NULL AS "AssetDisposalDate",
    NULL AS "AssetValuationType",
    'TOTAL' AS "ValuationClass",

    -- Aggregation of all cost indicators
    SUM(t."AcquisitionAndProductionCostsBegin") AS "AcquisitionAndProductionCostsBegin",
    SUM(t."AcquisitionAndProductionCostsEnd") AS "AcquisitionAndProductionCostsEnd",
    SUM(t."InvestmentSupport") AS "InvestmentSupport",
    NULL AS "AssetLifeYear",
    NULL AS "AssetLifeMonth",
    SUM(t."AssetAddition") AS "AssetAddition",
    SUM(t."Transfers") AS "Transfers",
    SUM(t."AssetDisposal") AS "AssetDisposal",
    SUM(t."BookValueBegin") AS "BookValueBegin",
    NULL AS "DepreciationMethod",
    NULL AS "DepreciationPercentage",
    SUM(t."DepreciationForPeriod") AS "DepreciationForPeriod",
    NULL AS "AppreciationMethod",
    SUM(t."AppreciationForPeriod") AS "AppreciationForPeriod",
    NULL AS "ExtraordinaryDepreciationMethod",
    SUM(t."ExtraordinaryDepreciationForPeriod") AS "ExtraordinaryDepreciationForPeriod",
    SUM(t."AccumulatedDepreciation") AS "AccumulatedDepreciation",
    SUM(t."BookValueEnd") AS "BookValueEnd",
    SUM(t."ResidualValue") AS "ResidualValue",

    -- Aggregation of calculated depreciation values
    SUM(t."CalculatedDepreciation") AS "CalculatedDepreciation",
    SUM(t."CalculatedDepreciation_Addition") AS "CalculatedDepreciation_Addition",
    SUM(t."CalculatedDepreciation_Disposal") AS "CalculatedDepreciation_Disposal",
    SUM(t."CalculatedDepreciation_Investment") AS "CalculatedDepreciation_Investment",
    SUM(t."TotalCalculatedDepreciation") AS "TotalCalculatedDepreciation",

    -- Total corporate tax amount
    SUM(
        CASE
          WHEN (COALESCE(t."DepreciationForPeriod", 0) - t."TotalCalculatedDepreciation") > 100 THEN
            (COALESCE(t."DepreciationForPeriod", 0) - t."TotalCalculatedDepreciation") * 0.18
          ELSE 0
        END
    ) AS "CorporateIncomeTax18%"
FROM TotalCalculated t;

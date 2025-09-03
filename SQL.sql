-- CTE 1: ASSET - Витягування базової інформації про активи

WITH Asset AS (
  SELECT
    t0.ID AS "ID",
    t0.ASSETID AS "Asset_ID",
    t0.ACCOUNTID AS "AccountID",
    t1.ACCOUNT_DESCRIPTION AS "AccountDescription",
    t0.DESCRIPTION AS "Description",
    t0.DATE_OF_AQUISITION AS "DateOfAquisition",
    t0.START_UP_DATE AS "StartUpDate",                    -- Дата початку використання
    t0.DECOMMISSION_DATE AS "DecommissionDate",          -- Дата виведення з експлуатації
    t0.ASSET_DISPOSAL_DATE AS "AssetDisposalDate",       -- Дата продажу/списання
    t0.RESIDUAL_VALUE AS "ResidualValue"                 -- Залишкова вартість
  FROM MASTER_ASSET t0
  LEFT JOIN DOC_ASSET_TRANSACTION t1 ON t0.ASSETID = t1.ASSETID
),


-- CTE 2: VALUATION - Отримання даних про оцінку та амортизацію активів

Valuation AS (
  SELECT 
    t0.ID AS "ID",
    t0.ASSET_ID AS "Asset_ID",
    t0.ASSET_VALUATION_TYPE AS "AssetValuationType",
    t0.VALUATION_CLASS AS "ValuationClass",              -- Класифікація для податкових цілей

    -- Вартісні показники
    t0.ACQUISITION_AND_PRODUCTION_COSTS_BEGIN AS "AcquisitionAndProductionCostsBegin",
    t0.ACQUISITION_AND_PRODUCTION_COSTS_END AS "AcquisitionAndProductionCostsEnd",
    t0.INVESTMENT_SUPPORT AS "InvestmentSupport",        -- Інвестиційна підтримка

    -- Параметри строку служби
    t0.ASSET_LIFE_YEAR AS "AssetLifeYear",               -- Строк служби в роках
    t0.ASSET_LIFE_MONTH AS "AssetLifeMonth",             -- Строк служби в місяцях

    -- Рухи по активу
    t0.ASSET_ADDITION AS "AssetAddition",                -- Надходження активу
    t0.TRANSFERS AS "Transfers",                         -- Переміщення активу
    t0.ASSET_DISPOSAL AS "AssetDisposal",                -- Вибуття активу

    -- Балансова вартість та амортизація
    t0.BOOK_VALUE_BEGIN AS "BookValueBegin",             -- Балансова вартість на початок
    t0.DEPRECIATION_METHOD AS "DepreciationMethod",       -- Метод амортизації
    t0.DEPRECIATION_PERCENTAGE AS "DepreciationPercentage", -- Відсоток амортизації
    t0.DEPRECIATION_FOR_PERIOD AS "DepreciationForPeriod", -- Амортизація за period

    -- Дооцінка активу
    t0.APPRECIATION_METHOD AS "AppreciationMethod",
    t0.APPRECIATION_FOR_PERIOD AS "AppreciationForPeriod",

    -- Надзвичайна амортизація
    t1.EXTRAORDINARY_DEPRECIATION_METHOD AS "ExtraordinaryDepreciationMethod",
    t1.EXTRAORDINARY_DEPRECIATION_FOR_PERIOD AS "ExtraordinaryDepreciationForPeriod",

    t0.ACCUMULATED_DEPRECIATION AS "AccumulatedDepreciation", -- Накопичена амортизація
    t0.BOOK_VALUE_END AS "BookValueEnd"                  -- Балансова вартість на кінець

  FROM ASSET_VALUATION t0
  LEFT JOIN ASSET_VALUATION_PERIOD t1 ON t0.ID = t1.ASSET_VALUATION_ID
  WHERE 
    t0.ASSET_VALUATION_TYPE = 2                          -- Тільки податкова оцінка
    AND t0.VALUATION_CLASS IN (                          -- Фільтр по класах активів
      'Д2', 'Д3', 'Д3.1', 'Д4', 'Д4.1', 'Д5', 'Д5.1',
      'Д6', 'Д7', 'Д8', 'Д9', 'Д9.1', 'Д12', 'Д14',
      'Д15', 'Д16', 'Д1', 'Д2', 'Д3', 'Д4', 'Д5', 'Д6'
    )
    AND t0.DEPRECIATION_METHOD = 1                       -- Прямолінійний метод амортизації
),


-- CTE 3: FORWARD_METHOD - Розрахунок податкової амортизації різними способами

ForwardMethod AS (
  SELECT 
    -- Базова інформація про актив
    a."Asset_ID",
    a."AccountID",
    a."AccountDescription",
    a."Description",
    a."DateOfAquisition",
    a."StartUpDate",
    a."DecommissionDate",
    a."AssetDisposalDate",

    -- Дані з оцінки
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


    -- РОЗРАХУНОК 1: Амортизація активів, що використовувались протягом періоду

    CASE
      WHEN v."AcquisitionAndProductionCostsBegin" > 0
        AND v."AcquisitionAndProductionCostsEnd" > 0
        AND a."StartUpDate" < DATE :startdate              -- Актив був введений до початку періоду
        AND a."DecommissionDate" IS NULL                   -- Актив не виведений з експлуатації
        AND a."AssetDisposalDate" IS NULL                  -- Актив не списаний
      THEN
        CASE
          -- Розрахунок через роки
          WHEN v."AssetLifeYear" <> 0 THEN
            (v."AcquisitionAndProductionCostsBegin" - a."ResidualValue")
            / (v."AssetLifeYear" * 12)
            * (MONTHS_BETWEEN(DATE :enddate, DATE :startdate) + 1)
          -- Розрахунок через місяці
          ELSE
            (v."AcquisitionAndProductionCostsBegin" - a."ResidualValue")
            / v."AssetLifeMonth"
            * (MONTHS_BETWEEN(DATE :enddate, DATE :startdate) + 1)
        END
      ELSE 0
    END AS "CalculatedDepreciation",


    -- РОЗРАХУНОК 2: Амортизація активів, що надійшли протягом періоду

    CASE
      WHEN v."AssetAddition" > 0
        AND a."StartUpDate" > DATE :startdate              -- Актив введений в періоді
        AND a."DecommissionDate" IS NULL
        AND a."AssetDisposalDate" IS NULL
      THEN
        CASE
          -- Розрахунок через роки
          WHEN v."AssetLifeYear" <> 0 THEN
            (v."AssetAddition" - a."ResidualValue")
            / (v."AssetLifeYear" * 12)
            * MONTHS_BETWEEN(DATE :enddate, ADD_MONTHS(a."StartUpDate", 1))
          -- Розрахунок через місяці
          ELSE
            (v."AssetAddition" - a."ResidualValue")
            / v."AssetLifeMonth"
            * MONTHS_BETWEEN(DATE :enddate, ADD_MONTHS(a."StartUpDate", 1))
        END
    ELSE 0
    END AS "CalculatedDepreciation_Addition",


    -- РОЗРАХУНОК 3: Амортизація активів, що вибули/виведені протягом періоду

    CASE
      WHEN 
        (v."Transfers" < 0 OR v."AssetDisposal" > 0)       -- Є вибуття активу
        AND (a."DecommissionDate" >= DATE :startdate OR a."DecommissionDate" IS NULL)
        AND (a."AssetDisposalDate" >= DATE :startdate OR a."AssetDisposalDate" IS NULL)
        AND (a."DecommissionDate" IS NOT NULL OR a."AssetDisposalDate" IS NOT NULL)
      THEN
        CASE
          -- Розрахунок через роки
          WHEN v."AssetLifeYear" <> 0 THEN
            (v."AcquisitionAndProductionCostsBegin" - a."ResidualValue")
            / (v."AssetLifeYear" * 12) *
          CASE 
            -- Вибираємо раніше з двох дат
            WHEN a."DecommissionDate" >= DATE :startdate 
                 AND (a."DecommissionDate" <= a."AssetDisposalDate" OR a."AssetDisposalDate" IS NULL) THEN 
              MONTHS_BETWEEN(ADD_MONTHS(a."DecommissionDate",1), DATE :startdate) + 1
            ELSE 
              MONTHS_BETWEEN(ADD_MONTHS(a."AssetDisposalDate",1), DATE :startdate) + 1
          END
        ELSE
          -- Розрахунок через місяці
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


    -- РОЗРАХУНОК 4: Амортизація інвестиційної підтримки (поліпшень) активів

    CASE
      WHEN v."InvestmentSupport" > 0
        AND a."StartUpDate" < DATE :startdate
      THEN
        CASE
          -- Розрахунок через роки
          WHEN v."AssetLifeYear" <> 0 THEN
            (v."InvestmentSupport")
            / (v."AssetLifeYear" * 12)
            * (MONTHS_BETWEEN(DATE :enddate, DATE :startdate) + 1)
          -- Розрахунок через місяці
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


-- CTE 4: TOTAL_CALCULATED - Загальний розрахунок амортизації за період

TotalCalculated AS (
  SELECT f.*,
        -- Сума всіх видів розрахованої амортизації
        COALESCE(f."CalculatedDepreciation", 0)
      + COALESCE(f."CalculatedDepreciation_Addition",0)
      + COALESCE(f."CalculatedDepreciation_Disposal",0)
      + COALESCE(f."CalculatedDepreciation_Investment",0) AS "TotalCalculatedDepreciation"
  FROM ForwardMethod f
)


-- ОСНОВНИЙ ЗАПИТ: Розрахунок корпоративного податку на прибуток

SELECT t.*,
        -- Розрахунок корпоративного податку 18% з різниці амортизації
        CASE 
          WHEN (COALESCE(t."DepreciationForPeriod", 0) - t."TotalCalculatedDepreciation") > 100 THEN 
            (COALESCE(t."DepreciationForPeriod", 0) - t."TotalCalculatedDepreciation") * 0.18 
          ELSE 0 
        END AS "CorporateIncomeTax18%"
FROM TotalCalculated t


-- ПІДСУМКОВІ РЯДКИ: Агрегація всіх показників

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

    -- Агрегація всіх вартісних показників
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

    -- Агрегація розрахованих значень амортизації
    SUM(t."CalculatedDepreciation") AS "CalculatedDepreciation",
    SUM(t."CalculatedDepreciation_Addition") AS "CalculatedDepreciation_Addition", 
    SUM(t."CalculatedDepreciation_Disposal") AS "CalculatedDepreciation_Disposal",
    SUM(t."CalculatedDepreciation_Investment") AS "CalculatedDepreciation_Investment",
    SUM(t."TotalCalculatedDepreciation") AS "TotalCalculatedDepreciation",

    -- Загальна сума корпоративного податку
    SUM(
        CASE 
          WHEN (COALESCE(t."DepreciationForPeriod", 0) - t."TotalCalculatedDepreciation") > 100 THEN 
            (COALESCE(t."DepreciationForPeriod", 0) - t."TotalCalculatedDepreciation") * 0.18 
          ELSE 0 
        END
    ) AS "CorporateIncomeTax18%"
FROM TotalCalculated t;
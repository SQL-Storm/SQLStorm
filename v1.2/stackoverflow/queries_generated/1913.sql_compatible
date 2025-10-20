WITH RECURSIVE CountiesAboveAvgRep AS (
    SELECT
        U.Id,
        U.Reputation,
        U.CreationDate,
        U.DisplayName,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS RepRank,
        (SELECT COUNT(*) FROM Users WHERE Reputation > U.Reputation) + 1 AS DenseRank
    FROM Users U
    WHERE U.Reputation >= (
        SELECT AVG(Reputation) FROM Users
    )

    UNION ALL

    SELECT
        U2.Id,
        U2.Reputation,
        U2.CreationDate,
        U2.DisplayName,
        ROW_NUMBER() OVER (ORDER BY U2.Reputation DESC) AS RepRank,
        (SELECT COUNT(*) FROM Users WHERE Reputation > U2.Reputation) + 1 AS DenseRank
    FROM Users U2
    JOIN CountiesAboveAvgRep C ON U2.Reputation < C.Reputation
)
SELECT
    Id,
    Reputation,
    CreationDate,
    DisplayName,
    RepRank,
    DenseRank
FROM CountiesAboveAvgRep;
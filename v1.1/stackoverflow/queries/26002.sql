-- {"query": "26002.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 564} 
WITH 
    UserReputation AS (
        SELECT 
            U.Id, 
            U.Reputation, 
            U.CreationDate, 
            ROW_NUMBER() OVER (PARTITION BY U.Location ORDER BY U.Reputation DESC) AS RowNum
        FROM 
            Users U
    ),
    PostVotes AS (
        SELECT 
            P.Id, 
            SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
            SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM 
            Posts P
        LEFT JOIN 
            Votes V ON P.Id = V.PostId
        GROUP BY 
            P.Id
    ),
    PostHistoryCTE AS (
        SELECT 
            PH.PostId, 
            PH.PostHistoryTypeId, 
            PH.UserId, 
            LAG(PH.CreationDate, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PrevCreationDate
        FROM 
            PostHistory PH
    ),
    TopPostUsers AS (
        SELECT 
            U.Id, 
            U.DisplayName, 
            COUNT(DISTINCT P.Id) AS PostCount
        FROM 
            Users U
        JOIN 
            Posts P ON U.Id = P.OwnerUserId
        GROUP BY 
            U.Id, 
            U.DisplayName
        ORDER BY 
            PostCount DESC
        LIMIT 10
    )
SELECT 
    U.Id, 
    U.DisplayName, 
    U.Reputation, 
    U.Location, 
    PV.UpVotes, 
    PV.DownVotes, 
    PH.PostId, 
    PH.PostHistoryTypeId, 
    PH.UserId, 
    PH.PrevCreationDate, 
    TU.PostCount, 
    CASE 
        WHEN U.Reputation > 1000 THEN 'High'
        WHEN U.Reputation BETWEEN 500 AND 1000 THEN 'Medium'
        ELSE 'Low'
    END AS ReputationLevel,
    ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS RepRowNum,
    LAG(U.Reputation, 1) OVER (ORDER BY U.Reputation DESC) AS PrevReputation
FROM 
    Users U
JOIN 
    UserReputation UR ON U.Id = UR.Id
LEFT JOIN 
    PostVotes PV ON U.Id = PV.Id
LEFT JOIN 
    PostHistoryCTE PH ON U.Id = PH.UserId
LEFT JOIN 
    TopPostUsers TU ON U.Id = TU.Id
WHERE 
    U.Reputation > 500
    AND U.Location IS NOT NULL
    AND PH.PostHistoryTypeId = 10
ORDER BY 
    U.Reputation DESC;
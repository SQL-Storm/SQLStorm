-- {"query": "2044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 441} 
WITH CTE_UserBadges AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        B.Name AS BadgeName,
        B.Class
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE U.Reputation > 1000
),
CTE_HighRepUsersPosts AS (
    SELECT 
        P.OwnerUserId,
        P.CreationDate,
        P.Title,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS Rn
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) AND P.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
),
CTE_VoteSummary AS (
    SELECT 
        P.Id AS PostId,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    GROUP BY P.Id
)
SELECT 
    U.DisplayName,
    UB.BadgeName,
    UB.Class,
    SUBSTR(REPLACE(U.Location, ' ', '_'), 1, 20) AS Location,
    HP.Title,
    VS.UpVotes,
    VS.DownVotes,
    COALESCE(HP.CreationDate, '1970-01-01') AS RecentPostDate
FROM CTE_UserBadges UB
JOIN CTE_HighRepUsersPosts HP ON UB.UserId = HP.OwnerUserId AND HP.Rn = 1
LEFT JOIN CTE_VoteSummary VS ON HP.OwnerUserId = VS.PostId
LEFT JOIN Users U ON UB.UserId = U.Id
WHERE UB.Class <= 2
AND (
    CASE 
        WHEN HP.Title IS NULL THEN FALSE 
        ELSE NOT VS.DownVotes > VS.UpVotes END
)
ORDER BY U.DisplayName;
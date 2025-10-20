-- {"query": "31081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 467} 

WITH UserStats AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        (SELECT COUNT(*) FROM Posts P WHERE P.OwnerUserId = U.Id) AS PostCount,
        (SELECT COUNT(*) FROM Comments C WHERE C.UserId = U.Id) AS CommentCount,
        (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id) AS BadgeCount
    FROM 
        Users U
    WHERE 
        U.Reputation > 1000
    ORDER BY 
        U.Reputation DESC
),
TopPostStats AS (
    SELECT 
        P.OwnerUserId,
        COUNT(*) AS TotalPosts,
        SUM(P.Score) AS TotalScore,
        AVG(P.ViewCount) AS AvgViewCount
    FROM 
        Posts P
    WHERE 
        P.CreationDate >= '2023-01-01'
    GROUP BY 
        P.OwnerUserId
),
CombinedStats AS (
    SELECT 
        US.UserId,
        US.DisplayName,
        US.Reputation,
        US.CreationDate,
        US.LastAccessDate,
        US.Views,
        US.UpVotes,
        US.DownVotes,
        US.PostCount,
        US.CommentCount,
        US.BadgeCount,
        T.TotalPosts,
        T.TotalScore,
        T.AvgViewCount
    FROM 
        UserStats US
    LEFT JOIN 
        TopPostStats T ON US.UserId = T.OwnerUserId
    WHERE 
        T.TotalPosts IS NOT NULL
)
SELECT 
    CS.DisplayName,
    CS.Reputation,
    CS.PostCount,
    CS.CommentCount,
    CS.BadgeCount,
    COALESCE(CS.TotalPosts, 0) AS TotalPosts,
    COALESCE(CS.TotalScore, 0) AS TotalScore,
    COALESCE(CS.AvgViewCount, 0) AS AvgViewCount
FROM 
    CombinedStats CS
WHERE 
    CS.Reputation BETWEEN 1000 AND 5000
ORDER BY 
    CS.TotalScore DESC, 
    CS.Reputation DESC
LIMIT 100;

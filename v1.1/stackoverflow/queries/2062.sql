-- {"query": "2062.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 374} 
WITH HighReputationUsers AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName,
        U.Reputation
    FROM 
        Users U
    WHERE 
        U.Reputation > (SELECT AVG(Reputation) FROM Users)
),
UserActivity AS (
    SELECT
        P.OwnerUserId,
        SUM(P.Score) AS TotalScore,
        COUNT(DISTINCT C.Id) AS CommentCount,
        COUNT(DISTINCT V.Id) AS VoteCount
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.CreationDate >= '2023-01-01' AND 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.OwnerUserId
)
SELECT 
    HRU.UserId,
    HRU.DisplayName,
    UA.TotalScore,
    UA.CommentCount,
    UA.VoteCount,
    B.BadgeCount,
    CASE 
        WHEN UA.VoteCount > 100 THEN 'Active voter'
        WHEN UA.CommentCount > 50 THEN 'Engaged commenter'
        ELSE 'Regular user'
    END AS UserCategory
FROM 
    HighReputationUsers HRU
LEFT JOIN 
    UserActivity UA ON HRU.UserId = UA.OwnerUserId
LEFT JOIN (
    SELECT 
        UserId, 
        COUNT(Id) AS BadgeCount
    FROM 
        Badges
    WHERE 
        Date > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY 
        UserId
) B ON HRU.UserId = B.UserId
ORDER BY 
    UA.TotalScore DESC NULLS LAST, 
    B.BadgeCount DESC NULLS LAST;
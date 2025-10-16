-- {"query": "24059.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3569} 
WITH Candidate AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        COALESCE(COUNT(c.Id),0) AS CommentCnt,
        (
            SELECT MIN(ch.CreationDate)
            FROM PostHistory ch
            WHERE ch.PostId = p.Id
              AND ch.PostHistoryTypeId IN (1,2,3)
        ) AS FirstEdit
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= '2021-01-01'
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate, p.Tags
),
VoteAgg AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Up,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Down,
        SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN v.BountyAmount ELSE 0 END) AS Bounty
    FROM Votes v
    GROUP BY v.PostId
),
PostTag AS (
    SELECT 
        c.Id   AS PostId,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY c.Id ORDER BY t.TagName) AS TagRank
    FROM Candidate c
    JOIN Tags t ON c.Tags LIKE '%' || t.TagName || '%'
),
UserAgg AS (
    SELECT 
        u.Id,
        u.Reputation,
        COALESCE(SUM(v.Bounty),0) + 0             AS TotalBounty,
        (COALESCE(SUM(v.Up),0)+COALESCE(SUM(v.Down),0)) AS TotalVts
    FROM Users u
    LEFT JOIN VoteAgg v ON v.PostId = u.Id  -- placeholder relation for demo purposes
    GROUP BY u.Id, u.Reputation
),
Ranked AS (
    SELECT 
        u.Id          AS UserId,
        u.Reputation,
        t.TagName,
        COUNT(DISTINCT c.Id)   AS QCnt,
        SUM(c.Score)           AS QScore,
        u.TotalBounty,
        u.TotalVts,
        MIN(c.FirstEdit)        AS FirstEdit,
        ROW_NUMBER() OVER (
            PARTITION BY u.Id ORDER BY SUM(c.Score) DESC
        )                      AS Rnk
    FROM Candidate c
    JOIN PostTag t ON t.PostId = c.Id
    JOIN UserAgg u ON u.Id = c.OwnerUserId
    WHERE t.TagRank = 1
    GROUP BY u.Id, u.Reputation, t.TagName, u.TotalBounty, u.TotalVts
)
SELECT 
    UserId,
    Reputation,
    TagName,
    QCnt,
    QScore,
    TotalBounty,
    TotalVts,
    FirstEdit,
    CASE 
        WHEN Reputation > 5000 THEN 'Gold'
        WHEN Reputation > 1000 THEN 'Silver'
        ELSE 'Bronze'
    END AS RepTier
FROM Ranked
WHERE Rnk = 1

UNION ALL

SELECT 
    u.Id,
    u.Reputation,
    NULL       AS TagName,
    0          AS QCnt,
    0          AS QScore,
    u2.TotalBounty,
    u2.TotalVts,
    NULL       AS FirstEdit,
    CASE 
        WHEN u.Reputation > 5000 THEN 'Gold'
        WHEN u.Reputation > 1000 THEN 'Silver'
        ELSE 'Bronze'
    END AS RepTier
FROM Users u
LEFT JOIN UserAgg u2 ON u2.Id = u.Id
WHERE u.Reputation BETWEEN 100 AND 500

ORDER BY RepTier DESC, QScore DESC, QCnt DESC
LIMIT 200;
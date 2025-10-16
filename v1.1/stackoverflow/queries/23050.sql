-- {"query": "23050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 862} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty,
        MAX(p.CreationDate) AS LatestPostDate,
        STRING_AGG(COALESCE(t.TagName, 'NoTag'), ', ') AS TagsUsed,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankInLocation
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT OUTER JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9)
    LEFT OUTER JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE u.Reputation > 1
      AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
      AND (EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) OR u.UpVotes > 100)
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5 OR SUM(COALESCE(v.BountyAmount, 0)) > 0
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        CASE 
            WHEN p.ClosedDate IS NULL THEN 'Open' 
            ELSE 'Closed' 
        END AS Status,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Title LIKE '%SQL%'
      AND p.ViewCount > 1000
),
Combined AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.TotalBounty,
        us.LatestPostDate,
        us.TagsUsed,
        us.RankInLocation,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.PositiveComments,
        pa.Status,
        pa.PreviousScore,
        pa.NextScore,
        COALESCE(pa.PreviousScore, 0) + COALESCE(pa.NextScore, 0) AS ScoreDelta
    FROM UserStats us
    FULL OUTER JOIN PostAnalysis pa ON us.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pa.PostId)
    WHERE us.RankInLocation <= 10
       OR pa.PositiveComments > 5
    UNION
    SELECT 
        NULL AS UserId,
        'Anonymous' AS DisplayName,
        0 AS Reputation,
        0 AS PostCount,
        0 AS TotalBounty,
        NULL AS LatestPostDate,
        NULL AS TagsUsed,
        NULL AS RankInLocation,
        ph.PostId,
        NULL AS Title,
        NULL AS Score,
        0 AS PositiveComments,
        'Historical' AS Status,
        NULL AS PreviousScore,
        NULL AS NextScore,
        0 AS ScoreDelta
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
      AND ph.CreationDate > '2020-01-01'
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    PostCount,
    TotalBounty,
    LatestPostDate,
    TagsUsed,
    RankInLocation,
    PostId,
    UPPER(Title) AS UpperTitle,
    Score,
    PositiveComments,
    Status,
    PreviousScore,
    NextScore,
    ScoreDelta,
    DENSE_RANK() OVER (ORDER BY Reputation DESC NULLS LAST) AS OverallRank
FROM Combined
WHERE ScoreDelta > 0 OR Status = 'Open'
ORDER BY OverallRank, UserId;
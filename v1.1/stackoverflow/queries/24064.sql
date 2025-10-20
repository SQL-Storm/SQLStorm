-- {"query": "24064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2339} 
WITH UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(SUM(p.Score),0) AS TotalScore,
        CASE WHEN COUNT(p.Id)=0 THEN NULL ELSE AVG(p.Score) END AS AvgScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentActivity AS (
    SELECT
        u.Id AS UserId,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),
PostRanks AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate ASC) AS ScoreRank,
        FIRST_VALUE(p.Id) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate ASC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS TopPostId
    FROM Posts p
    WHERE p.Score IS NOT NULL
),
UserDuplicates AS (
    SELECT
        pl.PostId,
        u.Id AS UserId,
        COUNT(*) AS DuplicateCount
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId, u.Id
),
Combined AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.TotalPosts,
        us.TotalComments,
        us.TotalScore,
        us.AvgScore,
        ra.LastPostDate,
        ra.LastCommentDate,
        pr.TopPostId,
        pr.Score AS TopPostScore,
        COALESCE(du.DuplicateCount,0) AS DuplicatePosts
    FROM UserStats us
    LEFT JOIN RecentActivity ra ON us.UserId = ra.UserId
    LEFT JOIN PostRanks pr ON us.UserId = pr.OwnerUserId AND pr.ScoreRank = 1
    LEFT JOIN UserDuplicates du ON du.UserId = us.UserId
    GROUP BY us.UserId, us.DisplayName, us.Reputation, us.TotalPosts, us.TotalComments, us.TotalScore, us.AvgScore, ra.LastPostDate, ra.LastCommentDate, pr.TopPostId, pr.Score, du.DuplicateCount
)
SELECT
    UserId,
    DisplayName,
    Reputation,
    TotalPosts,
    TotalComments,
    TotalScore,
    AvgScore,
    LastPostDate,
    LastCommentDate,
    TopPostId,
    TopPostScore,
    DuplicatePosts,
    (SELECT COUNT(*)
     FROM PostHistory ph
     WHERE ph.PostId IN (
           SELECT Id FROM Posts WHERE OwnerUserId = cs.UserId
       )
       AND ph.PostHistoryTypeId = 10
     ) AS CloseVotes
FROM Combined cs
WHERE TotalPosts >= 10
  AND (AvgScore > 5 OR TotalScore IS NULL)
  AND COALESCE(TotalScore,0) > 0
  AND EXISTS (
       SELECT 1
       FROM Posts p
       WHERE p.OwnerUserId = cs.UserId
         AND p.Tags IS NOT NULL
         AND p.Tags LIKE '%<c#>%'
         AND p.Score > 10
       LIMIT 1
   )
ORDER BY TotalScore DESC
FETCH FIRST 100 ROWS ONLY;
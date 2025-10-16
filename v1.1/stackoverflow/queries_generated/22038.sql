-- {"query": "22038.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 770} 
WITH UserPostStats AS (
  SELECT
    OwnerUserId,
    COUNT(*) as PostCount,
    SUM(Score) as TotalScore,
    AVG(COALESCE(ViewCount, 0)) as AvgViews,
    STRING_AGG(COALESCE(Tags, ''), ',') as AllTags
  FROM Posts
  WHERE OwnerUserId IS NOT NULL
  GROUP BY OwnerUserId
),
UserVoteStats AS (
  SELECT
    UserId,
    COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) as UpVotesGiven,
    COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) as DownVotesGiven,
    COALESCE(SUM(BountyAmount), 0) as TotalBounty
  FROM Votes
  WHERE UserId IS NOT NULL
  GROUP BY UserId
),
UserBadgeStats AS (
  SELECT
    UserId,
    COUNT(*) as BadgeCount,
    SUM(CASE WHEN Class = 1 THEN 10 WHEN Class = 2 THEN 5 WHEN Class = 3 THEN 1 ELSE 0 END) as BadgeScore
  FROM Badges
  GROUP BY UserId
),
CombinedStats AS (
  SELECT
    U.Id,
    U.DisplayName,
    COALESCE(UPS.PostCount, 0) as PostCount,
    COALESCE(UPS.TotalScore, 0) as TotalScore,
    COALESCE(UPS.AvgViews, 0) as AvgViews,
    LENGTH(COALESCE(UPS.AllTags, '')) as TagLength,
    COALESCE(UVS.UpVotesGiven, 0) as UpVotesGiven,
    COALESCE(UVS.DownVotesGiven, 0) as DownVotesGiven,
    COALESCE(UVS.TotalBounty, 0) as TotalBounty,
    COALESCE(UBS.BadgeCount, 0) as BadgeCount,
    COALESCE(UBS.BadgeScore, 0) as BadgeScore,
    (COALESCE(UPS.TotalScore, 0) * 1.0 + COALESCE(UBS.BadgeScore, 0) + COALESCE(UVS.TotalBounty, 0) / GREATEST(1, COALESCE(UVS.TotalBounty, 0))) / GREATEST(1, COALESCE(UPS.PostCount, 1)) as OverallScore
  FROM Users U
  LEFT JOIN UserPostStats UPS ON U.Id = UPS.OwnerUserId
  LEFT JOIN UserVoteStats UVS ON U.Id = UVS.UserId
  LEFT JOIN UserBadgeStats UBS ON U.Id = UBS.UserId
  WHERE U.Reputation > 0
    AND EXISTS (
      SELECT 1 FROM Posts P
      WHERE P.OwnerUserId = U.Id
        AND P.Score > (
          SELECT AVG(Score) 
          FROM Posts 
          WHERE OwnerUserId IS NOT NULL AND Score IS NOT NULL
        )
    )
)
SELECT
  Id,
  DisplayName,
  PostCount,
  TotalScore,
  AvgViews,
  TagLength,
  UpVotesGiven,
  DownVotesGiven,
  TotalBounty,
  BadgeCount,
  BadgeScore,
  OverallScore,
  ROW_NUMBER() OVER (ORDER BY OverallScore DESC) as Rank,
  CASE 
    WHEN OverallScore > 100 THEN 'High'
    WHEN OverallScore BETWEEN 10 AND 100 THEN 'Medium'
    ELSE 'Low'
  END as PerformanceCategory,
  SUBSTRING(DisplayName, 1, 10) || '...' as ShortName
FROM CombinedStats
WHERE OverallScore > 0
ORDER BY Rank ASC
LIMIT 100; -- Assuming Postgres, for benchmarking purposes, limit to top 100 for performance
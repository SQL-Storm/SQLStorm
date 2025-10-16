-- {"query": "20046.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1176} 

WITH PowerUserCandidates AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.CreationDate,
    u.UpVotes,
    u.DownVotes
  FROM Users u
  WHERE u.Reputation > 75000 AND u.Views > 1000 AND u.Id > 0
),
UserBadgeStats AS (
  SELECT
    UserId,
    COUNT(*) AS TotalBadges,
    SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges
  WHERE UserId IN (SELECT Id FROM PowerUserCandidates)
  GROUP BY UserId
  HAVING SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) >= 3
),
UserPostMetrics AS (
  SELECT
    p.OwnerUserId,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.FavoriteCount) AS MaxFavorites,
    COUNT(p.Id) AS TotalPosts,
    AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))) / 3600.0 AS AvgActivityHours,
    string_agg(DISTINCT SUBSTRING(t.TagName from 1 for 15), ', ')
      FILTER (WHERE t.TagName IS NOT NULL)
      OVER (PARTITION BY p.OwnerUserId) AS TopTagsSample
  FROM Posts p
  LEFT JOIN UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_name ON p.PostTypeId = 1
  LEFT JOIN Tags t ON t.TagName = tag_name
  WHERE p.OwnerUserId IN (SELECT UserId FROM UserBadgeStats)
    AND p.CommunityOwnedDate IS NULL
  GROUP BY p.OwnerUserId
),
UserActivityTimeline AS (
  SELECT UserId, CreationDate, 'Post' AS ActivityType FROM Posts WHERE UserId IN (SELECT UserId FROM UserBadgeStats)
  UNION ALL
  SELECT UserId, CreationDate, 'Comment' AS ActivityType FROM Comments WHERE UserId IN (SELECT UserId FROM UserBadgeStats)
  UNION ALL
  SELECT UserId, Date AS CreationDate, 'Badge' AS ActivityType FROM Badges WHERE UserId IN (SELECT UserId FROM UserBadgeStats)
),
UserEngagement AS (
  SELECT
    UserId,
    ActivityYear,
    ActivityMonth,
    ActivityCount,
    LAG(ActivityCount, 1, 0) OVER (PARTITION BY UserId ORDER BY ActivityYear, ActivityMonth) AS PrevMonthCount,
    SUM(ActivityCount) OVER (PARTITION BY UserId ORDER BY ActivityYear, ActivityMonth ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS Rolling3MonthSum
  FROM (
    SELECT
      UserId,
      EXTRACT(YEAR FROM CreationDate) AS ActivityYear,
      EXTRACT(MONTH FROM CreationDate) AS ActivityMonth,
      COUNT(*) AS ActivityCount
    FROM UserActivityTimeline
    GROUP BY UserId, ActivityYear, ActivityMonth
  ) AS MonthlyActivity
)
SELECT
  puc.DisplayName,
  puc.Reputation,
  ubs.GoldBadges,
  upm.AvgPostScore,
  (
    SELECT
      p_inner.Title
    FROM Posts p_inner
    WHERE p_inner.OwnerUserId = puc.Id AND p_inner.PostTypeId = 1
    ORDER BY p_inner.Score DESC, p_inner.ViewCount DESC
    LIMIT 1
  ) AS TopQuestionTitle,
  COALESCE(puc.Location, 'Location Not Specified') AS UserLocation,
  upm.TopTagsSample,
  ue.Rolling3MonthSum,
  (ue.ActivityCount - ue.PrevMonthCount)::numeric / NULLIF(ue.PrevMonthCount, 0) AS MonthOverMonthGrowth,
  RANK() OVER (PARTITION BY COALESCE(puc.Location, 'Location Not Specified') ORDER BY puc.Reputation DESC, ubs.GoldBadges DESC) AS LocationRank
FROM PowerUserCandidates puc
JOIN UserBadgeStats ubs ON puc.Id = ubs.UserId
JOIN UserPostMetrics upm ON puc.Id = upm.OwnerUserId
LEFT JOIN UserEngagement ue ON puc.Id = ue.UserId
WHERE
  upm.AvgPostScore > 5
  AND puc.Id IN (
    SELECT DISTINCT v.UserId
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IN (SELECT UserId FROM UserBadgeStats) AND vt.Name IN ('UpMod', 'AcceptedByOriginator', 'Favorite')
    GROUP BY v.UserId
    HAVING COUNT(v.Id) > 1000
  )
  AND ue.ActivityYear = EXTRACT(YEAR FROM CURRENT_DATE) - 2
  AND ue.ActivityMonth = 12
ORDER BY
  LocationRank, puc.Reputation DESC
LIMIT 200;

-- {"query": "22020.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 902} 
WITH UserStats AS (
  SELECT u.Id, u.Reputation, u.DisplayName,
         COUNT(DISTINCT p.Id) AS PostCount,
         COALESCE(SUM(p.Score), 0) AS TotalScore,
         AVG(c.Score) AS AvgCommentScore
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c ON p.Id = c.PostId
  GROUP BY u.Id, u.Reputation, u.DisplayName
),
UserBadges AS (
  SELECT UserId, COUNT(*) AS BadgeCount, MAX(Date) AS LastBadgeDate
  FROM Badges
  GROUP BY UserId
),
UserVoteStats AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesReceived,
         COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesReceived
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.OwnerUserId
),
UserTagStats AS (
  SELECT p.OwnerUserId AS UserId, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
UserTagCounts AS (
  SELECT UserId, TagName, COUNT(*) AS TagCount
  FROM UserTagStats
  GROUP BY UserId, TagName
),
UserTopTags AS (
  SELECT UserId, STRING_AGG(TagName, ', ' ORDER BY TagCount DESC) AS TopTags
  FROM (
    SELECT UserId, TagName, TagCount,
           ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC) AS rn
    FROM UserTagCounts
  ) x
  WHERE rn <= 3
  GROUP BY UserId
),
UserEditCount AS (
  SELECT ph.UserId, COUNT(*) AS EditCount
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 24)
  GROUP BY ph.UserId
)
SELECT us.Id, us.DisplayName, us.Reputation,
       us.PostCount,
       us.TotalScore,
       COALESCE(ub.BadgeCount, 0) AS BadgeCount,
       COALESCE(uv.UpvotesReceived, 0) AS UpvotesReceived,
       COALESCE(uv.DownvotesReceived, 0) AS DownvotesReceived,
       CASE 
         WHEN uv.UpvotesReceived > uv.DownvotesReceived THEN 'Positive'
         WHEN uv.UpvotesReceived IS NULL OR uv.DownvotesReceived IS NULL THEN 'Unknown'
         ELSE 'Negative'
       END AS VoteBalance,
       CASE 
         WHEN ub.LastBadgeDate IS NULL THEN NULL
         ELSE EXTRACT(YEAR FROM ub.LastBadgeDate) - EXTRACT(YEAR FROM u.CreationDate)
       END AS BadgeYearsSinceCreation,
       ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.TotalScore DESC) AS ReputationRank,
       DENSE_RANK() OVER (ORDER BY us.TotalScore DESC NULLS LAST) AS ScoreRank,
       COALESCE(ue.EditCount, 0) AS PostEditCount,
       (SELECT AVG(a.Score) 
        FROM Posts a 
        WHERE a.ParentId IN (SELECT q.Id FROM Posts q WHERE q.OwnerUserId = us.Id AND q.PostTypeId = 1) 
        AND a.PostTypeId = 2) AS AvgAnswerScore,
       COALESCE(ut.TopTags, 'No Tags') AS TopTags,
       LENGTH(COALESCE(us.DisplayName, '')) + CASE WHEN POSITION('@' IN COALESCE(us.DisplayName, '')) > 0 THEN 1 ELSE 0 END AS NameComplexityScore
FROM UserStats us
JOIN Users u ON us.Id = u.Id
LEFT JOIN UserBadges ub ON us.Id = ub.UserId
LEFT JOIN UserVoteStats uv ON us.Id = uv.UserId
LEFT JOIN UserTopTags ut ON us.Id = ut.UserId
LEFT JOIN UserEditCount ue ON us.Id = ue.UserId
WHERE us.PostCount > 0
ORDER BY ReputationRank, ScoreRank;
-- {"query": "88.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1343} 
WITH
-- Time-bounded activity snapshot by user, including badge and post activity aggregation
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(p.PostCount, 0) AS PostCount,
    COALESCE(a.AnswerCount, 0) AS AnswerCount,
    COALESCE(v.UpvoteTotal, 0) AS UpvoteTotal,
    COALESCE(v.DownvoteTotal, 0) AS DownvoteTotal,
    -- Activity window: last 365 days
    COALESCE(w.WindowActivity, 0) AS WindowActivity
  FROM Users u
  LEFT JOIN (
    SELECT
      UserId,
      SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT
      OwnerUserId AS UserId,
      COUNT(*) AS PostCount
    FROM Posts
    GROUP BY OwnerUserId
  ) p ON p.UserId = u.Id
  LEFT JOIN (
    SELECT
      OwnerUserId AS UserId,
      SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts
    GROUP BY OwnerUserId
  ) a ON a.UserId = u.Id
  LEFT JOIN (
    SELECT
      UserId,
      SUM(CASE WHEN VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS UpvoteTotal,
      SUM(CASE WHEN VoteTypeId IN (3) THEN 1 ELSE 0 END) AS DownvoteTotal
    FROM Votes
    GROUP BY UserId
  ) v ON v.UserId = u.Id
  LEFT JOIN (
    SELECT
      UserId,
      SUM(CASE WHEN CreationDate >= NOW() - INTERVAL '365 days' THEN 1 ELSE 0 END) AS WindowActivity
    FROM Votes
    GROUP BY UserId
  ) w ON w.UserId = u.Id
),
-- Per-post detailed signals with advanced predicates and window functions
PostSignals AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    -- Flag: recent activity and high movement
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_by_user,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScoreByUser,
    SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS TotalViewsByUser,
    -- Correlated subquery: existence of a close event in PostHistory within 30 days
    EXISTS (
      SELECT 1
      FROM PostHistory ph
      WHERE ph.PostId = p.Id
        AND ph.PostHistoryTypeId = 10 -- Post Closed
        AND ph.CreationDate >= p.CreationDate
        AND ph.CreationDate <= p.CreationDate + INTERVAL '30 days'
    ) AS WasClosedSoon,
    -- Tokenized string expression: count of tags as array length derived from Tags field
    (SELECT COUNT(*) FROM unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS c) AS TagCount
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
-- Optional: complex join graph to exercise outer joins and set operators
PostLinksExpanded AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  UNION ALL
  SELECT
    p.Id AS PostId,
    NULL AS RelatedPostId,
    NULL AS LinkTypeId,
    NULL AS LinkTypeName
  FROM Posts p
  WHERE p.PostTypeId = 1
),
ComplexQuery AS (
  SELECT
    pu.UserId,
    pu.DisplayName,
    ps.PostId,
    ps.Title,
    ps.TagCount,
    ps.Score,
    ps.ViewCount,
    ps.WasClosedSoon,
    ps.AvgScoreByUser,
    ps.TotalViewsByUser,
    CASE
      WHEN ps.TagCount > 3 AND ps.Score > 5 THEN 'High engagement with multiple tags'
      WHEN ps.TagCount = 1 AND ps.Score > 0 THEN 'Single-tag high score'
      ELSE 'General'
    END AS EngagementSegment,
    CASE
      WHEN p.OwnerUserId IS NULL THEN 'Unknown'
      ELSE 'Known'
    END AS OwnerKnown
  FROM PostSignals ps
  INNER JOIN Posts p ON ps.PostId = p.Id
  LEFT JOIN Users pu ON p.OwnerUserId = pu.Id
  WHERE ps.WinExists IS NULL -- placeholder to ensure syntax compatibility in some engines
)
SELECT
  ca.UserId,
  ca.DisplayName,
  ca.PostId,
  ca.Title,
  ca.TagCount,
  ca.Score,
  ca.ViewCount,
  ca.WasClosedSoon,
  ca.AvgScoreByUser,
  ca.TotalViewsByUser,
  ca.EngagementSegment,
  ca.OwnerKnown
FROM ComplexQuery ca
JOIN UserActivity ua ON ua.UserId = ca.UserId
ORDER BY ua.Reputation DESC, ca.ViewCount DESC
LIMIT 100;
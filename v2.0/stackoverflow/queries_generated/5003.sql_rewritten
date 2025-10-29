-- {"query": "5003.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 875} 
WITH TopActiveUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE u.Reputation > 0
),
QuestionStats AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.PostTypeId,
    COUNT(DISTINCT c.Id) AS CommentCountTotal,
    AVG(COALESCE(v.BountyAmount,0)) AS AvgBounty
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
  GROUP BY
    p.Id, p.OwnerUserId, p.Title, p.Tags, p.CreationDate, p.Score,
    p.ViewCount, p.AnswerCount, p.CommentCount, p.LastActivityDate,
    p.PostTypeId
),
EnhancedPosts AS (
  SELECT
    q.PostId,
    q.OwnerUserId,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    q.LastActivityDate,
    q.PostTypeId,
    q.CommentCountTotal,
    q.AvgBounty,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Location,
    b.Name AS BadgeName,
    b.Date AS BadgeDate
  FROM QuestionStats q
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE (q.PostTypeId = 1 OR q.PostTypeId = 2)
)
SELECT
  ep.PostId,
  ep.OwnerUserId,
  ep.OwnerDisplayName,
  ep.Title,
  ep.Tags,
  ep.CreationDate,
  ep.Score,
  ep.ViewCount,
  ep.AnswerCount,
  ep.CommentCount,
  ep.LastActivityDate,
  ep.PostTypeId,
  ep.CommentCountTotal,
  ep.AvgBounty,
  ep.Reputation,
  ep.Location,
  ep.BadgeName,
  ep.BadgeDate,
  -- Window function to show cumulative sum of scores over time per user
  SUM(ep.Score) OVER (PARTITION BY ep.OwnerUserId ORDER BY ep.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ScoreCumulative,
  -- Correlated subquery: count of posts by same user with length of Title > 100 chars
  (
    SELECT COUNT(*) 
    FROM Posts p2
    WHERE p2.OwnerUserId = ep.OwnerUserId
      AND LENGTH(p2.Title) > 100
  ) AS LongTitlePostCount,
  -- Set operation: difference between posts created in last 30 days vs before
  (
    SELECT COUNT(*) FROM Posts p3
    WHERE p3.OwnerUserId = ep.OwnerUserId
      AND p3.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
  ) - (
    SELECT COUNT(*) FROM Posts p4
    WHERE p4.OwnerUserId = ep.OwnerUserId
      AND p4.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
  ) AS Last30DayWindowBalance,
  -- Complex predicate with NULL handling on Tags
  CASE
    WHEN ep.Tags IS NULL THEN 'NoTags'
    WHEN ep.Tags LIKE '%<%>' THEN 'TagsPresent'
    ELSE 'TagFormatUnknown'
  END AS TagsFormatFlag
FROM EnhancedPosts ep
ORDER BY ep.Reputation DESC NULLS LAST, ep.Score DESC
LIMIT 100;
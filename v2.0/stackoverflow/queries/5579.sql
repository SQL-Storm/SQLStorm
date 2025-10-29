-- {"query": "5579.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 655} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    ARRAY_LENGTH(string_to_array(p.Tags, '>><'), 1) AS TagCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
    AND p.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
TopVoted AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    v.UserId AS VoterUserId
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '60 days'
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    -- compute a derived activity score
    (COALESCE(u.Reputation,0) * 2 + COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) +
     COALESCE((SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = u.Id AND pr.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'),0)
    ) AS ActivityScore
  FROM Users u
),
TagAnalytics AS (
  SELECT
    t.TagName,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM Tags t
  LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
  GROUP BY t.TagName
)
SELECT
  -- combine hot questions with top votes and user activity hints
  rh.PostId,
  rh.Title,
  rh.Tags,
  rh.CreationDate,
  rh.ViewCount,
  rh.Score AS HotScore,
  rh.OwnerDisplayName,
  us.ActivityScore,
  tv.VoteTypeId,
  tv.VoteDate,
  tv.VoterUserId,
  ta.TagName
FROM RecentHot rh
LEFT JOIN TopVoted tv ON tv.PostId = rh.PostId
LEFT JOIN UserStats us ON us.UserId = rh.OwnerUserId
LEFT JOIN (
  SELECT DISTINCT unnest(string_to_array(p.Tags, '>><')) AS TagName, p.Id
  FROM Posts p
  WHERE p.PostTypeId = 1
) AS ta ON ta.Id = rh.PostId
ORDER BY rh.LastActivityDate DESC, rh.Score DESC
LIMIT 200;
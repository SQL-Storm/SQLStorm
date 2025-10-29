-- {"query": "5055.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1050}
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.Body,
    p.FavoriteCount,
    p.ClosedDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
tag_aggregates AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    AVG(q.Score) AS AvgScore,
    MAX(q.ViewCount) AS MaxViews
  FROM (
    SELECT
      unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
      p.Id,
      p.Score,
      p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
  ) q
  JOIN Tags t ON q.TagName = t.TagName
  GROUP BY t.TagName
),
latest_comments AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.Text,
    c.CreationDate,
    c.UserDisplayName,
    c.UserId
  FROM Comments c
  JOIN (
    SELECT PostId, MAX(CreationDate) AS max_cd
    FROM Comments
    GROUP BY PostId
  ) m ON c.PostId = m.PostId AND c.CreationDate = m.max_cd
),
top_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.Reputation IS NOT NULL
),
influential_posts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    v.VoteTypeId,
    v.CreationDate AS VoteDate
  FROM Posts p
  JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
    AND v.VoteTypeId IN (2,6,10,11,16)
),
complex_calc AS (
  SELECT
    rq.PostId,
    rq.OwnerUserId,
    rq.Title,
    rq.Score,
    rq.ViewCount,
    rq.CommentCount,
    rq.AnswerCount,
    (rq.Score * 1.0 / NULLIF(rq.ViewCount,0)) AS score_per_view,
    (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - rq.CreationDate)) / 3600) AS hours_since_creation
  FROM recent_questions rq
),
combined AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.OwnerUserId,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.CommentCount,
    rq.AnswerCount,
    rq.LastActivityDate,
    rq.Body,
    rq.FavoriteCount,
    rq.ClosedDate,
    lc.CommentId AS LatestCommentId,
    lc.Text AS LatestCommentText,
    lc.CreationDate AS LatestCommentDate,
    u.DisplayName AS OwnerDisplayName
  FROM recent_questions rq
  LEFT JOIN latest_comments lc ON rq.PostId = lc.PostId
  LEFT JOIN Users u ON rq.OwnerUserId = u.Id
)
SELECT
  c.PostId,
  c.Title,
  c.Tags,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.CommentCount,
  c.AnswerCount,
  c.LastActivityDate,
  c.Body,
  c.FavoriteCount,
  c.ClosedDate,
  ta.TagName,
  ta.QuestionCount,
  ta.AvgScore,
  ta.MaxViews,
  iu.rn AS TopUserRank,
  iu.DisplayName AS TopUserName,
  iu.Reputation AS TopUserReputation
FROM combined c
LEFT JOIN tag_aggregates ta ON true
LEFT JOIN latest_comments lc ON c.PostId = lc.PostId
LEFT JOIN top_users iu ON iu.rn = 1
LEFT JOIN (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
  FROM Users u
) ic ON ic.Id = iu.Id
WHERE c.OwnerUserId IS NOT NULL
ORDER BY c.CreationDate DESC
LIMIT 100;
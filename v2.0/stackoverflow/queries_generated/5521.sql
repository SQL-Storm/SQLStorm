-- {"query": "5521.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 932} 
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    p.ParentId,
    p.PostTypeId
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= (CURRENT_DATE - INTERVAL '180 days')
),
popular_tags AS (
  SELECT
    t.TagName,
    t.Count AS TagCount
  FROM Tags t
  WHERE t.IsModeratorOnly = 0 AND t.Count > 100
),
tag_expanded AS (
  SELECT
    rq.PostId,
    unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) AS TagName
  FROM recent_questions rq
),
tag_pairs AS (
  SELECT
    te.PostId,
    te.TagName,
    pc.PostId AS LinkedPostId
  FROM tag_expanded te
  JOIN LATERAL (
    SELECT p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Id <> te.PostId
      AND p.Tags LIKE '%' || te.TagName || '%'
  ) pc ON true
),
latest_edits AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.CreationDate,
    v.UserId
  FROM Votes v
  WHERE v.VoteTypeId IN (2, 3, 6, 7) -- upvote, downvote, close, reopen (as example)
    AND v.CreationDate >= (CURRENT_DATE - INTERVAL '90 days')
),
user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostsCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentsCount
  FROM Users u
  WHERE u.LastAccessDate >= (CURRENT_DATE - INTERVAL '365 days')
),
complex_calc AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.LastActivityDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    (rq.Score * 1.0 + COALESCE((SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = rq.PostId AND v.BountyAmount IS NOT NULL), 0)) AS ScoreWithBountyAdj,
    CASE
      WHEN rq.CommentCount IS NULL THEN 0
      ELSE rq.CommentCount
    END AS Comments,
    CASE
      WHEN rq.OwnerUserId IN (SELECT UserId FROM user_activity) THEN true
      ELSE false
    END AS IsActiveAuthor
  FROM recent_questions rq
)
SELECT
  c.Title AS QuestionTitle,
  c.Tags AS Tags,
  c.CreationDate AS QuestionCreated,
  c.LastActivityDate AS LastActive,
  c.Score AS OriginalScore,
  c.ScoreWithBountyAdj,
  c.ViewCount,
  c.CommentCount,
  au.DisplayName AS OwnerDisplayName,
  au.Reputation,
  au.PostsCount,
  au.CommentsCount,
  pct.LinkedPostId AS RelatedQuestionId,
  p2.Title AS RelatedQuestionTitle,
  p2.Score AS RelatedQuestionScore,
  p2.ViewCount AS RelatedQuestionViews,
  t.TagName
FROM complex_calc c
LEFT JOIN Users au ON c.OwnerUserId = au.Id
LEFT JOIN tag_pairs pct ON pct.PostId = c.PostId
LEFT JOIN Posts p2 ON pct.LinkedPostId = p2.Id
LEFT JOIN latest_edits le ON le.PostId = c.PostId
LEFT JOIN popular_tags t ON t.TagName = ANY(string_to_array(substring(c.Tags, 2, length(c.Tags)-2), '><'))
LEFT JOIN user_activity ua ON au.Id = ua.UserId
ORDER BY c.ScoreWithBountyAdj DESC, c.LastActivityDate DESC
LIMIT 100;
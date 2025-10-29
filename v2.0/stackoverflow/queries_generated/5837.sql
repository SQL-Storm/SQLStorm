-- {"query": "5837.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1052} 
WITH
sentiments AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate AS UserSince,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(u.WebsiteUrl, '') AS Website,
    COALESCE(u.EmailHash, '') AS EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
top_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
),
recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.Views,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
),
activity AS (
  SELECT
    rp.PostId,
    rp.OwnerUserId,
    rp.Title,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    -- complex expression: normalized activity score
    (COALESCE(rp.Score,0) * 1.5) + (COALESCE(rp.ViewCount,0) * 0.2) + (COALESCE(rp.CommentCount,0) * 0.5) AS score_metric,
    -- window function: rank posts per user by activity
    ROW_NUMBER() OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.LastActivityDate DESC, (COALESCE(rp.Score,0) + COALESCE(rp.ViewCount,0)) DESC) AS user_rank
  FROM recent_posts rp
),
paired AS (
  SELECT
    a.PostId,
    a.OwnerUserId,
    a.Title,
    a.LastActivityDate,
    a.score_metric,
    a.user_rank,
    u.Reputation,
    u.DisplayName AS OwnerName,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = a.OwnerUserId AND p2.PostTypeId = 1) AS QuestionsByUser,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = a.OwnerUserId AND p2.PostTypeId = 2) AS AnswersByUser
  FROM activity a
  JOIN Users u ON u.Id = a.OwnerUserId
  WHERE a.user_rank <= 50
),
link_stats AS (
  SELECT
    l.PostId,
    l.RelatedPostId,
    lt.Name AS LinkTypeName,
    p.Title AS RelatedTitle,
    p.OwnerUserId AS RelatedOwner
  FROM PostLinks l
  JOIN Posts p ON p.Id = l.RelatedPostId
  JOIN LinkTypes lt ON lt.Id = l.LinkTypeId
  WHERE l.LinkTypeId IN (1,3)
),
complex_eval AS (
  SELECT
    b.PostId,
    b.OwnerUserId,
    b.Title,
    b.LastActivityDate,
    b.score_metric,
    b.user_rank,
    b.QuestionsByUser,
    b.AnswersByUser,
    -- correlated subquery: average score of owner's questions
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = b.OwnerUserId AND p2.PostTypeId = 1) AS AvgOwnerQuestionScore,
    -- correlated subquery: count of tags for this post's tags
    (SELECT COUNT(*) FROM unnest(string_to_array(b.Title, ' ')) AS t(tag)) AS TitleWordCount
  FROM paired b
)
SELECT
  cu.UserId,
  cu.UserName,
  cu.Reputation,
  cu.UserSince,
  cu.LastAccessDate,
  cu.Location,
  cu.AboutMe,
  cu.Views,
  cu.UpVotes,
  cu.DownVotes,
  cu.Website,
  cu.EmailHash,
  cu.AccountId,
  c.PostId,
  c.Title AS PostTitle,
  c.LastActivityDate,
  c.score_metric,
  c.user_rank,
  c.QuestionsByUser,
  c.AnswersByUser,
  c.AvgOwnerQuestionScore,
  c.TitleWordCount,
  ls.RelatedPostId AS LinkedPostId,
  ls.LinkTypeName,
  ls.RelatedTitle,
  ls.RelatedOwner
FROM complex_eval c
JOIN sentiments cu ON cu.Id = c.OwnerUserId
LEFT JOIN link_stats ls ON ls.PostId = c.PostId
ORDER BY c.LastActivityDate DESC, c.score_metric DESC
LIMIT 200;
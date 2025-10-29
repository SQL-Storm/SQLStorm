-- {"query": "5667.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1058} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
author_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
tag_hotness AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagUsage,
    AVG(p.Score) AS AvgTagScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId OR p.Id = tg.WikiPostId
  JOIN UNNEST(string_to_array(tg.TagName, ', ')) AS t(TagName) ON TRUE
  GROUP BY t.TagName
),
top_questions AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.OwnerUserId,
    rq.Score,
    rq.ViewCount,
    rq.LastActivityDate,
    a.DisplayName AS OwnerDisplayName,
    a.Reputation AS OwnerReputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.PostId) AS CommentCount,
    (SELECT STRING_AGG(CONCAT('u', c2.UserDisplayName), '|') FROM Votes v2 JOIN Users c2 ON v2.UserId = c2.Id WHERE v2.PostId = rq.PostId AND v2.VoteTypeId = 2) AS Upvoters,
    (SELECT STRING_AGG(CONCAT('u', c3.UserDisplayName), '|') FROM Votes v3 JOIN Users c3 ON v3.UserId = c3.Id WHERE v3.PostId = rq.PostId AND v3.VoteTypeId = 3) AS Downvoters
  FROM recent_questions rq
  LEFT JOIN author_stats a ON a.UserId = rq.OwnerUserId
  WHERE rq.rn = 1
),
complex_calcs AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.OwnerDisplayName,
    tq.OwnerReputation,
    tq.CreationDate,
    tq.LastActivityDate,
    tq.Score,
    tq.ViewCount,
    tq.CommentCount,
    (tq.Score * 1.5) AS ScoreWeighted,
    (CASE WHEN tq.ViewCount > 1000 THEN true ELSE false END) AS IsPopular,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.PostId AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT STRING_AGG(COALESCE(uv.DisplayName, uv.UserName), ',') FROM Votes v JOIN Users uv ON v.UserId = uv.Id WHERE v.PostId = tq.PostId AND v.VoteTypeId = 2) AS UpVotersList
  FROM top_questions tq
)
SELECT
  cc.PostId,
  cc.Title,
  cc.OwnerDisplayName,
  cc.OwnerReputation,
  cc.CreationDate,
  cc.LastActivityDate,
  cc.Score,
  cc.ViewCount,
  cc.CommentCount,
  cc.ScoreWeighted,
  cc.IsPopular,
  cc.UpVotes,
  cc.DownVotes,
  cc.UpVotersList,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = cc.PostId AND pl.LinkTypeId = 1) AS LinkedCount,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = cc.PostId AND pl.LinkTypeId = 3) AS DuplicatedToCount,
  (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.OwnerUserId = cc.OwnerUserId) AS LastActivityByOwner
FROM complex_calcs cc
ORDER BY cc.LastActivityDate DESC
LIMIT 100;
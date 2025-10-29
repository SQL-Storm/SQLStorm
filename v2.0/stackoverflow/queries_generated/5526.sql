-- {"query": "5526.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1068} 
WITH recent_questions AS (
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
    p.FavoriteCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= now() - interval '30 days'
),
tag_pop AS (
  SELECT
    unnest(string_to_array(substr(rq.Tags, 2, length(rq.Tags)-2), '><')) AS tag,
    count(*) AS tag_count
  FROM recent_questions rq
  GROUP BY tag
),
top_tags AS (
  SELECT tag FROM tag_pop ORDER BY tag_count DESC LIMIT 10
),
q_with_top_tags AS (
  SELECT
    rq.Id AS PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.LastActivityDate,
    rq.CommentCount,
    rq.FavoriteCount,
    rq.AnswerCount,
    array_agg(tt.tag) FILTER (WHERE tt.tag IS NOT NULL) AS TopTags
  FROM recent_questions rq
  LEFT JOIN LATERAL (
    SELECT t.tag FROM unnest(string_to_array(substr(rq.Tags, 2, length(rq.Tags)-2), '><')) AS t(tag)
  ) tt ON true
  LEFT JOIN top_tags ttf ON tt.tag = ttf.tag
  GROUP BY rq.Id, rq.Title, rq.Tags, rq.CreationDate, rq.Score, rq.ViewCount, rq.OwnerUserId, rq.LastActivityDate, rq.CommentCount, rq.FavoriteCount, rq.AnswerCount
),
author_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.AboutMe,
    a.PostCount,
    a.LastPostDate
  FROM Users u
  LEFT JOIN (
    SELECT OwnerUserId, count(*) AS PostCount, max(CreationDate) AS LastPostDate
    FROM Posts
    WHERE PostTypeId IN (1,2) -- questions and answers
    GROUP BY OwnerUserId
  ) a ON a.OwnerUserId = u.Id
  WHERE u.Id IN (SELECT OwnerUserId FROM Posts WHERE PostTypeId = 1)
),
activity_summary AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.LastActivityDate,
    q.CommentCount,
    q.FavoriteCount,
    q.AnswerCount,
    q.TopTags,
    aa.UserId AS LastEditorId
  FROM q_with_top_tags q
  LEFT JOIN Posts p ON p.Id = q.PostId
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Users uu ON uu.Id = p.OwnerUserId
  LEFT JOIN (SELECT UserId, MAX(CreationDate) AS LastEdit
             FROM Posts
             WHERE LastEditDate IS NOT NULL
             GROUP BY UserId) le ON le.UserId = p.OwnerUserId
  LEFT JOIN (SELECT UserId, MAX(LastEditDate) AS LastEdit
             FROM Posts
             WHERE LastEditDate IS NOT NULL
             GROUP BY UserId) le2 ON le2.UserId = p.OwnerUserId
  UNION
  SELECT
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
)
SELECT
  aq.PostId,
  aq.Title,
  aq.Tags,
  aq.CreationDate AS PostCreationDate,
  aq.Score AS PostScore,
  aq.ViewCount AS PostViewCount,
  aq.OwnerUserId,
  aq.LastActivityDate AS PostLastActivityDate,
  aq.CommentCount,
  aq.FavoriteCount,
  aq.AnswerCount,
  aq.TopTags,
  au.UserId AS AuthorId,
  au.DisplayName AS AuthorName,
  au.Reputation AS AuthorReputation,
  au.UserCreationDate AS AuthorCreationDate,
  au.LastAccessDate AS AuthorLastAccessDate,
  au.Location AS AuthorLocation,
  au.AboutMe AS AuthorAbout,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = aq.PostId) AS CommentCountTotal,
  (SELECT ARRAY_AGG(DISTINCT v2.VoteTypeId) FROM Votes v2 WHERE v2.PostId = aq.PostId) AS VoteTypesOnPost
FROM activity_summary aq
LEFT JOIN author_activity au ON au.UserId = aq.OwnerUserId
LEFT JOIN LATERAL (
  SELECT *
) d ON true
ORDER BY aq.LastActivityDate DESC
LIMIT 100;
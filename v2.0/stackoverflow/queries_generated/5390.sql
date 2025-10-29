-- {"query": "5390.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 789} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
tag_pop AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) AS AvgScore
  FROM Unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
  JOIN Posts p ON p.Id = recent_questions.PostId
  GROUP BY t.TagName
),
top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    u.Location,
    u.AboutMe
  FROM Users u
  JOIN (
    SELECT OwnerUserId
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
  ) q ON q.OwnerUserId = u.Id
  ORDER BY u.Reputation DESC, u.UpVotes DESC
  LIMIT 100
),
activity AS (
  SELECT
    rp.PostId,
    rp.RelatedPostId,
    lt.Name AS LinkTypeName,
    rp.CreationDate AS LinkCreationDate
  FROM PostLinks rp
  JOIN LinkTypes lt ON rp.LinkTypeId = lt.Id
  WHERE rp.PostId IN (SELECT PostId FROM recent_questions)
)
SELECT
  rq.PostId,
  rq.Title,
  rq.CreationDate AS QuestionCreated,
  rq.OwnerUserId,
  rq.ViewCount,
  rq.Score,
  rq.AnswerCount,
  rq.CommentCount,
  uq.DisplayName AS OwnerDisplayName,
  coalesce(vt.Name, 'Unknown') AS LatestVoteType,
  MAX(v.CreationDate) AS LastVoteDate,
  STRING_AGG(DISTINCT tt.TagName, ',') AS TagsList,
  pa.AvgScore AS AvgTagScore,
  au.UserId AS TopContributorUserId,
  au.DisplayName AS TopContributorName,
  a.actions
FROM recent_questions rq
LEFT JOIN Votes v
  ON v.PostId = rq.PostId
LEFT JOIN VoteTypes vt
  ON v.VoteTypeId = vt.Id
LEFT JOIN (
  SELECT
    p.Id AS PostId,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  GROUP BY p.Id
) pa ON pa.PostId = rq.PostId
LEFT JOIN Users uq ON uq.Id = rq.OwnerUserId
LEFT JOIN top_users au ON au.Id = (
  SELECT OwnerUserId
  FROM Posts
  WHERE Id = rq.PostId
  LIMIT 1
)
LEFT JOIN unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) WITH ORDINALITY AS t(TagName, ord)
  ON true
LEFT JOIN tag_pop tp ON tp.TagName = t.TagName
GROUP BY
  rq.PostId,
  rq.Title,
  rq.CreationDate,
  rq.OwnerUserId,
  rq.ViewCount,
  rq.Score,
  rq.AnswerCount,
  rq.CommentCount,
  uq.DisplayName,
  vt.Name,
  pa.AvgScore,
  au.UserId,
  au.DisplayName
ORDER BY rq.CreationDate DESC
LIMIT 500;
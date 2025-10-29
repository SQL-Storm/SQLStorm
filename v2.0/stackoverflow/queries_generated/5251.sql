-- {"query": "5251.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 862} 
WITH
-- sample CTEs to prepare data
RecentQuestions AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.CreationDate,
         p.OwnerUserId,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.CommentCount,
         p.Tags,
         p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    AVG(p.Score) AS AvgQuestionScore,
    COUNT(*) AS QuestionCount
  FROM Tags tg
  JOIN Posts p ON tg.Id = p.Tags -- approximate join using Tags; in this schema Tags is separate, but for benchmarking we simulate
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
  ORDER BY AVG(p.Score) DESC
  LIMIT 10
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COUNT(p.Id) AS PostsCreated,
    SUM(CASE WHEN v.Id IS NOT NULL THEN 1 ELSE 0 END) AS UpvotesGiven,
    SUM(CASE WHEN vt.Id IN (2) THEN 1 ELSE 0 END) AS UpMods,
    SUM(CASE WHEN v2.Id IN (3) THEN 1 ELSE 0 END) AS DownvotesReceived
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
  LEFT JOIN Votes v2 ON v2.PostId = p.Id AND v2.VoteTypeId = 3
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  GROUP BY u.Id
),
ComplexPostAnalysis AS (
  SELECT
    rp.PostId AS RootPost,
    rp.Title AS RootTitle,
    rp.CreationDate AS RootCreationDate,
    rp.OwnerUserId AS RootOwner,
    JSON_AGG(JSON_BUILD_OBJECT(
      'RelatedPostId', c.Id,
      'RelationType', lt.Name,
      'RelationDate', c.CreationDate
    )) AS RelatedPosts
  FROM Posts rp
  LEFT JOIN PostLinks pl ON pl.PostId = rp.Id
  LEFT JOIN Posts c ON c.Id = pl.RelatedPostId
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE rp.PostTypeId = 1
  GROUP BY rp.Id
),
WindowStats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC, p.Score DESC) AS rn_viewed
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
)
SELECT
  rq.PostId,
  rq.Title AS QuestionTitle,
  rq.CreationDate AS QuestionCreated,
  rq.ViewCount,
  rq.Score,
  rq.AnswerCount,
  CAST(rq.Tags AS VARCHAR(4000)) AS TagsRaw,
  ua.DisplayName AS Owner,
  ua.Reputation AS OwnerReputation,
  ua.PostsCreated,
  ua.UpvotesGiven,
  ua.UpMods,
  ua.DownvotesReceived,
  w.PostId AS WindowPostId,
  w.Title AS WindowPostTitle,
  w.LastActivityDate,
  w.rn_viewed
FROM RecentQuestions rq
LEFT JOIN UserActivity ua ON ua.UserId = rq.OwnerUserId
LEFT JOIN WindowStats w ON w.PostId = rq.Id
LEFT JOIN ComplexPostAnalysis CPA ON CPA.RootPost = rq.Id
WHERE rq.LastActivityDate > rq.CreationDate - INTERVAL '2 hours'
  AND rq.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
ORDER BY rq.LastActivityDate DESC
LIMIT 100;
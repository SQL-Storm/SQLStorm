-- {"query": "5291.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 774} 
WITH
QualifiedQuestions AS (
  SELECT
    p.Id AS QuestionId,
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
    p.ContentLicense
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    t.TagName AS Tag,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesOnTag,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesOnTag
  FROM Tags t
  LEFT JOIN Posts p ON p.Id = t.WikiPostId
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE t.TagName IS NOT NULL
  GROUP BY t.TagName
),
RecentActivity AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.LastActivityDate DESC) AS rn
  FROM QualifiedQuestions q
),
UserInfluence AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT q.QuestionId) AS QuestionsCreated,
    SUM(q.Score) AS ScoreSum,
    SUM(q.ViewCount) AS TotalViews
  FROM Users u
  LEFT JOIN QualifiedQuestions q ON q.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
Aggregated AS (
  SELECT
    uq.QuestionId,
    uq.Title,
    uq.CreationDate,
    uq.LastActivityDate,
    uq.rn,
    t.Tag AS PrimaryTag
  FROM RecentActivity uq
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(uq.Tags, 2, length(uq.Tags)-2), ''><'')) AS Tag
  ) AS t ON TRUE
  WHERE uq.rn = 1
)
SELECT
  a.QuestionId,
  a.Title,
  a.CreationDate,
  a.LastActivityDate,
  a.PrimaryTag,
  u.DisplayName AS Owner,
  u.Reputation,
  a.Score,
  a.TotalViews,
  COALESCE(gt.UpvotesOnTag - gt.DownvotesOnTag, 0) AS NetTagMomentum,
  ARRAY_AGG(DISTINCT v.VoteTypeId) FILTER (WHERE v.PostId = a.QuestionId) AS VoteTypesOnQuestion,
  LEFT_JOINED.Tags AS TagsSnapshot
FROM Aggregated a
LEFT JOIN Users u ON u.Id = (SELECT OwnerUserId FROM Posts p WHERE p.Id = a.QuestionId)
LEFT JOIN TopTags gt ON gt.Tag = a.PrimaryTag
LEFT JOIN LATERAL (
  SELECT string_agg(t.TagName, ',') AS TagsSnapshot
  FROM (
    SELECT unnest(string_to_array(substring((SELECT Tags FROM Posts WHERE Id = a.QuestionId), 2, length((SELECT Tags FROM Posts WHERE Id = a.QuestionId))-2), ''><'')) AS TagName
  ) tsub
) AS LEFT_JOINED ON TRUE
LEFT JOIN Votes v ON v.PostId = a.QuestionId
GROUP BY
  a.QuestionId, a.Title, a.CreationDate, a.LastActivityDate, a.PrimaryTag, u.DisplayName, u.Reputation, a.Score, a.TotalViews, LEFT_JOINED.Tags;
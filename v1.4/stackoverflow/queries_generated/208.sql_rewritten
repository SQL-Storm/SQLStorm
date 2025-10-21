-- {"query": "208.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 7655} 
WITH TagAgg AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId AS UserId,
    u.DisplayName AS UserDisplayName,
    pt.Name AS PostTypeName,
    p.Title AS PostTitle,
    p.Score AS PostScore,
    p.ViewCount,
    COALESCE(p.LastActivityDate, p.CreationDate) AS LastActivityDate,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE((
      SELECT string_agg(t.TagName, ',')
      FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
    ), '') AS TagList
  FROM Posts p
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE (COALESCE(p.LastActivityDate, p.CreationDate) >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '60 days')::timestamp)
     OR (p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '60 days')::timestamp)
),
Ranked AS (
  SELECT
    UserId,
    UserDisplayName,
    PostId,
    PostTypeName,
    PostTitle,
    PostScore,
    ViewCount,
    LastActivityDate,
    AnswerCount,
    TagList,
    ROW_NUMBER() OVER (PARTITION BY UserId, PostTypeName ORDER BY PostScore DESC, LastActivityDate DESC) AS rn
  FROM TagAgg
),
PerUserTopQuestions AS (
  SELECT UserId, UserDisplayName, PostId, PostTypeName, PostTitle, PostScore, ViewCount, LastActivityDate, AnswerCount, TagList, rn
  FROM Ranked
  WHERE PostTypeName = 'Question' AND rn <= 5
),
PerUserTopAnswers AS (
  SELECT UserId, UserDisplayName, PostId, PostTypeName, PostTitle, PostScore, ViewCount, LastActivityDate, AnswerCount, TagList, rn
  FROM Ranked
  WHERE PostTypeName = 'Answer' AND rn <= 5
)
SELECT *
FROM PerUserTopQuestions
UNION ALL
SELECT *
FROM PerUserTopAnswers
ORDER BY UserId, PostTypeName, rn;
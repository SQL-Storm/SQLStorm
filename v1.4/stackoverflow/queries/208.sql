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
      SELECT STRING_AGG(t.TagName, ',')
      FROM (
        SELECT TRIM(t.TagName) AS TagName
        FROM UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
      ) AS t
    ), '') AS TagList
  FROM Posts p
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE (COALESCE(p.LastActivityDate, p.CreationDate) >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '60 days'))
     OR (p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '60 days'))
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
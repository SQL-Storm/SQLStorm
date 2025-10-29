WITH RecentQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title AS QuestionTitle,
    p.OwnerUserId,
    p.CreationDate AS QuestionCreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    RANK() OVER (ORDER BY p.CreationDate DESC) AS QuestionRank
  FROM Posts AS p
  JOIN Users AS u
    ON p.OwnerUserId = u.Id
  WHERE
    p.PostTypeId = 1 AND p.ClosedDate IS NULL AND p.CreationDate > TIMESTAMP '2023-01-01'
),
HighReputationAnswers AS (
  SELECT
    p.Id AS AnswerId,
    p.ParentId AS QuestionId,
    p.OwnerUserId,
    p.CreationDate AS AnswerCreationDate,
    u.DisplayName AS AnswererDisplayName,
    u.Reputation AS AnswererReputation,
    ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRank
  FROM Posts AS p
  JOIN Users AS u
    ON p.OwnerUserId = u.Id
  WHERE
    p.PostTypeId = 2 AND p.ParentId IN (SELECT QuestionId FROM RecentQuestions) AND p.Score > 5
),
UserActivity AS (
  SELECT
    UserId,
    COUNT(Id) AS NumComments,
    SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreComments
  FROM Comments
  WHERE
    UserId IS NOT NULL AND CreationDate > TIMESTAMP '2023-01-01'
  GROUP BY
    UserId
),
MergedPosts AS (
  SELECT
    PostId AS MergedSourceId,
    RelatedPostId AS MergedDestinationId,
    1 AS LinkType
  FROM PostLinks
  WHERE
    LinkTypeId = 3
  UNION ALL
  SELECT
    RelatedPostId AS MergedSourceId,
    PostId AS MergedDestinationId,
    1 AS LinkType
  FROM PostLinks
  WHERE
    LinkTypeId = 3
)
SELECT
  rq.QuestionTitle,
  rq.OwnerDisplayName AS QuestionOwner,
  rq.OwnerReputation,
  COALESCE(hra.AnswererDisplayName, 'No High-Score Answer') AS BestAnswerer,
  COALESCE(hra.AnswererReputation, 0) AS BestAnswererReputation,
  CAST((EXTRACT(EPOCH FROM ( (TIMESTAMP '2024-10-01 12:34:56' AT TIME ZONE 'UTC') - rq.QuestionCreationDate)) ) / 86400 AS INTEGER) AS DaysSinceQuestion,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = rq.QuestionId AND c.CreationDate BETWEEN rq.QuestionCreationDate AND (rq.QuestionCreationDate + INTERVAL '7 day')
  ) AS CommentsInFirstWeek,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM MergedPosts AS mp
      WHERE
        mp.MergedSourceId = rq.QuestionId
    )
    THEN 'Merged'
    ELSE 'Not Merged'
  END AS MergeStatus,
  ua.NumComments AS OwnerTotalComments,
  ua.PositiveScoreComments AS OwnerPositiveComments,
  CASE
    WHEN rq.QuestionTitle LIKE '%SQL%' AND rq.QuestionTitle NOT LIKE '%T-SQL%'
    THEN 'Standard SQL'
    WHEN rq.QuestionTitle LIKE '%T-SQL%'
    THEN 'T-SQL'
    ELSE 'Other'
  END AS TitleSqlType,
  COALESCE(pt.Name, 'Unknown') AS PostType
FROM RecentQuestions AS rq
LEFT JOIN HighReputationAnswers AS hra
  ON rq.QuestionId = hra.QuestionId AND hra.AnswerRank = 1
LEFT JOIN UserActivity AS ua
  ON rq.OwnerUserId = ua.UserId
LEFT JOIN PostTypes AS pt
  ON 1 = pt.Id
WHERE
  rq.QuestionRank <= 100
GROUP BY
  rq.QuestionTitle,
  rq.OwnerDisplayName,
  rq.OwnerReputation,
  hra.AnswererDisplayName,
  hra.AnswererReputation,
  rq.QuestionCreationDate,
  rq.QuestionId,
  ua.NumComments,
  ua.PositiveScoreComments,
  pt.Name,
  rq.OwnerUserId,
  hra.AnswerRank,
  rq.QuestionRank
ORDER BY
  rq.QuestionCreationDate DESC
LIMIT 50 OFFSET 0;
WITH RECURSIVE CaseTaggedPostsFromLast6Months AS (
  SELECT
    p.Id AS QuestionId
  FROM
    posts p
  WHERE
    p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '6 months'
)
SELECT
  QuestionId
FROM
  CaseTaggedPostsFromLast6Months;
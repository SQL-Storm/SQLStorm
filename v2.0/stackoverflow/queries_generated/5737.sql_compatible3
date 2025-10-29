WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.LastActivityDate IS NOT NULL
),
TopQuestions AS (
  SELECT
    rap.Id AS QuestionId,
    rap.Title,
    rap.OwnerUserId,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    rap.Tags,
    COALESCE(SQRT(ABS(rap.Score)) * 1.5, 0) +
      (SELECT AVG(vt.BountyAmount) FROM Votes vt WHERE vt.PostId = rap.Id AND vt.VoteTypeId = 8) AS QualityScore
  FROM RecentActivePosts rap
  WHERE rap.PostTypeId = 1
    AND rap.rn <= 50
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.Count > 100
),
ExplodedTags AS (
  SELECT
    q.QuestionId,
    TRIM(BOTH '<>' FROM UNNEST_TAG) AS TagName
  FROM TopQuestions q,
  LATERAL (
    SELECT unnest_val AS UNNEST_TAG
    FROM (
      SELECT regexp_split_to_table(
        replace(replace(q.Tags, '><', '>|<'), '><', '>|<'),
        '\|'
      ) AS unnest_val
    ) AS sub
  ) s
),
TagEngagement AS (
  SELECT
    e.TagName,
    COUNT(*) AS QuestionCount,
    AVG(q.Score) AS AvgQuestionScore,
    SUM(CASE WHEN q.ViewCount > 1000 THEN 1 ELSE 0 END) AS HighViewQuestions
  FROM ExplodedTags e
  JOIN TopQuestions q ON q.QuestionId = e.QuestionId
  GROUP BY e.TagName
)
SELECT
  q.QuestionId,
  q.Title AS QuestionTitle,
  u.DisplayName AS OwnerName,
  q.CreationDate,
  q.LastActivityDate,
  q.Score AS QuestionScore,
  q.ViewCount AS Views,
  q.Tags,
  (
    SELECT STRING_AGG(
      CASE WHEN v.VoteTypeId = 2 THEN 'Up' WHEN v.VoteTypeId = 3 THEN 'Down' END,
      ','
    )
    FROM Votes v
    WHERE v.PostId = q.QuestionId
  ) AS VoteSummary,
  CASE
    WHEN q.Score > 0 THEN 'Positive'
    WHEN q.Score = 0 THEN 'Neutral'
    ELSE 'Negative'
  END AS ScoreTone,
  ta.QuestionCount,
  ta.AvgQuestionScore,
  ta.HighViewQuestions
FROM TopQuestions q
LEFT JOIN Users u ON q.OwnerUserId = u.Id
LEFT JOIN (
  SELECT DISTINCT te.QuestionId, te.TagName, te.TagName AS join_tag
  FROM ExplodedTags te
) qtags ON q.QuestionId = qtags.QuestionId
LEFT JOIN TagEngagement ta ON ta.TagName = qtags.join_tag
WHERE q.QuestionId IS NOT NULL
GROUP BY
  q.QuestionId,
  q.Title,
  u.DisplayName,
  q.CreationDate,
  q.LastActivityDate,
  q.Score,
  q.ViewCount,
  q.Tags,
  ta.QuestionCount,
  ta.AvgQuestionScore,
  ta.HighViewQuestions,
  qtags.join_tag
ORDER BY q.LastActivityDate DESC, q.Score DESC
LIMIT 100;
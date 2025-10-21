WITH TagActivity AS (
  SELECT
    t.TagName,
    p.Id AS QuestionId,
    p.Title,
    p.Score,
    p.OwnerUserId,
    p.CreationDate AS QuestionCreationDate,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.CreationDate ASC) AS TagFirstQuestionRank
  FROM
    Tags t
    JOIN Posts p ON p.PostTypeId = 1 AND p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
),
TopContributors AS (
  SELECT
    ta.TagName,
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT ta.QuestionId) AS QuestionsAsked,
    COALESCE(SUM(po.Score),0) AS TotalQuestionScore,
    DENSE_RANK() OVER (PARTITION BY ta.TagName ORDER BY COUNT(DISTINCT ta.QuestionId) DESC, COALESCE(SUM(po.Score),0) DESC) AS ContributorRank
  FROM
    TagActivity ta
    JOIN Users u ON u.Id = ta.OwnerUserId
    LEFT JOIN Posts po ON po.Id = ta.QuestionId
  GROUP BY
    ta.TagName, u.Id, u.DisplayName
),
RecentEdits AS (
  SELECT
    ph.PostId,
    MAX(ph.CreationDate) AS LastEditDate
  FROM
    PostHistory ph
  WHERE
    ph.PostHistoryTypeId IN (4,5,6)
  GROUP BY
    ph.PostId
),
CommentStats AS (
  SELECT
    c.PostId,
    COUNT(*) AS TotalComments,
    MAX(c.Score) AS MaxCommentScore,
    MIN(c.Score) AS MinCommentScore
  FROM
    Comments c
  GROUP BY
    c.PostId
)
SELECT
  ta.TagName,
  tc.DisplayName AS TopContributor,
  tc.QuestionsAsked,
  tc.TotalQuestionScore,
  ta.QuestionId,
  ta.Title AS QuestionTitle,
  ta.Score AS QuestionScore,
  u.Reputation AS OwnerReputation,
  ta.QuestionCreationDate,
  re.LastEditDate,
  CASE
    WHEN re.LastEditDate IS NULL THEN 'Never Edited'
    ELSE
      CASE
        WHEN re.LastEditDate > ta.QuestionCreationDate + INTERVAL '30' DAY THEN 'Heavily Edited'
        ELSE 'Lightly Edited'
      END
  END AS EditStatus,
  cs.TotalComments,
  COALESCE(cs.MaxCommentScore,0) - COALESCE(cs.MinCommentScore,0) AS CommentScoreSpread,
  CASE
    WHEN ta.TagFirstQuestionRank = 1 THEN 'Tag Pioneer'
    ELSE NULL
  END AS SpecialTitle
FROM
  TagActivity ta
  INNER JOIN TopContributors tc ON tc.TagName = ta.TagName
    AND tc.ContributorRank = 1
    AND tc.UserId = ta.OwnerUserId
  LEFT JOIN Users u ON u.Id = ta.OwnerUserId
  LEFT JOIN RecentEdits re ON re.PostId = ta.QuestionId
  LEFT JOIN CommentStats cs ON cs.PostId = ta.QuestionId
WHERE
  (tc.QuestionsAsked > 3 OR tc.TotalQuestionScore > 10)
  AND ta.Score >= (
    SELECT AVG(Score) FROM Posts p2 WHERE p2.PostTypeId = 1 AND p2.Tags LIKE '%' || '<' || ta.TagName || '>' || '%'
  )
  AND (
    ta.QuestionCreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days'
    OR ta.TagFirstQuestionRank = 1
  )
ORDER BY
  tc.TotalQuestionScore DESC, ta.Score DESC, ta.QuestionCreationDate DESC
LIMIT 100;
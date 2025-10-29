-- {"query": "5037.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 724} 
WITH TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ViewCount > 0
),
OwnerStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT t.PostId) AS QuestionsViewed,
    SUM(t.ViewCount) AS TotalViewsByUser,
    MAX(t.CreationDate) AS LastQuestionDate
  FROM TopQuestions t
  JOIN Users u ON u.Id = t.OwnerUserId
  WHERE t.rn_owner = 1
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.LastActivityDate,
    v.VoteTypeId,
    v.UserId AS VoterId,
    v.CreationDate AS VoteDate
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > DATEADD(minute, -60, GETDATE())
),
TagLinkage AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagUseCount
  FROM Tags t
  GROUP BY t.TagName
  HAVING COUNT(*) > 5
),
ComplexComposition AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    EXISTS (
      SELECT 1
      FROM Posts p
      WHERE p.OwnerUserId = u.Id
        AND p.PostTypeId = 1
        AND p.Title IS NOT NULL
        AND p.Title <> ''
    ) AS HasQuestionWithTitle
  FROM Users u
  WHERE u.AccountId IS NOT NULL
)
SELECT
  oc.UserId,
  oc.DisplayName,
  oc.Reputation,
  os.QuestionsViewed,
  os.TotalViewsByUser,
  os.LastQuestionDate,
  ra.PostId AS MostActiveQuestionId,
  ra.Title AS MostActiveQuestionTitle,
  ra.LastActivityDate AS MostActiveDate,
  tc.TagName AS PredominantTag,
  tc.TagUseCount AS TagFrequency,
  cc.HasQuestionWithTitle
FROM ComplexComposition cc
JOIN OwnerStats os ON os.UserId = cc.UserId
LEFT JOIN (
  SELECT
    p.OwnerUserId,
    p.Id,
    p.Title,
    p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 1
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) = 1
) ra ON ra.OwnerUserId = cc.UserId
LEFT JOIN (
  SELECT
    t.TagName,
    t.Count AS TagCount
  FROM Tags t
) tc ON 1=1
ORDER BY os.TotalViewsByUser DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
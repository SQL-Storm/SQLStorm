-- {"query": "4556.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1195}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserAvgScore AS (
    SELECT
      p.OwnerUserId,
      AVG(CAST(p.Score AS DECIMAL(10, 2))) AS AvgPostScore
    FROM
      Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.Score IS NOT NULL
      AND p.PostTypeId = 1
    GROUP BY
      p.OwnerUserId
  ),
  QuestionLag AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.CreationDate,
      LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousQuestionDate
    FROM
      Posts p
    WHERE
      p.PostTypeId = 1
  )
SELECT
  p.Id AS PostId,
  p.Title,
  pt.Name AS PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.CreationDate AS PostCreationDate,
  p.LastActivityDate,
  COALESCE(p.ClosedDate, CAST('1900-01-01' AS DATE)) AS CoalescedClosedDate,
  CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
  uav.AvgPostScore AS OwnerAvgQuestionScore,
  qag.DisplayName AS RecentEditorDisplayName,
  qag.Reputation AS RecentEditorReputation,
  -- minutes difference between previous question by same owner and this question's creation
  EXTRACT(EPOCH FROM (ql.CreationDate - ql.PreviousQuestionDate)) / 60.0 AS TimeBetweenQuestions,
  phr.rn AS RecentEditRank,
  CASE
    WHEN ph.Comment LIKE '%exact duplicate%' THEN 'Exact Duplicate'
    WHEN ph.Comment LIKE '%off-topic%' THEN 'Off-Topic'
    WHEN ph.Comment LIKE '%subjective%' THEN 'Subjective'
    WHEN ph.Comment LIKE '%not a real question%' THEN 'Not A Real Question'
    WHEN ph.Comment LIKE '%too localized%' THEN 'Too Localized'
    WHEN ph.Comment LIKE '%general reference%' THEN 'General Reference'
    WHEN ph.Comment LIKE '%opinion-based%' THEN 'Opinion-Based'
    ELSE 'Other Close Reason'
  END AS CloseReasonCategory
FROM
  Posts p
LEFT JOIN
  PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN
  Users u
  ON p.OwnerUserId = u.Id
LEFT JOIN
  UserAvgScore uav
  ON p.OwnerUserId = uav.OwnerUserId
LEFT JOIN
  QuestionLag ql
  ON p.Id = ql.QuestionId
LEFT JOIN
  RankedPostEdits phr
  ON p.Id = phr.PostId AND phr.rn = 1
LEFT JOIN
  Users qag
  ON phr.UserId = qag.Id
LEFT JOIN
  PostHistory ph
  ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
WHERE
  p.PostTypeId = 1
  AND p.Score > 10
  AND u.Reputation > 1000
  AND p.AnswerCount BETWEEN 1 AND 10
  AND EXISTS (
    SELECT
      1
    FROM
      Tags t
    WHERE
      t.TagName IN ('sql', 'performance', 'optimization')
      AND p.Tags LIKE '%' || t.TagName || '%'
  )
  AND (
    p.Title LIKE '%benchmark%'
    OR p.Body LIKE '%benchmark%'
  )
  AND p.CreationDate BETWEEN CAST('2023-01-01' AS DATE) AND CAST('2023-12-31' AS DATE)
GROUP BY
  p.Id,
  p.Title,
  pt.Name,
  u.DisplayName,
  u.Reputation,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.CreationDate,
  p.LastActivityDate,
  COALESCE(p.ClosedDate, CAST('1900-01-01' AS DATE)),
  CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END,
  uav.AvgPostScore,
  qag.DisplayName,
  qag.Reputation,
  ql.PreviousQuestionDate,
  ql.CreationDate,
  phr.rn,
  ph.Comment
HAVING
  COUNT(DISTINCT ph.PostHistoryTypeId) > 1
ORDER BY
  p.LastActivityDate DESC
LIMIT 100;
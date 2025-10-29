-- {"query": "4556.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1195} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserAvgScore AS (
    SELECT
      p.OwnerUserId,
      AVG(CAST(p.Score AS DECIMAL(10, 2))) AS AvgPostScore
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.Score IS NOT NULL
      AND p.PostTypeId = 1 -- Questions
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
      Posts AS p
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
  COALESCE(p.ClosedDate, '1900-01-01') AS CoalescedClosedDate,
  CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
  uav.AvgPostScore AS OwnerAvgQuestionScore,
  qag.OwnerDisplayName AS RecentEditorDisplayName,
  qag.Reputation AS RecentEditorReputation,
  DATEDIFF(minute, ql.PreviousQuestionDate, ql.CreationDate) AS TimeBetweenQuestions,
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
  Posts AS p
LEFT OUTER JOIN
  PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT OUTER JOIN
  Users AS u
  ON p.OwnerUserId = u.Id
LEFT OUTER JOIN
  UserAvgScore AS uav
  ON p.OwnerUserId = uav.OwnerUserId
LEFT OUTER JOIN
  QuestionLag AS ql
  ON p.Id = ql.QuestionId
LEFT OUTER JOIN
  RankedPostEdits AS phr
  ON p.Id = phr.PostId AND phr.rn = 1
LEFT OUTER JOIN
  Users AS qag
  ON phr.UserId = qag.Id
LEFT OUTER JOIN
  PostHistory AS ph
  ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10 AND ph.rn = 1 -- Assuming we are looking at the first close event
WHERE
  p.PostTypeId = 1 -- Focusing on Questions
  AND p.Score > 10
  AND u.Reputation > 1000
  AND p.AnswerCount BETWEEN 1 AND 10
  AND EXISTS (
    SELECT
      1
    FROM
      Tags AS t
    WHERE
      t.TagName IN ('sql', 'performance', 'optimization')
      AND p.Tags LIKE '%' || t.TagName || '%'
  )
  AND (
    p.Title LIKE '%benchmark%'
    OR p.Body LIKE '%benchmark%'
  )
  AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY
  p.Id,
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
  CoalescedClosedDate,
  IsCommunityOwned,
  OwnerAvgQuestionScore,
  RecentEditorDisplayName,
  RecentEditorReputation,
  TimeBetweenQuestions,
  phr.rn,
  CloseReasonCategory
HAVING
  COUNT(DISTINCT ph.PostHistoryTypeId) > 1 -- Ensure post has been edited and closed/reopened etc.
ORDER BY
  p.LastActivityDate DESC
LIMIT 100;

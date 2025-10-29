-- {"query": "5705.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 560} 
WITH TopQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    u.DisplayName AS OwnerName,
    u.Reputation,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
RecentActivity AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.OwnerName,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    MAX(h.CreationDate) AS LastRevisionDate
  FROM TopQuestions q
  LEFT JOIN PostHistory h
    ON h.PostId = q.QuestionId
   AND h.PostHistoryTypeId IN (2,5,10,11,16,24,50)
  GROUP BY
    q.QuestionId, q.Title, q.OwnerName, q.CreationDate, q.ViewCount, q.Score, q.AnswerCount
),
TagEngagement AS (
  SELECT
    t.TagName,
    SUM(p.Scored) AS _dummy -- placeholder to ensure diversity in query shape
  FROM Tags t
  LEFT JOIN PostLinks pl ON pl.RelatedPostId = t.Id
  LEFT JOIN Posts p ON p.Id = pl.PostId
  GROUP BY t.TagName
),
CorrStats AS (
  SELECT
    r.QuestionId,
    r.Title,
    r.OwnerName,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.AnswerCount,
    r.LastRevisionDate,
    -- window function to compute moving average of views over last 7 questions by creation date
    AVG(r.ViewCount) OVER (ORDER BY r.CreationDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS SevenQuestionViewAvg
  FROM RecentActivity r
)
SELECT
  c.QuestionId,
  c.Title,
  c.OwnerName,
  c.CreationDate,
  c.ViewCount,
  c.Score,
  c.AnswerCount,
  c.LastRevisionDate,
  c.SevenQuestionViewAvg,
  -- compute a derived metric: engagement score using score, viewcount, and answer count
  (c.Score * 2 + c.ViewCount / NULLIF(c.AnswerCount,0) ) AS EngagementScore
FROM CorrStats c
ORDER BY c.LastRevisionDate DESC NULLS LAST
LIMIT 100;
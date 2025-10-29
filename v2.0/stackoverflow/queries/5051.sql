-- {"query": "5051.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 821} 
WITH

-- 1) Identify highly engaged questions with a rich edit history and multiple related posts
EngagedQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.Score is not null
    AND p.ViewCount > 100
),

-- 2) Correlated subquery: fetch the latest 5 edits (PostHistoryTypeId in 4/5/6) per question
LatestEdits AS (
  SELECT
    ph.PostId AS QuestionId,
    ph.Id AS HistoryId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserDisplayName,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.PostId IN (SELECT QuestionId FROM EngagedQuestions)
    AND ph.PostHistoryTypeId IN (4,5,6)
  ORDER BY ph.CreationDate DESC
),
LatestEditsRanked AS (
  SELECT
    QuestionId,
    HistoryId,
    PostHistoryTypeId,
    CreationDate,
    UserDisplayName,
    Comment,
    ROW_NUMBER() OVER (PARTITION BY QuestionId ORDER BY CreationDate DESC) AS rn
  FROM LatestEdits
)

-- 3) Windowed summary: compute a moving average of comments per post over last 7 days
, MovingCommentAvg AS (
  SELECT
    p.Id AS PostId,
    AVG(c.Cnt) OVER (PARTITION BY p.Id ORDER BY c.Dt ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS AvgCommentsLast7d
  FROM Posts p
  LEFT JOIN (
    SELECT
      PostId,
      COUNT(*) AS Cnt,
      CAST(CreationDate AS DATE) AS Dt
    FROM Comments
    GROUP BY PostId, CAST(CreationDate AS DATE)
  ) c ON c.PostId = p.Id
  WHERE p.PostTypeId IN (1,2) -- include questions and answers
)

-- 4) Aggregate: link relationships and tag-based activity
, LinkAnalysis AS (
  SELECT
    pl.PostId,
    COUNT(*) AS LinkCount,
    SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinks
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY pl.PostId
)

SELECT
  eq.QuestionId,
  eq.Title AS QuestionTitle,
  eq.CreationDate AS QuestionCreated,
  eq.Score AS QuestionScore,
  eq.ViewCount AS QuestionViews,
  eq.OwnerUserId,
  eq.Tags,
  eq.CommentCount,
  eq.AnswerCount,
  eq.LastActivityDate,
  le.HistoryId AS LatestEditId,
  le.PostHistoryTypeId AS LatestEditType,
  le.CreationDate AS LatestEditDate,
  le.UserDisplayName AS LatestEditUser,
  le.Comment AS LatestEditComment,
  mec.AvgCommentsLast7d,
  la.LinkCount,
  la.DuplicateLinks
FROM EngagedQuestions eq
LEFT JOIN LatestEditsRanked le
  ON le.QuestionId = eq.QuestionId AND le.rn = 1
LEFT JOIN MovingCommentAvg mec
  ON mec.PostId = eq.QuestionId
LEFT JOIN LinkAnalysis la
  ON la.PostId = eq.QuestionId
WHERE
  -- Complicated predicate: questions that have at least one edit, more than 1 related link, and a high engagement
  le.HistoryId IS NOT NULL
  AND la.LinkCount > 0
  AND eq.ViewCount > 300
ORDER BY eq.LastActivityDate DESC
LIMIT 100;
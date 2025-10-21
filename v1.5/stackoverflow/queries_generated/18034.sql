-- {"query": "18034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1126} 

WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
  ),
  LatestEdits AS (
    SELECT
      rph.PostId,
      rph.UserId AS LastEditorUserId,
      rph.CreationDate AS LastEditDate,
      u.DisplayName AS LastEditorDisplayName
    FROM RankedPostHistory AS rph
    LEFT JOIN Users AS u
      ON rph.UserId = u.Id
    WHERE
      rph.rn = 1 AND rph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
  ),
  QuestionPostHistory AS (
    SELECT
      ph.PostId,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseVoteCount,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS ReopenVoteCount
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (10, 11)
    GROUP BY
      ph.PostId
  ),
  UserPostCounts AS (
    SELECT
      p.OwnerUserId,
      COUNT(CASE WHEN pt.Name = 'Question' THEN 1 ELSE NULL END) AS QuestionCount,
      COUNT(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE NULL END) AS AnswerCount
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    GROUP BY
      p.OwnerUserId
  )
SELECT
  p.Id AS PostId,
  pt.Name AS PostType,
  p.Title,
  COALESCE(le.LastEditorDisplayName, 'Community') AS LastEditor,
  le.LastEditDate,
  COALESCE(upc.QuestionCount, 0) AS UserQuestions,
  COALESCE(upc.AnswerCount, 0) AS UserAnswers,
  phq.CloseVoteCount,
  phq.ReopenVoteCount,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  LENGTH(p.Body) AS BodyLength,
  REPLACE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><', ',') AS FormattedTags,
  CASE
    WHEN INSTR(p.Tags, '<sql>') > 0 THEN 'SQL Tag Present'
    WHEN INSTR(p.Tags, '<python>') > 0 THEN 'Python Tag Present'
    ELSE 'Other Tags'
  END AS TagCategory,
  UPPER(COALESCE(u.DisplayName, 'N/A')) AS OwnerDisplayName,
  CASE
    WHEN p.Score > 100 THEN 'High Score'
    WHEN p.Score < 0 THEN 'Negative Score'
    ELSE 'Neutral Score'
  END AS ScoreCategory,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) THEN 'Is Duplicate Link'
    ELSE 'No Duplicate Link'
  END AS DuplicateLinkStatus,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = p.Id AND c.UserId IS NULL
  ) AS AnonymousCommentCount
FROM Posts AS p
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN LatestEdits AS le
  ON p.Id = le.PostId
LEFT JOIN QuestionPostHistory AS phq
  ON p.Id = phq.PostId
LEFT JOIN UserPostCounts AS upc
  ON p.OwnerUserId = upc.OwnerUserId
LEFT JOIN Users AS u
  ON p.OwnerUserId = u.Id
WHERE
  p.CreationDate >= '2023-01-01' AND p.CreationDate < '2024-01-01'
  AND (
    p.Score > 5 OR p.AnswerCount > 3 OR p.CommentCount > 5
  )
UNION ALL
SELECT
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM Users
WHERE
  NOT EXISTS (
    SELECT
      1
    FROM Posts AS p
    WHERE
      p.OwnerUserId = Users.Id
  );

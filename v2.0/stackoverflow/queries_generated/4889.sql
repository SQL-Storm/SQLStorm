-- {"query": "4889.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1098} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  LatestPostInfo AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.CreationDate AS PostCreationDate,
      MAX(p.LastActivityDate) AS LatestActivityDate
    FROM
      Posts AS p
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.CreationDate
  ),
  UserContributions AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
      SUM(COALESCE(v.VoteTypeId, 0)) AS TotalVotesCast -- Placeholder for vote type sum, actual logic might differ
    FROM
      Users AS u
    LEFT JOIN
      Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN
      Votes AS v
      ON u.Id = v.UserId
    WHERE
      u.Reputation > 1000
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  PostEditDetails AS (
    SELECT
      lpe.PostId,
      lpe.UserId AS EditorUserId,
      lpe.CreationDate AS EditDate,
      u.DisplayName AS EditorDisplayName,
      CASE
        WHEN lpe.PostHistoryTypeId = 4 THEN 'Title Edit'
        WHEN lpe.PostHistoryTypeId = 5 THEN 'Body Edit'
        WHEN lpe.PostHistoryTypeId = 6 THEN 'Tags Edit'
        ELSE 'Unknown Edit'
      END AS EditType
    FROM
      RankedPostEdits AS lpe
    JOIN
      Users AS u
      ON lpe.UserId = u.Id
    WHERE
      lpe.rn = 1
  )
SELECT
  lpi.PostId,
  lpi.Title,
  lpe.EditType,
  lpe.EditDate,
  lpe.EditorDisplayName,
  lpi.OwnerUserId,
  uc.DisplayName AS OwnerDisplayName,
  uc.QuestionCount,
  uc.AnswerCount,
  uc.TotalVotesCast,
  CASE
    WHEN lpi.LatestActivityDate > DATE('now', '-30 day') THEN 'Recent Activity'
    WHEN lpi.PostCreationDate < DATE('now', '-365 day') THEN 'Old Post'
    ELSE 'Mid-Age Post'
  END AS PostAgeCategory,
  COALESCE(p.Score, 0) AS PostScore,
  COALESCE(p.AnswerCount, 0) AS NumberOfAnswers,
  CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
  CONCAT(SUBSTRING(lpi.Tags, 2, INSTR(lpi.Tags, '>') - 2), ', ', SUBSTRING(lpi.Tags, INSTR(lpi.Tags, '>') + 2, INSTR(lpi.Tags, '><', INSTR(lpi.Tags, '>') + 2) - (INSTR(lpi.Tags, '>') + 2))) AS FirstTwoTags -- Extracts first two tags, assuming they exist and are delimited by ><
FROM
  LatestPostInfo AS lpi
JOIN
  PostEditDetails AS lpe
  ON lpi.PostId = lpe.PostId
LEFT JOIN
  UserContributions AS uc
  ON lpi.OwnerUserId = uc.UserId
LEFT JOIN
  Posts AS p
  ON lpi.PostId = p.Id
WHERE
  lpi.Title IS NOT NULL
  AND uc.Reputation > 5000
  AND (
    uc.AnswerCount > 10
    OR uc.QuestionCount > 5
  )
  AND EXISTS (
    SELECT
      1
    FROM
      Comments AS c
    WHERE
      c.PostId = lpi.PostId
      AND c.CreationDate > DATE('now', '-7 day')
      AND LENGTH(c.Text) > 50
  )
ORDER BY
  lpe.EditDate DESC
LIMIT 100;

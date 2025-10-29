-- {"query": "4898.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1050} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  LatestEdits AS (
    SELECT
      rpe.PostId,
      rpe.UserId AS LastEditorUserId,
      rpe.CreationDate AS LastEditDate
    FROM RankedPostEdits AS rpe
    WHERE
      rpe.rn = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    GROUP BY
      u.Id
  ),
  TagEngagement AS (
    SELECT
      p.Id AS PostId,
      pt.Name AS PostTypeName,
      t.TagName,
      CASE
        WHEN ph.PostHistoryTypeId = 6 THEN 'Edited'
        WHEN ph.PostHistoryTypeId = 3 THEN 'Initial'
        ELSE 'Other'
      END AS TagHistoryType,
      COUNT(ph.Id) AS TagHistoryCount,
      ROW_NUMBER() OVER (PARTITION BY p.Id, t.TagName ORDER BY ph.CreationDate DESC) AS rn_tag
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN PostHistory AS ph
      ON p.Id = ph.PostId
      AND ph.PostHistoryTypeId IN (3, 6) -- Initial Tags, Edit Tags
    CROSS APPLY STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), '><') AS s
    JOIN Tags AS t
      ON s.value = t.TagName
    WHERE
      p.PostTypeId = 1 -- Questions
    GROUP BY
      p.Id,
      pt.Name,
      t.TagName,
      ph.PostHistoryTypeId,
      ph.CreationDate
  )
SELECT
  p.Id AS PostId,
  pt.Name AS PostType,
  p.Title,
  p.CreationDate AS PostCreationDate,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  le.LastEditorUserId,
  le.LastEditDate,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.UpVoteCount,
  ua.DownVoteCount,
  (
    SELECT
      COUNT(c.Id)
    FROM Comments AS c
    WHERE
      c.PostId = p.Id
      AND c.UserId IS NOT NULL
  ) AS CommenterCount,
  COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
  p.ClosedDate,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  te.TagName,
  te.TagHistoryType,
  te.TagHistoryCount
FROM Posts AS p
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users AS u
  ON p.OwnerUserId = u.Id
LEFT JOIN LatestEdits AS le
  ON p.Id = le.PostId
LEFT JOIN UserActivity AS ua
  ON u.Id = ua.UserId
LEFT JOIN TagEngagement AS te
  ON p.Id = te.PostId
  AND te.rn_tag = 1
WHERE
  p.Id BETWEEN 1 AND 10000
  AND p.CreationDate >= '2023-01-01'
  AND (
    u.DisplayName LIKE '%John%'
    OR u.Location IS NULL
  )
  AND pt.Name IN ('Question', 'Answer')
ORDER BY
  p.LastActivityDate DESC
LIMIT 100;

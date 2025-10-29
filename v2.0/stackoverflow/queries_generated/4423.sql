-- {"query": "4423.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1736} 

WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ph.Text,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL
  ),
  UserPostInteractions AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      COALESCE(pv.VoteTypeId, 0) AS VoteTypeId,
      CASE
        WHEN p.OwnerUserId = pv.UserId THEN 'Owner'
        WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
        ELSE 'Other'
      END AS InteractionType,
      p.Title,
      p.Tags,
      p.Score,
      ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS post_rn
    FROM Posts AS p
    LEFT JOIN Votes AS pv
      ON p.Id = pv.PostId AND pv.VoteTypeId IN (2, 3) -- UpMod and DownMod
    WHERE
      p.PostTypeId IN (1, 2) AND p.CreationDate > '2023-01-01'
  ),
  PostEditInfo AS (
    SELECT
      rph.PostId,
      u.DisplayName AS EditorDisplayName,
      rph.CreationDate AS EditDate,
      rph.Text AS EditContent,
      rph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY rph.PostId ORDER BY rph.CreationDate DESC) as rn
    FROM RankedPostHistory AS rph
    JOIN Users AS u
      ON rph.UserId = u.Id
  ),
  CommentAggregates AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS CommentCount,
      AVG(c.Score) AS AvgCommentScore,
      SUM(CASE WHEN c.UserDisplayName LIKE '%deleted%' THEN 1 ELSE 0 END) AS DeletedUserComments
    FROM Comments AS c
    GROUP BY
      c.PostId
  )
SELECT
  upi.PostId,
  upi.Title,
  upi.Tags,
  upi.Score,
  upi.PostCreationDate,
  upi.InteractionType,
  upi.VoteTypeId,
  COALESCE(pe.EditorDisplayName, 'N/A') AS LastEditorName,
  pe.EditDate AS LastEditDate,
  pe.EditContent AS LastEditContent,
  ca.CommentCount,
  ca.AvgCommentScore,
  ca.DeletedUserComments,
  CASE
    WHEN pi.OwnerUserId IS NULL THEN 'No Owner'
    WHEN pi.PostTypeId = 1 AND pi.OwnerUserId = pi.OwnerUserId THEN 'Question Owner'
    WHEN pi.PostTypeId = 2 AND pi.OwnerUserId = pi.OwnerUserId THEN 'Answer Owner'
    ELSE 'Other Owner'
  END AS OwnerStatus,
  IIF(upi.PostId IS NULL, 'No Votes', 'Has Votes') AS VoteStatus,
  IIF(pe.PostId IS NULL, 'No Edits', 'Has Edits') AS EditStatus,
  CASE
    WHEN upi.Tags IS NULL THEN 'No Tags'
    WHEN upi.Tags LIKE '%<sql>%' THEN 'Contains SQL Tag'
    WHEN upi.Tags LIKE '%<performance>%' THEN 'Contains Performance Tag'
    ELSE 'Other Tags'
  END AS TagCategory,
  LEN(upi.Title) AS TitleLength,
  DATEDIFF(day, upi.PostCreationDate, GETDATE()) AS DaysSinceCreation,
  UPPER(LEFT(upi.Title, 3)) AS FirstThreeTitleCharsUpper
FROM UserPostInteractions AS upi
LEFT JOIN PostEditInfo AS pe
  ON upi.PostId = pe.PostId AND pe.rn = 1
LEFT JOIN CommentAggregates AS ca
  ON upi.PostId = ca.PostId
LEFT JOIN Users AS pi
  ON upi.OwnerUserId = pi.Id
WHERE
  upi.post_rn = 1 AND upi.Score > 10 AND upi.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
UNION ALL
SELECT
  p.Id,
  p.Title,
  p.Tags,
  p.Score,
  p.CreationDate,
  CASE
    WHEN p.OwnerUserId = v.UserId THEN 'Owner'
    WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
    ELSE 'Other'
  END AS InteractionType,
  v.VoteTypeId,
  COALESCE(ue.DisplayName, 'N/A') AS LastEditorName,
  ph.CreationDate AS EditDate,
  ph.Text AS EditContent,
  ca.CommentCount,
  ca.AvgCommentScore,
  ca.DeletedUserComments,
  CASE
    WHEN p.OwnerUserId IS NULL THEN 'No Owner'
    WHEN p.PostTypeId = 1 AND p.OwnerUserId = p.OwnerUserId THEN 'Question Owner'
    WHEN p.PostTypeId = 2 AND p.OwnerUserId = p.OwnerUserId THEN 'Answer Owner'
    ELSE 'Other Owner'
  END AS OwnerStatus,
  IIF(v.PostId IS NULL, 'No Votes', 'Has Votes') AS VoteStatus,
  IIF(ph.PostId IS NULL, 'No Edits', 'Has Edits') AS EditStatus,
  CASE
    WHEN p.Tags IS NULL THEN 'No Tags'
    WHEN p.Tags LIKE '%<database>%' THEN 'Contains Database Tag'
    WHEN p.Tags LIKE '%<performance>%' THEN 'Contains Performance Tag'
    ELSE 'Other Tags'
  END AS TagCategory,
  LEN(p.Title) AS TitleLength,
  DATEDIFF(day, p.CreationDate, GETDATE()) AS DaysSinceCreation,
  LOWER(SUBSTRING(p.Title, 1, 3)) AS FirstThreeTitleCharsUpper
FROM Posts AS p
JOIN Votes AS v
  ON p.Id = v.PostId AND v.VoteTypeId = 2 -- Only UpMods for the UNION
LEFT JOIN PostHistory AS ph
  ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 6) AND ph.UserId = p.OwnerUserId
LEFT JOIN Users AS ue
  ON ph.UserId = ue.Id
LEFT JOIN CommentAggregates AS ca
  ON p.Id = ca.PostId
WHERE
  p.PostTypeId = 1 AND p.CreationDate < '2023-01-01' AND p.Score > 50
GROUP BY
  p.Id,
  p.Title,
  p.Tags,
  p.Score,
  p.CreationDate,
  v.VoteTypeId,
  ue.DisplayName,
  ph.CreationDate,
  ph.Text,
  ca.CommentCount,
  ca.AvgCommentScore,
  ca.DeletedUserComments,
  p.OwnerUserId,
  p.PostTypeId,
  v.PostId,
  ph.PostId
HAVING
  COUNT(v.Id) > 5
ORDER BY
  Score DESC,
  DaysSinceCreation ASC;

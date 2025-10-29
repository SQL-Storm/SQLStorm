-- {"query": "4145.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1429}
WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ph.UserId,
      ph.Comment,
      ph.Text AS HistoryText,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  LatestPostEdits AS (
    SELECT
      rph.PostId,
      CASE WHEN rph.PostHistoryTypeId = 4 THEN rph.HistoryText ELSE NULL END AS LatestTitleEdit,
      CASE WHEN rph.PostHistoryTypeId = 5 THEN rph.HistoryText ELSE NULL END AS LatestBodyEdit,
      CASE WHEN rph.PostHistoryTypeId = 6 THEN rph.HistoryText ELSE NULL END AS LatestTagsEdit,
      rph.CreationDate AS LastEditDate,
      rph.UserId AS LastEditorUserId
    FROM RankedPostHistory AS rph
    WHERE rph.rn = 1
  ),
  PostEditStats AS (
    SELECT
      p.Id AS PostId,
      COUNT(ph.Id) AS EditCount,
      SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEditCount,
      AVG(LENGTH(ph.Text)) AS AvgEditLength,
      MAX(CASE WHEN ph.PostHistoryTypeId = 6 THEN ph.CreationDate ELSE NULL END) AS LastTagEditDate
    FROM Posts AS p
    LEFT JOIN PostHistory AS ph
      ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      p.Id
  )
SELECT
  p.Id,
  pt.Name AS PostType,
  p.Title,
  u.DisplayName AS OwnerDisplayName,
  COALESCE(p.Score, 0) AS PostScore,
  COALESCE(p.ViewCount, 0) AS PostViewCount,
  COALESCE(p.AnswerCount, 0) AS AnswerCount,
  COALESCE(p.CommentCount, 0) AS CommentCount,
  COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
  lpe.LatestTitleEdit,
  SUBSTRING(lpe.LatestBodyEdit FROM 1 FOR 200) AS SnippetOfLatestBodyEdit,
  lpe.LatestTagsEdit,
  lpe.LastEditDate,
  pes.EditCount,
  pes.BodyEditCount,
  pes.AvgEditLength,
  pes.LastTagEditDate,
  COALESCE(u.Reputation, 0) AS OwnerReputation,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  -- compute days difference using standard SQL: date subtraction yielding interval, then extract days
  CAST(
    EXTRACT(DAY FROM (COALESCE(p.ClosedDate, p.LastActivityDate) - p.CreationDate)) AS INTEGER
  ) AS PostLifecycleDays,
  CASE
    WHEN LENGTH(p.Tags) > 0
    THEN REPLACE(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '#', '')
    ELSE 'No Tags'
  END AS FormattedTags,
  UPPER(SUBSTRING(u.DisplayName FROM 1 FOR 1)) AS OwnerInitial,
  CASE
    WHEN p.OwnerUserId IS NULL OR p.OwnerUserId = -1 THEN 'Community User'
    ELSE 'Registered User'
  END AS OwnerType,
  vt.Name AS LastVoteType,
  v.CreationDate AS LastVoteDate
FROM Posts AS p
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users AS u
  ON p.OwnerUserId = u.Id
LEFT JOIN LatestPostEdits AS lpe
  ON p.Id = lpe.PostId
LEFT JOIN PostEditStats AS pes
  ON p.Id = pes.PostId
LEFT JOIN Votes AS v
  ON p.Id = v.PostId
LEFT JOIN VoteTypes AS vt
  ON v.VoteTypeId = vt.Id AND vt.Id IN (2, 3)
WHERE
  p.Id > 1000000
  AND pt.Name = 'Question'
  AND (
    p.Score > 5 OR COALESCE(pes.EditCount, 0) > 10
  )
  AND EXISTS (
    SELECT 1
    FROM Comments AS c
    WHERE c.PostId = p.Id AND c.Score > 3
  )
GROUP BY
  p.Id,
  pt.Name,
  p.Title,
  u.DisplayName,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  lpe.LatestTitleEdit,
  lpe.LatestBodyEdit,
  lpe.LatestTagsEdit,
  lpe.LastEditDate,
  pes.EditCount,
  pes.BodyEditCount,
  pes.AvgEditLength,
  pes.LastTagEditDate,
  u.Reputation,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END,
  COALESCE(p.ClosedDate, p.LastActivityDate),
  p.CreationDate,
  p.Tags,
  u.DisplayName,
  p.OwnerUserId,
  vt.Name,
  v.CreationDate,
  v.Id,
  v.VoteTypeId
HAVING
  COUNT(DISTINCT v.Id) = SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
ORDER BY
  p.CreationDate DESC
LIMIT 100;
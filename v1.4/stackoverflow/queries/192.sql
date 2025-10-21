WITH
Q AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount,
    (SELECT MAX(ph.CreationDate)
     FROM PostHistory ph
     WHERE ph.PostId = p.Id
       AND ph.PostHistoryTypeId = 10) AS ClosedDate
  FROM Posts p
  WHERE p.PostTypeId = 1
),
VoteSum AS (
  SELECT
    q.Id,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Q q
  LEFT JOIN Votes v ON v.PostId = q.Id
  GROUP BY q.Id
),
TagInfo AS (
  SELECT
    q.Id,
    CASE
      WHEN LENGTH(q.Tags) > 2 THEN
        SUBSTRING(q.Tags FROM 2 FOR (POSITION('>' IN (q.Tags || '>')) - 2))
      ELSE NULL
    END AS PrimaryTag
  FROM Q q
),
LastEditor AS (
  SELECT
    p.Id,
    p.LastEditorDisplayName,
    p.LastEditDate
  FROM Posts p
  WHERE p.Id IN (SELECT Id FROM Q)
),
History AS (
  SELECT
    ph.PostId,
    ph.UserId,
    ph.UserDisplayName,
    ph.CreationDate AS RevisionDate,
    ph.Text,
    ph.PostHistoryTypeId
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 16) -- close/reopen or community owned events
)
SELECT
  q.Id AS PostId,
  q.Title,
  ti.PrimaryTag,
  q.CreationDate,
  q.ViewCount,
  q.Score,
  q.AnswerCount,
  vs.UpVotes,
  vs.DownVotes,
  le.LastEditorDisplayName,
  le.LastEditDate,
  CASE
    WHEN q.ClosedDate IS NULL THEN 'Open'
    ELSE 'Closed'
  END AS Status,
  CASE
    WHEN q.ClosedDate IS NULL THEN NULL
    ELSE q.ClosedDate
  END AS ClosedDate
FROM Q q
LEFT JOIN VoteSum vs ON vs.Id = q.Id
LEFT JOIN TagInfo ti ON ti.Id = q.Id
LEFT JOIN LastEditor le ON le.Id = q.Id
LEFT JOIN History h ON h.PostId = q.Id
ORDER BY q.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 500 ROWS ONLY;
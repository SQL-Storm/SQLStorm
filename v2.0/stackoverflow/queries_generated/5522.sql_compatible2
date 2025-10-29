WITH 
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense
  FROM Posts p
  WHERE p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.Id,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
CorrelationSub AS (
  SELECT
    ro.Id AS PostHistoryId,
    ro.PostId,
    ro.PostHistoryTypeId,
    ro.CreationDate AS HistoryDate,
    ro.UserId AS HistoryUserId,
    ro.Text,
    ro.Comment
  FROM PostHistory ro
  WHERE ro.PostHistoryTypeId IN (10,11,16,50)
),
Flags AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(v.CreationDate) AS LastVoteDate,
    COUNT(*) AS VoteCount
  FROM Votes v
  GROUP BY v.PostId
),
Aggregate AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.AcceptedAnswerId,
    rp.ParentId,
    rp.Body,
    rp.LastEditorUserId,
    rp.LastEditDate,
    rp.ContentLicense,
    COALESCE(f.UpVotes, 0) AS UpVotes,
    COALESCE(f.DownVotes, 0) AS DownVotes,
    COALESCE(aq.Reputation, 0) AS OwnerReputation,
    ROW_NUMBER() OVER (
      PARTITION BY rp.OwnerUserId
      ORDER BY rp.Score DESC, rp.LastActivityDate DESC
    ) AS OwnerRank
  FROM RecentActivePosts rp
  LEFT JOIN Flags f ON f.PostId = rp.PostId
  LEFT JOIN Users aq ON aq.Id = rp.OwnerUserId
  LEFT JOIN TopTags tt ON tt.Id = (
    CASE WHEN POSITION('<' IN rp.Tags) > 0 THEN NULL ELSE tt.Id END
  )
  LEFT JOIN CorrelationSub cs ON cs.PostId = rp.PostId
)
SELECT
  a.PostId,
  a.PostTypeId,
  a.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  a.Title,
  a.Tags,
  a.CreationDate,
  a.LastActivityDate,
  a.Score,
  a.ViewCount,
  a.AnswerCount,
  a.CommentCount,
  a.FavoriteCount,
  a.AcceptedAnswerId,
  a.ParentId,
  a.Body,
  a.LastEditorUserId,
  a.LastEditDate,
  a.ContentLicense,
  a.UpVotes,
  a.DownVotes,
  a.OwnerReputation,
  a.OwnerRank,
  (a.UpVotes - a.DownVotes) AS NetVotes,
  (CASE 
     WHEN a.OwnerUserId IS NULL THEN NULL
     ELSE (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = a.PostId)
   END) AS AvgBounty
FROM Aggregate a
LEFT JOIN Users u ON u.Id = a.OwnerUserId
LEFT JOIN Votes v2 ON v2.PostId = a.PostId
GROUP BY
  a.PostId,
  a.PostTypeId,
  a.OwnerUserId,
  u.DisplayName,
  a.Title,
  a.Tags,
  a.CreationDate,
  a.LastActivityDate,
  a.Score,
  a.ViewCount,
  a.AnswerCount,
  a.CommentCount,
  a.FavoriteCount,
  a.AcceptedAnswerId,
  a.ParentId,
  a.Body,
  a.LastEditorUserId,
  a.LastEditDate,
  a.ContentLicense,
  a.UpVotes,
  a.DownVotes,
  a.OwnerReputation,
  a.OwnerRank
ORDER BY a.LastActivityDate DESC, a.Score DESC
LIMIT 100;
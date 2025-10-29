-- {"query": "5258.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1140} 
WITH RecentUserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly,
    t.IsRequired,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.Count > 0
),
PostActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Tags,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    COALESCE(a.DisplayName, p.OwnerDisplayName) AS OwnerName,
    -- days since creation
    DATEDIFF(day, p.CreationDate, GETDATE()) AS AgeDays,
    -- total linked posts (including duplicates) via self-join on PostLinks
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id) AS LinkCount
  FROM Posts p
  LEFT JOIN Users a ON p.OwnerUserId = a.Id
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
  FROM Votes v
  WHERE v.CreationDate >= DATEADD(day, -30, GETDATE())
),
FilteredPosts AS (
  SELECT *
  FROM PostActivity pa
  WHERE pa.PostTypeId IN (1,2) -- questions and answers
    AND pa.Score IS NOT NULL
    AND pa.ViewCount >= 100
),
CorrelatedSubquery AS (
  SELECT
    fp.*,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = fp.PostId) AS CommentCountTotal,
    (SELECT TOP 1 v2.CreationDate
     FROM Votes v2
     WHERE v2.PostId = fp.PostId AND v2.VoteTypeId = 2
     ORDER BY v2.CreationDate DESC) AS LastUpVoteDate
  FROM FilteredPosts fp
),
Windowed AS (
  SELECT
    cs.*,
    ROW_NUMBER() OVER (PARTITION BY cs.PostTypeId ORDER BY cs.AgeDays DESC, cs.Score DESC) AS SeqByType
  FROM CorrelatedSubquery cs
),
Joined AS (
  SELECT
    w.*,
    rt.Name AS HistoryTypeName,
    lt.Name AS LinkTypeName
  FROM Windowed w
  LEFT JOIN PostHistory ph ON ph.PostId = w.PostId
  LEFT JOIN PostHistoryTypes rt ON ph.PostHistoryTypeId = rt.Id
  LEFT JOIN PostLinks pl ON pl.PostId = w.PostId
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
Final AS (
  SELECT DISTINCT
    j.PostId,
    j.PostTypeId,
    j.Title,
    j.CreationDate,
    j.LastActivityDate,
    j.Score,
    j.ViewCount,
    j.OwnerName,
    j.ParentId,
    j.AcceptedAnswerId,
    j.Tags,
    j.CommentCount,
    j.FavoriteCount,
    j.ContentLicense,
    j.CommentCountTotal,
    j.LastUpVoteDate,
    j.SeqByType,
    j.HistoryTypeName,
    j.LinkTypeName,
    CASE
      WHEN j.OwnerName IS NULL THEN 'Unknown'
      ELSE j.OwnerName
    END AS DisplayOwner
  FROM Joined j
  WHERE j.SeqByType <= 100
     OR j.LastUpVoteDate IS NOT NULL
)
SELECT
  -- generate a rich dataset with computed fields and string expressions
  PostId,
  PostTypeId,
  Title,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  DisplayOwner,
  ParentId,
  AcceptedAnswerId,
  Tags,
  CommentCount,
  FavoriteCount,
  ContentLicense,
  CommentCountTotal,
  LastUpVoteDate,
  SeqByType,
  HistoryTypeName,
  LinkTypeName,
  (CASE
     WHEN Location LIKE '%USA%' THEN 'North America'
     ELSE 'Other'
   END) AS RegionCategory,
  CONCAT_WS(' | ', Title, COALESCE(Tags, ''), OwnerName) AS TitleTagOwner,
  COALESCE((SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = Final.OwnerUserId AND p2.CreationDate >= DATEADD(year, -1, GETDATE())), 0) AS AvgUserPostScoreLastYear
FROM Final
ORDER BY LastActivityDate DESC
LIMIT 100;
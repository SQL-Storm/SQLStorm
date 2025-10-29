-- {"query": "5518.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1096} 
WITH
RecentUserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COALESCE(u.LastAccessDate, u.CreationDate) AS LastActiveDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COALESCE(uu.LastActivityDate, u.LastAccessDate) DESC) AS rn
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, MAX(CreationDate) AS LastActivityDate
    FROM Votes
    GROUP BY PostId
  ) va ON va.PostId = COALESCE(p.Id, p2.Id)
  CROSS APPLY (SELECT CreationDate AS LastActivityDate) ca
  -- Note: the CROSS APPLY is non-portable in some engines; replace with a simple COALESCE in a real environment
),
TopBadges AS (
  SELECT
    b.UserId,
    b.Name,
    b.Date,
    b.Class,
    b.TagBased
  FROM Badges b
  WHERE b.Date >= DATEADD(year, -1, GETDATE())
),
TagInsights AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
  WHERE t.Count > 0
),
PostStats AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_by_owner
  FROM Posts p
),
ComplexQuery AS (
  SELECT
    ps.PostId,
    ps.Title,
    ps.Tags,
    ps.Score,
    ps.ViewCount,
    ps.CreationDate,
    ps.LastActivityDate,
    ps.OwnerUserId,
    ps.AcceptedAnswerId,
    ps.AnswerCount,
    ps.CommentCount,
    ps.FavoriteCount,
    ps.ClosedDate,
    ps.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    CASE
      WHEN ps.Score > 10 THEN 'Hot'
      WHEN ps.Score BETWEEN 0 AND 10 THEN 'Active'
      ELSE 'New'
    END AS ActivityBand,
    COUNT(v.Id) OVER (PARTITION BY ps.PostId) AS VoteCountTotal,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY ps.PostId) AS UpVotesForPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY ps.PostId) AS DownVotesForPost,
    L.Name AS LastLinkType
  FROM PostStats ps
  LEFT JOIN Users u ON u.Id = ps.OwnerUserId
  LEFT JOIN Votes v ON v.PostId = ps.PostId
  LEFT JOIN PostLinks pl ON pl.PostId = ps.PostId
  LEFT JOIN LinkTypes L ON L.Id = pl.LinkTypeId
  WHERE ps.LastActivityDate >= DATEADD(day, -7, GETDATE())
    AND (ps.Score > 0 OR ps.ViewCount > 100)
    AND (ps.Tags LIKE '%<java>%' OR ps.Tags LIKE '%<sql>%')
),
Windowed AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY LastActivityDate DESC) AS rn_owner
  FROM ComplexQuery
)
SELECT
  w.PostId,
  w.Title,
  w.Tags,
  w.Score,
  w.ViewCount,
  w.CreationDate,
  w.LastActivityDate,
  w.OwnerUserId,
  w.OwnerDisplayName,
  w.AcceptedAnswerId,
  w.AnswerCount,
  w.CommentCount,
  w.FavoriteCount,
  w.ClosedDate,
  w.ContentLicense,
  w.ActivityBand,
  w.VoteCountTotal,
  w.UpVotesForPost,
  w.DownVotesForPost,
  w.LastLinkType,
  (SELECT COUNT(*) FROM Badges b WHERE b.UserId = w.OwnerUserId) AS BadgeCount,
  (SELECT STRING_AGG(DISTINCT t.TagName, ',') WITHIN GROUP (ORDER BY t.TagName)
     FROM Tags t
     WHERE t.Id IN (
       SELECT unnest(string_to_array(REPLACE(w.Tags, '<', ''), '>')) -- pseudo-parse tag list for demonstration
     )
  ) AS ParsedTags
FROM Windowed w
WHERE w.rn_owner = 1
ORDER BY w.LastActivityDate DESC
FETCH FIRST 100 ROWS ONLY;
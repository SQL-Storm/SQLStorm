-- {"query": "5378.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1108} 
WITH Q AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AcceptedAnswerId,
    p.PostTypeId,
    p.ParentId,
    p.Body,
    p.FavoriteCount,
    p.ContentLicense,
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.EmailHash,
    u.AccountId,
    -- badge aggregation for the post author (count of Gold/Silver/Bronze via a left join)
    b.Class AS BadgeClass,
    b.Name AS BadgeName,
    b.Date AS BadgeDate
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE p.PostTypeId = 1 -- questions only
),
Agg AS (
  SELECT
    p.PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.FavoriteCount,
    p.ContentLicense,
    p.UserId,
    p.DisplayName,
    p.Reputation,
    p.UserCreationDate,
    p.LastAccessDate,
    p.Views,
    p.UpVotes,
    p.DownVotes,
    p.Location,
    p.WebsiteUrl,
    p.EmailHash,
    p.AccountId,
    STRING_AGG(DISTINCT CONCAT(b.Name, '#', b.Date), '|') AS BadgeInfo
  FROM Q
  LEFT JOIN Badges b ON b.UserId = Q.UserId
  GROUP BY
    p.PostId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId,
    p.LastActivityDate, p.CommentCount, p.AcceptedAnswerId, p.ParentId, p.Body,
    p.FavoriteCount, p.ContentLicense, p.UserId, p.DisplayName, p.Reputation,
    p.UserCreationDate, p.LastAccessDate, p.Views, p.UpVotes, p.DownVotes,
    p.Location, p.WebsiteUrl, p.EmailHash, p.AccountId
),
Ref AS (
  SELECT
    a.PostId,
    a.Title,
    a.CreationDate,
    a.Score,
    a.ViewCount,
    a.Tags,
    a.OwnerUserId,
    a.LastActivityDate,
    a.CommentCount,
    a.AcceptedAnswerId,
    a.ParentId,
    a.Body,
    a.FavoriteCount,
    a.ContentLicense,
    a.UserId,
    a.DisplayName,
    a.Reputation,
    a.UserCreationDate,
    a.LastAccessDate,
    a.Views,
    a.UpVotes,
    a.DownVotes,
    a.Location,
    a.WebsiteUrl,
    a.EmailHash,
    a.AccountId,
    a.BadgeInfo,
    -- correlated subquery: latest edit by any user on this post before now
    (SELECT MAX(pl.CreationDate)
     FROM PostLinks pl
     WHERE pl.PostId = a.PostId) AS LastLinkDate,
    -- window function: rank posts by Reputation of owner within the same CreationDate day
    ROW_NUMBER() OVER (
      PARTITION BY CAST(a.CreationDate AS date)
      ORDER BY a.Reputation DESC, a.Score DESC
    ) AS DayRank
  FROM Agg a
)
SELECT
  r.PostId,
  r.Title,
  r.CreationDate,
  r.Score,
  r.ViewCount,
  r.Tags,
  r.OwnerUserId,
  r.LastActivityDate,
  r.CommentCount,
  r.AcceptedAnswerId,
  r.ParentId,
  r.Body,
  r.FavoriteCount,
  r.ContentLicense,
  r.UserId,
  r.DisplayName,
  r.Reputation,
  r.UserCreationDate,
  r.LastAccessDate,
  r.Views,
  r.UpVotes,
  r.DownVotes,
  r.Location,
  r.WebsiteUrl,
  r.EmailHash,
  r.AccountId,
  r.BadgeInfo,
  r.LastLinkDate,
  r.DayRank
FROM Ref r
WHERE
  -- complicated predicate: only include posts with at least 2 badges of any class or at least one badge with a date in the last 365 days
  (CASE
     WHEN r.BadgeInfo IS NULL THEN 0
     ELSE
       (SELECT COUNT(*) FROM Badges b2 WHERE b2.UserId = r.UserId) 
  END) >= 2
  OR
  EXISTS (
    SELECT 1
    FROM Badges b3
    WHERE b3.UserId = r.UserId
      AND b3.Date >= DATEADD(day, -365, CURRENT_TIMESTAMP)
  )
ORDER BY r.DayRank, r.CreationDate DESC
LIMIT 100;
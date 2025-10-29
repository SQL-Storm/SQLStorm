-- {"query": "5779.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1070} 
WITH ranked_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
recent_badges AS (
  SELECT
    b.UserId,
    b.Name AS BadgeName,
    b.Date AS EarnedDate,
    b.Class,
    b.TagBased,
    ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS badge_rn
  FROM Badges b
  JOIN ranked_users ru ON ru.UserId = b.UserId
  WHERE b.Date >= DATEADD(year, -2, GETDATE())
),
post_summary AS (
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
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= DATEADD(year, -3, GETDATE())
),
comment_activity AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountLast30d
  FROM Comments c
  WHERE c.CreationDate >= DATEADD(day, -30, GETDATE())
  GROUP BY c.PostId
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    RANK() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS r
  FROM Votes v
  WHERE v.CreationDate >= DATEADD(month, -6, GETDATE())
),
link_trends AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkType,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE pl.CreationDate >= DATEADD(year, -1, GETDATE())
),
tag_wiki_activity AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
cte_window AS (
  SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.LastAccessDate,
    SUM(p.Score) OVER (PARTITION BY ru.UserId) AS TotalPostScore,
    SUM(p.ViewCount) OVER (PARTITION BY ru.UserId) AS TotalViews,
    MAX(p.LastActivityDate) OVER (PARTITION BY ru.UserId) AS LastActivityForUser
  FROM ranked_users ru
  LEFT JOIN Posts p ON p.OwnerUserId = ru.UserId
)
SELECT
  ru.UserId,
  ru.DisplayName,
  ru.Reputation,
  ru.CreationDate AS AccountCreated,
  ru.LastAccessDate,
  ru.Views,
  ru.UpVotes,
  ru.DownVotes,
  ru.Location,
  ru.AccountId,
  rb.BadgeName,
  rb.EarnedDate,
  rb.Class,
  rb.TagBased,
  ps.PostId,
  ps.PostTypeId,
  ps.Title,
  ps.Tags,
  ps.CreationDate AS PostCreated,
  ps.LastActivityDate AS PostLastActive,
  ps.Score,
  ps.ViewCount,
  ps.AnswerCount,
  cs.CommentCountLast30d,
  rv.VoteTypeId,
  rv.UserId AS VoterUserId,
  rv.CreationDate AS VoteDate,
  tw.LinkType,
  tw.RelatedPostId,
  ta.TagName,
  ta.Count AS TagCount,
  wact.TotalPostScore,
  wact.TotalViews,
  wact.LastActivityForUser
FROM ranked_users ru
LEFT JOIN recent_badges rb ON rb.UserId = ru.UserId AND rb.badge_rn = 1
LEFT JOIN post_summary ps ON ps.OwnerUserId = ru.UserId
LEFT JOIN comment_activity ca ON ca.PostId = ps.PostId
LEFT JOIN recent_votes rv ON rv.PostId = ps.PostId AND rv.r = 1
LEFT JOIN link_trends tw ON tw.PostId = ps.PostId
LEFT JOIN tag_wiki_activity ta ON ta.TagId = CASE WHEN ps.Tags IS NOT NULL THEN  CAST(PARSENAME(REPLACE(ps.Tags,'><','.'),1) AS int) ELSE NULL END
LEFT JOIN cte_window wact ON wact.UserId = ru.UserId
ORDER BY ru.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
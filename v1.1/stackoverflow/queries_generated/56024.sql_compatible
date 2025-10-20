WITH Top10UsersWithMostBadges AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    COUNT(b.Id) AS BadgeCount
  FROM 
    Users u
  JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id, 
    u.DisplayName
  ORDER BY 
    BadgeCount DESC
  LIMIT 10
),
Top10PostsByScore AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Score
  FROM 
    Posts p
  ORDER BY 
    p.Score DESC
  LIMIT 10
),
Top10TagsByCount AS (
  SELECT 
    t.TagName, 
    t.Count
  FROM 
    Tags t
  ORDER BY 
    t.Count DESC
  LIMIT 10
),
Top10UsersWithMostUpVotes AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    u.Id, 
    u.DisplayName
  ORDER BY 
    UpVoteCount DESC
  LIMIT 10
)
SELECT 
  u.Id, 
  u.DisplayName, 
  u.Reputation, 
  u.UpVotes, 
  u.DownVotes, 
  u.Views, 
  b.Name AS BadgeName, 
  p.Title AS PostTitle, 
  p.Score AS PostScore, 
  t.TagName, 
  t.Count AS TagCount
FROM 
  Users u
JOIN 
  Badges b ON u.Id = b.UserId
JOIN 
  Posts p ON u.Id = p.OwnerUserId
JOIN 
  PostLinks pl ON p.Id = pl.PostId
JOIN 
  Tags t ON pl.RelatedPostId = t.WikiPostId
WHERE 
  u.Id IN (SELECT Id FROM Top10UsersWithMostBadges)
  AND p.Id IN (SELECT Id FROM Top10PostsByScore)
  AND t.TagName IN (SELECT TagName FROM Top10TagsByCount)
  AND u.Id IN (SELECT Id FROM Top10UsersWithMostUpVotes)
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.UpVotes,
  u.DownVotes,
  u.Views,
  b.Name,
  p.Title,
  p.Score,
  t.TagName,
  t.Count
ORDER BY 
  u.Reputation DESC, 
  u.UpVotes DESC, 
  u.Views DESC;
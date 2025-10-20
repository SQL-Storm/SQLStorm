-- {"query": "172.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1252} 
WITH RecentActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS Posts,
    MAX(p.CreationDate) AS LastPostDate,
    COUNT(DISTINCT c.Id) AS Comments,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(p.CreationDate) DESC NULLS LAST) AS rn
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgesPerUser AS (
  SELECT
    u.Id AS UserId,
    COUNT(b.Id) AS Badges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
),
PostLinkDensity AS (
  SELECT
    p.OwnerUserId,
    COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS ExternalLinks,
    COUNT(pl.Id) AS TotalLinks
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  GROUP BY p.OwnerUserId
),
TopUsers AS (
  SELECT
    ra.UserId,
    ra.DisplayName,
    ra.Reputation,
    ra.Posts,
    ra.LastPostDate,
    bp.Badges,
    pld.TotalLinks,
    pld.ExternalLinks,
    (COALESCE(ra.Posts,0) + COALESCE(bp.Badges,0) + COALESCE(pld.TotalLinks,0)) AS ScoreComposite,
    ROW_NUMBER() OVER (ORDER BY 
      (COALESCE(ra.Posts,0) * 3) + (COALESCE(bp.Badges,0) * 5) + (COALESCE(pld.TotalLinks,0) * 2) DESC,
      COALESCE(ra.LastPostDate, TIMESTAMP 'epoch') DESC
    ) AS overal_rank
  FROM RecentActivity ra
  LEFT JOIN BadgesPerUser bp ON bp.UserId = ra.UserId
  LEFT JOIN PostLinkDensity pld ON pld.OwnerUserId = ra.UserId
  WHERE ra.rn = 1
)
SELECT
  tu.UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.Posts,
  tu.LastPostDate,
  tu.Badges,
  tu.TotalLinks,
  tu.ExternalLinks,
  tu.ScoreComposite
FROM TopUsers tu
ORDER BY tu.overall_rank
LIMIT 100;
-- {"query": "5399.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 492} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COALESCE(bc.Count, 0) AS BronzeBadges,
  COALESCE(sc.Count, 0) AS SilverBadges,
  COALESCE(gc.Count, 0) AS GoldBadges,
  p1.PostTypeId AS PostTypeViewed,
  AVG(p1.Score) OVER (PARTITION BY u.Id) AS AvgPostScoreByUser,
  MAX(p1.LastActivityDate) OVER (PARTITION BY u.Id) AS LastActivityByUser,
  v.TotalVotes AS TotalVotesByUser,
  t.TagNameBounds
FROM
  Users u
  LEFT JOIN Badges bc ON bc.UserId = u.Id AND bc.Class = 3
  LEFT JOIN Badges sc ON sc.UserId = u.Id AND sc.Class = 2
  LEFT JOIN Badges gc ON gc.UserId = u.Id AND gc.Class = 1
  LEFT JOIN (
    SELECT OwnerUserId, MAX(PostTypeId) AS PostTypeViewed, MAX(LastActivityDate) AS LastActivityDate
    FROM Posts
    GROUP BY OwnerUserId
  ) p1 ON p1.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS TotalVotes
    FROM Votes v
    JOIN Posts p ON p.Id = v.PostId
    WHERE v.VoteTypeId IN (2, 3) -- upvotes and downvotes
    GROUP BY OwnerUserId
  ) v ON v.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT p.OwnerUserId,
           STRING_AGG(DISTINCT t.TagName, ',') AS TagNameBounds
    FROM Posts p
    JOIN Tags t ON t.Id = p.Tags::text::int -- placeholder for multi-tag extraction, varies by dialect
    GROUP BY p.OwnerUserId
  ) t ON t.OwnerUserId = u.Id
WHERE
  u.CreationDate >= NOW() - INTERVAL '2 years'
  AND u.LastAccessDate >= NOW() - INTERVAL '6 months'
ORDER BY
  COALESCE(bc.Count, 0) + COALESCE(sc.Count, 0) + COALESCE(gc.Count, 0) DESC
LIMIT 100;
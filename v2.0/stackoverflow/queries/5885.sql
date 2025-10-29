-- {"query": "5885.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 614}
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  COALESCE(u.Location, 'Unknown') AS Location,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
  MAX(p.LastActivityDate) AS LastActivity,
  STRING_AGG(DISTINCT tt.TagName, ',') AS TopTags,
  COALESCE(bc.BronzeCount, 0) AS BronzeBadges,
  COALESCE(gs.TotalRepliers, 0) AS TotalRepliers
FROM
  Users u
LEFT JOIN
  Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
  (
    SELECT
      u2.Id AS UserForTag,
      t.TagName,
      COUNT(*) AS TagCount
    FROM
      Posts p2
      JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p2.Tags FROM 2 FOR CHAR_LENGTH(p2.Tags) - 2), '><')) AS TagName
      ) t ON true
      JOIN Users u2 ON p2.OwnerUserId = u2.Id
    GROUP BY
      u2.Id, t.TagName
  ) tt ON tt.UserForTag = u.Id
LEFT JOIN
  (
    SELECT
      b.UserId,
      COUNT(*) AS BronzeCount
    FROM
      Badges b
    WHERE b.Class = 3
    GROUP BY b.UserId
  ) bc ON bc.UserId = u.Id
LEFT JOIN
  (
    SELECT
      p2.OwnerUserId AS UserId,
      COUNT(DISTINCT p2.Title) AS TotalRepliers
    FROM
      Posts p2
    JOIN
      Votes v ON v.PostId = p2.Id AND v.VoteTypeId = 15
    GROUP BY p2.OwnerUserId
  ) gs ON gs.UserId = u.Id
WHERE
  u.LastAccessDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 days')
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  u.Location,
  bc.BronzeCount,
  gs.TotalRepliers
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  TotalPosts DESC,
  u.Reputation DESC
LIMIT 100;
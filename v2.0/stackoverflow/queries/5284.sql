-- {"query": "5284.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 504}
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
  MAX(p.LastActivityDate) AS LastActivity,
  COUNT(DISTINCT bl.PostId) AS LinkedPostsCount,
  STRING_AGG(CASE WHEN bl.LinkTypeName IS NOT NULL THEN bl.LinkTypeName ELSE '' END, ',') AS LinkTypesUsed,
  STRING_AGG(DISTINCT t.TagName, ',') AS TagsUsed,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
  SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
  SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT
      l.PostId,
      l.RelatedPostId,
      lt.Name AS LinkTypeName
    FROM
      PostLinks l
      LEFT JOIN LinkTypes lt ON l.LinkTypeId = lt.Id
  ) bl ON bl.PostId = p.Id
  LEFT JOIN (
    SELECT
      p.Id,
      NULLIF(TRIM(tag), '') AS TagName
    FROM Posts p,
    LATERAL (
      SELECT regexp_split_to_table(COALESCE(p.Tags, ''), '<>') AS tag
    ) s
  ) t ON t.Id = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
  u.Id IS NOT NULL
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation
ORDER BY
  TotalPosts DESC,
  (SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)) DESC
LIMIT 100;
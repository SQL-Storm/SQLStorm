-- {"query": "5608.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 603} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  COALESCE(u.Location, 'Unknown') AS Location,
  COALESCE(u.WebsiteUrl, '') AS Website,
  b.GoldCount,
  b.SilverCount,
  b.BronzeCount,
  COALESCE(vs.TotalVotes, 0) AS TotalVotesReceived,
  COALESCE(vs.UpVotes, 0) AS UpVotesReceived,
  COALESCE(vs.DownVotes, 0) AS DownVotesReceived,
  COUNT(p.Id) AS PostsCreated,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
  MAX(p.LastActivityDate) AS LastActivePostDate,
  STRING_AGG(DISTINCT t.Name, ',') AS TopTagsUsed
FROM Users u
LEFT JOIN (
  SELECT UserId,
         SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
         SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
         SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
  FROM Badges
  GROUP BY UserId
) b ON b.UserId = u.Id
LEFT JOIN (
  SELECT
    v.UserId,
    SUM(v.BountyAmount) AS TotalVotes,
    SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes v
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  GROUP BY v.UserId
) vs ON vs.UserId = u.Id
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN (
  SELECT
    p.OwnerUserId AS UserId,
    t.Name
  FROM Posts p
  JOIN LATERAL UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS t(Name) ON true
) t ON t.UserId = u.Id
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  u.Location,
  u.WebsiteUrl,
  b.GoldCount,
  b.SilverCount,
  b.BronzeCount,
  vs.TotalVotes,
  vs.UpVotes,
  vs.DownVotes
ORDER BY
  COALESCE(vs.TotalVotes, 0) DESC,
  u.Reputation DESC
LIMIT 100;
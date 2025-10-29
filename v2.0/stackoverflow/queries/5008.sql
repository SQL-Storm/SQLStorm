SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(p.Score) AS AvgScorePerPost,
  MAX(p.LastActivityDate) AS MostRecentActivity,
  STRING_AGG(DISTINCT pht.Name, ',') FILTER (WHERE pht.Name IS NOT NULL) AS RecentHistoryTypes,
  COUNT(DISTINCT bh.Id) AS HistoryEntries,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
  SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
  SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory bh ON bh.PostId = p.Id
    AND bh.PostHistoryTypeId IN (10,11,12,13,16,24,36)
  LEFT JOIN PostHistoryTypes pht ON pht.Id = bh.PostHistoryTypeId
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
  (u.CreationDate >= DATE '2024-10-01' - INTERVAL '2' YEAR
   OR u.LastAccessDate >= DATE '2024-10-01' - INTERVAL '1' YEAR)
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 5
ORDER BY
  TotalPosts DESC, MostRecentActivity DESC
LIMIT 100;
-- {"query": "5335.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 515} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.CreationDate) AS LastActivity,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned,
  STRING_AGG(DISTINCT tt.Name, ',') AS TopHistoryTypes
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT
      ph.UserId,
      ph.PostId,
      ph.PostHistoryTypeId,
      MAX(ph.CreationDate) AS MaxDate
    FROM PostHistory ph
    GROUP BY ph.UserId, ph.PostId, ph.PostHistoryTypeId
  ) phmax ON phmax.UserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = phmax.PostId
        AND ph.PostHistoryTypeId = phmax.PostHistoryTypeId
        AND ph.CreationDate = phmax.MaxDate
  LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
  LEFT JOIN (
    SELECT
      p.Id,
      p.PostTypeId,
      p.Title,
      p.Tags,
      p.OwnerUserId,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
    FROM Posts p
  ) latest ON latest.OwnerUserId = u.Id AND latest.rn = 1
WHERE
  u.Id IS NOT NULL
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  TotalPosts DESC, UserName ASC
LIMIT 100;
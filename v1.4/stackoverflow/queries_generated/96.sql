-- {"query": "96.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 531} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  MAX(p.CreationDate) AS LastPostDate,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
  AVG(p.ViewCount) AS AvgViewsPerPost,
  COUNT(DISTINCT bl.RelatedPostId) AS LinkedPostsCount,
  STRING_AGG(DISTINCT t.Name, ',') AS TagNames,
  COALESCE(SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END), 0) AS AcceptedVotes,
  COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS Upvotes,
  COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS Downvotes,
  MAX(CASE WHEN p.ClosedDate IS NOT NULL THEN p.ClosedDate END) AS LastClosedDate
FROM
  Users u
LEFT JOIN Posts p
  ON p.OwnerUserId = u.Id
LEFT JOIN LATERAL (
  SELECT
    substring(p.Tags, 2, length(p.Tags) - 2) AS raw_tags -- only for PostTypeId = 1 (questions)
) ttags ON p.PostTypeId = 1
LEFT JOIN Tags t ON LOWER(t.TagName) IN (
  SELECT LOWER(value)
  FROM unnest(string_to_array(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '><')) AS value
)
LEFT JOIN PostLinks bl ON bl.PostId = p.Id AND bl.RelatedPostId <> p.Id
LEFT JOIN Votes v ON v.PostId = p.Id
  AND v.CreationDate = (
    SELECT MAX(v2.CreationDate)
    FROM Votes v2
    WHERE v2.PostId = p.Id
      AND v2.VoteTypeId IN (1,2,3,6,8,9,10,11,12,14,15,16)
  )
WHERE
  p.PostTypeId IN (1,2)
  AND (p.CreationDate >= NOW() - INTERVAL '2 years')
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 5
ORDER BY
  PostsCreated DESC, LastPostDate DESC
LIMIT 100;
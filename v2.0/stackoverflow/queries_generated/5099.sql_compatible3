SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(*) AS PostCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.CreationDate) AS LastPostDate,
  COUNT(DISTINCT v.Id) AS VoteCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  STRING_AGG(DISTINCT t.TagName, ',') AS TagsInPosts,
  SUM(CASE WHEN p.OwnerUserId = u.Id THEN 1 ELSE 0 END) AS OwnPostsCount
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN LATERAL (
    SELECT TRIM(BOTH '<>' FROM part) AS tagname
    FROM UNNEST(string_to_array(COALESCE(p.Tags, ''), '><')) AS t(part)
  ) tn ON TRUE
  LEFT JOIN Tags t ON t.TagName = tn.tagname
WHERE
  u.CreationDate >= CAST('2015-01-01 00:00:00' AS TIMESTAMP)
  AND u.LastAccessDate IS NOT NULL
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(*) > 5
ORDER BY
  Reputation DESC, UserName
LIMIT 100;
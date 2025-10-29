-- {"query": "5231.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 778} 
WITH RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
),
CorrelatedTagStats AS (
  SELECT
    rh.PostId,
    t.TagName,
    t.Count AS TagCount,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COALESCE(b.Class, 0) AS BadgeClass,
    MAX(v.CreationDate) AS LastVoteDate
  FROM RecentHot rh
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(rh.Tags, 2, length(rh.Tags)-2), '><')) AS TagName
  ) s ON TRUE
  LEFT JOIN Tags t ON t.TagName = s.TagName
  LEFT JOIN Users u ON u.Id = rh.OwnerUserId
  LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date = (
    SELECT MAX(Date) FROM Badges b2 WHERE b2.UserId = u.Id
  )
  LEFT JOIN Votes v ON v.PostId = rh.PostId
  GROUP BY rh.PostId, t.TagName, t.Count, u.Reputation, u.CreationDate, b.Class
),
TopVotes AS (
  SELECT
    rh.PostId,
    rh.Title,
    rh.Tags,
    rh.Score,
    rh.ViewCount,
    rh.CreationDate,
    rh.OwnerUserId,
    rh.LastActivityDate,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT c.Id) AS CommentCount
  FROM RecentHot rh
  LEFT JOIN Votes v ON v.PostId = rh.PostId
  LEFT JOIN Comments c ON c.PostId = rh.PostId
  GROUP BY
    rh.PostId, rh.Title, rh.Tags, rh.Score, rh.ViewCount,
    rh.CreationDate, rh.OwnerUserId, rh.LastActivityDate
),
Enhanced AS (
  SELECT
    tv.PostId,
    tv.Title,
    tv.Tags,
    tv.Score,
    tv.ViewCount,
    tv.CreationDate,
    tv.OwnerUserId,
    tv.LastActivityDate,
    tv.UpVotes,
    tv.DownVotes,
    tc.TagName,
    tc.TagCount,
    tc.Reputation,
    tc.UserCreationDate,
    tc.BadgeClass,
    tc.LastVoteDate,
    tv.CommentCount,
    CASE
      WHEN tv.ViewCount > 1000 THEN 'HighTraffic'
      WHEN tv.Score > 5 THEN 'Trending'
      ELSE 'Normal'
    END AS TrafficLabel
  FROM TopVotes tv
  LEFT JOIN CorrelatedTagStats tc ON tc.PostId = tv.PostId
)
SELECT
  PostId,
  Title,
  Tags,
  Score,
  ViewCount,
  CreationDate,
  LastActivityDate,
  OwnerUserId,
  UpVotes,
  DownVotes,
  CommentCount,
  COALESCE(TagName, 'untagged') AS PrimaryTag,
  TagCount,
  Reputation,
  UserCreationDate,
  BadgeClass,
  LastVoteDate,
  TrafficLabel
FROM Enhanced
ORDER BY LastActivityDate DESC, UpVotes DESC
LIMIT 200;
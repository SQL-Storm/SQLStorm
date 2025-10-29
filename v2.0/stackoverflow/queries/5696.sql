WITH
RecentPopular AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    u.DisplayName AS Owner,
    u.Reputation AS OwnerReputation,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
    CASE WHEN p.PostTypeId = 1 THEN 'Question' ELSE 'Other' END AS PostKind,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY)
    AND (p.ViewCount > 0 OR p.Score > 0)
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, u.DisplayName, u.Reputation, p.PostTypeId
),
Tagged AS (
  SELECT
    rp.*,
    tag
  FROM RecentPopular rp,
  LATERAL (
    SELECT unnest(string_to_array(substring(rp.Tags FROM 2 FOR char_length(rp.Tags)-2), '><')) AS tag
  ) t
),
TagStats AS (
  SELECT
    Tag,
    COUNT(*) AS PostsWithTag,
    AVG(OwnerReputation) AS AvgOwnerRep,
    SUM(UpVotes) AS TotalUpVotes,
    SUM(DownVotes) AS TotalDownVotes
  FROM Tagged
  GROUP BY Tag
),
TopTags AS (
  SELECT Tag
  FROM TagStats
  ORDER BY PostsWithTag DESC, TotalUpVotes DESC
  LIMIT 10
)
SELECT
  rp.PostId,
  rp.Title,
  rp.Owner,
  rp.OwnerReputation,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.Tags,
  rp.UpVotes,
  rp.DownVotes,
  rp.PostKind,
  ts.Tag AS TrendingTag,
  ts.PostsWithTag,
  ts.AvgOwnerRep
FROM RecentPopular rp
LEFT JOIN Tagged t ON t.PostId = rp.PostId
LEFT JOIN TopTags tt ON tt.Tag = t.tag
LEFT JOIN TagStats ts ON ts.Tag = t.tag
WHERE rp.rn = 1
ORDER BY rp.Score DESC, rp.ViewCount DESC;
-- {"query": "181.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1689} 
WITH recent AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerName,
    u.Location AS OwnerLocation,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_owner
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate IS NOT NULL
    AND p.LastActivityDate >= NOW() - INTERVAL '180 days'
),
tag_extracted AS (
  SELECT
    r.*,
    t.TagName AS TagName,
    t.Id AS TagId
  FROM recent r
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(SUBSTRING(r.Tags, 2, LENGTH(r.Tags) - 2), '><')) AS TagName
  ) AS s
  LEFT JOIN Tags t ON t.TagName = s.TagName
),
votes_by_post AS (
  SELECT
    p.Id,
    SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS NetVotes,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id
),
tag_metrics AS (
  SELECT
    te.TagName AS Tag,
    COUNT(*) AS TagPostCount,
    MAX(te.LastActivityDate) AS LastActiveForTag
  FROM tag_extracted te
  GROUP BY te.TagName
),
final AS (
  SELECT
    te.Id,
    te.Title,
    te.PostTypeId,
    te.OwnerUserId,
    te.OwnerName,
    te.OwnerReputation,
    te.OwnerLocation,
    te.LastActivityDate,
    te.Score,
    te.ViewCount,
    te.AnswerCount,
    te.CommentCount,
    te.TagName AS Tag,
    vb.NetVotes,
    vb.LastVoteDate,
    tm.TagPostCount
  FROM tag_extracted te
  LEFT JOIN votes_by_post vb ON vb.Id = te.Id
  LEFT JOIN tag_metrics tm ON tm.Tag = te.TagName
  WHERE te.rn_owner = 1
)
SELECT *
FROM final
ORDER BY LastActivityDate DESC
LIMIT 200;
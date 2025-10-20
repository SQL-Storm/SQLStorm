-- {"query": "250.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 12228} 
WITH PostStats AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn_by_type
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '365 days'
),
TagList AS (
  SELECT ps.PostId, STRING_AGG(DISTINCT TRIM(ts.tag), ',') AS TagList
  FROM PostStats ps
  CROSS JOIN LATERAL (
    SELECT TRIM(v) AS tag
    FROM unnest(string_to_array(COALESCE(substring(ps.Tags FROM 2 FOR length(ps.Tags)-2), ''), '><')) AS s(v)
  ) ts
  GROUP BY ps.PostId
),
PostView AS (
  SELECT ps.PostId, ps.OwnerUserId, ps.PostTypeId, ps.Title, tl.TagList, ps.Score, ps.ViewCount, ps.CreationDate, ps.CommentCount, ps.UpVotes, ps.rn_by_type
  FROM PostStats ps
  LEFT JOIN TagList tl ON tl.PostId = ps.PostId
)
SELECT
  pv.PostId,
  COALESCE(u.DisplayName, 'Community') AS OwnerName,
  COALESCE(u.Location, 'Unknown') AS OwnerLocation,
  pv.Title,
  pv.TagList,
  pv.Score,
  pv.ViewCount,
  pv.CreationDate,
  pv.CommentCount,
  pv.UpVotes,
  pv.rn_by_type
FROM PostView pv
LEFT JOIN Users u ON u.Id = pv.OwnerUserId
ORDER BY pv.Score DESC NULLS LAST, pv.ViewCount DESC NULLS LAST
LIMIT 200;
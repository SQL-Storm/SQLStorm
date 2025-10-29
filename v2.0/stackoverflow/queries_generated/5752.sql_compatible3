WITH
recent_qs AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.PostTypeId,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY
),
tag_cooccurrence AS (
  SELECT
    t1.TagName AS TagA,
    t2.TagName AS TagB,
    COUNT(*) AS Cooccurrence
  FROM Posts p,
       LATERAL (SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName) t1,
       LATERAL (SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName) t2
  WHERE t1.TagName IS NOT NULL
    AND t2.TagName IS NOT NULL
    AND t1.TagName <> t2.TagName
  GROUP BY t1.TagName, t2.TagName
  HAVING COUNT(*) > 0
),
most_viewed AS (
  SELECT
    p.PostId AS Id,
    p.Title,
    CAST(NULL AS VARCHAR) AS OwnerDisplayName,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags
  FROM recent_qs p
  ORDER BY p.ViewCount DESC
  LIMIT 50
),
complex_metrics AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.CommentCount,
    q.LastActivityDate,
    v_sum.TotalUp AS UpVotes,
    v_sum.TotalDown AS DownVotes,
    (COALESCE(v_sum.TotalUp,0) - COALESCE(v_sum.TotalDown,0)) AS NetVotes,
    CASE
      WHEN q.OwnerUserId IS NULL THEN 'Anonymous'
      WHEN u.Reputation IS NULL THEN 'Unknown'
      ELSE CAST(u.Reputation AS VARCHAR)
    END AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName
  FROM recent_qs q
  LEFT JOIN (
    SELECT v.PostId,
           SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS TotalUp,
           SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS TotalDown
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
  ) v_sum ON v_sum.PostId = q.PostId
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  GROUP BY
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.CommentCount,
    q.LastActivityDate,
    v_sum.TotalUp,
    v_sum.TotalDown,
    u.Reputation,
    u.DisplayName
  ORDER BY q.CreationDate DESC, q.PostId, q.Title, q.OwnerUserId, q.ViewCount, q.Score, q.AnswerCount, q.CommentCount, q.LastActivityDate, v_sum.TotalUp, v_sum.TotalDown, u.Reputation, u.DisplayName
  LIMIT 200
)
SELECT
  cm.PostId,
  cm.Title,
  cm.OwnerDisplayName,
  cm.CreationDate,
  cm.ViewCount,
  cm.Score,
  cm.AnswerCount,
  cm.CommentCount,
  cm.LastActivityDate,
  cm.UpVotes,
  cm.DownVotes,
  cm.NetVotes,
  cm.OwnerReputation
FROM complex_metrics cm
LEFT JOIN most_viewed mv ON mv.Id = cm.PostId
LEFT JOIN tag_cooccurrence tc ON tc.TagA = ANY(string_to_array(substr(coalesce(cm.Title, ''), 2, greatest(length(coalesce(cm.Title, '')),1)-2), '><'))
GROUP BY
  cm.PostId,
  cm.Title,
  cm.OwnerDisplayName,
  cm.CreationDate,
  cm.ViewCount,
  cm.Score,
  cm.AnswerCount,
  cm.CommentCount,
  cm.LastActivityDate,
  cm.UpVotes,
  cm.DownVotes,
  cm.NetVotes,
  cm.OwnerReputation,
  mv.Id,
  mv.Title,
  mv.OwnerDisplayName,
  mv.CreationDate,
  mv.ViewCount,
  mv.Score,
  mv.Tags,
  tc.TagA,
  tc.TagB,
  tc.Cooccurrence
ORDER BY cm.CreationDate DESC, cm.PostId, cm.Title
LIMIT 100;
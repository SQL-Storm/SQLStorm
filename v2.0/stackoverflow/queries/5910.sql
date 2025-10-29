WITH recursive tag_exploded_posts AS (
  SELECT
    p.Id AS PostId,
    TRIM(BOTH '>' FROM REPLACE(p.Tags, '<', '')) AS TagsStr
  FROM Posts p
  WHERE p.Tags IS NOT NULL
),
split_tags AS (
  SELECT
    PostId,
    CASE WHEN TagsStr = '' THEN NULL
         WHEN POSITION('>' IN TagsStr) = 0 THEN TagsStr
         ELSE SUBSTRING(TagsStr FROM 1 FOR POSITION('>' IN TagsStr)-1)
    END AS TagName,
    CASE WHEN POSITION('>' IN TagsStr) = 0 THEN ''
         ELSE SUBSTRING(TagsStr FROM POSITION('>' IN TagsStr)+1)
    END AS rest
  FROM tag_exploded_posts
  UNION ALL
  SELECT
    PostId,
    CASE WHEN POSITION('>' IN rest) = 0 THEN rest
         ELSE SUBSTRING(rest FROM 1 FOR POSITION('>' IN rest)-1)
    END AS TagName,
    CASE WHEN POSITION('>' IN rest) = 0 THEN ''
         ELSE SUBSTRING(rest FROM POSITION('>' IN rest)+1)
    END AS rest
  FROM split_tags
  WHERE rest <> ''
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    COALESCE(a.TotalUp, 0) AS UpVotes,
    COALESCE(a.TotalDown, 0) AS DownVotes,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN (
    SELECT
      V.PostId,
      SUM(CASE WHEN Vt.Id = 2 THEN 1 ELSE 0 END) AS TotalUp,
      SUM(CASE WHEN Vt.Id = 3 THEN 1 ELSE 0 END) AS TotalDown
    FROM Votes V
    JOIN VoteTypes Vt ON V.VoteTypeId = Vt.Id
    GROUP BY V.PostId
  ) a ON p.Id = a.PostId
  WHERE p.PostTypeId IN (1,2)
),
top_posts AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.OwnerUserId,
    ra.Score,
    ra.ViewCount,
    ra.Tags,
    ra.PostTypeId,
    ra.UpVotes,
    ra.DownVotes
  FROM recent_activity ra
  WHERE ra.rn <= 50
),
tag_summary AS (
  SELECT
    s.TagName,
    COUNT(*) AS BotPosts,
    AVG(ra.Score) AS AvgScore,
    SUM(ra.UpVotes - ra.DownVotes) AS NetScore
  FROM top_posts tp
  JOIN Posts p ON tp.PostId = p.Id
  JOIN split_tags s ON p.Id = s.PostId
  JOIN top_posts ra ON ra.PostId = p.Id
  WHERE p.Tags IS NOT NULL
  GROUP BY s.TagName
),
complex_filter AS (
  SELECT
    tp.PostId,
    tp.Title,
    tp.LastActivityDate,
    tp.OwnerUserId,
    tp.Score,
    tp.ViewCount,
    tp.UpVotes,
    tp.DownVotes,
    tp.Tags,
    CASE
      WHEN tp.Score > 5 AND tp.UpVotes >= 10 THEN 'HighQuality'
      WHEN tp.ViewCount > 1000 OR tp.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7' DAY) THEN 'Hot'
      ELSE 'Normal'
    END AS Category,
    ROW_NUMBER() OVER (ORDER BY tp.LastActivityDate DESC, tp.Score DESC) AS Seq
  FROM top_posts tp
)
SELECT
  cf.PostId,
  cf.Title,
  cf.LastActivityDate,
  cu.DisplayName AS OwnerName,
  cf.Score,
  cf.ViewCount,
  cf.UpVotes,
  cf.DownVotes,
  cf.Tags,
  cf.Category,
  ct.TagName AS TagExploded
FROM complex_filter cf
LEFT JOIN Users cu ON cf.OwnerUserId = cu.Id
LEFT JOIN (
  SELECT DISTINCT TRIM(st.TagName) AS TagName
  FROM split_tags st
  WHERE st.TagName IS NOT NULL
    AND st.TagName <> ''
) AS ct ON 1=1
WHERE cf.Seq <= 200
ORDER BY cf.Category, cf.LastActivityDate DESC, cf.Score DESC;
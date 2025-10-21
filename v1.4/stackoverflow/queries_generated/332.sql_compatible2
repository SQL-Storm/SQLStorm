WITH
AllPosts AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.PostTypeId,
         p.Score,
         p.ViewCount,
         p.CreationDate,
         p.LastActivityDate,
         p.OwnerUserId,
         u.DisplayName AS OwnerName,
         u.Reputation,
         p.Tags
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
),
TagInfo AS (
  SELECT ap.PostId,
         COALESCE(TAGS.TagList, '') AS TagList,
         COALESCE(TAGS.TagCount, 0) AS TagCount
  FROM AllPosts ap
  LEFT JOIN (
     SELECT COUNT(*) AS TagCount,
            STRING_AGG(tag_tag, ', ') AS TagList
     FROM (
        SELECT UNNEST(string_to_array(SUBSTRING(ap.Tags FROM 2 FOR LENGTH(ap.Tags) - 2), '><')) AS tag_tag
        FROM AllPosts ap
     ) s
  ) AS TAGS ON TRUE
),
UpDown AS (
  SELECT ap.PostId,
         ap.Title,
         ap.PostTypeId,
         ap.OwnerName,
         ap.Reputation,
         ap.Score,
         ap.ViewCount,
         ap.CreationDate,
         ap.LastActivityDate,
         ti.TagList,
         ti.TagCount,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ap.PostId AND v.VoteTypeId = 2) AS UpVotesCorrelated,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ap.PostId AND v.VoteTypeId = 3) AS DownVotesCorrelated,
         CASE WHEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ap.PostId AND v.VoteTypeId = 2) > 50 THEN 'Hot' ELSE 'Normal' END AS UpVoteTier,
         ROW_NUMBER() OVER (PARTITION BY ap.PostTypeId ORDER BY ap.Score DESC) AS ScoreRank
  FROM AllPosts ap
  LEFT JOIN TagInfo ti ON ap.PostId = ti.PostId
)
SELECT *
FROM (
  SELECT * FROM UpDown WHERE PostTypeId = 1
  UNION ALL
  SELECT * FROM UpDown WHERE PostTypeId = 2
) AS unified
ORDER BY ScoreRank, UpVotesCorrelated DESC NULLS LAST
LIMIT 300;
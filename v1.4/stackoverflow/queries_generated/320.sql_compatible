WITH
  PostsBase AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.PostTypeId,
      p.Score,
      p.ViewCount,
      p.CommentCount,
      p.CreationDate,
      p.LastActivityDate,
      p.Tags,
      COALESCE(u.DisplayName, 'Unknown') AS OwnerName,
      COALESCE(u.Reputation, 0) AS OwnerRep,
      (
        SELECT COUNT(*) FROM Comments c
        WHERE c.PostId = p.Id
          AND c.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days')
      ) AS Last30Comments
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
  ),
  EngTop AS (
    SELECT
      pb.PostId,
      pb.Title,
      pb.PostTypeId,
      (pb.Score * 3.0 + pb.ViewCount * 0.5 + pb.CommentCount * 2.0) AS Engagement,
      pb.Score,
      pb.ViewCount,
      pb.CommentCount,
      pb.CreationDate,
      pb.LastActivityDate,
      pb.OwnerName,
      pb.OwnerRep,
      pb.Last30Comments,
      STRING_AGG(DISTINCT t.TagName, ',') AS TagList
    FROM PostsBase pb
    LEFT JOIN LATERAL (
      SELECT TagName
      FROM unnest(string_to_array(substring(coalesce(pb.Tags, ''), 2, greatest(length(coalesce(pb.Tags, '')) - 2, 0)), '><')) AS TagName
      WHERE TagName <> ''
    ) t ON TRUE
    GROUP BY pb.PostId, pb.Title, pb.PostTypeId, pb.Score, pb.ViewCount, pb.CommentCount, pb.CreationDate, pb.LastActivityDate, pb.OwnerName, pb.OwnerRep, pb.Last30Comments
    ORDER BY Engagement DESC
    LIMIT 200
  ),
  TagSummary AS (
    SELECT
      pb.PostId,
      pb.Title,
      pb.PostTypeId,
      (pb.Score * 3.0 + pb.ViewCount * 0.5 + pb.CommentCount * 2.0) AS Engagement,
      pb.Score,
      pb.ViewCount,
      pb.CommentCount,
      pb.CreationDate,
      pb.LastActivityDate,
      pb.OwnerName,
      pb.OwnerRep,
      pb.Last30Comments,
      STRING_AGG(DISTINCT t.TagName, ',') AS TagList
    FROM PostsBase pb
    LEFT JOIN LATERAL (
      SELECT TagName
      FROM unnest(string_to_array(substring(coalesce(pb.Tags, ''), 2, greatest(length(coalesce(pb.Tags, '')) - 2, 0)), '><')) AS TagName
      WHERE TagName <> ''
    ) t ON TRUE
    WHERE pb.PostTypeId = 1
    GROUP BY pb.PostId, pb.Title, pb.PostTypeId, pb.Score, pb.ViewCount, pb.CommentCount, pb.CreationDate, pb.LastActivityDate, pb.OwnerName, pb.OwnerRep, pb.Last30Comments
    ORDER BY Engagement DESC
    LIMIT 200
  )
SELECT c.PostId, c.Title, c.PostTypeId, c.Engagement, c.Score, c.ViewCount, c.CommentCount, c.CreationDate, c.LastActivityDate, c.OwnerName, c.OwnerRep, c.Last30Comments, c.TagList,
       ROW_NUMBER() OVER (PARTITION BY c.PostTypeId ORDER BY c.Engagement DESC) AS RowRank
FROM (
  SELECT * FROM EngTop
  UNION ALL
  SELECT * FROM TagSummary
) AS c
ORDER BY c.Engagement DESC
LIMIT 500;
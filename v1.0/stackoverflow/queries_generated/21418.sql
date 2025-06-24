WITH RankedPosts AS (
    SELECT p.Id AS PostId,
           p.Title,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           U.Reputation AS OwnerReputation,
           ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS Rank
    FROM Posts p
    JOIN Users U ON p.OwnerUserId = U.Id
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
      AND p.Score >= (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= NOW() - INTERVAL '1 year')
),
PostMetadata AS (
    SELECT rp.PostId,
           rp.Title,
           rp.CreationDate,
           rp.Score,
           COALESCE(Count(comments.Id), 0) AS CommentCount,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS Upvotes,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS Downvotes,
           COUNT(DISTINCT b.Id) AS BadgeCount
    FROM RankedPosts rp
    LEFT JOIN Comments comments ON comments.PostId = rp.PostId
    LEFT JOIN Votes v ON v.PostId = rp.PostId
    LEFT JOIN Badges b ON b.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = rp.PostId)
    GROUP BY rp.PostId, rp.Title, rp.CreationDate, rp.Score
)
SELECT pm.PostId, 
       pm.Title, 
       pm.CreationDate,
       pm.Score,
       pm.CommentCount,
       pm.Upvotes,
       pm.Downvotes,
       pm.BadgeCount,
       CASE
           WHEN pm.Score >= 100 THEN 'Hot'
           WHEN pm.Score BETWEEN 50 AND 99 THEN 'Trending'
           ELSE 'Normal' 
       END AS PostStatus,
       ROW_NUMBER() OVER (ORDER BY pm.Score DESC) AS GlobalRank
FROM PostMetadata pm
WHERE pm.CommentCount > 10
  AND pm.BadgeCount > 0
ORDER BY pm.Score DESC
LIMIT 50;

-- Bizarre semantic use case:
WITH RecursiveTagAssociations AS (
    SELECT p.Id AS PostId,
           unnest(string_to_array(p.Tags, '><'))::varchar AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL
),
RelatedPosts AS (
    SELECT r.PostId AS RelatedPostId,
           GROUP_CONCAT(DISTINCT r.TagName) AS RelatedTags
    FROM RecursiveTagAssociations r
    JOIN Posts p ON p.Id = r.PostId 
    WHERE r.PostId <> p.Id
    GROUP BY r.PostId
)
SELECT rp.RelatedPostId,
       COUNT(*) AS TagAssociationCount,
       COALESCE(SUM(pm.Score), 0) AS AggregateScore
FROM RelatedPosts rp
LEFT JOIN Posts pm ON pm.Id = rp.RelatedPostId
GROUP BY rp.RelatedPostId
HAVING COUNT(*) > 3
ORDER BY AggregateScore DESC
LIMIT 100;

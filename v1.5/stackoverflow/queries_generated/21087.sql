-- {"query": "21087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1129} 

WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.ViewCount DESC, p.Score DESC) AS yearly_rank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS running_avg_score,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.FavoriteCount, 0) AS engagement_score
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.Score > 0 
      AND (p.Title ILIKE '%sql%' OR p.Tags ILIKE '%<sql>%' OR p.Tags ILIKE '%<sql-server>%')
      AND p.CreationDate > NOW() - INTERVAL '5 years'
),
ActiveUsers AS (
    SELECT 
        u.Id,
        u.Reputation,
        COUNT(DISTINCT ph.PostId) AS total_edits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS content_edits,
        STRING_AGG(DISTINCT SUBSTRING(ph.Comment, 1, 50), ' | ') AS edit_comments_summary
    FROM Users u
    INNER JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE ph.CreationDate > NOW() - INTERVAL '2 years'
      AND ph.PostHistoryTypeId IN (4, 5, 6, 10, 11)
      AND u.Reputation > 100
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT ph.PostId) >= 5
),
LinkedPostsStats AS (
    SELECT 
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS outbound_links,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS duplicate_links,
        STRING_AGG(DISTINCT t.TagName, ', ') AS linked_tags
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    INNER JOIN Posts related ON pl.RelatedPostId = related.Id
    INNER JOIN Tags t ON related.Tags ILIKE '%' || t.TagName || '%'
    WHERE pl.CreationDate > NOW() - INTERVAL '3 years'
    GROUP BY pl.PostId
)
SELECT 
    rp.Title AS post_title,
    rp.yearly_rank,
    rp.engagement_score,
    au.total_edits,
    au.edit_comments_summary,
    lps.outbound_links,
    lps.duplicate_links,
    lps.linked_tags,
    CASE 
        WHEN rp.yearly_rank <= 10 THEN 'Top Performer'
        WHEN rp.prev_post_score IS NULL OR rp.running_avg_score > rp.prev_post_score * 1.5 THEN 'Improving'
        WHEN rp.Score < 0 THEN 'Negative Score'
        ELSE 'Average'
    END AS performance_category,
    COALESCE(rp.ViewCount, 0) * (1.0 + COALESCE(rp.yearly_rank, 999) / 1000.0) AS weighted_views,
    UPPER(SUBSTRING(rp.Title, 1, LENGTH(rp.Title)/2)) || 
    CASE WHEN lps.duplicate_links > 0 THEN ' [DUPLICATE ALERT]' ELSE '' END AS modified_title,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id AND c.Score > 0) AS positive_comment_count,
    (SELECT STRING_AGG(DISTINCT b.Name, '; ') 
     FROM Badges b 
     WHERE b.UserId = rp.OwnerUserId 
       AND b.Class = 1 
       AND b.Date > rp.CreationDate - INTERVAL '1 year') AS recent_gold_badges
FROM RankedPosts rp
FULL OUTER JOIN ActiveUsers au ON rp.OwnerUserId = au.Id
LEFT JOIN LinkedPostsStats lps ON rp.Id = lps.PostId
LEFT JOIN VoteTypes vt ON vt.Id IN (
    SELECT v.VoteTypeId 
    FROM Votes v 
    WHERE v.PostId = rp.Id 
      AND v.CreationDate > rp.CreationDate 
      AND v.VoteTypeId IN (2, 3)  -- Upvotes and Downvotes
    GROUP BY v.VoteTypeId
    HAVING COUNT(*) > 10
    EXCEPT
    SELECT 3 WHERE rp.Score < 0  -- Exclude downvotes if post has negative score
)
WHERE rp.yearly_rank <= 50
   OR (au.total_edits > 20 AND lps.outbound_links IS NULL)
   OR EXISTS (
       SELECT 1 FROM Posts p2 
       WHERE p2.ParentId = rp.Id 
         AND p2.Score > rp.running_avg_score * 0.8
         AND p2.CreationDate BETWEEN rp.CreationDate AND rp.CreationDate + INTERVAL '1 month'
   )
ORDER BY rp.engagement_score DESC NULLS LAST, 
         COALESCE(au.total_edits, 0) DESC,
         weighted_views DESC
LIMIT 100;

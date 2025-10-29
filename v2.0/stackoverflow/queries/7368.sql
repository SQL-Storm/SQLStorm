-- {"query": "7368.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2115}
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS moving_avg_score,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END AS score_category,
        COALESCE(p.Tags, '') AS cleaned_tags,
        CHAR_LENGTH(COALESCE(p.Tags, '')) AS tag_length,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS comment_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS upvote_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS downvote_count,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) AS gold_badge_count
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= TIMESTAMP '2020-01-01'
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) AS total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count,
        AVG(p.Score) AS avg_post_score,
        MAX(p.CreationDate) AS last_post_date,
        STRING_AGG(DISTINCT p.Tags, '; ') AS all_tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= TIMESTAMP '2019-01-01'
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS usage_count,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS avg_score_for_tag,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END AS tag_popularity
    FROM Tags t
    WHERE t.Count > 0
),
PostActivity AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ph.Text,
        CASE 
            WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN 'Title/Tag Edit'
            WHEN ph.PostHistoryTypeId IN (2, 5) THEN 'Content Edit'
            WHEN ph.PostHistoryTypeId IN (10, 12, 13) THEN 'Status Change'
            ELSE 'Other'
        END AS activity_type,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS prev_activity_date,
        CAST(EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) AS BIGINT) AS time_since_last_activity
    FROM PostHistory ph
    WHERE ph.CreationDate >= TIMESTAMP '2021-01-01'
),
CombinedData AS (
    SELECT 
        rp.Id AS PostId,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.score_category,
        rp.tag_length,
        rp.comment_count,
        rp.upvote_count,
        rp.downvote_count,
        rp.gold_badge_count,
        us.Reputation,
        us.Views AS user_views,
        us.total_posts,
        us.question_count,
        us.answer_count,
        us.avg_post_score,
        ta.Count AS tag_count,
        ta.usage_count AS tag_usage_count,
        ta.avg_score_for_tag,
        ta.tag_popularity,
        pa.activity_type,
        pa.time_since_last_activity,
        CASE 
            WHEN rp.Score IS NULL OR us.Reputation IS NULL THEN 'Incomplete Data'
            WHEN rp.Score > 0 AND us.Reputation > 1000 THEN 'Active Contributor'
            WHEN rp.Score <= 0 AND us.Reputation <= 1000 THEN 'Newbie'
            ELSE 'Regular User'
        END AS user_status
    FROM RankedPosts rp
    LEFT JOIN UserStats us ON rp.OwnerUserId = us.UserId
    LEFT JOIN TagAnalysis ta ON rp.cleaned_tags LIKE '%' || ta.TagName || '%'
    LEFT JOIN PostActivity pa ON rp.Id = pa.PostId
    WHERE rp.rn <= 100
      AND (us.total_posts IS NULL OR us.total_posts >= 1)
)
SELECT 
    cd.PostId,
    cd.PostTypeId,
    cd.OwnerUserId,
    cd.Score,
    cd.ViewCount,
    cd.Title,
    cd.Tags,
    cd.AnswerCount,
    cd.CommentCount,
    cd.FavoriteCount,
    cd.score_category,
    cd.tag_length,
    cd.comment_count,
    cd.upvote_count,
    cd.downvote_count,
    cd.gold_badge_count,
    cd.Reputation,
    cd.user_views,
    cd.total_posts,
    cd.question_count,
    cd.answer_count,
    cd.avg_post_score,
    cd.tag_count,
    cd.tag_usage_count,
    cd.avg_score_for_tag,
    cd.tag_popularity,
    cd.activity_type,
    cd.time_since_last_activity,
    cd.user_status,
    CASE 
        WHEN cd.CommentCount > 0 AND cd.Score > 0 THEN 
            ROUND((cd.CommentCount * 100.0 / NULLIF(cd.Score, 0)), 2)
        ELSE 0 
    END AS comment_to_score_ratio,
    CASE 
        WHEN cd.total_posts > 0 AND cd.Reputation > 0 THEN 
            ROUND((cd.avg_post_score * 100.0 / NULLIF(cd.Reputation, 0)), 4)
        ELSE 0 
    END AS score_efficiency,
    CASE 
        WHEN cd.tag_usage_count > 0 THEN 
            ROUND((cd.tag_count * 100.0 / NULLIF(cd.tag_usage_count, 0)), 2)
        ELSE 0 
    END AS tag_usage_percentage,
    COALESCE(cd.Title, 'No Title') || ' - ' || 
    COALESCE(cd.Tags, 'No Tags') || ' - ' || 
    COALESCE(cd.user_status, 'Unknown Status') AS post_summary,
    COUNT(*) OVER () AS total_records,
    COUNT(cd.PostId) OVER (PARTITION BY cd.OwnerUserId) AS user_post_count,
    MAX(cd.Score) OVER (PARTITION BY cd.OwnerUserId) AS user_max_score,
    MIN(cd.ViewCount) OVER (PARTITION BY cd.PostTypeId) AS type_min_views,
    CASE WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = cd.OwnerUserId AND b.Class = 1) 
         THEN 'Has Gold Badge' 
         ELSE 'No Gold Badge' 
    END AS gold_badge_status,
    (CASE WHEN cd.Reputation > 10000 THEN 1 ELSE 0 END + 
     CASE WHEN cd.Score > 100 THEN 1 ELSE 0 END + 
     CASE WHEN cd.comment_count > 5 THEN 1 ELSE 0 END +
     CASE WHEN cd.gold_badge_count > 2 THEN 1 ELSE 0 END) AS user_engagement_score
FROM CombinedData cd
WHERE (cd.Score IS NOT NULL OR cd.Reputation IS NOT NULL)
  AND cd.user_status != 'Incomplete Data'
  AND (EXISTS (SELECT 1 FROM Tags t WHERE t.TagName LIKE '%java%' AND cd.Tags LIKE '%' || t.TagName || '%') 
       OR (cd.score_category != 'Low' AND cd.comment_count > 3))
GROUP BY 
    cd.PostId, cd.PostTypeId, cd.OwnerUserId, cd.Score, cd.ViewCount, cd.Title, 
    cd.Tags, cd.AnswerCount, cd.CommentCount, cd.FavoriteCount, cd.score_category,
    cd.tag_length, cd.comment_count, cd.upvote_count, cd.downvote_count,
    cd.gold_badge_count, cd.Reputation, cd.user_views, cd.total_posts,
    cd.question_count, cd.answer_count, cd.avg_post_score, cd.tag_count,
    cd.tag_usage_count, cd.avg_score_for_tag, cd.tag_popularity, cd.activity_type,
    cd.time_since_last_activity, cd.user_status
HAVING COUNT(*) > 0
ORDER BY cd.Score DESC, cd.Reputation DESC, cd.total_posts DESC, user_engagement_score DESC
LIMIT 1000;
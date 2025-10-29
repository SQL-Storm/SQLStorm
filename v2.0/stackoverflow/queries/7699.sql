-- {"query": "7699.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1673}
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
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avg_score_3posts,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS score_rank,
        NTILE(100) OVER (ORDER BY p.Score) AS score_quintile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers,
        MAX(p.Score) AS max_score,
        AVG(p.Score) AS avg_score,
        SUM(p.ViewCount) AS total_views,
        COUNT(DISTINCT b.Id) AS badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS silver_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS bronze_badges,
        STRING_AGG(DISTINCT CASE WHEN p.Tags IS NOT NULL THEN SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)) END, ', ') AS all_tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p1.ViewCount, 0) AS excerpt_views,
        COALESCE(p2.ViewCount, 0) AS wiki_views,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderate'
            WHEN t.Count > 100 THEN 'Quiet'
            ELSE 'Rare'
        END AS tag_category,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) AS popularity_rank
    FROM Tags t
    LEFT JOIN Posts p1 ON t.ExcerptPostId = p1.Id
    LEFT JOIN Posts p2 ON t.WikiPostId = p2.Id
    WHERE t.TagName IS NOT NULL
),
ComplexQueryResults AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        COALESCE(rp.prev_score, 0) AS previous_score,
        COALESCE(rp.avg_score_3posts, 0) AS rolling_avg_score,
        COALESCE(us.max_score, 0) AS user_max_score,
        COALESCE(us.avg_score, 0) AS user_avg_score,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Avg Question'
            ELSE 'Below Avg Question'
        END AS score_category,
        (rp.Score - COALESCE(rp.prev_score, 0)) AS score_change,
        (rp.Score * 0.1) + (rp.ViewCount * 0.0001) + (COALESCE(rp.AnswerCount, 0) * 0.2) AS performance_index,
        ta.TagName,
        ta.Count AS tag_count,
        ta.tag_category,
        ta.popularity_rank,
        CASE 
            WHEN COALESCE(us.badge_count, 0) > 50 THEN 'Veteran'
            WHEN COALESCE(us.badge_count, 0) > 20 THEN 'Experienced'
            WHEN COALESCE(us.badge_count, 0) > 5 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS reputation_level,
        CASE 
            WHEN rp.Score > us.max_score THEN 1
            WHEN rp.Score > (us.max_score * 0.8) THEN 2
            WHEN rp.Score > (us.max_score * 0.6) THEN 3
            ELSE 4
        END AS performance_level,
        CASE 
            WHEN rp.LastActivityDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '7' DAY) THEN 'Active'
            WHEN rp.LastActivityDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY) THEN 'Inactive'
            ELSE 'Very Inactive'
        END AS activity_status,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts) AND rp.ViewCount > (SELECT AVG(ViewCount) FROM Posts) THEN 'High Performing'
            ELSE 'Standard'
        END AS post_quality,
        STRING_AGG(DISTINCT ta.TagName, ', ') AS top_tags,
        STRING_AGG(DISTINCT CASE WHEN c.Text IS NOT NULL AND CHAR_LENGTH(c.Text) > 100 THEN SUBSTRING(c.Text FROM 1 FOR 50) END, ' ... ') AS sample_comments,
        MIN(ta.popularity_rank) AS min_tag_popularity_rank
    FROM RankedPosts rp
    LEFT JOIN UserStats us ON rp.OwnerUserId = us.UserId
    LEFT JOIN (
        SELECT t.TagName, t.TagName AS TagNameDup FROM Tags t
    ) t ON t.TagName = ANY(string_to_array(SUBSTRING(rp.Tags FROM 2 FOR (CHAR_LENGTH(rp.Tags) - 2)), '><'))
    LEFT JOIN TagAnalysis ta ON t.TagName = ta.TagName
    LEFT JOIN Comments c ON c.PostId = rp.Id AND c.Text IS NOT NULL
    WHERE rp.rn = 1
    GROUP BY 
        rp.Id, rp.PostTypeId, rp.OwnerUserId, rp.Score, rp.ViewCount, rp.Title, 
        rp.Tags, rp.AnswerCount, rp.CommentCount, rp.FavoriteCount, 
        rp.prev_score, rp.avg_score_3posts, us.max_score, us.avg_score, 
        ta.TagName, ta.Count, ta.tag_category, ta.popularity_rank, us.badge_count, rp.LastActivityDate
)
SELECT 
    Id,
    PostTypeId,
    OwnerUserId,
    Score,
    ViewCount,
    Title,
    Tags,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    previous_score,
    rolling_avg_score,
    user_max_score,
    user_avg_score,
    score_category,
    score_change,
    performance_index,
    TagName,
    tag_count,
    tag_category,
    popularity_rank,
    reputation_level,
    performance_level,
    activity_status,
    post_quality,
    top_tags,
    sample_comments
FROM ComplexQueryResults
WHERE 
    (Score > 100 OR ViewCount > 1000 OR AnswerCount > 10)
    AND (tag_category = 'Popular' OR tag_category = 'Moderate')
    AND (activity_status = 'Active' OR activity_status = 'Inactive')
    AND reputation_level IN ('Veteran', 'Experienced')
    AND performance_level IN (1, 2)
    AND post_quality = 'High Performing'
ORDER BY Score DESC, performance_index DESC, min_tag_popularity_rank ASC
LIMIT 1000;
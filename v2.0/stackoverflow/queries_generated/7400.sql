-- {"query": "7400.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1728} 
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
        p.ParentId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score,
        NTILE(4) OVER (ORDER BY p.Score) as quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as post_count,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as question_count,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as answer_count,
        MAX(p.Score) as max_score,
        AVG(p.Score) as avg_score,
        STRING_AGG(DISTINCT p.Tags, ', ') as all_tags,
        COUNT(DISTINCT b.Id) as badge_count
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'High'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'Low'
            ELSE 'Average'
        END as tag_level,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as popularity_rank
    FROM Tags t
),
ComplexFilter AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.ParentId,
        rp.rn,
        rp.prev_score,
        rp.avg_score,
        rp.quartile,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts) THEN 'Above Average'
            WHEN rp.Score < (SELECT AVG(Score) FROM Posts) THEN 'Below Average'
            ELSE 'Average'
        END as score_category,
        CASE 
            WHEN rp.ViewCount IS NULL OR rp.ViewCount = 0 THEN 'No Views'
            WHEN rp.ViewCount > 1000 THEN 'High Views'
            WHEN rp.ViewCount > 100 THEN 'Medium Views'
            ELSE 'Low Views'
        END as view_category,
        CASE 
            WHEN rp.AnswerCount > 5 THEN 'Many Answers'
            WHEN rp.AnswerCount > 0 THEN 'Some Answers'
            ELSE 'No Answers'
        END as answer_category
    FROM RankedPosts rp
    WHERE rp.rn <= 10
),
FinalResult AS (
    SELECT 
        cf.Id,
        cf.PostTypeId,
        cf.OwnerUserId,
        cf.Score,
        cf.ViewCount,
        cf.CreationDate,
        cf.Title,
        cf.Tags,
        cf.AnswerCount,
        cf.CommentCount,
        cf.FavoriteCount,
        cf.ParentId,
        cf.rn,
        cf.prev_score,
        cf.avg_score,
        cf.quartile,
        cf.score_category,
        cf.view_category,
        cf.answer_category,
        us.DisplayName,
        us.Reputation,
        us.Views as user_views,
        us.UpVotes,
        us.DownVotes,
        us.post_count,
        us.question_count,
        us.answer_count,
        us.max_score,
        us.avg_score as user_avg_score,
        us.all_tags,
        us.badge_count,
        ta.TagName,
        ta.Count as tag_count,
        ta.tag_level,
        ta.popularity_rank,
        CASE 
            WHEN cf.Score IS NULL OR cf.ViewCount IS NULL THEN 'Incomplete Data'
            WHEN cf.Score > 100 AND cf.ViewCount > 500 THEN 'High Impact'
            WHEN cf.Score < 10 AND cf.ViewCount < 10 THEN 'Low Impact'
            WHEN cf.Score BETWEEN 10 AND 100 AND cf.ViewCount BETWEEN 10 AND 500 THEN 'Moderate Impact'
            ELSE 'Mixed Impact'
        END as impact_level,
        CASE 
            WHEN cf.CreationDate > '2022-01-01' THEN 'Recent'
            WHEN cf.CreationDate BETWEEN '2020-01-01' AND '2021-12-31' THEN 'Recent Past'
            WHEN cf.CreationDate < '2020-01-01' THEN 'Old'
            ELSE 'Unknown Period'
        END as time_period,
        COALESCE(cf.Title, 'No Title') as processed_title,
        COALESCE(cf.Tags, 'No Tags') as processed_tags,
        CASE 
            WHEN cf.Tags IS NOT NULL AND cf.Tags != '' THEN 
                STRING_AGG(SUBSTRING(cf.Tags, 2, LENGTH(cf.Tags) - 2), ', ') 
            ELSE 'No Tags'
        END as separate_tags,
        CONCAT(
            'PostID:', cf.Id,
            '|Owner:', cf.OwnerUserId,
            '|Score:', cf.Score,
            '|View:', cf.ViewCount,
            '|Title:', COALESCE(cf.Title, 'No Title')
        ) as post_summary
    FROM ComplexFilter cf
    LEFT JOIN UserStats us ON cf.OwnerUserId = us.UserId
    LEFT JOIN Tags ta ON ta.TagName = ANY(string_to_array(REPLACE(REPLACE(cf.Tags, '<', ''), '>', ''), ','))
    WHERE cf.PostTypeId IS NOT NULL
    AND (cf.Score IS NULL OR cf.Score >= 0)
    AND (cf.ViewCount IS NULL OR cf.ViewCount >= 0)
    AND cf.CreationDate IS NOT NULL
)
SELECT 
    Id,
    PostTypeId,
    OwnerUserId,
    Score,
    ViewCount,
    CreationDate,
    Title,
    Tags,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    ParentId,
    rn,
    prev_score,
    avg_score,
    quartile,
    score_category,
    view_category,
    answer_category,
    DisplayName,
    Reputation,
    user_views,
    UpVotes,
    DownVotes,
    post_count,
    question_count,
    answer_count,
    max_score,
    user_avg_score,
    all_tags,
    badge_count,
    TagName,
    tag_count,
    tag_level,
    popularity_rank,
    impact_level,
    time_period,
    processed_title,
    processed_tags,
    separate_tags,
    post_summary
FROM FinalResult fr
WHERE 
    (fr.Score IS NULL OR fr.Score > -50)
    AND (fr.ViewCount IS NULL OR fr.ViewCount >= 0)
    AND (fr.AnswerCount IS NULL OR fr.AnswerCount >= 0)
    AND (fr.CommentCount IS NULL OR fr.CommentCount >= 0)
    AND (fr.FavoriteCount IS NULL OR fr.FavoriteCount >= 0)
    AND EXISTS (
        SELECT 1 
        FROM Posts p2 
        WHERE p2.Id = fr.Id 
        AND (p2.Title IS NOT NULL OR p2.Body IS NOT NULL)
    )
    AND (fr.post_count IS NULL OR fr.post_count > 0)
    AND (
        (fr.TagName IS NULL AND fr.tag_count IS NULL) 
        OR (fr.TagName IS NOT NULL AND fr.tag_count > 0)
    )
ORDER BY fr.CreationDate DESC, fr.Score DESC
LIMIT 1000;
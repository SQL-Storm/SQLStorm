-- {"query": "7585.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2150} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as avg_score_3posts,
        CASE 
            WHEN p.PostTypeId = 1 AND p.Score > 100 THEN 'HighlyVotedQuestion'
            WHEN p.PostTypeId = 2 AND p.Score > 50 THEN 'HighlyVotedAnswer'
            ELSE 'Other'
        END as post_category,
        COALESCE(
            CASE WHEN p.Tags LIKE '%<c>%<%>' THEN 'HasCCode' ELSE 'NoCCode' END,
            'Unknown'
        ) as has_c_code
    FROM Posts p
    WHERE p.CreationDate >= DATEADD(YEAR, -1, GETDATE())
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        AVG(p.Score) as avg_post_score,
        MAX(p.Score) as max_post_score,
        SUM(p.ViewCount) as total_views,
        COUNT(DISTINCT b.Id) as badge_count,
        STRING_AGG(DISTINCT b.Name, ',') as badge_names
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= DATEADD(YEAR, -2, GETDATE())
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) * 0.5 THEN 'Rare'
            ELSE 'Moderate'
        END as tag_popularity,
        COALESCE(
            (SELECT COUNT(*) FROM Posts WHERE Tags LIKE '%' + t.TagName + '%'),
            0
        ) as tag_usage_count
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
PostActivity AS (
    SELECT 
        ph.PostId,
        COUNT(*) as history_count,
        MAX(ph.CreationDate) as last_activity,
        STRING_AGG(ph.PostHistoryTypeId, ',') as activity_types,
        STRING_AGG(COALESCE(ph.Comment, ''), '|') as comments
    FROM PostHistory ph
    WHERE ph.CreationDate >= DATEADD(MONTH, -6, GETDATE())
    GROUP BY ph.PostId
),
ComplexJoin AS (
    SELECT 
        rp.Id as PostId,
        rp.Title,
        rp.Tags,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.post_category,
        rp.has_c_code,
        rp.prev_score,
        rp.avg_score_3posts,
        us.DisplayName as AuthorName,
        us.Reputation as AuthorReputation,
        us.total_posts,
        us.questions,
        us.answers,
        us.avg_post_score,
        us.max_post_score,
        us.total_views,
        ta.TagName,
        ta.Count as TagCount,
        ta.tag_popularity,
        pa.history_count,
        pa.last_activity,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) 
            AND rp.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1)
            AND rp.AnswerCount > 0 THEN 'HighValueQuestion'
            ELSE 'RegularQuestion'
        END as question_quality,
        CASE 
            WHEN rp.PostTypeId = 1 AND EXISTS (
                SELECT 1 FROM Posts p2 
                WHERE p2.ParentId = rp.Id AND p2.Score > 10
            ) THEN 'AnsweredWithHighScore'
            WHEN rp.PostTypeId = 1 AND rp.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END as answer_status,
        ISNULL(
            (SELECT TOP 1 Title FROM Posts WHERE Id = rp.ParentId),
            'NoParent'
        ) as ParentTitle,
        DATEDIFF(DAY, rp.CreationDate, GETDATE()) as DaysSinceCreation,
        CASE 
            WHEN rp.CreationDate >= DATEADD(DAY, -7, GETDATE()) THEN 'LastWeek'
            WHEN rp.CreationDate >= DATEADD(DAY, -30, GETDATE()) THEN 'LastMonth'
            ELSE 'Older'
        END as temporal_category
    FROM RankedPosts rp
    INNER JOIN UserStats us ON rp.OwnerUserId = us.UserId
    LEFT JOIN PostActivity pa ON rp.Id = pa.PostId
    LEFT JOIN Tags ta ON rp.Tags LIKE '%' + ta.TagName + '%' 
    WHERE rp.rn = 1 
    AND us.total_posts > 0 
    AND (rp.Tags IS NOT NULL OR rp.Tags != '')
)
SELECT 
    PostId,
    Title,
    Tags,
    Score,
    ViewCount,
    CreationDate,
    AuthorName,
    AuthorReputation,
    total_posts,
    questions,
    answers,
    avg_post_score,
    max_post_score,
    total_views,
    TagName,
    TagCount,
    tag_popularity,
    history_count,
    last_activity,
    question_quality,
    answer_status,
    ParentTitle,
    DaysSinceCreation,
    temporal_category,
    post_category,
    has_c_code,
    prev_score,
    avg_score_3posts,
    CASE 
        WHEN AVG(Score) OVER (ORDER BY CreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) > 50 
        THEN 'TrendingUp'
        WHEN AVG(Score) OVER (ORDER BY CreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) < 10 
        THEN 'TrendingDown'
        ELSE 'Stable'
    END as trend_status,
    DENSE_RANK() OVER (ORDER BY Score DESC) as score_rank,
    PERCENT_RANK() OVER (ORDER BY Score DESC) as score_percentile,
    CONCAT(
        'Author: ', AuthorName, 
        ' | Post: ', Title, 
        ' | Tags: ', ISNULL(Tags, 'None')
    ) as metadata_string,
    CASE 
        WHEN Score > 100 AND ViewCount > 1000 THEN 'Viral'
        WHEN Score > 50 AND ViewCount > 500 THEN 'Popular'
        WHEN Score > 10 AND ViewCount > 100 THEN 'Moderate'
        ELSE 'Low'
    END as popularity_level,
    CASE 
        WHEN history_count > 10 THEN 'HighlyActive'
        WHEN history_count > 5 THEN 'Active'
        ELSE 'Inactive'
    END as activity_level,
    CASE 
        WHEN AnswerCount > 5 THEN 'WellAnswered'
        WHEN AnswerCount > 0 THEN 'Answered'
        ELSE 'Unanswered'
    END as response_level
FROM ComplexJoin
WHERE Score > 0 
AND (Tags IS NOT NULL AND Tags != '')
AND (Total_views IS NOT NULL AND Total_views > 0)
UNION ALL
SELECT 
    0 as PostId,
    'AggregateStats' as Title,
    '' as Tags,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= DATEADD(YEAR, -1, GETDATE())) as Score,
    (SELECT SUM(ViewCount) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= DATEADD(YEAR, -1, GETDATE())) as ViewCount,
    NULL as CreationDate,
    NULL as AuthorName,
    (SELECT AVG(Reputation) FROM Users WHERE CreationDate >= DATEADD(YEAR, -2, GETDATE())) as AuthorReputation,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= DATEADD(YEAR, -1, GETDATE())) as total_posts,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= DATEADD(YEAR, -1, GETDATE())) as questions,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND CreationDate >= DATEADD(YEAR, -1, GETDATE())) as answers,
    (SELECT AVG(Score) FROM Posts) as avg_post_score,
    (SELECT MAX(Score) FROM Posts) as max_post_score,
    (SELECT SUM(ViewCount) FROM Posts) as total_views,
    NULL as TagName,
    0 as TagCount,
    NULL as tag_popularity,
    (SELECT COUNT(*) FROM PostHistory WHERE CreationDate >= DATEADD(MONTH, -6, GETDATE())) as history_count,
    NULL as last_activity,
    'Overall' as question_quality,
    'AllPosts' as answer_status,
    'Summary' as ParentTitle,
    0 as DaysSinceCreation,
    'AllTime' as temporal_category,
    NULL as post_category,
    NULL as has_c_code,
    NULL as prev_score,
    NULL as avg_score_3posts,
    'Summary' as trend_status,
    1 as score_rank,
    1 as score_percentile,
    'Summary Record' as metadata_string,
    'Summary' as popularity_level,
    'Summary' as activity_level,
    'Summary' as response_level
ORDER BY PostId, CreationDate DESC;
-- {"query": "7946.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2149} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as total_posts_by_user,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score_by_user,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        LEN(p.Title) as title_length,
        ISNULL(p.Tags, '') as normalized_tags,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with accepted answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without accepted answer'
            ELSE 'Other'
        END as post_type_description
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01' 
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT r.Id) as total_revisions,
        COUNT(DISTINCT c.Id) as total_comments,
        COUNT(DISTINCT v.Id) as total_votes,
        SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) as up_down_votes,
        COUNT(DISTINCT b.Id) as total_badges,
        STRING_AGG(DISTINCT b.Name, ', ') as badge_names,
        MAX(v.CreationDate) as last_vote_date,
        MAX(c.CreationDate) as last_comment_date,
        MAX(r.CreationDate) as last_revision_date
    FROM Users u
    LEFT JOIN PostHistory r ON u.Id = r.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
ComplexAnalysis AS (
    SELECT 
        rp.Id,
        rp.Title,
        rp.Body,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.AcceptedAnswerId,
        rp.ParentId,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.score_category,
        rp.title_length,
        rp.post_type_description,
        rp.total_posts_by_user,
        rp.avg_score_by_user,
        rp.prev_score,
        CASE 
            WHEN rp.prev_score IS NOT NULL AND rp.Score > rp.prev_score THEN 'Increased'
            WHEN rp.prev_score IS NOT NULL AND rp.Score < rp.prev_score THEN 'Decreased'
            WHEN rp.prev_score IS NOT NULL AND rp.Score = rp.prev_score THEN 'Same'
            ELSE 'New'
        END as score_trend,
        ISNULL(ua.DisplayName, 'Unknown') as owner_display_name,
        ISNULL(ua.Reputation, 0) as owner_reputation,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= '2020-01-01') THEN 'Above Average'
            WHEN rp.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= '2020-01-01') THEN 'Below Average'
            ELSE 'Average'
        END as score_comparison,
        COALESCE(
            (SELECT TOP 1 ph.Comment FROM PostHistory ph WHERE ph.PostId = rp.Id AND ph.PostHistoryTypeId = 10 ORDER BY ph.CreationDate DESC),
            'No Close Reason'
        ) as latest_close_reason,
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(rp.Tags, '<', ''), '>', ''), '&lt;', ''), '&gt;', ''), ' ', '') as cleaned_tags,
        CASE 
            WHEN CHARINDEX('sql', LOWER(rp.Body)) > 0 OR CHARINDEX('database', LOWER(rp.Body)) > 0 THEN 'Technology Focus'
            WHEN CHARINDEX('java', LOWER(rp.Title)) > 0 OR CHARINDEX('java', LOWER(rp.Body)) > 0 THEN 'Java Focus'
            WHEN CHARINDEX('python', LOWER(rp.Title)) > 0 OR CHARINDEX('python', LOWER(rp.Body)) > 0 THEN 'Python Focus'
            ELSE 'General'
        END as subject_focus
    FROM RankedPosts rp
    LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
    WHERE rp.rn = 1
),
CombinedResults AS (
    SELECT 
        ca.Id,
        ca.Title,
        ca.Body,
        ca.Score,
        ca.ViewCount,
        ca.CreationDate,
        ca.OwnerUserId,
        ca.AcceptedAnswerId,
        ca.ParentId,
        ca.AnswerCount,
        ca.CommentCount,
        ca.FavoriteCount,
        ca.score_category,
        ca.title_length,
        ca.post_type_description,
        ca.total_posts_by_user,
        ca.avg_score_by_user,
        ca.prev_score,
        ca.score_trend,
        ca.owner_display_name,
        ca.owner_reputation,
        ca.score_comparison,
        ca.latest_close_reason,
        ca.cleaned_tags,
        ca.subject_focus,
        CASE 
            WHEN ca.owner_reputation > 10000 AND ca.Score > 50 THEN 'Highly Active Expert'
            WHEN ca.owner_reputation > 5000 AND ca.Score > 25 THEN 'Active Contributor'
            WHEN ca.owner_reputation > 1000 AND ca.Score > 10 THEN 'Regular Contributor'
            ELSE 'New User'
        END as contributor_status,
        CASE 
            WHEN ca.total_posts_by_user > 100 AND ca.avg_score_by_user > 10 THEN 'High Volume Contributor'
            WHEN ca.total_posts_by_user > 50 AND ca.avg_score_by_user > 5 THEN 'Medium Volume Contributor'
            WHEN ca.total_posts_by_user > 10 AND ca.avg_score_by_user > 2 THEN 'Low Volume Contributor'
            ELSE 'New Contributor'
        END as volume_status,
        DATEDIFF(day, ca.CreationDate, GETDATE()) as days_since_creation,
        ROW_NUMBER() OVER (ORDER BY ca.Score DESC, ca.ViewCount DESC) as rank_by_score_view,
        NTILE(4) OVER (ORDER BY ca.Score DESC) as score_quartile,
        PERCENT_RANK() OVER (ORDER BY ca.ViewCount) as view_percentile
    FROM ComplexAnalysis ca
    WHERE ca.OwnerUserId IS NOT NULL
),
FinalAggregation AS (
    SELECT 
        'Performance Benchmark Query' as query_name,
        COUNT(*) as total_records,
        AVG(Score) as avg_score,
        MAX(ViewCount) as max_views,
        MIN(CreationDate) as earliest_date,
        MAX(CreationDate) as latest_date,
        COUNT(DISTINCT OwnerUserId) as unique_owners,
        COUNT(DISTINCT (SELECT TOP 1 ph.UserId FROM PostHistory ph WHERE ph.PostId = cr.Id)) as posts_with_history,
        AVG(CAST(title_length AS FLOAT)) as avg_title_length,
        STRING_AGG(DISTINCT subject_focus, '; ') as all_subject_focuses,
        STRING_AGG(DISTINCT score_category, '; ') as all_score_categories,
        COUNT(DISTINCT CASE WHEN score_trend = 'Increased' THEN 1 END) as increased_trend_count,
        COUNT(DISTINCT CASE WHEN score_trend = 'Decreased' THEN 1 END) as decreased_trend_count,
        COUNT(DISTINCT CASE WHEN score_trend = 'Same' THEN 1 END) as same_trend_count,
        STDEV(Score) as score_std_deviation,
        AVG(total_posts_by_user) as avg_posts_per_user,
        AVG(avg_score_by_user) as avg_avg_score_per_user,
        CASE 
            WHEN COUNT(*) > 0 THEN 'Query completed successfully'
            ELSE 'No records found'
        END as processing_status
    FROM CombinedResults cr
)
SELECT * FROM FinalAggregation
UNION ALL
SELECT 
    'Detailed Results',
    COUNT(*) as total_records,
    AVG(Score) as avg_score,
    MAX(ViewCount) as max_views,
    MIN(CreationDate) as earliest_date,
    MAX(CreationDate) as latest_date,
    COUNT(DISTINCT OwnerUserId) as unique_owners,
    COUNT(DISTINCT (SELECT TOP 1 ph.UserId FROM PostHistory ph WHERE ph.PostId = cr.Id)) as posts_with_history,
    AVG(CAST(title_length AS FLOAT)) as avg_title_length,
    STRING_AGG(DISTINCT subject_focus, '; ') as all_subject_focuses,
    STRING_AGG(DISTINCT score_category, '; ') as all_score_categories,
    COUNT(DISTINCT CASE WHEN score_trend = 'Increased' THEN 1 END) as increased_trend_count,
    COUNT(DISTINCT CASE WHEN score_trend = 'Decreased' THEN 1 END) as decreased_trend_count,
    COUNT(DISTINCT CASE WHEN score_trend = 'Same' THEN 1 END) as same_trend_count,
    STDEV(Score) as score_std_deviation,
    AVG(total_posts_by_user) as avg_posts_per_user,
    AVG(avg_score_by_user) as avg_avg_score_per_user,
    CASE 
        WHEN COUNT(*) > 0 THEN 'Query completed successfully'
        ELSE 'No records found'
    END as processing_status
FROM CombinedResults cr
WHERE rank_by_score_view <= 100
ORDER BY total_records DESC;
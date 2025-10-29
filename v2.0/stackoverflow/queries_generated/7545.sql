-- {"query": "7545.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1824} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_views,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as avg_score_3_posts,
        MAX(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) as max_views_per_user,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as total_posts_per_user,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without Accepted Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as post_category,
        CONCAT(p.Title, ' - ', COALESCE(p.Tags, 'No Tags')) as title_tag_concat
    FROM Posts p
    WHERE p.CreationDate >= '2019-01-01' 
      AND p.CreationDate < '2021-01-01'
),
UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score,
        MAX(p.CreationDate) as latest_activity,
        STRING_AGG(DISTINCT p.Tags, '; ') as all_tags_used,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as questions_with_accepted_answers,
        COUNT(DISTINCT CASE WHEN p.CommentCount > 0 THEN p.Id END) as posts_with_comments,
        RANK() OVER (ORDER BY SUM(p.Score) DESC) as reputation_rank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2019-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
ComplexVotesAnalysis AS (
    SELECT 
        v.PostId,
        v.UserId,
        v.VoteTypeId,
        v.CreationDate,
        v.BountyAmount,
        CASE 
            WHEN v.VoteTypeId IN (2, 3) THEN 'Mod Vote'
            WHEN v.VoteTypeId IN (8, 9) THEN 'Bounty Vote'
            ELSE 'Other Vote'
        END as vote_category,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) as vote_rank,
        LAG(v.CreationDate, 1) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) as prev_vote_time,
        LEAD(v.VoteTypeId, 1) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) as next_vote_type,
        CASE 
            WHEN v.VoteTypeId = 2 AND LAG(v.VoteTypeId, 1) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) = 3 THEN 'Down-then-Up Vote Pattern'
            WHEN v.VoteTypeId = 3 AND LAG(v.VoteTypeId, 1) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) = 2 THEN 'Up-then-Down Vote Pattern'
            ELSE 'Normal Vote Pattern'
        END as vote_pattern,
        DATEDIFF(MINUTE, LAG(v.CreationDate, 1) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate), v.CreationDate) as minutes_since_prev_vote,
        DATEDIFF(MINUTE, v.CreationDate, LAG(v.CreationDate, 1) OVER (PARTITION BY v.UserId ORDER BY v.CreationDate)) as minutes_since_prev_vote_by_user
    FROM Votes v
    WHERE v.CreationDate >= '2019-01-01' 
      AND v.VoteTypeId IN (1, 2, 3, 8, 9)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as tag_frequency,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'High Frequency'
            WHEN t.Count > 500 THEN 'Medium Frequency'
            WHEN t.Count > 100 THEN 'Low Frequency'
            ELSE 'Very Low Frequency'
        END as frequency_category,
        CASE 
            WHEN t.ExcerptPostId IS NOT NULL THEN 'Has Excerpt'
            WHEN t.WikiPostId IS NOT NULL THEN 'Has Wiki'
            ELSE 'No Content'
        END as content_status,
        RANK() OVER (ORDER BY t.Count DESC) as frequency_rank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) as previous_frequency
    FROM Tags t
    WHERE t.Count > 25
)
SELECT 
    COUNT(*) as total_results,
    COUNT(DISTINCT ra.Id) as unique_posts_analyzed,
    COUNT(DISTINCT CASE WHEN ra.post_category = 'Question with Accepted Answer' THEN ra.Id END) as questions_with_accepts,
    COUNT(DISTINCT CASE WHEN ra.post_category = 'Answer' THEN ra.Id END) as total_answers,
    AVG(ra.Score) as avg_post_score,
    AVG(ra.ViewCount) as avg_post_views,
    MIN(ra.CreationDate) as earliest_post_date,
    MAX(ra.CreationDate) as latest_post_date,
    COUNT(DISTINCT us.UserId) as active_users,
    AVG(us.post_count) as avg_posts_per_user,
    COUNT(DISTINCT CASE WHEN va.vote_category = 'Mod Vote' THEN va.PostId END) as mod_votes_count,
    COUNT(DISTINCT CASE WHEN va.vote_category = 'Bounty Vote' THEN va.PostId END) as bounty_votes_count,
    COUNT(DISTINCT ta.TagName) as total_tags_analyzed,
    AVG(ta.tag_frequency) as avg_tag_frequency,
    COUNT(DISTINCT CASE WHEN ta.frequency_category = 'High Frequency' THEN ta.TagName END) as high_freq_tags,
    COUNT(DISTINCT CASE WHEN ta.frequency_category = 'Medium Frequency' THEN ta.TagName END) as medium_freq_tags,
    AVG(CASE WHEN ra.prev_score IS NOT NULL THEN ra.Score - ra.prev_score ELSE 0 END) as avg_score_change,
    AVG(CASE WHEN ra.prev_views IS NOT NULL THEN ra.ViewCount - ra.prev_views ELSE 0 END) as avg_views_change,
    AVG(ra.avg_score_3_posts) as avg_3post_score_avg,
    AVG(CASE WHEN va.vote_pattern = 'Down-then-Up Vote Pattern' THEN 1 ELSE 0 END) * 100 as down_then_up_vote_pct,
    AVG(CASE WHEN va.vote_pattern = 'Up-then-Down Vote Pattern' THEN 1 ELSE 0 END) * 100 as up_then_down_vote_pct,
    MAX(us.reputation_rank) as max_reputation_rank
FROM RankedPosts ra
FULL OUTER JOIN UserActivityStats us ON ra.OwnerUserId = us.UserId
LEFT JOIN ComplexVotesAnalysis va ON ra.Id = va.PostId
LEFT JOIN TagAnalysis ta ON EXISTS (SELECT 1 FROM STRING_TO_ARRAY(ra.Tags, '<>') s WHERE s = ta.TagName)
WHERE ra.rn = 1 
   OR ra.post_category = 'Answer'
   OR va.vote_category IS NOT NULL
   OR ta.TagName IS NOT NULL
   OR ra.Score > 0
HAVING COUNT(*) > 0
ORDER BY 
    CASE WHEN AVG(us.post_count) > 10 THEN 1 ELSE 2 END,
    AVG(ta.tag_frequency) DESC,
    COUNT(DISTINCT ra.OwnerUserId) DESC
LIMIT 1000;
-- {"query": "7433.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1857} 
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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) as moving_avg_score,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = p.PostTypeId) 
            THEN 'AboveAvg' 
            ELSE 'BelowAvg' 
        END as score_category,
        COALESCE(p.Title, 'No Title') as title_or_default,
        REPLACE(p.Tags, '<', '') as clean_tags
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
        COUNT(DISTINCT rp.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN rp.PostTypeId = 1 THEN rp.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN rp.PostTypeId = 2 THEN rp.Id END) as answer_count,
        SUM(rp.Score) as total_score,
        AVG(rp.Score) as avg_score,
        MAX(rp.Score) as max_score,
        STRING_AGG(rp.Title, '; ') as all_titles,
        STRING_AGG(rp.Tags, ', ') as all_tags
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
ComplexVotes AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        v.BountyAmount,
        CASE 
            WHEN v.VoteTypeId IN (1, 2, 3) THEN 'Moderation'
            WHEN v.VoteTypeId IN (8, 9) THEN 'Bounty'
            WHEN v.VoteTypeId IN (5, 15) THEN 'UserInteraction'
            ELSE 'Other'
        END as vote_category,
        DENSE_RANK() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) as vote_rank,
        SUM(v.BountyAmount) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) as running_bounty_total,
        LAG(v.CreationDate) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) as prev_vote_date,
        DATEDIFF('day', LAG(v.CreationDate) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate), v.CreationDate) as days_since_prev_vote,
        CASE 
            WHEN v.UserId IS NOT NULL THEN 'UserVote'
            ELSE 'CommunityVote'
        END as vote_source
    FROM Votes v
    WHERE v.VoteTypeId IN (1, 2, 3, 5, 8, 9, 15)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        CASE 
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 50 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as tag_popularity,
        COALESCE(t.ExcerptPostId, t.WikiPostId) as associated_post,
        p.Title as post_title,
        p.Score as post_score,
        p.ViewCount as post_views
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id OR t.WikiPostId = p.Id
),
FinalAnalysis AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.total_posts,
        us.question_count,
        us.answer_count,
        us.total_score,
        us.avg_score,
        us.max_score,
        us.all_titles,
        us.all_tags,
        COALESCE(
            (SELECT COUNT(*) FROM ComplexVotes cv WHERE cv.PostId IN (
                SELECT Id FROM Posts WHERE OwnerUserId = us.UserId)
            ), 0) as total_votes,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = us.UserId AND Score > 0) as positive_score_posts,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = us.UserId AND Score < 0) as negative_score_posts,
        (SELECT AVG(datediff('day', p.CreationDate, p.LastActivityDate)) 
         FROM Posts p 
         WHERE p.OwnerUserId = us.UserId 
         AND p.CreationDate IS NOT NULL 
         AND p.LastActivityDate IS NOT NULL) as avg_days_active,
        (SELECT STRING_AGG(CONCAT('V', cv.VoteTypeId, ':', cv.vote_rank), ', ') 
         FROM ComplexVotes cv 
         WHERE cv.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = us.UserId)) as vote_summary,
        COALESCE(
            (SELECT STRING_AGG(CONCAT(ta.TagName, ':', ta.Count), ', ') 
             FROM Tags ta 
             WHERE ta.TagName IN (SELECT unnest(string_to_array(p.Tags, '<>')) FROM Posts p WHERE p.OwnerUserId = us.UserId)
            ), 'No Tags') as tag_summary,
        CASE 
            WHEN us.Reputation > (SELECT AVG(Reputation) FROM Users) * 1.5 THEN 'HighReputation'
            WHEN us.Reputation < (SELECT AVG(Reputation) FROM Users) * 0.5 THEN 'LowReputation'
            ELSE 'AverageReputation'
        END as reputation_level,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.LastActivityDate > NOW() - INTERVAL '30 day') as active_in_last_30_days
    FROM UserStats us
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.total_posts,
    fa.question_count,
    fa.answer_count,
    fa.total_score,
    fa.avg_score,
    fa.max_score,
    fa.all_titles,
    fa.all_tags,
    fa.total_votes,
    fa.positive_score_posts,
    fa.negative_score_posts,
    fa.avg_days_active,
    fa.vote_summary,
    fa.tag_summary,
    fa.reputation_level,
    fa.active_in_last_30_days,
    CASE 
        WHEN fa.total_votes > 0 THEN 
            ROUND(CAST(fa.total_score AS FLOAT) / CAST(fa.total_votes AS FLOAT), 2)
        ELSE 0 
    END as score_per_vote,
    (SELECT COUNT(*) FROM ComplexVotes cv 
     WHERE cv.vote_source = 'UserVote' 
     AND cv.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = fa.UserId)) as user_votes,
    (SELECT COUNT(*) FROM ComplexVotes cv 
     WHERE cv.vote_source = 'CommunityVote' 
     AND cv.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = fa.UserId)) as community_votes,
    (SELECT STRING_AGG(p.Title, ' | ') 
     FROM Posts p 
     WHERE p.OwnerUserId = fa.UserId 
     AND p.PostTypeId = 1) as question_titles,
    (SELECT STRING_AGG(p.Title, ' | ') 
     FROM Posts p 
     WHERE p.OwnerUserId = fa.UserId 
     AND p.PostTypeId = 2) as answer_titles,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = fa.UserId AND AnswerCount > 0) as answered_questions,
    (SELECT COUNT(*) FROM Posts p 
     JOIN ComplexVotes cv ON p.Id = cv.PostId 
     WHERE p.OwnerUserId = fa.UserId 
     AND cv.VoteTypeId IN (2, 3)) as mod_votes,
    (SELECT MAX(v.BountyAmount) 
     FROM Votes v 
     JOIN Posts p ON v.PostId = p.Id 
     WHERE p.OwnerUserId = fa.UserId 
     AND v.VoteTypeId = 8) as max_bounty,
    (SELECT SUM(COALESCE(v.BountyAmount, 0)) 
     FROM Votes v 
     JOIN Posts p ON v.PostId = p.Id 
     WHERE p.OwnerUserId = fa.UserId 
     AND v.VoteTypeId = 8) as total_bounty_earned
FROM FinalAnalysis fa
WHERE fa.total_posts > 0
  AND fa.UserId IS NOT NULL
ORDER BY fa.Reputation DESC, fa.total_score DESC
LIMIT 1000;
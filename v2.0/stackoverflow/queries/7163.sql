-- {"query": "7163.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1499} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.LastActivityDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts) THEN 'Above_Avg'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts) THEN 'Below_Avg'
            ELSE 'Avg'
        END as score_category,
        REPLACE(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ', '') as clean_tags,
        COALESCE(p.Title, 'No Title') as title_or_default,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NULL THEN 'Question without Accepted Answer'
            ELSE 'Not a Question'
        END as post_type_status
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as total_question_score,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as total_answer_score,
        COUNT(DISTINCT b.Id) as badge_count,
        MAX(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) as latest_gold_badge_date
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'Unpopular'
            ELSE 'Average'
        END as tag_popularity,
        COALESCE((SELECT COUNT(*) FROM Posts WHERE Tags LIKE '%' || t.TagName || '%'), 0) as posts_with_tag
    FROM Tags t
),
ComplexJoinResult AS (
    SELECT
        rp.Id as post_id,
        rp.PostTypeId,
        rp.ParentId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.Title,
        rp.Tags,
        rp.CreationDate,
        rp.LastActivityDate,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.rn,
        rp.prev_score,
        rp.avg_score,
        rp.score_category,
        rp.clean_tags,
        rp.title_or_default,
        rp.post_type_status,
        us.Reputation,
        us.DisplayName,
        us.Views,
        us.UpVotes,
        us.DownVotes,
        us.question_count,
        us.answer_count,
        us.total_question_score,
        us.total_answer_score,
        us.badge_count,
        us.latest_gold_badge_date,
        ta.TagName,
        ta.Count as tag_count,
        ta.ExcerptPostId,
        ta.WikiPostId,
        ta.tag_popularity,
        ta.posts_with_tag,
        (CASE WHEN rp.Score > 0 THEN CAST(CAST(rp.Score AS FLOAT) / CAST(us.Reputation AS FLOAT) * 100 AS INT) ELSE 0 END) as score_to_rep_ratio,
        CASE 
            WHEN rp.PostTypeId = 1 AND rp.AnswerCount > 0 THEN CAST(rp.AnswerCount AS FLOAT) / NULLIF(rp.Score, 0)
            ELSE NULL 
        END as answers_per_score,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) as comment_count_of_post,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 2) as upvote_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 3) as downvote_count,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = rp.Id AND ph.PostHistoryTypeId IN (10, 11, 12)) as history_event_count,
        (SELECT STRING_AGG(CAST(ph.UserId AS VARCHAR), ', ') FROM PostHistory ph WHERE ph.PostId = rp.Id AND ph.UserId IS NOT NULL) as history_user_ids,
        (SELECT STRING_AGG(ph.Comment, ' | ') FROM PostHistory ph WHERE ph.PostId = rp.Id AND ph.Comment IS NOT NULL) as history_comments
    FROM RankedPosts rp
    JOIN UserStats us ON rp.OwnerUserId = us.Id
    LEFT JOIN TagAnalysis ta ON (rp.clean_tags LIKE '%' || ta.TagName || '%' OR rp.clean_tags = ta.TagName)
    WHERE us.Reputation > 0
    AND (rp.Score > (SELECT AVG(Score) FROM Posts) OR rp.Score < (SELECT AVG(Score) FROM Posts) * -1)
    AND (rp.ViewCount > 100 OR rp.AnswerCount > 0 OR rp.FavoriteCount > 0)
    AND (rp.CreationDate > '2020-01-01' OR rp.LastActivityDate > '2020-01-01')
),
FinalAggregation AS (
    SELECT 
        *
    FROM ComplexJoinResult
    WHERE (score_to_rep_ratio > 0 OR score_to_rep_ratio < 0) 
    AND (answers_per_score > 1 OR answers_per_score IS NULL)
    AND comment_count_of_post > 0
    AND upvote_count >= 10
)
SELECT 
    *,
    (SELECT COUNT(*) FROM FinalAggregation) as total_records,
    (SELECT AVG(Reputation) FROM FinalAggregation) as avg_reputation,
    ROW_NUMBER() OVER (ORDER BY Score DESC, Reputation DESC) as final_rank,
    NTILE(10) OVER (ORDER BY Score DESC) as score_decile,
    DENSE_RANK() OVER (ORDER BY question_count DESC) as question_rank,
    RANK() OVER (ORDER BY total_question_score DESC) as question_score_rank
FROM FinalAggregation
ORDER BY Score DESC, Reputation DESC
LIMIT 5000;
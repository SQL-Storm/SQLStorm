-- {"query": "7397.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2571} 
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
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_views
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score,
        MAX(p.ViewCount) as max_views,
        MAX(p.CreationDate) as last_activity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as tag_count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'High'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'Low'
            ELSE 'Average'
        END as popularity_level,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) as prev_count
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
PostActivity AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ph.Comment,
        CASE 
            WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN 'Title/Tag Edit'
            WHEN ph.PostHistoryTypeId IN (2, 5) THEN 'Content Edit'
            WHEN ph.PostHistoryTypeId IN (10, 11) THEN 'Close/Reopen'
            WHEN ph.PostHistoryTypeId IN (12, 13) THEN 'Delete/Undelete'
            ELSE 'Other'
        END as activity_type,
        LEAD(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) as next_activity_date,
        DATEDIFF(day, ph.CreationDate, LEAD(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate)) as days_since_last_activity
    FROM PostHistory ph
    WHERE ph.PostId IS NOT NULL
    AND ph.CreationDate >= '2020-01-01'
),
ComplexVotes AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        v.BountyAmount,
        CASE 
            WHEN v.VoteTypeId = 8 THEN 'Bounty Start'
            WHEN v.VoteTypeId = 9 THEN 'Bounty Close'
            WHEN v.VoteTypeId = 2 THEN 'Upvote'
            WHEN v.VoteTypeId = 3 THEN 'Downvote'
            ELSE 'Other'
        END as vote_category,
        ROW_NUMBER() OVER (PARTITION BY v.PostId, v.VoteTypeId ORDER BY v.CreationDate ASC) as vote_sequence,
        COUNT(*) OVER (PARTITION BY v.PostId) as total_votes_per_post
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 8, 9)
),
FinalAnalysis AS (
    SELECT 
        rp.Id as PostId,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        CASE 
            WHEN rp.PostTypeId = 1 THEN 
                CASE 
                    WHEN rp.Score > 100 THEN 'Highly Voted Question'
                    WHEN rp.Score > 50 THEN 'Moderately Voted Question'
                    WHEN rp.Score > 0 THEN 'Slightly Voted Question'
                    ELSE 'Unpopular Question'
                END
            WHEN rp.PostTypeId = 2 THEN 
                CASE 
                    WHEN rp.Score > 50 THEN 'Highly Voted Answer'
                    WHEN rp.Score > 25 THEN 'Moderately Voted Answer'
                    WHEN rp.Score > 0 THEN 'Slightly Voted Answer'
                    ELSE 'Unpopular Answer'
                END
        END as post_category,
        CASE 
            WHEN rp.AnswerCount IS NOT NULL AND rp.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'No Answers'
        END as answer_status,
        CASE 
            WHEN rp.CommentCount IS NOT NULL AND rp.CommentCount > 0 THEN 'Has Comments'
            ELSE 'No Comments'
        END as comment_status,
        CASE 
            WHEN rp.FavoriteCount IS NOT NULL AND rp.FavoriteCount > 0 THEN 'Favorited'
            ELSE 'Not Favorited'
        END as favorite_status,
        DATEDIFF(day, rp.CreationDate, GETDATE()) as days_since_creation,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) 
                 OR rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) 
            THEN 'Above Avg'
            WHEN rp.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) 
                 OR rp.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) 
            THEN 'Below Avg'
            ELSE 'Avg'
        END as score_comparison,
        ISNULL(u.Reputation, 0) as user_reputation,
        ISNULL(ustats.total_posts, 0) as user_total_posts,
        ISNULL(ustats.questions, 0) as user_questions,
        ISNULL(ustats.answers, 0) as user_answers,
        ISNULL(ustats.total_score, 0) as user_total_score,
        CASE 
            WHEN rp.prev_score IS NOT NULL AND rp.Score IS NOT NULL 
                 AND rp.prev_score != 0 THEN (rp.Score - rp.prev_score) * 100.0 / rp.prev_score
            ELSE NULL 
        END as score_change_percentage,
        CASE 
            WHEN rp.prev_views IS NOT NULL AND rp.ViewCount IS NOT NULL 
                 AND rp.prev_views != 0 THEN (rp.ViewCount - rp.prev_views) * 100.0 / rp.prev_views
            ELSE NULL 
        END as view_change_percentage,
        ta.tag_count,
        ta.popularity_level,
        pa.activity_type,
        pa.days_since_last_activity,
        cv.vote_category,
        cv.vote_sequence,
        cv.total_votes_per_post,
        CASE 
            WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rp.Id AND pl.LinkTypeId = 3) THEN 'Duplicate'
            WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rp.Id AND pl.LinkTypeId = 1) THEN 'Linked'
            ELSE 'Normal'
        END as link_status
    FROM RankedPosts rp
    LEFT JOIN Users u ON rp.OwnerUserId = u.Id
    LEFT JOIN UserStats ustats ON rp.OwnerUserId = ustats.UserId
    LEFT JOIN TagAnalysis ta ON rp.Tags LIKE '%' + ta.TagName + '%'
    LEFT JOIN PostActivity pa ON rp.Id = pa.PostId
    LEFT JOIN ComplexVotes cv ON rp.Id = cv.PostId
    WHERE rp.rn = 1 
      AND rp.CreationDate >= '2021-01-01'
),
AggregatedResults AS (
    SELECT 
        fa.PostId,
        fa.PostTypeId,
        fa.OwnerUserId,
        fa.Score,
        fa.ViewCount,
        fa.Title,
        fa.Tags,
        fa.AnswerCount,
        fa.CommentCount,
        fa.FavoriteCount,
        fa.post_category,
        fa.answer_status,
        fa.comment_status,
        fa.favorite_status,
        fa.days_since_creation,
        fa.score_comparison,
        fa.user_reputation,
        fa.user_total_posts,
        fa.user_questions,
        fa.user_answers,
        fa.user_total_score,
        fa.score_change_percentage,
        fa.view_change_percentage,
        fa.tag_count,
        fa.popularity_level,
        fa.activity_type,
        fa.days_since_last_activity,
        fa.vote_category,
        fa.vote_sequence,
        fa.total_votes_per_post,
        fa.link_status,
        COUNT(*) OVER () as total_record_count,
        AVG(fa.Score) OVER (PARTITION BY fa.OwnerUserId) as avg_score_per_user,
        AVG(fa.ViewCount) OVER (PARTITION BY fa.OwnerUserId) as avg_views_per_user,
        PERCENT_RANK() OVER (ORDER BY fa.Score) as score_percentile,
        ROW_NUMBER() OVER (ORDER BY fa.Score DESC, fa.ViewCount DESC) as ranking
    FROM FinalAnalysis fa
)
SELECT 
    ar.PostId,
    ar.PostTypeId,
    ar.OwnerUserId,
    ar.Score,
    ar.ViewCount,
    ar.Title,
    ar.Tags,
    ar.AnswerCount,
    ar.CommentCount,
    ar.FavoriteCount,
    ar.post_category,
    ar.answer_status,
    ar.comment_status,
    ar.favorite_status,
    ar.days_since_creation,
    ar.score_comparison,
    ar.user_reputation,
    ar.user_total_posts,
    ar.user_questions,
    ar.user_answers,
    ar.user_total_score,
    ar.score_change_percentage,
    ar.view_change_percentage,
    ar.tag_count,
    ar.popularity_level,
    ar.activity_type,
    ar.days_since_last_activity,
    ar.vote_category,
    ar.vote_sequence,
    ar.total_votes_per_post,
    ar.link_status,
    ar.total_record_count,
    ar.avg_score_per_user,
    ar.avg_views_per_user,
    ar.score_percentile,
    ar.ranking,
    CASE 
        WHEN ar.score_percentile > 0.8 THEN 'Top 20%'
        WHEN ar.score_percentile > 0.6 THEN 'Top 40%'
        WHEN ar.score_percentile > 0.4 THEN 'Top 60%'
        WHEN ar.score_percentile > 0.2 THEN 'Top 80%'
        ELSE 'Bottom 20%'
    END as performance_tier,
    CASE 
        WHEN ar.user_total_score > 10000 THEN 'Veteran'
        WHEN ar.user_total_score > 1000 THEN 'Regular'
        WHEN ar.user_total_score > 100 THEN 'Beginner'
        ELSE 'Newbie'
    END as user_experience_level,
    IIF(ar.Score > 50 AND ar.ViewCount > 1000 AND ar.AnswerCount > 5, 'High Impact', 
        IIF(ar.Score > 25 OR ar.ViewCount > 500, 'Medium Impact', 'Low Impact')) as impact_level,
    COALESCE(ar.Tags, 'No Tags') as formatted_tags,
    CASE 
        WHEN ar.PostTypeId = 1 AND ar.AnswerCount > 0 THEN 'Question with Answers'
        WHEN ar.PostTypeId = 1 AND ar.AnswerCount IS NULL THEN 'Question without Answers'
        WHEN ar.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END as content_type
FROM AggregatedResults ar
WHERE ar.ranking BETWEEN 1 AND 1000
ORDER BY ar.ranking ASC,
         ar.Score DESC,
         ar.ViewCount DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;
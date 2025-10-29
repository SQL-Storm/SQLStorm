-- {"query": "7838.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2506} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LAG(p.ViewCount, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_views,
        CASE WHEN p.Score > 100 THEN 'High' WHEN p.Score > 50 THEN 'Medium' ELSE 'Low' END as score_category,
        CASE WHEN p.ViewCount > 1000 THEN 'Popular' WHEN p.ViewCount > 500 THEN 'Moderate' ELSE 'Low' END as view_category,
        COALESCE(p.Title, '') as title_cleaned,
        COALESCE(p.Tags, '') as tags_cleaned,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed Question'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered Question'
            WHEN p.PostTypeId = 1 THEN 'Unanswered Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as post_type_description,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as comment_count,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as days_since_creation,
        CASE WHEN p.ViewCount > 0 THEN 
            ROUND(CAST(p.Score AS FLOAT) / CAST(p.ViewCount AS FLOAT) * 100, 2) 
        ELSE 0 END as score_per_view_ratio,
        CASE WHEN p.AnswerCount > 0 THEN 
            ROUND(CAST(p.Score AS FLOAT) / CAST(p.AnswerCount AS FLOAT), 2) 
        ELSE 0 END as score_per_answer,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) as total_votes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as downvotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Name LIKE '%Yearling%' AND b.Date BETWEEN p.CreationDate AND p.CreationDate + INTERVAL '1 YEAR') as yearling_badge_count,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as duplicate_link_count
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2022-01-01 00:00:00'
      AND (p.Score > 0 OR p.ViewCount > 0 OR p.CommentCount > 0)
),
UserActivity AS (
    SELECT 
        u.Id as user_id,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(u.WebsiteUrl, '') as website_url,
        COALESCE(u.Location, '') as location,
        COALESCE(u.AboutMe, '') as about_me,
        DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate) as days_since_registration,
        CASE WHEN u.Reputation > 10000 THEN 'Elite' WHEN u.Reputation > 1000 THEN 'Advanced' ELSE 'Beginner' END as reputation_level,
        (SELECT COUNT(DISTINCT p.Id) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) as question_count,
        (SELECT COUNT(DISTINCT p.Id) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) as answer_count,
        (SELECT COUNT(DISTINCT b.Id) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) as gold_badge_count,
        (SELECT COUNT(DISTINCT b.Id) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) as silver_badge_count,
        (SELECT COUNT(DISTINCT b.Id) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) as bronze_badge_count
    FROM Users u
    WHERE u.Reputation > 100 
      AND u.CreationDate >= '2020-01-01 00:00:00'
),
TopPosts AS (
    SELECT 
        rp.Id as post_id,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.Title,
        rp.Tags,
        sp.question_count,
        sp.answer_count,
        sp.gold_badge_count,
        sp.silver_badge_count,
        sp.bronze_badge_count,
        rp.score_per_view_ratio,
        rp.score_per_answer,
        rp.days_since_creation
    FROM RankedPosts rp
    JOIN UserActivity sp ON rp.OwnerUserId = sp.user_id
    WHERE rp.rn = 1 
      AND rp.score_category IN ('High', 'Medium')
      AND rp.view_category IN ('Popular', 'Moderate')
),
PostHistoryAnalysis AS (
    SELECT 
        ph.PostId,
        COUNT(*) as total_history_entries,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 1 END) as state_change_events,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) as edit_events,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (17, 35, 36) THEN 1 END) as migration_events,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (24, 35) THEN 1 END) as edit_applied_events,
        MIN(ph.CreationDate) as first_event_date,
        MAX(ph.CreationDate) as last_event_date,
        DATEDIFF(MAX(ph.CreationDate), MIN(ph.CreationDate)) as duration_days
    FROM PostHistory ph
    WHERE ph.CreationDate >= '2022-01-01 00:00:00'
    GROUP BY ph.PostId
),
TagAnalysis AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as usage_count,
        (SELECT MAX(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as max_score,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as avg_score,
        CASE WHEN t.Count > 100 THEN 'Popular' WHEN t.Count > 50 THEN 'Moderate' ELSE 'Rare' END as tag_category,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%' AND p.Score > 50) as high_scoring_posts
    FROM Tags t
    WHERE t.Count > 10 
      AND t.TagName IS NOT NULL
      AND t.TagName != ''
    ORDER BY t.Count DESC
    LIMIT 1000
)
SELECT 
    tp.post_id,
    tp.Score,
    tp.ViewCount,
    tp.OwnerUserId,
    tp.Title,
    tp.Tags,
    tp.question_count,
    tp.answer_count,
    tp.gold_badge_count,
    tp.silver_badge_count,
    tp.bronze_badge_count,
    tp.score_per_view_ratio,
    tp.score_per_answer,
    tp.days_since_creation,
    CASE 
        WHEN tp.days_since_creation < 30 AND tp.score_per_view_ratio > 10 THEN 'Hot New'
        WHEN tp.days_since_creation >= 30 AND tp.score_per_view_ratio > 5 THEN 'Established Popular'
        WHEN tp.days_since_creation >= 30 AND tp.score_per_answer > 10 THEN 'High Quality Answer'
        WHEN tp.days_since_creation < 30 AND tp.score_per_answer > 5 THEN 'Quality New'
        ELSE 'Standard'
    END as post_category,
    CASE 
        WHEN pa.total_history_entries > 10 AND pa.state_change_events > 3 THEN 'Frequently Modified'
        WHEN pa.total_history_entries > 5 AND pa.edit_events > 2 THEN 'Regularly Edited'
        WHEN pa.state_change_events > 0 THEN 'Has State Changes'
        ELSE 'Stable'
    END as modification_status,
    ta.TagName,
    ta.Count as tag_count,
    ta.usage_count,
    ta.avg_score,
    (CASE WHEN tp.Score > tp.score_per_answer * 2 THEN 1 ELSE 0 END) as high_ratio_indicator,
    (CASE WHEN tp.question_count >= 5 AND tp.gold_badge_count >= 2 THEN 1 ELSE 0 END) as expert_contributor,
    (CASE WHEN tp.ViewCount > 10000 OR tp.Score > 100 THEN 1 ELSE 0 END) as high_impact_post,
    (tp.days_since_creation * tp.score_per_view_ratio) as time_weighted_score,
    NULLIF(tp.score_per_answer - COALESCE((SELECT AVG(score_per_answer) FROM TopPosts), 0), 0) as relative_score_difference,
    CASE 
        WHEN tp.Score > 100 THEN 'High Impact'
        WHEN tp.Score > 50 THEN 'Medium Impact'
        WHEN tp.Score > 10 THEN 'Low Impact'
        ELSE 'Minimal Impact'
    END as impact_level,
    COALESCE(pa.duration_days, 0) as post_lifespan_days,
    COALESCE(ta.tag_category, 'Unknown') as tag_category,
    (CASE WHEN tp.question_count > 0 AND tp.answer_count = 0 THEN 1 ELSE 0 END) as unanswered_question,
    (CASE WHEN tp.question_count > 0 AND tp.answer_count > 0 THEN 1 ELSE 0 END) as answered_question,
    (CASE WHEN tp.tags_cleaned != '' THEN 1 ELSE 0 END) as has_tags,
    (CASE WHEN tp.title_cleaned != '' THEN 1 ELSE 0 END) as has_title,
    (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.PostId = tp.post_id AND ph.PostHistoryTypeId = 24) as edit_suggestions_applied
FROM TopPosts tp
LEFT JOIN PostHistoryAnalysis pa ON tp.post_id = pa.PostId
LEFT JOIN TagAnalysis ta ON EXISTS (
    SELECT 1 FROM (
        SELECT TRIM(unnest(string_to_array(tp.Tags, '<'))) as tag_item
        WHERE tp.Tags IS NOT NULL
    ) t1 
    WHERE t1.tag_item = ta.TagName
)
WHERE tp.Score > 0 
  AND tp.ViewCount > 0
  AND (tp.question_count > 0 OR tp.answer_count > 0)
  AND NOT (
    (ta.tag_category = 'Rare' AND ta.Count < 50) 
    OR 
    (tp.days_since_creation > 365 AND tp.score_per_view_ratio < 1)
  )
ORDER BY tp.Score DESC, tp.ViewCount DESC, tp.days_since_creation ASC
LIMIT 100000;
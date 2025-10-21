-- {"query": "16082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2315}

WITH RECURSIVE user_influence AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS rep_rank,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Views DESC) AS views_rank_by_year
    FROM Users u
    WHERE u.Reputation > 1000 
        AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '2 years'
),
post_metrics AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        LENGTH(COALESCE(p.Body, '')) AS BodyLength,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
            WHEN p.PostTypeId = 2 AND EXISTS(
                SELECT 1 FROM Posts parent 
                WHERE parent.Id = p.ParentId AND parent.AcceptedAnswerId = p.Id
            ) THEN 2
            ELSE 0
        END AS acceptance_flag,
        EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) / 3600.0 AS hours_active,
        string_to_array(COALESCE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ''), '><') AS tag_array
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'
        AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
),
tag_performance AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT pm.PostId) AS post_count,
        AVG(pm.Score) FILTER (WHERE pm.PostTypeId = 1) AS avg_question_score,
        AVG(pm.Score) FILTER (WHERE pm.PostTypeId = 2) AS avg_answer_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pm.ViewCount) AS median_views,
        SUM(CASE WHEN pm.acceptance_flag > 0 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0) AS acceptance_rate
    FROM Tags t
    INNER JOIN post_metrics pm ON t.TagName = ANY(pm.tag_array)
    WHERE t.Count > 100
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT pm.PostId) > 50
),
badge_stats AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges,
        COUNT(DISTINCT b.Name) AS unique_badge_types,
        MAX(b.Date) AS last_badge_date,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, ', ') AS gold_badge_names
    FROM Badges b
    WHERE b.Date >= '2019-01-01'
    GROUP BY b.UserId
),
comment_engagement AS (
    SELECT 
        c.PostId,
        COUNT(*) AS comment_count,
        AVG(c.Score) AS avg_comment_score,
        MAX(c.CreationDate) - MIN(c.CreationDate) AS comment_timespan,
        COUNT(DISTINCT c.UserId) AS unique_commenters
    FROM Comments c
    WHERE c.CreationDate >= '2020-01-01'
    GROUP BY c.PostId
),
vote_patterns AS (
    SELECT 
        v.PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS favorites,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 8) AS bounty_starts,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS total_bounty,
        LAG(MAX(v.CreationDate)) OVER (PARTITION BY v.PostId ORDER BY v.VoteTypeId) AS prev_vote_time
    FROM Votes v
    WHERE v.CreationDate >= '2020-01-01'
    GROUP BY v.PostId, v.VoteTypeId
)
SELECT DISTINCT
    ui.DisplayName,
    ui.Reputation,
    ui.rep_rank,
    COALESCE(bs.gold_badges, 0) || 'G/' || COALESCE(bs.silver_badges, 0) || 'S/' || COALESCE(bs.bronze_badges, 0) || 'B' AS badge_summary,
    pm.PostId,
    CASE 
        WHEN pm.PostTypeId = 1 THEN 'Question'
        WHEN pm.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS post_type,
    pm.Score AS post_score,
    ROUND(pm.hours_active::numeric, 2) AS hours_active,
    COALESCE(ce.comment_count, 0) AS comments,
    COALESCE(vp.upvotes, 0) - COALESCE(vp.downvotes, 0) AS net_votes,
    COALESCE(vp.total_bounty, 0) AS bounty_value,
    ARRAY_TO_STRING(pm.tag_array, ', ') AS tags,
    (SELECT AVG(tp.avg_question_score) 
     FROM tag_performance tp 
     WHERE tp.TagName = ANY(pm.tag_array)) AS avg_tag_performance,
    (SELECT COUNT(*) 
     FROM post_metrics pm2 
     WHERE pm2.OwnerUserId = ui.Id 
         AND pm2.acceptance_flag > 0) AS total_accepted_posts,
    CASE 
        WHEN pm.BodyLength < 500 THEN 'Short'
        WHEN pm.BodyLength BETWEEN 500 AND 2000 THEN 'Medium'
        ELSE 'Long'
    END AS content_length_category,
    (SELECT COUNT(*) 
     FROM PostLinks pl 
     WHERE pl.PostId = pm.PostId AND pl.LinkTypeId = 3) AS duplicate_count,
    ROUND(
        (COALESCE(vp.upvotes, 0) * 10.0 + 
         COALESCE(vp.favorites, 0) * 5.0 + 
         COALESCE(ce.unique_commenters, 0) * 2.0 +
         pm.Score * 3.0) / 
        NULLIF(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - (SELECT MIN(CreationDate) FROM Posts WHERE Id = pm.PostId))) / 86400.0, 0)
    , 4) AS engagement_velocity,
    EXISTS(
        SELECT 1 
        FROM PostHistory ph 
        WHERE ph.PostId = pm.PostId 
            AND ph.PostHistoryTypeId IN (4, 5, 6)
            AND ph.UserId != pm.OwnerUserId
    ) AS has_external_edits,
    (SELECT STRING_AGG(pt.Name, ' -> ') 
     FROM (
         SELECT DISTINCT pht.Name, ph2.CreationDate
         FROM PostHistory ph2
         JOIN PostHistoryTypes pht ON ph2.PostHistoryTypeId = pht.Id
         WHERE ph2.PostId = pm.PostId
         ORDER BY ph2.CreationDate DESC
         LIMIT 3
     ) pt) AS recent_history
FROM user_influence ui
LEFT JOIN post_metrics pm ON pm.OwnerUserId = ui.Id
LEFT JOIN badge_stats bs ON bs.UserId = ui.Id
LEFT JOIN comment_engagement ce ON ce.PostId = pm.PostId
LEFT JOIN vote_patterns vp ON vp.PostId = pm.PostId
WHERE ui.rep_rank <= 10000
    AND (pm.Score IS NULL OR pm.Score >= -5)
    AND (pm.ViewCount IS NULL OR pm.ViewCount > 100)
    AND (bs.gold_badges IS NULL OR bs.gold_badges > 0 OR bs.silver_badges > 5)
ORDER BY 
    engagement_velocity DESC NULLS LAST,
    ui.Reputation DESC,
    pm.Score DESC NULLS LAST
LIMIT 500;

-- {"query": "16039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2501}

WITH RECURSIVE user_engagement_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        EXTRACT(YEAR FROM u.CreationDate) AS join_year,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS net_votes,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS bronze_badges,
        CASE 
            WHEN u.Location IS NULL OR TRIM(u.Location) = '' THEN 'Unknown'
            WHEN LOWER(u.Location) LIKE '%usa%' OR LOWER(u.Location) LIKE '%united states%' THEN 'USA'
            WHEN LOWER(u.Location) LIKE '%uk%' OR LOWER(u.Location) LIKE '%united kingdom%' THEN 'UK'
            ELSE SUBSTRING(u.Location, 1, 20)
        END AS normalized_location
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes, u.Location
),
post_statistics AS (
    SELECT 
        p.Id AS post_id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COALESCE(LENGTH(p.Body), 0) AS body_length,
        CASE 
            WHEN p.Tags IS NOT NULL THEN array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1)
            ELSE 0 
        END AS tag_count,
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400.0 AS days_active,
        EXISTS(SELECT 1 FROM Posts a WHERE a.ParentId = p.Id AND a.Score > 5) AS has_quality_answer,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS user_post_rank,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate)) AS median_views_year
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= TIMESTAMP '2015-01-01'
        AND (p.ClosedDate IS NULL OR p.ClosedDate > p.CreationDate + INTERVAL '30 days')
),
answer_acceptance_stats AS (
    SELECT 
        q.Id AS question_id,
        q.OwnerUserId AS questioner_id,
        a.OwnerUserId AS answerer_id,
        a.Id AS answer_id,
        a.Score AS answer_score,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600.0 AS hours_to_answer,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS is_accepted,
        DENSE_RANK() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS answer_quality_rank
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 
        AND a.PostTypeId = 2
        AND a.OwnerUserId IS NOT NULL
        AND q.OwnerUserId IS NOT NULL
),
comment_interaction_patterns AS (
    SELECT 
        c.PostId,
        c.UserId AS commenter_id,
        COUNT(*) AS comment_count,
        AVG(c.Score) AS avg_comment_score,
        MAX(LENGTH(c.Text)) AS max_comment_length,
        STRING_AGG(SUBSTRING(c.Text, 1, 50), ' | ' ORDER BY c.CreationDate) AS comment_preview
    FROM Comments c
    WHERE c.UserId IS NOT NULL
        AND c.CreationDate >= TIMESTAMP '2018-01-01'
    GROUP BY c.PostId, c.UserId
    HAVING COUNT(*) >= 3
),
vote_diversity_metrics AS (
    SELECT 
        v.PostId,
        COUNT(DISTINCT v.UserId) AS unique_voters,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS upvote_count,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS downvote_count,
        SUM(COALESCE(v.BountyAmount, 0)) AS total_bounty,
        MAX(v.CreationDate) AS last_vote_date
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 5, 8, 9)
    GROUP BY v.PostId
)
SELECT 
    uem.DisplayName,
    uem.normalized_location AS location,
    uem.Reputation,
    uem.gold_badges,
    uem.silver_badges,
    uem.bronze_badges,
    ROUND(AVG(ps.Score)::numeric, 2) AS avg_post_score,
    ROUND(AVG(CASE WHEN ps.PostTypeId = 1 THEN ps.Score END)::numeric, 2) AS avg_question_score,
    ROUND(AVG(CASE WHEN ps.PostTypeId = 2 THEN ps.Score END)::numeric, 2) AS avg_answer_score,
    COUNT(DISTINCT ps.post_id) AS total_posts,
    COUNT(DISTINCT CASE WHEN ps.has_quality_answer THEN ps.post_id END) AS posts_with_quality_answers,
    ROUND(AVG(ps.body_length)::numeric, 0) AS avg_body_length,
    ROUND(AVG(ps.tag_count)::numeric, 2) AS avg_tags_per_post,
    COUNT(DISTINCT aas.answer_id) AS total_answers_given,
    COUNT(DISTINCT CASE WHEN aas.is_accepted = 1 THEN aas.answer_id END) AS accepted_answers,
    ROUND(AVG(CASE WHEN aas.is_accepted = 1 THEN aas.hours_to_answer END)::numeric, 2) AS avg_hours_to_accepted_answer,
    COALESCE(SUM(vdm.upvote_count), 0) AS total_upvotes_received,
    COALESCE(SUM(vdm.downvote_count), 0) AS total_downvotes_received,
    COALESCE(SUM(vdm.total_bounty), 0) AS total_bounty_earned,
    COUNT(DISTINCT cip.PostId) AS posts_with_active_comments,
    ROUND(AVG(cip.comment_count)::numeric, 2) AS avg_comments_per_active_post,
    CASE 
        WHEN uem.Reputation >= 10000 AND uem.gold_badges >= 1 THEN 'Elite'
        WHEN uem.Reputation >= 5000 OR uem.gold_badges >= 1 THEN 'Advanced'
        WHEN uem.Reputation >= 2000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS user_tier,
    ROUND((COALESCE(SUM(vdm.upvote_count), 0)::numeric / NULLIF(COUNT(DISTINCT ps.post_id), 0))::numeric, 2) AS upvotes_per_post,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     WHERE ph.UserId = uem.Id 
       AND ph.PostHistoryTypeId IN (4, 5, 6)
       AND ph.CreationDate >= TIMESTAMP '2015-01-01') AS edit_contributions
FROM user_engagement_metrics uem
LEFT JOIN post_statistics ps ON uem.Id = ps.OwnerUserId AND ps.user_post_rank <= 100
LEFT JOIN answer_acceptance_stats aas ON uem.Id = aas.answerer_id AND aas.answer_quality_rank <= 5
LEFT JOIN vote_diversity_metrics vdm ON ps.post_id = vdm.PostId
LEFT JOIN comment_interaction_patterns cip ON ps.post_id = cip.PostId
WHERE uem.join_year >= 2010
    AND (ps.post_id IS NOT NULL OR aas.answer_id IS NOT NULL)
    AND uem.net_votes >= 0
GROUP BY 
    uem.Id, 
    uem.DisplayName, 
    uem.normalized_location, 
    uem.Reputation, 
    uem.gold_badges, 
    uem.silver_badges, 
    uem.bronze_badges
HAVING COUNT(DISTINCT ps.post_id) >= 5
    AND (COUNT(DISTINCT CASE WHEN aas.is_accepted = 1 THEN aas.answer_id END) > 0 
         OR AVG(ps.Score) > 2)
ORDER BY 
    uem.Reputation DESC,
    total_upvotes_received DESC,
    accepted_answers DESC NULLS LAST
LIMIT 500;

-- {"query": "21042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1470} 

WITH question_activities AS (
    SELECT 
        p.Id AS question_id,
        p.Title,
        p.CreationDate AS q_creation_date,
        p.Score AS q_score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS answer_count,
        p.CommentCount AS q_comment_count,
        p.ClosedDate,
        u.Reputation AS owner_reputation,
        u.DisplayName AS owner_name,
        ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.ViewCount DESC) AS monthly_popularity_rank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
        AND p.DeletionDate IS NULL
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
),
answer_stats AS (
    SELECT 
        parent_q.question_id,
        COUNT(a.Id) AS total_answers,
        SUM(a.Score) AS total_answer_score,
        AVG(a.Score) AS avg_answer_score,
        COUNT(CASE WHEN a.Score > q_acts.q_score THEN 1 END) AS better_answers_count,
        STRING_AGG(
            CASE 
                WHEN a.Score = (SELECT MAX(ans.Score) FROM question_activities q2 
                                 JOIN Posts ans ON ans.ParentId = q2.question_id 
                                 WHERE q2.question_id = parent_q.question_id) 
                THEN COALESCE(a.OwnerDisplayName, 'Anonymous') 
                ELSE NULL 
            END, 
            ' | '
        ) AS top_answer_authors
    FROM question_activities parent_q
    JOIN Posts a ON a.ParentId = parent_q.question_id 
        AND a.PostTypeId = 2 
        AND a.DeletionDate IS NULL
    JOIN question_activities q_acts ON q_acts.question_id = parent_q.question_id
    GROUP BY parent_q.question_id
),
user_engagement AS (
    SELECT 
        qa.question_id,
        COUNT(DISTINCT v.UserId) AS unique_voters,
        SUM(CASE WHEN v.VoteTypeId IN (2) THEN 1 ELSE 0 END) AS total_upvotes,
        SUM(CASE WHEN v.VoteTypeId IN (3) THEN 1 ELSE 0 END) AS total_downvotes,
        COUNT(CASE WHEN v.VoteTypeId = 1 THEN 1 END) AS accepted_count,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS total_bounties
    FROM question_activities qa
    LEFT JOIN Votes v ON v.PostId = qa.question_id 
        AND v.CreationDate >= qa.q_creation_date - INTERVAL '30 days'
        AND v.VoteTypeId IN (1,2,3,8)
    GROUP BY qa.question_id
),
closed_details AS (
    SELECT 
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment::int = 101 THEN 'Duplicate'
                 WHEN ph.PostHistoryTypeId = 10 AND ph.Comment::int = 102 THEN 'Off-topic'
                 WHEN ph.PostHistoryTypeId = 10 AND ph.Comment::int = 103 THEN 'Needs details'
                 ELSE 'Other' END) AS primary_close_reason,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) AS reopen_count
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 11)
        AND ph.PostId IN (SELECT question_id FROM question_activities)
    GROUP BY ph.PostId
),
tag_popularity AS (
    SELECT 
        p.Id AS post_id,
        STRING_AGG(t.TagName, ',') AS all_tags,
        COUNT(t.TagName) AS tag_count,
        STRING_AGG(
            CASE WHEN t.Count > 10000 THEN t.TagName ELSE NULL END, 
            ','
        ) AS popular_tags
    FROM Posts p
    JOIN Tags t ON position(t.TagName IN p.Tags) > 0
    WHERE p.PostTypeId = 1 
        AND p.Id IN (SELECT question_id FROM question_activities)
    GROUP BY p.Id
)
SELECT 
    qa.question_id,
    qa.Title,
    TO_CHAR(qa.q_creation_date, 'YYYY-MM-DD') AS creation_date,
    qa.q_score,
    qa.view_count,
    COALESCE(as_stats.total_answers, 0) AS total_answers,
    COALESCE(as_stats.avg_answer_score, 0) AS avg_answer_score,
    COALESCE(as_stats.better_answers_count, 0) AS better_scoring_answers,
    COALESCE(as_stats.top_answer_authors, 'No answers') AS top_answerers,
    COALESCE(ue.unique_voters, 0) AS unique_voters,
    COALESCE(ue.total_upvotes, 0) AS upvotes,
    COALESCE(ue.total_downvotes, 0) AS downvotes,
    COALESCE(ue.total_bounties, 0) AS bounty_amount,
    qa.monthly_popularity_rank,
    CASE 
        WHEN qa.closed_date IS NOT NULL THEN 
            COALESCE(cd.primary_close_reason, 'Unknown') || 
            CASE WHEN COALESCE(cd.reopen_count, 0) > 0 
                 THEN ' (Reopened ' || cd.reopen_count || ' times)' 
                 ELSE '' END
        WHEN qa.answer_count >= 3 AND qa.q_score > 5 THEN 'Active & Resolved'
        WHEN qa.owner_reputation > 10000 THEN 'Expert Authored'
        ELSE 'Standard'
    END AS question_status,
    COALESCE(tp.tag_count, 0) AS tag_count,
    COALESCE(tp.popular_tags, 'None') AS hot_tags,
    LENGTH(COALESCE(qa.Title, '')) + 
    COALESCE(LENGTH(tp.all_tags), 0) + 
    (COALESCE(ue.total_upvotes, 0) * 10) AS complexity_score,
    CASE 
        WHEN qa.view_count IS NULL OR qa.view_count = 0 THEN 0
        ELSE ROUND((qa.q_score + COALESCE(ue.total_upvotes, 0))::numeric / NULLIF(qa.view_count, 0) * 1000, 2)
    END AS engagement_ratio
FROM question_activities qa
LEFT JOIN answer_stats as_stats ON qa.question_id = as_stats.question_id
LEFT JOIN user_engagement ue ON qa.question_id = ue.question_id
LEFT JOIN closed_details cd ON qa.question_id = cd.PostId
LEFT JOIN tag_popularity tp ON qa.question_id = tp.post_id
WHERE qa.monthly_popularity_rank <= 50  -- Top 50 per month
    OR (qa.closed_date IS NOT NULL AND COALESCE(cd.reopen_count, 0) > 1)  -- Controversial closures
    OR COALESCE(ue.total_bounties, 0) > 100  -- High bounty questions
ORDER BY complexity_score DESC, engagement_ratio DESC
LIMIT 100;

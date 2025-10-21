-- {"query": "51053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1312} 

WITH popular_tags AS (
    SELECT t.Id, t.TagName,
           ROW_NUMBER() OVER (ORDER BY t.Count DESC) as tag_rank
    FROM Tags t
    WHERE t.Count > 1000
),
active_users AS (
    SELECT u.Id, u.Reputation, u.CreationDate,
           ROW_NUMBER() OVER (ORDER BY u.UpVotes DESC, u.Reputation DESC) as user_rank
    FROM Users u
    WHERE u.Reputation > 500
      AND u.CreationDate > CURRENT_DATE - INTERVAL '2 years'
),
question_metrics AS (
    SELECT p.Id as question_id,
           p.CreationDate as q_created,
           p.Score as q_score,
           p.ViewCount,
           p.AnswerCount,
           p.CommentCount,
           p.FavoriteCount,
           COALESCE(ph.text, '') as close_details,
           CASE 
               WHEN ph.PostHistoryTypeId = 10 THEN 'CLOSED'
               WHEN p.CommunityOwnedDate IS NOT NULL THEN 'COMMUNITY'
               WHEN ph.PostHistoryTypeId = 11 THEN 'REOPENED'
               ELSE 'OPEN'
           END as status
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId 
        AND ph.PostHistoryTypeId IN (10, 11)
        AND ph.CreationDate = (
            SELECT MAX(ph2.CreationDate)
            FROM PostHistory ph2
            WHERE ph2.PostId = p.Id
              AND ph2.PostHistoryTypeId IN (10, 11)
        )
    WHERE p.PostTypeId = 1
      AND p.Score > 0
      AND p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
),
answer_engagement AS (
    SELECT a.ParentId as question_id,
           COUNT(a.Id) as total_answers,
           AVG(a.Score) as avg_answer_score,
           SUM(CASE WHEN a.Score >= 5 THEN 1 ELSE 0 END) as high_quality_answers,
           COUNT(c.Id) as total_comments,
           AVG(v.BountyAmount) as avg_bounty
    FROM Posts a
    LEFT JOIN Comments c ON a.Id = c.PostId
    LEFT JOIN Votes v ON a.Id = v.PostId 
        AND v.VoteTypeId = 8  -- BountyStart
    WHERE a.PostTypeId = 2
      AND a.ParentId IS NOT NULL
    GROUP BY a.ParentId
),
user_interactions AS (
    SELECT 
        au.Id as user_id,
        COUNT(DISTINCT q.Id) as questions_asked,
        COUNT(DISTINCT ans.Id) as answers_given,
        SUM(q.AnswerCount) as total_answers_received,
        AVG(q.Score) as avg_question_score,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) as total_edits
    FROM active_users au
    LEFT JOIN Posts q ON q.OwnerUserId = au.Id AND q.PostTypeId = 1
    LEFT JOIN Posts ans ON ans.OwnerUserId = au.Id AND ans.PostTypeId = 2
    LEFT JOIN PostHistory ph ON ph.UserId = au.Id 
        AND ph.PostHistoryTypeId IN (4,5,6)  -- Edits
    GROUP BY au.Id
),
tag_popularity_trends AS (
    SELECT 
        pt.TagName,
        COUNT(DISTINCT q.Id) as question_count,
        AVG(q.q_score) as avg_score,
        COUNT(DISTINCT ua.user_id) as unique_authors,
        SUM(qm.AnswerCount) as total_answers,
        EXTRACT(MONTH FROM q.q_created) as month,
        EXTRACT(YEAR FROM q.q_created) as year
    FROM popular_tags pt
    JOIN Posts q ON q.Tags LIKE '%' || pt.TagName || '%'
    JOIN question_metrics qm ON q.Id = qm.question_id
    LEFT JOIN user_interactions ua ON q.OwnerUserId = ua.user_id
    WHERE q.PostTypeId = 1
      AND q.CreationDate > CURRENT_DATE - INTERVAL '6 months'
    GROUP BY pt.TagName, EXTRACT(MONTH FROM q.q_created), EXTRACT(YEAR FROM q.q_created)
)
SELECT 
    tpt.TagName as trending_tag,
    tpt.month,
    tpt.year,
    tpt.question_count,
    tpt.avg_score,
    tpt.unique_authors,
    tpt.total_answers,
    ae.total_answers as actual_answers,
    ae.avg_answer_score,
    ae.high_quality_answers,
    ui.questions_asked,
    ui.avg_question_score,
    ui.total_edits,
    CASE 
        WHEN tpt.question_count > 50 AND tpt.avg_score > 5 THEN 'HIGH_IMPACT'
        WHEN tpt.unique_authors > 20 THEN 'WIDESPREAD'
        WHEN ae.high_quality_answers > 5 THEN 'QUALITY_FOCUSED'
        ELSE 'EMERGING'
    END as trend_category,
    ROW_NUMBER() OVER (
        PARTITION BY tpt.month, tpt.year 
        ORDER BY tpt.question_count DESC, tpt.unique_authors DESC
    ) as monthly_rank
FROM tag_popularity_trends tpt
LEFT JOIN answer_engagement ae ON tpt.question_count > 0 
    AND ae.question_id IN (
        SELECT q.Id 
        FROM Posts q 
        WHERE q.Tags LIKE '%' || tpt.TagName || '%'
    )
LEFT JOIN (
    SELECT 
        ui.*,
        ROW_NUMBER() OVER (ORDER BY ui.questions_asked DESC) as overall_user_rank
    FROM user_interactions ui
    WHERE ui.questions_asked > 0
      AND ui.user_id IN (
          SELECT DISTINCT OwnerUserId 
          FROM Posts 
          WHERE Tags LIKE '%' || tpt.TagName || '%'
            AND PostTypeId = 1
      )
    LIMIT 100
) ui ON ui.user_id IN (
    SELECT DISTINCT OwnerUserId 
    FROM Posts 
    WHERE Tags LIKE '%' || tpt.TagName || '%'
      AND PostTypeId = 1
)
WHERE tpt.question_count > 10
  AND tpt.monthly_rank <= 15
ORDER BY tpt.year DESC, tpt.month DESC, tpt.monthly_rank;

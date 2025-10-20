WITH top_answerers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as answer_count,
        AVG(p.Score) as avg_answer_score,
        SUM(CASE WHEN p.Id = parent.AcceptedAnswerId THEN 1 ELSE 0 END) as accepted_count
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    INNER JOIN Posts parent ON p.ParentId = parent.Id
    WHERE p.PostTypeId = 2
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) >= 50
),
question_metrics AS (
    SELECT 
        q.Id as question_id,
        q.Title,
        q.Score as question_score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.CreationDate,
        string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><') as tag_array,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvotes,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 5) as edit_count,
        AVG(a.Score) as avg_answer_score,
        MAX(a.Score) as max_answer_score
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Votes v ON q.Id = v.PostId
    LEFT JOIN PostHistory ph ON q.Id = ph.PostId
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years'
        AND q.Score >= 5
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.CommentCount, q.CreationDate, q.Tags
),
tag_expertise AS (
    SELECT 
        ta.Id as user_id,
        t.TagName,
        COUNT(DISTINCT a.Id) as answers_in_tag,
        AVG(a.Score) as avg_score_in_tag,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) as accepted_in_tag,
        RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(DISTINCT a.Id) DESC) as rank_in_tag
    FROM top_answerers ta
    INNER JOIN Posts a ON ta.Id = a.OwnerUserId
    INNER JOIN Posts q ON a.ParentId = q.Id
    CROSS JOIN LATERAL unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as t(TagName)
    WHERE a.PostTypeId = 2
        AND q.PostTypeId = 1
    GROUP BY ta.Id, t.TagName
    HAVING COUNT(DISTINCT a.Id) >= 10
),
engagement_scores AS (
    SELECT 
        qm.question_id,
        qm.Title,
        qm.question_score,
        qm.ViewCount,
        ta.Id as answerer_id,
        ta.DisplayName,
        ta.Reputation,
        te.TagName,
        te.avg_score_in_tag,
        te.rank_in_tag,
        (CAST(qm.upvotes AS double precision) / NULLIF(qm.upvotes + qm.downvotes, 0)) * 100 as approval_rating,
        (CAST(qm.ViewCount AS double precision) / NULLIF(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - qm.CreationDate))/86400, 0)) as views_per_day,
        COALESCE(b.badge_count, 0) as user_badge_count,
        ROW_NUMBER() OVER (PARTITION BY qm.question_id ORDER BY te.avg_score_in_tag DESC, ta.Reputation DESC) as answerer_rank
    FROM question_metrics qm
    CROSS JOIN LATERAL unnest(qm.tag_array) as qt(tag)
    INNER JOIN tag_expertise te ON qt.tag = te.TagName
    INNER JOIN top_answerers ta ON te.user_id = ta.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) as badge_count
        FROM Badges
        WHERE Class <= 2
        GROUP BY UserId
    ) b ON ta.Id = b.UserId
    WHERE te.rank_in_tag <= 20
        AND qm.AnswerCount < 10
)
SELECT 
    es.question_id,
    es.Title,
    es.question_score,
    es.ViewCount,
    ROUND(CAST(es.approval_rating AS numeric), 2) as approval_percentage,
    ROUND(CAST(es.views_per_day AS numeric), 2) as daily_views,
    es.answerer_id,
    es.DisplayName as recommended_answerer,
    es.Reputation,
    es.TagName as expertise_tag,
    ROUND(CAST(es.avg_score_in_tag AS numeric), 2) as avg_tag_score,
    es.rank_in_tag as tag_rank,
    es.user_badge_count,
    COUNT(DISTINCT c.Id) as question_comment_count,
    MAX(pl.RelatedPostId) as related_duplicate_id
FROM engagement_scores es
LEFT JOIN Comments c ON es.question_id = c.PostId
LEFT JOIN PostLinks pl ON es.question_id = pl.PostId AND pl.LinkTypeId = 3
WHERE es.answerer_rank <= 3
GROUP BY 
    es.question_id, es.Title, es.question_score, es.ViewCount, 
    es.approval_rating, es.views_per_day, es.answerer_id, es.DisplayName,
    es.Reputation, es.TagName, es.avg_score_in_tag, es.rank_in_tag,
    es.user_badge_count
HAVING COUNT(DISTINCT c.Id) >= 2
ORDER BY 
    es.views_per_day DESC,
    es.approval_rating DESC,
    es.Reputation DESC
LIMIT 100;
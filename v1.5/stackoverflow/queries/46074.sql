-- {"query": "46074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 169756, "output_tokens": 136004} 
WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) as question_count,
        AVG(p.Score) as avg_score,
        SUM(p.ViewCount) as total_views
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '2 years'
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerMetrics AS (
    SELECT 
        a.ParentId as question_id,
        a.Id as answer_id,
        a.OwnerUserId as answerer_id,
        a.Score as answer_score,
        a.CreationDate as answer_date,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvote_count,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvote_count,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as answer_rank
    FROM Posts a
    LEFT JOIN Comments c ON c.PostId = a.Id
    LEFT JOIN Votes v ON v.PostId = a.Id AND v.VoteTypeId IN (2, 3)
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= cast('2024-10-01' as date) - INTERVAL '2 years'
    GROUP BY a.ParentId, a.Id, a.OwnerUserId, a.Score, a.CreationDate
),
TagEngagement AS (
    SELECT 
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag_name,
        p.Id as post_id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.Tags IS NOT NULL
        AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '2 years'
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) as gold_badges,
        COUNT(*) FILTER (WHERE b.Class = 2) as silver_badges,
        COUNT(*) FILTER (WHERE b.Class = 3) as bronze_badges,
        COUNT(*) FILTER (WHERE b.TagBased = true) as tag_badges,
        MAX(b.Date) as last_badge_date
    FROM Badges b
    GROUP BY b.UserId
),
EditActivity AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT ph.Id) as edit_count,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        MIN(ph.CreationDate) as first_edit,
        MAX(ph.CreationDate) as last_edit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.PostId
)
SELECT 
    u.DisplayName as author_name,
    u.Reputation,
    u.Location,
    tqa.question_count,
    tqa.avg_score as avg_question_score,
    tqa.total_views,
    COALESCE(ubs.gold_badges, 0) as gold_badges,
    COALESCE(ubs.silver_badges, 0) as silver_badges,
    COALESCE(ubs.bronze_badges, 0) as bronze_badges,
    p.Title as question_title,
    p.Score as question_score,
    p.ViewCount as question_views,
    p.AnswerCount,
    p.CommentCount as question_comments,
    COALESCE(ea.edit_count, 0) as question_edits,
    COALESCE(ea.unique_editors, 0) as unique_editors,
    te.tag_name,
    COUNT(DISTINCT am.answer_id) as answer_count_on_question,
    AVG(am.answer_score) as avg_answer_score,
    MAX(am.upvote_count) as max_answer_upvotes,
    COUNT(DISTINCT am.answerer_id) as unique_answerers,
    COUNT(DISTINCT pl.RelatedPostId) as linked_posts_count,
    STRING_AGG(DISTINCT lt.Name, ', ') as link_types,
    EXTRACT(EPOCH FROM (MAX(am.answer_date) - p.CreationDate))/3600 as hours_to_last_answer,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 5) as favorite_count,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 8) as bounty_count,
    SUM(v.BountyAmount) as total_bounty_amount
FROM TopQuestionAuthors tqa
INNER JOIN Users u ON u.Id = tqa.OwnerUserId
INNER JOIN Posts p ON p.OwnerUserId = tqa.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN TagEngagement te ON te.post_id = p.Id
LEFT JOIN AnswerMetrics am ON am.question_id = p.Id AND am.answer_rank <= 5
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = u.Id
LEFT JOIN EditActivity ea ON ea.PostId = p.Id
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
LEFT JOIN Votes v ON v.PostId = p.Id
WHERE p.Score >= 5
    AND p.ViewCount >= 1000
    AND te.tag_name IN (SELECT TagName FROM Tags WHERE Count >= 1000 ORDER BY Count DESC LIMIT 50)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location,
    tqa.question_count, tqa.avg_score, tqa.total_views,
    ubs.gold_badges, ubs.silver_badges, ubs.bronze_badges,
    p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.CreationDate,
    ea.edit_count, ea.unique_editors, te.tag_name
HAVING COUNT(DISTINCT am.answer_id) >= 3
ORDER BY 
    tqa.total_views DESC,
    p.Score DESC,
    COUNT(DISTINCT am.answer_id) DESC
LIMIT 100;
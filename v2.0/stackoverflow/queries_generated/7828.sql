-- {"query": "7828.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1613} 
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
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as moving_avg_score
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
        COUNT(DISTINCT r.Id) as posts_count,
        SUM(CASE WHEN r.PostTypeId = 1 THEN 1 ELSE 0 END) as questions_count,
        SUM(CASE WHEN r.PostTypeId = 2 THEN 1 ELSE 0 END) as answers_count,
        AVG(r.Score) as avg_score,
        MAX(r.CreationDate) as last_post_date
    FROM Users u
    LEFT JOIN RankedPosts r ON u.Id = r.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) * 1.5 FROM Tags) THEN 'High'
            WHEN t.Count < (SELECT AVG(Count) * 0.5 FROM Tags) THEN 'Low'
            ELSE 'Normal'
        END as tag_category,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as post_reference_count
    FROM Tags t
),
QuestionStats AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.CreationDate,
        q.OwnerUserId,
        q.Tags,
        COALESCE(q.AcceptedAnswerId, 0) as has_accepted_answer,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) as comment_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) as upvotes_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) as downvotes_count,
        CASE 
            WHEN q.AnswerCount > 0 AND q.Score > 0 THEN 'Active'
            WHEN q.AnswerCount = 0 AND q.Score >= 0 THEN 'Unanswered'
            ELSE 'Inactive'
        END as question_status
    FROM Posts q
    WHERE q.PostTypeId = 1
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.posts_count,
    us.questions_count,
    us.answers_count,
    us.avg_score,
    us.last_post_date,
    ta.TagName,
    ta.Count as tag_count,
    ta.tag_category,
    qs.QuestionId,
    qs.Title,
    qs.Score,
    qs.ViewCount,
    qs.AnswerCount,
    qs.question_status,
    CASE 
        WHEN us.posts_count > 10 AND us.avg_score > 50 THEN 'High Contributor'
        WHEN us.posts_count > 5 AND us.avg_score > 25 THEN 'Medium Contributor'
        WHEN us.posts_count > 0 THEN 'New Contributor'
        ELSE 'Inactive'
    END as contributor_level,
    COALESCE((
        SELECT AVG(r.Score)
        FROM RankedPosts r
        WHERE r.OwnerUserId = us.UserId
        AND r.rn <= 3
    ), 0) as recent_avg_score,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 1 AND p.CreationDate > '2023-01-01') as recent_questions,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 2 AND p.CreationDate > '2023-01-01') as recent_answers,
    COALESCE((
        SELECT STRING_AGG(t.TagName, ', ')
        FROM Tags t
        WHERE t.Id IN (
            SELECT DISTINCT TRIM(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2)) 
            FROM Posts p 
            WHERE p.OwnerUserId = us.UserId AND p.Tags IS NOT NULL
        )
    ), 'No Tags') as user_tags,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Class = 1) THEN 'Gold Medalist'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Class = 2) THEN 'Silver Medalist'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Class = 3) THEN 'Bronze Medalist'
        ELSE 'No Badges'
    END as medal_status,
    (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = us.UserId) as edit_count,
    (SELECT COUNT(DISTINCT v.PostId) FROM Votes v WHERE v.UserId = us.UserId AND v.VoteTypeId IN (2,3)) as vote_count,
    (SELECT COUNT(DISTINCT u.Id) FROM Users u WHERE u.AccountId IN (SELECT AccountId FROM Users WHERE Id = us.UserId) AND u.Id != us.UserId) as account_member_count
FROM UserStats us
FULL OUTER JOIN TagAnalysis ta ON (ta.Count > 100 OR ta.post_reference_count > 10)
FULL OUTER JOIN QuestionStats qs 
    ON (qs.OwnerUserId = us.UserId OR qs.QuestionId IN (
        SELECT p.Id 
        FROM Posts p 
        WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 1
    ))
WHERE 
    (us.posts_count > 0 OR ta.TagName IS NOT NULL OR qs.QuestionId IS NOT NULL)
    AND (us.UserId IS NOT NULL OR ta.TagName IS NOT NULL OR qs.QuestionId IS NOT NULL)
    AND (
        (us.Reputation > 1000 AND us.avg_score > 10) 
        OR ta.tag_category IN ('High', 'Low') 
        OR qs.question_status IN ('Active', 'Unanswered')
    )
    AND (
        (us.last_post_date > '2023-01-01' AND us.posts_count > 5)
        OR (ta.post_reference_count > 50 AND ta.Count > 500)
        OR (qs.CreationDate > '2023-01-01' AND qs.AnswerCount > 0)
    )
    AND NOT (
        (us.posts_count = 0 AND ta.tag_category = 'Normal' AND qs.QuestionId IS NULL)
        OR (us.UserId IS NULL AND ta.TagName IS NULL AND qs.QuestionId IS NULL)
    )
ORDER BY 
    CASE WHEN us.Reputation > 10000 THEN 1 ELSE 2 END,
    COALESCE(us.last_post_date, '1900-01-01'),
    ta.Count DESC,
    qs.Score DESC
LIMIT 1000;
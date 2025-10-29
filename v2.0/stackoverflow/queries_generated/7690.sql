-- {"query": "7690.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2103} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) as avg_score_3_period,
        NTILE(4) OVER (ORDER BY p.Score) as score_quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2020-01-01'
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        COUNT(DISTINCT b.Id) as badges_count,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as total_question_score,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as total_answer_score,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as avg_question_score,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as avg_answer_score,
        MAX(p.LastActivityDate) as last_activity_date
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2018-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.Title,
        rp.Tags,
        rp.OwnerUserId,
        rp.CreationDate,
        rp.LastActivityDate,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.prev_score,
        rp.next_score,
        rp.avg_score_3_period,
        rp.score_quartile,
        CASE 
            WHEN rp.prev_score IS NOT NULL AND rp.next_score IS NOT NULL 
            THEN (rp.next_score - rp.prev_score) / NULLIF((rp.next_score + rp.prev_score), 0) * 100
            ELSE NULL
        END as score_change_percentage,
        CASE 
            WHEN rp.Score > 0 AND rp.ViewCount > 0 
            THEN CAST(rp.Score AS FLOAT) / rp.ViewCount
            ELSE NULL
        END as score_per_view,
        CASE 
            WHEN rp.AnswerCount > 0 AND rp.Score > 0 
            THEN CAST(rp.Score AS FLOAT) / rp.AnswerCount
            ELSE NULL
        END as score_per_answer,
        TRIM(BOTH '<>' FROM COALESCE(rp.Tags, '')) as cleaned_tags,
        STRING_AGG(SUBSTRING(COALESCE(rp.Tags, ''), 2, LENGTH(COALESCE(rp.Tags, '')) - 2), ', ') as tag_list
    FROM RankedPosts rp
    WHERE rp.rn <= 5
    GROUP BY 
        rp.Id, rp.PostTypeId, rp.Score, rp.ViewCount, rp.Title, rp.Tags, rp.OwnerUserId, 
        rp.CreationDate, rp.LastActivityDate, rp.AnswerCount, rp.CommentCount, rp.FavoriteCount,
        rp.prev_score, rp.next_score, rp.avg_score_3_period, rp.score_quartile
),
QuestionStats AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        u.DisplayName as owner_name,
        COALESCE(COUNT(c.Id), 0) as comment_count,
        COALESCE(COUNT(DISTINCT v.Id), 0) as vote_count,
        COALESCE(SUM(v.BountyAmount), 0) as total_bounty,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Yes' 
            ELSE 'No' 
        END as has_accepted_answer,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2 AND a.Score > 0) THEN 'Yes'
            ELSE 'No'
        END as has_positive_answer,
        COALESCE(p.Title, '') || ' - Tags: ' || COALESCE(p.Tags, '') as title_tag_info
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= '2021-01-01'
    GROUP BY 
        p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, 
        p.FavoriteCount, p.CreationDate, p.LastActivityDate, u.DisplayName, p.AcceptedAnswerId, p.Tags
),
AnswerAnalysis AS (
    SELECT 
        a.Id,
        a.PostTypeId,
        a.Score,
        a.ViewCount,
        a.Body,
        a.OwnerUserId,
        a.OwnerDisplayName,
        a.CreationDate,
        a.LastEditDate,
        a.LastActivityDate,
        a.ParentId,
        q.Title as question_title,
        q.Score as question_score,
        q.ViewCount as question_view_count,
        DATEDIFF('day', a.CreationDate, q.LastActivityDate) as days_since_question_activity,
        DATEDIFF('day', q.CreationDate, a.CreationDate) as days_from_question_creation,
        CASE 
            WHEN a.Score > q.Score THEN 'Higher than Question'
            WHEN a.Score < q.Score THEN 'Lower than Question'
            ELSE 'Equal to Question'
        END as score_comparison,
        CASE 
            WHEN a.CreationDate > q.CreationDate THEN 
                COALESCE(DATEDIFF('hour', q.CreationDate, a.CreationDate), 0)
            ELSE 0 
        END as hours_to_answer,
        CASE 
            WHEN CHAR_LENGTH(a.Body) > 100 THEN SUBSTRING(a.Body, 1, 100) || '...'
            ELSE a.Body
        END as body_preview
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= '2021-01-01'
      AND q.PostTypeId = 1
      AND q.CreationDate >= '2021-01-01'
)
SELECT 
    'Overall Analysis' as report_type,
    COUNT(*) as total_records,
    COUNT(DISTINCT OwnerUserId) as unique_users,
    AVG(Score) as avg_score,
    MAX(LastActivityDate) as latest_activity,
    MIN(CreationDate) as earliest_creation,
    COUNT(DISTINCT PostTypeId) as post_type_count,
    SUM(ViewCount) as total_views,
    SUM(AnswerCount) as total_answers,
    STRING_AGG(DISTINCT COALESCE(Title, ''), ', ') as sample_titles
FROM PostAnalysis pa
LEFT JOIN UserStats us ON pa.OwnerUserId = us.UserId
LEFT JOIN QuestionStats qs ON pa.Id = qs.Id
UNION ALL
SELECT 
    'User Performance Analysis' as report_type,
    COUNT(*) as total_records,
    COUNT(DISTINCT UserId) as unique_users,
    AVG(Reputation) as avg_reputation,
    MAX(last_activity_date) as latest_activity,
    MIN(CreationDate) as earliest_creation,
    COUNT(DISTINCT Score) as score_count,
    SUM(Views) as total_views,
    SUM(answers) as total_answers,
    STRING_AGG(DisplayName, ', ') as sample_display_names
FROM UserStats us
LEFT JOIN Posts p ON us.UserId = p.OwnerUserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 11, 12) -- Close, Reopen, Delete
WHERE LastActivityDate >= '2021-01-01'
UNION ALL
SELECT 
    'Question Depth Analysis' as report_type,
    COUNT(*) as total_records,
    COUNT(DISTINCT ParentId) as unique_question_parents,
    AVG(Score) as avg_score,
    MAX(LastActivityDate) as latest_activity,
    MIN(CreationDate) as earliest_creation,
    COUNT(DISTINCT PostTypeId) as post_type_count,
    SUM(ViewCount) as total_views,
    SUM(CommentCount) as total_comments,
    STRING_AGG(DISTINCT Title, ', ') as sample_titles
FROM AnswerAnalysis aa
LEFT JOIN Posts q ON aa.ParentId = q.Id
LEFT JOIN Users u ON q.OwnerUserId = u.Id
WHERE LastActivityDate >= '2021-01-01'
  AND Days_from_question_creation <= 30
ORDER BY report_type;
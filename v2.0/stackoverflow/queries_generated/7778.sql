-- {"query": "7778.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1586} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
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
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'Unanswered Question'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Answered Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as post_category
    FROM Posts p
    WHERE p.Score IS NOT NULL
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LatestActivity,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Expert'
            WHEN u.Reputation >= 100 THEN 'Novice'
            ELSE 'Beginner'
        END as ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 50 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Rare'
            ELSE 'Unique'
        END as TagPopularity,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'),
            0
        ) as PostsUsingThisTag
    FROM Tags t
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) as EditCount,
        MAX(ph.CreationDate) as LastEdit,
        COUNT(DISTINCT ph.UserId) as Editors,
        STRING_AGG(
            CASE 
                WHEN ph.PostHistoryTypeId IN (1, 4) THEN 'Title'
                WHEN ph.PostHistoryTypeId IN (2, 5) THEN 'Body'
                WHEN ph.PostHistoryTypeId IN (3, 6) THEN 'Tags'
                ELSE 'Other'
            END, 
            ', ' 
        ) as EditTypes
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
    GROUP BY ph.PostId
),
ComplexQuestionAnalysis AS (
    SELECT 
        rp.Id as QuestionId,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.CreationDate,
        rp.post_category,
        rp.avg_score,
        COALESCE(ph.EditCount, 0) as TotalEdits,
        COALESCE(ph.Editors, 0) as EditorCount,
        COALESCE(ph.EditTypes, 'No edits') as EditTypes,
        CASE 
            WHEN rp.Score > 10 THEN 'Highly Voted'
            WHEN rp.Score > 5 THEN 'Moderately Voted'
            WHEN rp.Score > 0 THEN 'Slightly Voted'
            ELSE 'Not Voted'
        END as VotingStatus,
        CASE 
            WHEN rp.AnswerCount = 0 THEN 'No Answers'
            WHEN rp.AnswerCount = 1 THEN 'One Answer'
            WHEN rp.AnswerCount > 1 THEN 'Multiple Answers'
            ELSE 'Unknown'
        END as AnswerStatus,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
            ELSE 'Below Average'
        END as PerformanceAgainstAverage
    FROM RankedPosts rp
    LEFT JOIN PostHistorySummary ph ON rp.Id = ph.PostId
    WHERE rp.PostTypeId = 1
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.ReputationTier,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.Badges,
    ua.LatestActivity,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 1 AND p.Score > 100) THEN 'High Performer'
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 1 AND p.Score > 50) THEN 'Mid Performer'
        ELSE 'Regular'
    END as PerformanceLevel,
    COUNT(DISTINCT cq.QuestionId) as HighVotedQuestions,
    AVG(cq.Score) as AvgQuestionScore,
    MAX(cq.ViewCount) as MaxQuestionViews,
    STRING_AGG(
        CASE 
            WHEN cq.VotingStatus = 'Highly Voted' THEN cq.Title
            ELSE NULL
        END, 
        ' | '
    ) as HighVotedQuestionTitles,
    STRING_AGG(
        CASE 
            WHEN cq.AnswerStatus = 'Multiple Answers' THEN cq.Title
            ELSE NULL
        END, 
        ' | '
    ) as MultiAnsweredQuestions,
    NULLIF(
        STRING_AGG(
            CASE 
                WHEN cq.EditTypes LIKE '%Title%' THEN 'Title Edits'
                WHEN cq.EditTypes LIKE '%Body%' THEN 'Body Edits'
                ELSE 'Other Edits'
            END, 
            ', '
        ), 
        ''
    ) as EditPattern,
    CASE 
        WHEN COUNT(DISTINCT cq.QuestionId) > 5 AND AVG(cq.Score) > 20 THEN 'Active and Popular'
        WHEN COUNT(DISTINCT cq.QuestionId) > 5 THEN 'Active'
        WHEN AVG(cq.Score) > 20 THEN 'Popular'
        ELSE 'Neutral'
    END as UserEngagementStatus
FROM UserActivity ua
LEFT JOIN ComplexQuestionAnalysis cq ON ua.UserId = (
    SELECT OwnerUserId FROM Posts WHERE Id = cq.QuestionId
)
WHERE ua.Reputation > 0
GROUP BY 
    ua.UserId, 
    ua.DisplayName, 
    ua.Reputation, 
    ua.ReputationTier, 
    ua.TotalPosts, 
    ua.Questions, 
    ua.Answers, 
    ua.Badges, 
    ua.LatestActivity
HAVING 
    COUNT(DISTINCT cq.QuestionId) > 0 
    OR MIN(ua.Reputation) > 100
ORDER BY 
    AVG(cq.Score) DESC,
    ua.TotalPosts DESC
LIMIT 100;
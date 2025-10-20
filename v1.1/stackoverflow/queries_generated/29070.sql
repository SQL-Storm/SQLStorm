-- {"query": "29070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1873} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT t.TagName, ', ') as TagInterests,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Highly Active'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Active'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Regular'
            ELSE 'Occasional'
        END as ActivityLevel,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN (
        SELECT DISTINCT UserId, TagName 
        FROM (
            SELECT p.OwnerUserId as UserId, UNNEST(STRING_TO_ARRAY(p.Tags, '<>')) as TagName
            FROM Posts p
            WHERE p.Tags IS NOT NULL AND p.Tags != ''
        ) tags
    ) t ON u.Id = t.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopQuestions AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        u.DisplayName as OwnerName,
        p.OwnerUserId,
        STRING_AGG(DISTINCT t.TagName, ', ') as Tags
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT DISTINCT PostId, UNNEST(STRING_TO_ARRAY(Tags, '<>')) as TagName
        FROM Posts
        WHERE Tags IS NOT NULL AND Tags != ''
    ) t ON p.Id = t.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.CreationDate, u.DisplayName, p.OwnerUserId
),
QuestionStats AS (
    SELECT 
        tq.QuestionId,
        tq.Title,
        tq.OwnerName,
        tq.Score,
        tq.ViewCount,
        tq.AnswerCount,
        tq.CommentCount,
        tq.CreationDate,
        tq.Tags,
        CASE 
            WHEN tq.Score > 100 THEN 'Highly Voted'
            WHEN tq.Score > 50 THEN 'Well Voted'
            WHEN tq.Score > 10 THEN 'Moderately Voted'
            ELSE 'Low Voted'
        END as VotingLevel,
        NTILE(4) OVER (ORDER BY tq.Score DESC) as ScoreQuartile,
        ROW_NUMBER() OVER (PARTITION BY tq.OwnerName ORDER BY tq.CreationDate DESC) as QuestionRank,
        AVG(tq.Score) OVER (PARTITION BY tq.OwnerName) as OwnerAvgScore,
        (tq.Score - AVG(tq.Score) OVER (PARTITION BY tq.OwnerName)) / NULLIF(STDDEV(tq.Score) OVER (PARTITION BY tq.OwnerName), 0) as ZScore
    FROM TopQuestions tq
),
RecentActivity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.LastActivityDate,
        u.DisplayName as OwnerName,
        p.PostTypeId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        DATEDIFF('day', p.CreationDate, CURRENT_DATE) as AgeInDays,
        DATEDIFF('day', p.LastActivityDate, p.CreationDate) as DaysSinceActivity
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= DATEADD('month', -6, CURRENT_DATE)
),
CommunityMetrics AS (
    SELECT 
        COUNT(*) as TotalPosts,
        COUNT(DISTINCT OwnerUserId) as ActiveUsers,
        AVG(Score) as AvgScore,
        AVG(ViewCount) as AvgViews,
        COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) as TotalQuestions,
        COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN Id END) as TotalAnswers,
        (COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) * 100.0) / NULLIF(COUNT(*), 0) as QuestionPercentage,
        STRING_AGG(DISTINCT Name, ', ') as PopularVoteTypes
    FROM Posts p
    LEFT JOIN VoteTypes v ON v.Id = (
        SELECT VoteTypeId 
        FROM Votes v2 
        WHERE v2.PostId = p.Id 
        GROUP BY VoteTypeId 
        ORDER BY COUNT(*) DESC 
        LIMIT 1
    )
    WHERE CreationDate >= DATEADD('month', -6, CURRENT_DATE)
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.PostCount,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.BadgeCount,
    uas.ActivityLevel,
    uas.ActivityRank,
    qs.QuestionId,
    qs.Title as QuestionTitle,
    qs.Score as QuestionScore,
    qs.ViewCount as QuestionViews,
    qs.AnswerCount as QuestionAnswers,
    qs.CommentCount as QuestionComments,
    qs.CreationDate as QuestionCreated,
    qs.Tags as QuestionTags,
    qs.VotingLevel,
    qs.ScoreQuartile,
    qs.QuestionRank,
    qs.OwnerAvgScore,
    qs.ZScore,
    ra.PostId,
    ra.Title as RecentTitle,
    ra.Score as RecentScore,
    ra.CreationDate as RecentCreated,
    ra.LastActivityDate as RecentLastActivity,
    ra.PostType,
    ra.AgeInDays,
    ra.DaysSinceActivity,
    cm.TotalPosts,
    cm.ActiveUsers,
    cm.AvgScore,
    cm.AvgViews,
    cm.TotalQuestions,
    cm.TotalAnswers,
    cm.QuestionPercentage,
    CASE 
        WHEN uas.PostCount > 50 AND uas.Reputation > 5000 THEN 'Elite Contributor'
        WHEN uas.PostCount > 20 AND uas.Reputation > 1000 THEN 'Regular Contributor'
        WHEN uas.PostCount > 5 AND uas.Reputation > 100 THEN 'New Contributor'
        ELSE 'Inactive'
    END as ContributorTier,
    COALESCE(uas.PostCount, 0) + COALESCE(uas.CommentCount, 0) + COALESCE(uas.BadgeCount, 0) as TotalEngagement,
    CASE 
        WHEN (uas.QuestionCount * 1.0) / NULLIF(uas.PostCount, 0) > 0.3 THEN 'Question Focused'
        WHEN (uas.AnswerCount * 1.0) / NULLIF(uas.PostCount, 0) > 0.3 THEN 'Answer Focused'
        ELSE 'Mixed Focus'
    END as ContributionFocus,
    RANK() OVER (ORDER BY uas.Reputation DESC, uas.PostCount DESC) as ReputationRank,
    DENSE_RANK() OVER (ORDER BY uas.ActivityLevel, uas.Reputation DESC) as ActivityReputationRank
FROM UserActivityStats uas
LEFT JOIN QuestionStats qs ON uas.UserId = qs.OwnerName OR (qs.OwnerName IS NULL AND uas.UserId = qs.OwnerName)
LEFT JOIN RecentActivity ra ON uas.UserId = ra.OwnerName
LEFT JOIN CommunityMetrics cm
WHERE uas.ActivityLevel IN ('Highly Active', 'Active')
  AND (qs.QuestionId IS NOT NULL OR ra.PostId IS NOT NULL)
  AND uas.PostCount >= 3
  AND EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.OwnerUserId = uas.UserId 
      AND p.CreationDate >= DATEADD('month', -3, CURRENT_DATE)
  )
  AND uas.Reputation >= (
    SELECT AVG(Reputation) + STDDEV(Reputation) 
    FROM Users
  )
ORDER BY uas.ActivityRank, qs.ZScore DESC, ra.CreationDate DESC
LIMIT 5000;
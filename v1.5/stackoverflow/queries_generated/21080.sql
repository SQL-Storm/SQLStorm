-- {"query": "21080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1793} 

WITH ActiveUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as Answers,
        AVG(p.Score) as AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate > CURRENT_DATE - INTERVAL '365 days'
    WHERE u.Reputation > 100 
      AND u.LastAccessDate > CURRENT_DATE - INTERVAL '90 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 0
),
QuestionStats AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score as QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        COALESCE(p.ClosedDate, p.CreationDate) as LastStatusChange,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.ViewCount DESC) as ViewRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousQuestionScore,
        SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) as RawTags,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community'
            ELSE 'Open'
        END as QuestionStatus
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.CreationDate > CURRENT_DATE - INTERVAL '2 years'
      AND p.DeletionDate IS NULL  -- Assuming DeletionDate exists or use NOT EXISTS
),
TopContributors AS (
    SELECT au.*,
           RANK() OVER (ORDER BY au.TotalPosts DESC, au.Reputation DESC) as ContributionRank
    FROM ActiveUsers au
),
DetailedContributions AS (
    SELECT 
        tc.Id,
        tc.DisplayName,
        tc.ContributionRank,
        qs.QuestionId,
        qs.Title,
        qs.QuestionScore,
        qs.ViewRank,
        qs.QuestionStatus,
        CASE 
            WHEN qs.ViewRank <= 10 THEN 'High Impact'
            WHEN qs.ViewRank <= 50 THEN 'Medium Impact'
            ELSE 'Low Impact'
        END as ImpactLevel,
        LENGTH(COALESCE(qs.RawTags, '')) as TagComplexity,
        CASE 
            WHEN qs.AnswerCount > 5 AND qs.QuestionScore > 10 THEN 1
            WHEN qs.AnswerCount = 0 AND qs.ViewCount > 1000 THEN 1
            ELSE 0
        END as NeedsAttention
    FROM TopContributors tc
    INNER JOIN QuestionStats qs ON tc.Id = (SELECT OwnerUserId FROM Posts WHERE Id = qs.QuestionId)
    WHERE tc.ContributionRank <= 50
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) as Favorites,
        AVG(v.BountyAmount) as AvgBounty,
        COUNT(*) as TotalInteractions
    FROM Votes v
    WHERE v.CreationDate > CURRENT_DATE - INTERVAL '1 year'
      AND v.VoteTypeId IN (2, 3, 5, 8)
    GROUP BY v.PostId
),
ComplexRelationships AS (
    SELECT 
        dc.DisplayName,
        dc.QuestionId,
        dc.Title,
        dc.QuestionScore,
        dc.ViewRank,
        dc.ImpactLevel,
        dc.NeedsAttention,
        COALESCE(va.UpVotes, 0) as UpVotes,
        COALESCE(va.DownVotes, 0) as DownVotes,
        COALESCE(va.Favorites, 0) as Favorites,
        dc.TagComplexity,
        -- Complex string manipulation
        CASE 
            WHEN POSITION('sql' IN LOWER(COALESCE(dc.RawTags, ''))) > 0 
                 OR POSITION('database' IN LOWER(COALESCE(dc.RawTags, ''))) > 0 
                 THEN CONCAT('Technical: ', SUBSTRING(dc.Title FROM 1 FOR 50))
            WHEN LENGTH(dc.Title) > 100 THEN CONCAT('Long: ', LEFT(dc.Title, 97), '...')
            ELSE dc.Title
        END as FormattedTitle,
        -- NULL logic and complex predicates
        CASE 
            WHEN dc.NeedsAttention = 1 AND COALESCE(va.UpVotes, 0) < 5 THEN 'Urgent Attention'
            WHEN dc.ViewRank <= 10 AND dc.QuestionScore > (COALESCE(va.UpVotes, 0) * 2) THEN 'Star Performer'
            WHEN dc.ClosedDate IS NOT NULL AND COALESCE(va.DownVotes, 0) > 3 THEN 'Controversial'
            ELSE 'Standard'
        END as PriorityCategory,
        -- Date calculations
        EXTRACT(EPOCH FROM (CURRENT_DATE - COALESCE(qs.ClosedDate, qs.CreationDate))) / 86400 as DaysSinceLastActivity
    FROM DetailedContributions dc
    INNER JOIN QuestionStats qs ON dc.QuestionId = qs.QuestionId
    LEFT JOIN VoteAnalysis va ON qs.QuestionId = va.PostId
    WHERE dc.ContributionRank <= 20
      OR (dc.NeedsAttention = 1 AND COALESCE(va.UpVotes, 0) < 10)
)
SELECT 
    cr.DisplayName,
    cr.FormattedTitle,
    cr.QuestionScore,
    cr.UpVotes,
    cr.DownVotes,
    cr.Favorites,
    cr.ViewRank,
    cr.ImpactLevel,
    cr.PriorityCategory,
    cr.DaysSinceLastActivity,
    -- Window function for running totals
    SUM(cr.UpVotes) OVER (PARTITION BY cr.DisplayName ORDER BY cr.DaysSinceLastActivity) as RunningUpVotes,
    -- Complex aggregation with conditional logic
    COUNT(CASE WHEN cr.PriorityCategory = 'Urgent Attention' THEN 1 END) OVER (PARTITION BY cr.ImpactLevel) as UrgentCountInGroup,
    -- Percentile calculation
    PERCENT_RANK() OVER (ORDER BY cr.QuestionScore DESC) as ScorePercentile,
    -- Complex arithmetic expression
    (cr.UpVotes * 2.0 - cr.DownVotes + cr.Favorites * 0.5 + cr.ViewRank * 0.1)::numeric(10,2) as EngagementScore,
    -- String aggregation for tags
    STRING_AGG(
        CASE 
            WHEN cr.TagComplexity > 50 THEN 'Complex'
            WHEN cr.TagComplexity > 20 THEN 'Medium'
            ELSE 'Simple'
        END, 
        ', '
        ORDER BY cr.QuestionId
    ) OVER (PARTITION BY cr.DisplayName) as TagProfile
FROM ComplexRelationships cr
WHERE cr.DaysSinceLastActivity < 365
  AND (cr.PriorityCategory IN ('Urgent Attention', 'Star Performer') 
       OR cr.ImpactLevel = 'High Impact')
UNION ALL
SELECT 
    'GLOBAL_AVG' as DisplayName,
    'Overall Statistics' as FormattedTitle,
    AVG(cr.QuestionScore) as QuestionScore,
    AVG(cr.UpVotes) as UpVotes,
    AVG(cr.DownVotes) as DownVotes,
    AVG(cr.Favorites) as Favorites,
    AVG(cr.ViewRank) as ViewRank,
    'Aggregate' as ImpactLevel,
    'Benchmark' as PriorityCategory,
    AVG(cr.DaysSinceLastActivity) as DaysSinceLastActivity,
    NULL as RunningUpVotes,
    NULL as UrgentCountInGroup,
    NULL as ScorePercentile,
    AVG((cr.UpVotes * 2.0 - cr.DownVotes + cr.Favorites * 0.5 + cr.ViewRank * 0.1))::numeric(10,2) as EngagementScore,
    NULL as TagProfile
FROM ComplexRelationships cr
ORDER BY 
    CASE cr.PriorityCategory 
        WHEN 'Urgent Attention' THEN 1
        WHEN 'Star Performer' THEN 2
        ELSE 3
    END,
    cr.EngagementScore DESC,
    cr.DaysSinceLastActivity ASC
LIMIT 100;

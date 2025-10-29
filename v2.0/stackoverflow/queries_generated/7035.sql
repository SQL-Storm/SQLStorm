-- {"query": "7035.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2115} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        AVG(p.ViewCount) as AvgViewCount,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id))
            ELSE 0 
        END as QuestionPercentage
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        QuestionCount,
        AnswerCount,
        TotalScore,
        AvgViewCount,
        QuestionPercentage,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, Reputation DESC) as RankByScore,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as RankByReputation,
        NTILE(10) OVER (ORDER BY PostCount DESC) as PostCountDecile,
        CASE 
            WHEN Reputation > 10000 THEN 'Elite'
            WHEN Reputation > 5000 THEN 'Veteran'
            WHEN Reputation > 1000 THEN 'Regular'
            ELSE 'Newbie'
        END as ReputationTier,
        -- Calculate bonus score based on activity
        (PostCount * 10 + QuestionCount * 5 + AnswerCount * 3 + TotalScore * 0.1 + 
         CASE WHEN AvgViewCount > 100 THEN AvgViewCount * 0.01 ELSE 0 END) as BonusScore
    FROM UserStats
    WHERE PostCount > 0
),
UserPostAnalysis AS (
    SELECT 
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        DATEDIFF(DAY, p.CreationDate, GETDATE()) as DaysSinceCreation,
        CASE 
            WHEN DATEDIFF(DAY, p.CreationDate, GETDATE()) < 30 THEN 'New'
            WHEN DATEDIFF(DAY, p.CreationDate, GETDATE()) < 90 THEN 'Recent'
            WHEN DATEDIFF(DAY, p.CreationDate, GETDATE()) < 365 THEN 'Active'
            ELSE 'Stale'
        END as PostAgeCategory,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as PostRecencyRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousPostDate,
        LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COUNT(DISTINCT p.Id) as AssociatedPostCount,
        AVG(p.Score) as AvgScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as TopContributors,
        -- Calculate tag popularity score
        (t.Count * 10 + AVG(p.Score) * 0.5) as TagPopularityScore,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as PopularityLevel
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' + t.TagName + '%'
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalScore,
    tu.AvgViewCount,
    tu.QuestionPercentage,
    tu.RankByScore,
    tu.RankByReputation,
    tu.PostCountDecile,
    tu.ReputationTier,
    tu.BonusScore,
    -- Complex calculations combining multiple metrics
    CASE 
        WHEN tu.BonusScore > 1000 THEN 'Highly Active'
        WHEN tu.BonusScore > 500 THEN 'Active'
        WHEN tu.BonusScore > 100 THEN 'Regular'
        ELSE 'Casual'
    END as ActivityLevel,
    -- Get top posts information
    (SELECT STRING_AGG(
        CASE 
            WHEN upa.PostTypeId = 1 THEN 'Question: ' + LEFT(upa.Title, 50) + ' (Score: ' + CAST(upa.Score AS VARCHAR(10)) + ')'
            WHEN upa.PostTypeId = 2 THEN 'Answer: Score ' + CAST(upa.Score AS VARCHAR(10))
            ELSE 'Post: Score ' + CAST(upa.Score AS VARCHAR(10))
        END, '; '
    ) 
    FROM UserPostAnalysis upa 
    WHERE upa.OwnerUserId = tu.UserId 
    AND upa.Score >= (SELECT AVG(Score) FROM UserPostAnalysis WHERE OwnerUserId = tu.UserId) + 10
    ORDER BY upa.Score DESC
    OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY) as HighScoringPosts,
    -- Tag analysis for user's posts
    (SELECT STRING_AGG(
        ta.TagName + ' (' + CAST(ta.TagCount AS VARCHAR(10)) + ')', 
        ', '
    ) 
    FROM TagAnalysis ta
    WHERE ta.TagName IN (
        SELECT DISTINCT TRIM(value) 
        FROM STRING_SPLIT(
            (SELECT STRING_AGG(p.Tags, ' ') 
             FROM Posts p 
             WHERE p.OwnerUserId = tu.UserId AND p.Tags IS NOT NULL), 
            '><'
        )
        WHERE value IS NOT NULL AND value != ''
    )
    ORDER BY ta.TagCount DESC
    OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY) as TopTags,
    -- Calculate performance indicators
    (CASE 
        WHEN tu.QuestionCount > 0 AND tu.AnswerCount > 0 THEN 
            CAST(tu.AnswerCount AS FLOAT) / tu.QuestionCount
        ELSE 0 
    END) as AnswerToQuestionRatio,
    -- Include complex date calculations
    (SELECT AVG(DATEDIFF(DAY, upa.PreviousPostDate, upa.CreationDate))
     FROM UserPostAnalysis upa 
     WHERE upa.OwnerUserId = tu.UserId 
     AND upa.PreviousPostDate IS NOT NULL) as AvgDaysBetweenPosts,
    -- Get last activity info
    (SELECT MAX(upa.CreationDate) 
     FROM UserPostAnalysis upa 
     WHERE upa.OwnerUserId = tu.UserId) as LastActivePost,
    -- Calculate growth rate
    (CASE 
        WHEN tu.PostCount > 1 THEN 
            (tu.PostCount - (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = tu.UserId AND CreationDate < DATEADD(YEAR, -1, GETDATE()))) * 100.0 / NULLIF((SELECT COUNT(*) FROM Posts WHERE OwnerUserId = tu.UserId AND CreationDate < DATEADD(YEAR, -1, GETDATE())), 0)
        ELSE 0 
    END) as AnnualGrowthRate,
    -- Complex boolean logic
    CASE 
        WHEN tu.PostCount >= 100 OR tu.Reputation >= 10000 OR tu.TotalScore >= 1000 
        THEN CAST(1 AS BIT)
        ELSE CAST(0 AS BIT)
    END as HighAchievementFlag,
    -- Final score calculation
    (tu.TotalScore * 1.2 + tu.Reputation * 0.001 + 
     COALESCE((SELECT AVG(Score) FROM UserPostAnalysis WHERE OwnerUserId = tu.UserId) * 0.5, 0) +
     COALESCE((SELECT AVG(ViewCount) FROM UserPostAnalysis WHERE OwnerUserId = tu.UserId) * 0.01, 0)) as FinalUserScore
FROM TopUsers tu
WHERE tu.PostCount >= 10
HAVING (
    -- Complex predicate with set operators and subqueries
    EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = tu.UserId AND PostTypeId = 1) 
    OR EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = tu.UserId AND PostTypeId = 2)
    OR EXISTS (SELECT 1 FROM Comments WHERE UserId = tu.UserId)
    OR EXISTS (SELECT 1 FROM Badges WHERE UserId = tu.UserId)
)
ORDER BY tu.BonusScore DESC, tu.TotalScore DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
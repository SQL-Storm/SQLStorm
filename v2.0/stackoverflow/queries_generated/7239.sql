-- {"query": "7239.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1852} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        AVG(p.ViewCount) as AvgViewCount,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        TotalScore,
        LastPostDate,
        LastCommentDate,
        AvgViewCount,
        AllTags,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, PostCount DESC) as RankByScore,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC, Reputation DESC) as RankByPosts
    FROM UserActivityStats
),
UserPostAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalScore,
        tu.PostCount,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.AvgViewCount,
        tu.AllTags,
        (tu.AnswerCount * 100.0 / NULLIF(tu.QuestionCount, 0)) as AnswerPercentage,
        CASE 
            WHEN tu.QuestionCount > 0 THEN (tu.AnswerCount * 100.0 / NULLIF(tu.QuestionCount, 0))
            ELSE 0 
        END as AnswerToQuestionRatio,
        CASE 
            WHEN tu.Reputation >= 10000 THEN 'Elite'
            WHEN tu.Reputation >= 5000 THEN 'Advanced'
            WHEN tu.Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationTier,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.PostTypeId = 1 AND p.Score > 0),
            0
        ) as HighScoreQuestions,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.PostTypeId = 2 AND p.Score > 0),
            0
        ) as HighScoreAnswers,
        DATEDIFF(DAY, tu.LastPostDate, CURRENT_TIMESTAMP) as DaysSinceLastPost,
        DATEDIFF(DAY, tu.LastCommentDate, CURRENT_TIMESTAMP) as DaysSinceLastComment,
        CASE 
            WHEN DATEDIFF(DAY, tu.LastPostDate, CURRENT_TIMESTAMP) < 30 THEN 'Active'
            WHEN DATEDIFF(DAY, tu.LastPostDate, CURRENT_TIMESTAMP) BETWEEN 30 AND 180 THEN 'ModeratelyActive'
            ELSE 'Inactive'
        END as ActivityStatus
    FROM TopUsers tu
    WHERE tu.PostCount > 0
),
TagAnalysis AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalScore,
        ua.PostCount,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AnswerToQuestionRatio,
        ua.ReputationTier,
        ua.ActivityStatus,
        ta.TagName,
        ta.Count as TagCount,
        ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY ta.Count DESC) as TagRank,
        CASE 
            WHEN ta.Count >= 100 THEN 'HotTag'
            WHEN ta.Count >= 50 THEN 'PopularTag'
            WHEN ta.Count >= 10 THEN 'RegularTag'
            ELSE 'NicheTag'
        END as TagPopularity,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.Tags LIKE '%' || ta.TagName || '%') as UserTagPostCount
    FROM UserPostAnalysis ua
    CROSS JOIN LATERAL (
        SELECT t.TagName, t.Count
        FROM Tags t
        WHERE t.TagName IN (
            SELECT TRIM(SUBSTRING(ua.AllTags, 
                POSITION('<' IN ua.AllTags) + 1, 
                POSITION('>' IN ua.AllTags, POSITION('<' IN ua.AllTags)) - POSITION('<' IN ua.AllTags) - 1
            )) as Tag
            FROM (VALUES ('<c++>'), ('<python>'), ('<javascript>')) AS v(Tag)
            WHERE ua.AllTags LIKE '%' || v.Tag || '%'
        )
        ORDER BY t.Count DESC
        LIMIT 10
    ) ta
)
SELECT 
    ta.UserId,
    ta.DisplayName,
    ta.Reputation,
    ta.TotalScore,
    ta.PostCount,
    ta.QuestionCount,
    ta.AnswerCount,
    ta.AnswerToQuestionRatio,
    ta.ReputationTier,
    ta.ActivityStatus,
    ta.TagName,
    ta.TagCount,
    ta.TagRank,
    ta.TagPopularity,
    ta.UserTagPostCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ta.UserId AND p.CreationDate >= DATEADD(MONTH, -6, CURRENT_TIMESTAMP)) as RecentPosts,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = ta.UserId AND p.CreationDate >= DATEADD(MONTH, -6, CURRENT_TIMESTAMP)) as AvgRecentScore,
    (SELECT COUNT(DISTINCT p.Id) FROM Posts p 
     JOIN Votes v ON p.Id = v.PostId 
     WHERE p.OwnerUserId = ta.UserId 
     AND v.VoteTypeId IN (2, 3) 
     AND v.CreationDate >= DATEADD(MONTH, -6, CURRENT_TIMESTAMP)) as RecentVotes,
    CASE 
        WHEN ta.ReputationTier = 'Elite' AND ta.ActivityStatus = 'Active' THEN 'TopPerformer'
        WHEN ta.ReputationTier IN ('Advanced', 'Intermediate') AND ta.AnswerToQuestionRatio > 20 THEN 'ActiveContributor'
        ELSE 'RegularUser'
    END as UserCategory,
    CASE 
        WHEN ta.TagCount > 100 AND ta.AnswerToQuestionRatio > 50 THEN 'HighImpactExpert'
        WHEN ta.TagCount > 50 AND ta.AnswerToQuestionRatio > 30 THEN 'SubjectExpert'
        ELSE 'Generalist'
    END as ExpertiseLevel,
    ROW_NUMBER() OVER (ORDER BY ta.TotalScore DESC, ta.Reputation DESC) as OverallRank,
    CONCAT(
        'UserID: ', ta.UserId,
        ', Display: ', ta.DisplayName,
        ', Reputation: ', ta.Reputation,
        ', Score: ', ta.TotalScore,
        ', Tag: ', ta.TagName,
        ', Popularity: ', ta.TagPopularity,
        ', Category: ', CASE 
            WHEN ta.ReputationTier = 'Elite' AND ta.ActivityStatus = 'Active' THEN 'TopPerformer'
            WHEN ta.ReputationTier IN ('Advanced', 'Intermediate') AND ta.AnswerToQuestionRatio > 20 THEN 'ActiveContributor'
            ELSE 'RegularUser'
        END
    ) as FullProfile
FROM TagAnalysis ta
WHERE ta.TagRank <= 5
    AND ta.Reputation > 1000
    AND (ta.ReputationTier IN ('Elite', 'Advanced') OR ta.ActivityStatus = 'Active')
    AND ta.UserTagPostCount > 0
    AND EXISTS (
        SELECT 1 FROM Posts p 
        JOIN PostHistory ph ON p.Id = ph.PostId 
        WHERE p.OwnerUserId = ta.UserId 
        AND ph.PostHistoryTypeId IN (1, 2, 3) 
        AND ph.CreationDate >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)
    )
    AND ta.UserTagPostCount >= (SELECT AVG(UserTagPostCount) FROM TagAnalysis ta2 WHERE ta2.UserId = ta.UserId)
    AND EXISTS (
        SELECT 1 FROM Badges b 
        WHERE b.UserId = ta.UserId 
        AND b.Name LIKE '%Favorite%'
        AND b.Date >= DATEADD(MONTH, -12, CURRENT_TIMESTAMP)
    )
ORDER BY ta.TotalScore DESC, ta.TagCount DESC, ta.UserId;
```
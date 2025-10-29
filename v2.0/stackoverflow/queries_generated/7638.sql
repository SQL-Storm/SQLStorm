-- {"query": "7638.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1885} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT p.PostTypeId::TEXT, ',') as PostTypes,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) as WikiCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        TotalScore,
        LastPostDate,
        PostTypes,
        QuestionCount,
        AnswerCount,
        WikiCount,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as RepRank
    FROM UserStats
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'), 0) as TaggedPosts,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as AvgScore,
        (SELECT COUNT(DISTINCT AuthorId) FROM (
            SELECT DISTINCT OwnerUserId as AuthorId FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'
        ) a) as DistinctAuthors,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1) as QuestionCount
    FROM Tags t
    WHERE t.Count > 100
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ParentId,
        p.AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Question with answers'
            WHEN p.PostTypeId = 1 THEN 'Question no answers'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            ELSE 'Other'
        END as PostCategory,
        CASE 
            WHEN p.Score > 100 THEN 'Highly_Voted'
            WHEN p.Score > 50 THEN 'Moderately_Voted'
            WHEN p.Score > 0 THEN 'Slightly_Voted'
            ELSE 'Non_Positive'
        END as ScoreCategory,
        EXTRACT(YEAR FROM p.CreationDate) as YearCreated,
        EXTRACT(MONTH FROM p.CreationDate) as MonthCreated,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (SELECT COUNT(*) FROM unnest(string_to_array(trim(p.Tags, '<>'), '><')) as tag 
                 WHERE tag = ANY(SELECT TagName FROM Tags WHERE Count > 1000))
            ELSE 0
        END as PopularTagCount
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'::timestamp
      AND p.CreationDate < '2023-01-01'::timestamp
),
UserActivity AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) as DailyPosts,
        AVG(p.Score) as AvgScorePerPost,
        MAX(p.CreationDate) as LastPost,
        STRING_AGG(DISTINCT p.PostTypeId::TEXT, ',') as ActivityTypes
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    GROUP BY p.OwnerUserId
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.CommentCount,
    tu.BadgeCount,
    tu.TotalScore,
    tu.LastPostDate,
    tu.PostTypes,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.WikiCount,
    tu.ScoreRank,
    tu.RepRank,
    ta.TagName,
    ta.TagCount,
    ta.TaggedPosts,
    ta.AvgScore,
    ta.DistinctAuthors,
    ta.QuestionCount,
    pa.Id as PostId,
    pa.Title,
    pa.Body,
    pa.Score,
    pa.ViewCount,
    pa.CreationDate,
    pa.PostCategory,
    pa.ScoreCategory,
    pa.PopularTagCount,
    ua.DailyPosts,
    ua.AvgScorePerPost,
    ua.LastPost,
    ua.ActivityTypes,
    CASE 
        WHEN tu.Reputation > 50000 AND pa.Score > 50 AND pa.PostCategory = 'Question with answers' THEN 'EliteQuestionMaster'
        WHEN tu.Reputation > 25000 AND pa.Score > 25 AND pa.PostCategory = 'Answer' THEN 'ExpertAnswerer'
        WHEN tu.Reputation > 10000 AND ta.TagCount > 500 AND ta.QuestionCount > 5 THEN 'TagExpert'
        ELSE 'RegularUser'
    END as UserCategory,
    ROUND((
        CASE WHEN tu.TotalScore > 0 THEN 1000000000000 / (tu.Reputation + 1) ELSE 0 END +
        CASE WHEN pa.Score > 0 THEN 3000000000000 / (pa.Score + 1) ELSE 0 END +
        CASE WHEN ta.TagCount > 0 THEN 5000000000000 / (ta.TagCount + 1) ELSE 0 END +
        CASE WHEN pa.ViewCount > 0 THEN 7000000000000 / (pa.ViewCount + 1) ELSE 0 END
    ), 2) as ComprehensiveScore,
    COUNT(*) OVER () as TotalResults,
    RANK() OVER (ORDER BY (
        CASE WHEN tu.TotalScore > 0 THEN 1000000000000 / (tu.Reputation + 1) ELSE 0 END +
        CASE WHEN pa.Score > 0 THEN 3000000000000 / (pa.Score + 1) ELSE 0 END +
        CASE WHEN ta.TagCount > 0 THEN 5000000000000 / (ta.TagCount + 1) ELSE 0 END +
        CASE WHEN pa.ViewCount > 0 THEN 7000000000000 / (pa.ViewCount + 1) ELSE 0 END
    ) DESC) as OverallRank
FROM TopUsers tu
LEFT JOIN TagAnalysis ta ON ta.TagCount > (SELECT AVG(TagCount) FROM TagAnalysis)
LEFT JOIN PostAnalysis pa ON pa.OwnerUserId = tu.UserId AND pa.Score > 0
LEFT JOIN UserActivity ua ON ua.OwnerUserId = tu.UserId
WHERE (
    CASE 
        WHEN tu.Reputation > 50000 AND pa.Score > 50 AND pa.PostCategory = 'Question with answers' THEN TRUE
        WHEN tu.Reputation > 25000 AND pa.Score > 25 AND pa.PostCategory = 'Answer' THEN TRUE
        WHEN tu.Reputation > 10000 AND ta.TagCount > 500 AND ta.QuestionCount > 5 THEN TRUE
        WHEN tu.TotalScore > 100000 AND pa.ViewCount > 500 THEN TRUE
        ELSE FALSE
    END
)
AND EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.OwnerUserId = tu.UserId 
    AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '60 days'
)
ORDER BY ComprehensiveScore DESC
LIMIT 1000
OFFSET 0;
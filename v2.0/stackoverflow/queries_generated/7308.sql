-- {"query": "7308.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2143} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        LAG(u.Reputation) OVER (ORDER BY u.CreationDate) as PrevReputation,
        ROW_NUMBER() OVER (PARTITION BY u.AccountId ORDER BY u.CreationDate) as UserRankInAccount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= '2010-01-01'::timestamp
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question' 
            WHEN p.PostTypeId = 2 THEN 'Answer' 
            ELSE 'Other' 
        END as PostType,
        COALESCE(p.Tags, '') as Tags,
        STRING_TO_ARRAY(COALESCE(p.Tags, ''), '><') as TagArray,
        TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')) as TrimmedTags,
        LENGTH(COALESCE(p.Tags, '')) as TagsLength,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Medium Voted'
            WHEN p.Score > 0 THEN 'Low Voted'
            ELSE 'No Votes'
        END as VoteCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 500 THEN 'Moderately Popular'
            WHEN p.ViewCount > 100 THEN 'Less Popular'
            ELSE 'Rarely Viewed'
        END as Popularity,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as PostRank,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        NTILE(4) OVER (ORDER BY p.Score) as ScoreQuartile,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) as PrevScore,
        LAG(p.ViewCount) OVER (ORDER BY p.CreationDate) as PrevViews
    FROM Posts p
    WHERE p.CreationDate >= '2010-01-01'::timestamp
    AND p.ContentLicense = 'CC BY-SA 2.5'
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        QuestionCount,
        AnswerCount,
        BadgeCount,
        CommentCount,
        VoteCount,
        Round(AvgPostScore, 2) as AvgPostScore,
        LastPostDate,
        PrevReputation,
        UserRankInAccount,
        CASE 
            WHEN Reputation > 10000 THEN 'Veteran'
            WHEN Reputation > 5000 THEN 'Experienced'
            WHEN Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as UserLevel,
        CASE 
            WHEN PostCount >= 100 AND QuestionCount >= 20 THEN 'Highly Active'
            WHEN PostCount >= 50 AND QuestionCount >= 10 THEN 'Active'
            WHEN PostCount >= 10 THEN 'Regular'
            ELSE 'Occasional'
        END as ActivityLevel
    FROM UserStats
    WHERE PostCount > 0
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Very Popular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderately Popular'
            ELSE 'Less Popular'
        END as PopularityLevel
    FROM Tags t
    WHERE t.Count > 10
),
ComplexPostAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.PostType,
        pa.Tags,
        pa.TagArray,
        pa.TrimmedTags,
        pa.TagsLength,
        pa.VoteCategory,
        pa.Popularity,
        pa.PostRank,
        pa.ScoreRank,
        pa.ViewRank,
        pa.ScoreQuartile,
        pa.PrevScore,
        pa.PrevViews,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 1
            ELSE 0
        END as AboveAverageScore,
        CASE 
            WHEN pa.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 1
            ELSE 0
        END as AboveAverageViews,
        CASE 
            WHEN pa.AnswerCount > 0 THEN (pa.Score::decimal / NULLIF(pa.AnswerCount, 0))
            ELSE 0
        END as ScorePerAnswer,
        CASE 
            WHEN pa.CommentCount > 0 THEN (pa.Score::decimal / NULLIF(pa.CommentCount, 0))
            ELSE 0
        END as ScorePerComment,
        CASE 
            WHEN pa.AnswerCount > 0 AND pa.CommentCount > 0 THEN ((pa.AnswerCount::decimal / NULLIF(pa.CommentCount, 0)) * (pa.Score::decimal / NULLIF(pa.AnswerCount, 0)))
            ELSE NULL
        END as ImpactFactor,
        DATEDIFF('day', pa.CreationDate, NOW()) as DaysSinceCreation,
        COALESCE(ut.DisplayName, 'Unknown') as OwnerDisplayName,
        ut.Reputation as OwnerReputation,
        ut.PostCount as OwnerPostCount,
        ut.QuestionCount as OwnerQuestionCount,
        ut.AnswerCount as OwnerAnswerCount,
        ut.BadgeCount as OwnerBadgeCount,
        ut.UserLevel as OwnerUserLevel,
        ut.ActivityLevel as OwnerActivityLevel
    FROM PostAnalysis pa
    LEFT JOIN TopUsers ut ON pa.OwnerUserId = ut.UserId
    WHERE pa.Score IS NOT NULL
    AND pa.ViewCount IS NOT NULL
)
SELECT 
    'Overall Statistics' as AnalysisType,
    COUNT(*) as TotalPosts,
    AVG(Score) as AvgScore,
    AVG(ViewCount) as AvgViews,
    MIN(AnswerCount) as MinAnswers,
    MAX(AnswerCount) as MaxAnswers,
    AVG(AnswerCount) as AvgAnswers,
    COUNT(DISTINCT OwnerUserId) as UniqueOwners,
    COUNT(DISTINCT CASE WHEN PostType = 'Question' THEN OwnerUserId END) as UniqueQuestionOwners,
    COUNT(DISTINCT CASE WHEN PostType = 'Answer' THEN OwnerUserId END) as UniqueAnswerOwners,
    '---' as Separator1
FROM ComplexPostAnalysis
UNION ALL
SELECT 
    'PostType Breakdown' as AnalysisType,
    COUNT(*) as TotalPosts,
    AVG(Score) as AvgScore,
    AVG(ViewCount) as AvgViews,
    MIN(AnswerCount) as MinAnswers,
    MAX(AnswerCount) as MaxAnswers,
    AVG(AnswerCount) as AvgAnswers,
    COUNT(DISTINCT OwnerUserId) as UniqueOwners,
    COUNT(DISTINCT CASE WHEN PostType = 'Question' THEN OwnerUserId END) as UniqueQuestionOwners,
    COUNT(DISTINCT CASE WHEN PostType = 'Answer' THEN OwnerUserId END) as UniqueAnswerOwners,
    PostType as Separator1
FROM ComplexPostAnalysis
GROUP BY PostType
UNION ALL
SELECT 
    'VoteCategory Analysis' as AnalysisType,
    COUNT(*) as TotalPosts,
    AVG(Score) as AvgScore,
    AVG(ViewCount) as AvgViews,
    MIN(AnswerCount) as MinAnswers,
    MAX(AnswerCount) as MaxAnswers,
    AVG(AnswerCount) as AvgAnswers,
    COUNT(DISTINCT OwnerUserId) as UniqueOwners,
    COUNT(DISTINCT CASE WHEN PostType = 'Question' THEN OwnerUserId END) as UniqueQuestionOwners,
    COUNT(DISTINCT CASE WHEN PostType = 'Answer' THEN OwnerUserId END) as UniqueAnswerOwners,
    VoteCategory as Separator1
FROM ComplexPostAnalysis
GROUP BY VoteCategory
UNION ALL
SELECT 
    'Popularity Analysis' as AnalysisType,
    COUNT(*) as TotalPosts,
    AVG(Score) as AvgScore,
    AVG(ViewCount) as AvgViews,
    MIN(AnswerCount) as MinAnswers,
    MAX(AnswerCount) as MaxAnswers,
    AVG(AnswerCount) as AvgAnswers,
    COUNT(DISTINCT OwnerUserId) as UniqueOwners,
    COUNT(DISTINCT CASE WHEN PostType = 'Question' THEN OwnerUserId END) as UniqueQuestionOwners,
    COUNT(DISTINCT CASE WHEN PostType = 'Answer' THEN OwnerUserId END) as UniqueAnswerOwners,
    Popularity as Separator1
FROM ComplexPostAnalysis
GROUP BY Popularity
ORDER BY AnalysisType, TotalPosts DESC
LIMIT 1000;
-- {"query": "7748.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2917} 
WITH RankedUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as rn,
        COUNT(p.Id) as PostCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LatestPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ', ') FILTER (WHERE p.Tags IS NOT NULL) as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000 AND u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
UserRankStats AS (
    SELECT 
        *,
        CASE 
            WHEN rn <= 10 THEN 'Top 10'
            WHEN rn <= 100 THEN 'Top 100'
            ELSE 'Other'
        END as RankGroup,
        CASE 
            WHEN TotalScore > 10000 THEN 'High'
            WHEN TotalScore > 1000 THEN 'Medium'
            ELSE 'Low'
        END as ScoreLevel
    FROM RankedUsers
),
PostActivity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.Tags,
        DATEDIFF('day', p.CreationDate, p.LastActivityDate) as DaysActive,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Answer'
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevDate
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= '2022-01-01'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        p.Title as ExcerptTitle,
        p.Body as ExcerptBody,
        COALESCE(p2.ViewCount, 0) as WikiViews,
        CASE 
            WHEN t.IsRequired = 1 THEN 'Required'
            WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only'
            ELSE 'Regular'
        END as TagStatus
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    LEFT JOIN Posts p2 ON t.WikiPostId = p2.Id
    WHERE t.Count > 100
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT v.Id) as TotalVotes,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        AVG(v.CreationDate) as AvgVoteTime,
        MAX(v.CreationDate) as LastVoteDate,
        STRING_AGG(DISTINCT u.Location, ', ') as Locations,
        STRING_AGG(DISTINCT p.Tags, '; ') as TagsUsed
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.LastAccessDate >= '2023-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(*) as TotalUsers,
    COUNT(DISTINCT CASE WHEN ur.ScoreLevel = 'High' THEN ur.Id END) as HighScoreUsers,
    COUNT(DISTINCT CASE WHEN ur.RankGroup = 'Top 10' THEN ur.Id END) as Top10Users,
    COUNT(DISTINCT CASE WHEN pa.PostType = 'Question with Answer' THEN pa.PostId END) as QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN pa.PostType = 'Answer' THEN pa.PostId END) as TotalAnswers,
    COUNT(DISTINCT ta.TagName) as PopularTags,
    COUNT(DISTINCT ue.UserId) as ActiveUsers,
    AVG(CAST(pa.DaysActive AS FLOAT)) as AvgDaysActive,
    MAX(pa.Score) as MaxPostScore,
    MIN(pa.Score) as MinPostScore,
    AVG(pa.Score) as AvgPostScore,
    SUM(CASE WHEN pa.Score > 0 THEN 1 ELSE 0 END) as PositiveScorePosts,
    SUM(CASE WHEN pa.Score < 0 THEN 1 ELSE 0 END) as NegativeScorePosts,
    SUM(CASE WHEN pa.Score = 0 THEN 1 ELSE 0 END) as ZeroScorePosts,
    COUNT(DISTINCT CASE WHEN pa.Score > 1000 THEN pa.PostId END) as HighScorePosts,
    COUNT(*) as CombinedCount,
    STRING_AGG(DISTINCT ur.DisplayName, ', ') as TopUserNames,
    STRING_AGG(DISTINCT pa.Title, ' | ') as PostTitles,
    STRING_AGG(DISTINCT ta.TagName, ', ') as TagList,
    STRING_AGG(DISTINCT ue.TagsUsed, ' | ') as AllTagsUsed,
    CASE 
        WHEN COUNT(*) > 1000 THEN 'Large Dataset'
        WHEN COUNT(*) > 100 THEN 'Medium Dataset'
        ELSE 'Small Dataset'
    END as DatasetSize,
    CASE 
        WHEN AVG(CAST(pa.DaysActive AS FLOAT)) > 365 THEN 'High Activity'
        WHEN AVG(CAST(pa.DaysActive AS FLOAT)) > 180 THEN 'Medium Activity'
        ELSE 'Low Activity'
    END as ActivityLevel,
    'Generated on ' || CURRENT_TIMESTAMP as GeneratedAt,
    (SELECT COUNT(*) FROM Posts p WHERE p.Score > 1000) as HighScorePostsCount,
    (SELECT COUNT(*) FROM Users u WHERE u.Reputation > 10000) as EliteUserCount,
    (SELECT COUNT(*) FROM Tags t WHERE t.Count > 1000) as VeryPopularTagsCount
FROM UserRankStats ur
FULL OUTER JOIN PostActivity pa ON ur.Id = pa.OwnerUserId
FULL OUTER JOIN TagAnalysis ta ON 1=1
FULL OUTER JOIN UserEngagement ue ON ur.Id = ue.UserId
WHERE 
    (ur.Id IS NOT NULL OR pa.PostId IS NOT NULL OR ta.TagName IS NOT NULL OR ue.UserId IS NOT NULL)
    AND (
        ur.Id IS NOT NULL 
        OR (pa.PostId IS NOT NULL AND pa.PostType IN ('Question', 'Answer'))
        OR (ta.TagName IS NOT NULL AND ta.Count > 100)
        OR (ue.UserId IS NOT NULL AND ue.TotalPosts > 0)
    )
    AND (ur.Reputation >= 100 OR pa.Score >= 0 OR ta.Count >= 100 OR ue.TotalPosts >= 1)
GROUP BY 
    CASE WHEN COUNT(*) > 1000 THEN 'Large Dataset' WHEN COUNT(*) > 100 THEN 'Medium Dataset' ELSE 'Small Dataset' END,
    CASE WHEN AVG(CAST(pa.DaysActive AS FLOAT)) > 365 THEN 'High Activity' WHEN AVG(CAST(pa.DaysActive AS FLOAT)) > 180 THEN 'Medium Activity' ELSE 'Low Activity' END
HAVING 
    COUNT(*) > 0
    AND (
        (COUNT(DISTINCT CASE WHEN ur.Id IS NOT NULL THEN ur.Id END) > 0 OR 
         COUNT(DISTINCT CASE WHEN pa.PostId IS NOT NULL THEN pa.PostId END) > 0 OR
         COUNT(DISTINCT CASE WHEN ta.TagName IS NOT NULL THEN ta.TagName END) > 0 OR
         COUNT(DISTINCT CASE WHEN ue.UserId IS NOT NULL THEN ue.UserId END) > 0)
    )
ORDER BY TotalUsers DESC, AvgPostScore DESC
LIMIT 1000 OFFSET 0
;

-- Query to ensure proper handling of edge cases and NULL values
UNION
SELECT 
    'Edge Case Analysis' as ReportTitle,
    CASE WHEN COUNT(*) = 0 THEN 0 ELSE COUNT(*) END as TotalUsers,
    CASE WHEN COUNT(DISTINCT CASE WHEN ur.Id IS NOT NULL THEN ur.Id END) = 0 THEN 0 ELSE COUNT(DISTINCT CASE WHEN ur.Id IS NOT NULL THEN ur.Id END) END as HighScoreUsers,
    CASE WHEN COUNT(DISTINCT CASE WHEN pa.PostId IS NOT NULL THEN pa.PostId END) = 0 THEN 0 ELSE COUNT(DISTINCT CASE WHEN pa.PostId IS NOT NULL THEN pa.PostId END) END as QuestionsWithAnswers,
    CASE WHEN SUM(CASE WHEN pa.Score > 0 THEN 1 ELSE 0 END) IS NULL THEN 0 ELSE SUM(CASE WHEN pa.Score > 0 THEN 1 ELSE 0 END) END as PositiveScorePosts,
    CASE WHEN AVG(CAST(pa.DaysActive AS FLOAT)) IS NULL THEN 0 ELSE AVG(CAST(pa.DaysActive AS FLOAT)) END as AvgDaysActive,
    CASE WHEN MIN(pa.Score) IS NULL THEN 0 ELSE MIN(pa.Score) END as MinPostScore,
    CASE WHEN MAX(pa.Score) IS NULL THEN 0 ELSE MAX(pa.Score) END as MaxPostScore,
    CASE WHEN COUNT(DISTINCT ta.TagName) IS NULL THEN 0 ELSE COUNT(DISTINCT ta.TagName) END as PopularTags,
    CASE WHEN COUNT(DISTINCT ue.UserId) IS NULL THEN 0 ELSE COUNT(DISTINCT ue.UserId) END as ActiveUsers,
    CASE WHEN COUNT(*) IS NULL THEN 0 ELSE COUNT(*) END as CombinedCount,
    CASE WHEN STRING_AGG(DISTINCT ur.DisplayName, ', ') IS NULL THEN 'N/A' ELSE STRING_AGG(DISTINCT ur.DisplayName, ', ') END as TopUserNames,
    CASE WHEN STRING_AGG(DISTINCT pa.Title, ' | ') IS NULL THEN 'N/A' ELSE STRING_AGG(DISTINCT pa.Title, ' | ') END as PostTitles,
    CASE WHEN STRING_AGG(DISTINCT ta.TagName, ', ') IS NULL THEN 'N/A' ELSE STRING_AGG(DISTINCT ta.TagName, ', ') END as TagList,
    CASE WHEN STRING_AGG(DISTINCT ue.TagsUsed, ' | ') IS NULL THEN 'N/A' ELSE STRING_AGG(DISTINCT ue.TagsUsed, ' | ') END as AllTagsUsed,
    CASE WHEN COUNT(*) IS NULL THEN 'Unknown' ELSE 
        CASE WHEN COUNT(*) > 1000 THEN 'Large Dataset' WHEN COUNT(*) > 100 THEN 'Medium Dataset' ELSE 'Small Dataset' END 
    END as DatasetSize,
    CASE WHEN AVG(CAST(pa.DaysActive AS FLOAT)) IS NULL THEN 'Unknown' ELSE 
        CASE WHEN AVG(CAST(pa.DaysActive AS FLOAT)) > 365 THEN 'High Activity' WHEN AVG(CAST(pa.DaysActive AS FLOAT)) > 180 THEN 'Medium Activity' ELSE 'Low Activity' END 
    END as ActivityLevel,
    'Generated on ' || CASE WHEN CURRENT_TIMESTAMP IS NULL THEN '1900-01-01' ELSE CURRENT_TIMESTAMP END as GeneratedAt,
    CASE WHEN (SELECT COUNT(*) FROM Posts p WHERE p.Score > 1000) IS NULL THEN 0 ELSE (SELECT COUNT(*) FROM Posts p WHERE p.Score > 1000) END as HighScorePostsCount,
    CASE WHEN (SELECT COUNT(*) FROM Users u WHERE u.Reputation > 10000) IS NULL THEN 0 ELSE (SELECT COUNT(*) FROM Users u WHERE u.Reputation > 10000) END as EliteUserCount,
    CASE WHEN (SELECT COUNT(*) FROM Tags t WHERE t.Count > 1000) IS NULL THEN 0 ELSE (SELECT COUNT(*) FROM Tags t WHERE t.Count > 1000) END as VeryPopularTagsCount
FROM UserRankStats ur
RIGHT JOIN PostActivity pa ON ur.Id = pa.OwnerUserId
RIGHT JOIN TagAnalysis ta ON 1=1
RIGHT JOIN UserEngagement ue ON ur.Id = ue.UserId
WHERE 
    (ur.Id IS NOT NULL OR pa.PostId IS NOT NULL OR ta.TagName IS NOT NULL OR ue.UserId IS NOT NULL)
    AND (
        ur.Id IS NOT NULL 
        OR (pa.PostId IS NOT NULL AND pa.PostType IN ('Question', 'Answer'))
        OR (ta.TagName IS NOT NULL AND ta.Count > 100)
        OR (ue.UserId IS NOT NULL AND ue.TotalPosts > 0)
    )
    AND (ur.Reputation >= 100 OR pa.Score >= 0 OR ta.Count >= 100 OR ue.TotalPosts >= 1)
ORDER BY CASE WHEN COUNT(*) IS NULL THEN 0 ELSE COUNT(*) END DESC
LIMIT 1;
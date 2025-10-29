-- {"query": "7751.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1794} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CAST(p.Score AS FLOAT)) AS AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') AS AllTags,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank
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
        Views,
        UpVotes,
        DownVotes,
        PostCount,
        CommentCount,
        BadgeCount,
        LastPostDate,
        LastCommentDate,
        QuestionCount,
        AnswerCount,
        AvgPostScore,
        AllTags,
        ReputationRank,
        PostRank,
        CASE 
            WHEN PostCount > 100 THEN 'Elite'
            WHEN PostCount > 50 THEN 'Veteran'
            WHEN PostCount > 10 THEN 'Regular'
            ELSE 'Newbie'
        END AS UserCategory
    FROM UserActivityStats
    WHERE PostCount > 0
),
PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score > 100 THEN 'Hot'
            WHEN p.Score > 50 THEN 'Popular'
            WHEN p.Score > 0 THEN 'Average'
            WHEN p.Score < 0 THEN 'Controversial'
            ELSE 'Neutral'
        END AS Popularity,
        DATEDIFF('DAY', p.CreationDate, CURRENT_TIMESTAMP) AS AgeInDays,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.ViewCount, 0) AS ViewCount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
TagAnalysis AS (
    SELECT 
        ta.TagName,
        ta.Count AS TagCount,
        ta.ExcerptPostId,
        ta.WikiPostId,
        CASE 
            WHEN ta.Count > 1000 THEN 'Trending'
            WHEN ta.Count > 100 THEN 'Popular'
            WHEN ta.Count > 10 THEN 'Moderate'
            ELSE 'Niche'
        END AS TagPopularity,
        COUNT(DISTINCT p.Id) AS PostsUsingTag,
        STRING_AGG(DISTINCT p.Title, '; ') AS SampleQuestions
    FROM Tags ta
    LEFT JOIN Posts p ON p.Tags LIKE '%' || ta.TagName || '%'
    WHERE ta.TagName IS NOT NULL AND ta.TagName != ''
    GROUP BY ta.TagName, ta.Count, ta.ExcerptPostId, ta.WikiPostId
),
ComplexVoting AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        vt.Name AS VoteTypeName,
        v.CreationDate,
        p.Title AS PostTitle,
        COALESCE(u.DisplayName, 'Anonymous') AS VoterName,
        CASE 
            WHEN v.VoteTypeId IN (2, 3) THEN 
                CASE WHEN v.VoteTypeId = 2 THEN 'Upvote' ELSE 'Downvote' END
            WHEN v.VoteTypeId IN (1, 4) THEN 
                CASE WHEN v.VoteTypeId = 1 THEN 'Accepted' ELSE 'Offensive' END
            ELSE 'Other'
        END AS VoteCategory,
        DENSE_RANK() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) AS VoteSequence,
        ROW_NUMBER() OVER (ORDER BY v.CreationDate DESC) AS GlobalVoteOrder
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Posts p ON v.PostId = p.Id
    LEFT JOIN Users u ON v.UserId = u.Id
    WHERE v.VoteTypeId BETWEEN 1 AND 10
),
AggregateResults AS (
    SELECT 
        'User Statistics' AS AnalysisType,
        COUNT(*) AS TotalRecords,
        COUNT(DISTINCT UserId) AS DistinctUsers,
        COUNT(DISTINCT PostId) AS DistinctPosts,
        NULL AS AdditionalInfo
    FROM (
        SELECT u.Id AS UserId, p.Id AS PostId
        FROM Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    ) combined
        
    UNION ALL
    
    SELECT 
        'Tag Analysis' AS AnalysisType,
        COUNT(*) AS TotalRecords,
        COUNT(DISTINCT TagName) AS DistinctTags,
        NULL AS DistinctPosts,
        NULL AS AdditionalInfo
    FROM TagAnalysis
    
    UNION ALL
    
    SELECT 
        'Voting Patterns' AS AnalysisType,
        COUNT(*) AS TotalRecords,
        COUNT(DISTINCT PostId) AS DistinctPosts,
        COUNT(DISTINCT UserId) AS DistinctVoters,
        NULL AS AdditionalInfo
    FROM ComplexVoting
    
    UNION ALL
    
    SELECT 
        'Post Distribution' AS AnalysisType,
        COUNT(*) AS TotalRecords,
        COUNT(DISTINCT OwnerUserId) AS DistinctOwners,
        NULL AS DistinctPosts,
        NULL AS AdditionalInfo
    FROM PostMetrics
)
SELECT 
    'FINAL_COMBINED_REPORT' AS ReportType,
    COUNT(*) AS TotalRecords,
    MAX(CASE WHEN AnalysisType = 'User Statistics' THEN TotalRecords END) AS UserStatsCount,
    MAX(CASE WHEN AnalysisType = 'Tag Analysis' THEN TotalRecords END) AS TagAnalysisCount,
    MAX(CASE WHEN AnalysisType = 'Voting Patterns' THEN TotalRecords END) AS VotingPatternCount,
    MAX(CASE WHEN AnalysisType = 'Post Distribution' THEN TotalRecords END) AS PostDistCount,
    SUM(CASE WHEN AnalysisType = 'User Statistics' THEN TotalRecords ELSE 0 END) AS UserStatsSum,
    SUM(CASE WHEN AnalysisType = 'Tag Analysis' THEN TotalRecords ELSE 0 END) AS TagAnalysisSum,
    ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS RankByVolume,
    CONCAT_WS(', ',
        COALESCE(CAST(MAX(CASE WHEN AnalysisType = 'User Statistics' THEN TotalRecords END) AS VARCHAR), '0'),
        COALESCE(CAST(MAX(CASE WHEN AnalysisType = 'Tag Analysis' THEN TotalRecords END) AS VARCHAR), '0'),
        COALESCE(CAST(MAX(CASE WHEN AnalysisType = 'Voting Patterns' THEN TotalRecords END) AS VARCHAR), '0'),
        COALESCE(CAST(MAX(CASE WHEN AnalysisType = 'Post Distribution' THEN TotalRecords END) AS VARCHAR), '0')
    ) AS SummaryTotals,
    STRING_AGG(AnalysisType, ' | ') WITHIN GROUP (ORDER BY AnalysisType) AS AnalysisMethods,
    CURRENT_TIMESTAMP AS ReportGeneratedAt,
    CAST(NULL AS VARCHAR) AS PlaceholderColumn
FROM AggregateResults
WHERE AnalysisType IS NOT NULL
GROUP BY ReportGeneratedAt
HAVING COUNT(*) > 0
ORDER BY TotalRecords DESC
LIMIT 100;
-- {"query": "7249.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2095} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(SUM(COALESCE(p.Score, 0)) AS FLOAT) / NULLIF(COUNT(DISTINCT p.Id), 0)
            ELSE 0 
        END as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as TagList,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByReputation,
        DENSE_RANK() OVER (ORDER BY AvgPostScore DESC) as RankByAvgScore,
        NTILE(10) OVER (ORDER BY Reputation DESC) as Decile
    FROM UserActivityStats
),
QuestionAnalysis AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Yes'
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.Score < 0 THEN 'Negative Score'
            ELSE 'Active'
        END as QuestionStatus,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as QuestionSequence
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
    AND p.CreationDate >= '2015-01-01'
),
AnswerQuality AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        CASE 
            WHEN a.Score > 10 THEN 'High Quality'
            WHEN a.Score > 0 THEN 'Medium Quality'
            WHEN a.Score = 0 THEN 'Neutral'
            ELSE 'Low Quality'
        END as QualityLevel,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as RankInQuestion
    FROM Posts a
    WHERE a.PostTypeId = 2
    AND a.CreationDate >= '2015-01-01'
),
UserVotingPatterns AS (
    SELECT 
        v.UserId,
        COUNT(DISTINCT v.PostId) as VotesCast,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) as FavoriteVotes,
        (SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) * 1.0 / NULLIF(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0)) as UpDownRatio,
        MIN(v.CreationDate) as FirstVoteDate,
        MAX(v.CreationDate) as LastVoteDate
    FROM Votes v
    WHERE v.CreationDate >= '2015-01-01'
    GROUP BY v.UserId
),
UserEngagement AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.PostCount,
        ru.CommentCount,
        ru.BadgeCount,
        ru.AvgPostScore,
        ru.QuestionCount,
        ru.AnswerCount,
        COALESCE(uvp.VotesCast, 0) as TotalVotesCast,
        COALESCE(uvp.UpVotes, 0) as TotalUpVotes,
        COALESCE(uvp.DownVotes, 0) as TotalDownVotes,
        COALESCE(uvp.UpDownRatio, 0) as UpDownRatio,
        CASE 
            WHEN ru.PostCount > 100 THEN 'High Engagement'
            WHEN ru.PostCount > 25 THEN 'Medium Engagement'
            WHEN ru.PostCount > 0 THEN 'Low Engagement'
            ELSE 'Inactive'
        END as EngagementLevel
    FROM RankedUsers ru
    LEFT JOIN UserVotingPatterns uvp ON ru.UserId = uvp.UserId
    WHERE ru.PostCount > 0
)
SELECT 
    CONCAT(
        'User: ', ue.DisplayName, 
        ' | Rank: ', ue.RankByReputation,
        ' | Reputation: ', ue.Reputation,
        ' | Posts: ', ue.PostCount,
        ' | Avg Score: ', ROUND(ue.AvgPostScore, 2),
        ' | Engagement: ', ue.EngagementLevel,
        ' | Tags: ', 
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN qa.QuestionId IS NOT NULL THEN qa.QuestionId END) > 0 
            THEN 'Questions with answers' 
            ELSE 'No questions' 
        END
    ) as UserProfileSummary,
    
    COUNT(DISTINCT CASE WHEN qa.QuestionId IS NOT NULL THEN qa.QuestionId END) as QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN aa.AnswerId IS NOT NULL THEN aa.AnswerId END) as AnswersWithScores,
    
    STRING_AGG(
        CASE 
            WHEN qa.QuestionId IS NOT NULL THEN CONCAT(qa.QuestionId, ':', qa.Title)
            ELSE NULL 
        END, '|'
    ) as QuestionTitles,
    
    STRING_AGG(
        CASE 
            WHEN aa.AnswerId IS NOT NULL THEN CONCAT(aa.AnswerId, ':', aa.Score)
            ELSE NULL 
        END, '|'
    ) as AnswerScores,
    
    MAX(ue.TotalVotesCast) as MaxVotesCast,
    MIN(ue.TotalUpVotes) as MinUpVotes,
    AVG(ue.TotalDownVotes) as AvgDownVotes,
    
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.OwnerUserId = ue.UserId 
        AND p.PostTypeId = 1
        AND p.CreationDate >= '2020-01-01'
    ) as RecentQuestions,
    
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Posts p 
            JOIN PostHistory ph ON p.Id = ph.PostId 
            WHERE p.OwnerUserId = ue.UserId 
            AND ph.PostHistoryTypeId = 10 
            AND ph.CreationDate >= '2020-01-01'
        ) THEN 'Has Closed Posts'
        ELSE 'No Closed Posts'
    END as CloseHistory,
    
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Badges b 
            WHERE b.UserId = ue.UserId 
            AND b.Date >= '2020-01-01'
        ) THEN 'Recent Badges'
        ELSE 'No Recent Badges'
    END as BadgeStatus,
    
    CASE 
        WHEN 
            (SELECT COUNT(DISTINCT p.Id) FROM Posts p WHERE p.OwnerUserId = ue.UserId AND p.PostTypeId = 1) > 50
            AND (SELECT COUNT(DISTINCT c.Id) FROM Comments c WHERE c.UserId = ue.UserId) < 100
        THEN 'Potential Spam User'
        ELSE 'Normal User'
    END as UserClassification,
    
    IIF(
        (ue.PostCount + ue.CommentCount + ue.BadgeCount) > 1000
        AND ue.Reputation > 10000,
        'High Achiever',
        'Other'
    ) as AchievementLevel
    
FROM UserEngagement ue
LEFT JOIN QuestionAnalysis qa ON ue.UserId = qa.OwnerUserId
LEFT JOIN AnswerQuality aa ON ue.UserId = aa.OwnerUserId
WHERE ue.Reputation > 1000
GROUP BY 
    ue.UserId, 
    ue.DisplayName, 
    ue.Reputation, 
    ue.PostCount, 
    ue.CommentCount, 
    ue.BadgeCount, 
    ue.AvgPostScore, 
    ue.QuestionCount, 
    ue.AnswerCount, 
    ue.TotalVotesCast, 
    ue.TotalUpVotes, 
    ue.TotalDownVotes,
    ue.UpDownRatio,
    ue.EngagementLevel
HAVING 
    COUNT(DISTINCT CASE WHEN qa.QuestionId IS NOT NULL THEN qa.QuestionId END) > 0
    AND COUNT(DISTINCT CASE WHEN aa.AnswerId IS NOT NULL THEN aa.AnswerId END) > 0
    AND MIN(ue.TotalVotesCast) > 0
    AND MAX(ue.TotalUpVotes) > 0
ORDER BY 
    ue.Reputation DESC,
    ue.PostCount DESC,
    ue.AvgPostScore DESC
LIMIT 1000;
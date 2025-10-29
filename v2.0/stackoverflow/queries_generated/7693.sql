-- {"query": "7693.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1582} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.Body,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) + COALESCE(p.FavoriteCount, 0)
            WHEN p.PostTypeId = 2 THEN 
                COALESCE(p.Score, 0) + COALESCE(p.CommentCount, 0) 
            ELSE 0 
        END AS ActivityScore,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END AS QuestionStatus,
        CASE 
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN (
                SELECT TOP 1 q.Title 
                FROM Posts q 
                WHERE q.Id = p.ParentId 
                AND q.PostTypeId = 1
            )
            ELSE NULL
        END AS ParentQuestionTitle
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
    AND p.CreationDate >= '2018-01-01' 
    AND p.CreationDate < '2023-01-01'
),
UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS UserTier,
        (u.UpVotes - u.DownVotes) AS NetVotes,
        ROW_NUMBER() OVER (PARTITION BY u.AccountId ORDER BY u.Reputation DESC) AS AccountRank
    FROM Users u
    WHERE u.Reputation > 0 
    AND u.DisplayName IS NOT NULL
),
QuestionTagAnalysis AS (
    SELECT 
        ps.Id,
        ps.Title,
        ps.Tags,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        STRING_SPLIT(ps.Tags, '>') AS TagSplit,
        CASE 
            WHEN ps.Tags LIKE '%<java>%' THEN 1
            WHEN ps.Tags LIKE '%<python>%' THEN 1
            WHEN ps.Tags LIKE '%<javascript>%' THEN 1
            ELSE 0
        END AS HasPopularTag,
        DENSE_RANK() OVER (ORDER BY ps.Score DESC) AS ScoreRank,
        AVG(ps.Score) OVER (PARTITION BY ps.OwnerUserId) AS AvgUserScore
    FROM PostStats ps
    WHERE ps.PostTypeId = 1
),
UserPostActivity AS (
    SELECT 
        um.Id,
        um.DisplayName,
        um.Reputation,
        um.UserTier,
        COUNT(ps.Id) AS TotalPosts,
        SUM(ps.Score) AS TotalScore,
        AVG(ps.Score) AS AvgPostScore,
        MAX(ps.CreationDate) AS LastPostDate,
        STRING_AGG(ps.Title, '; ') WITHIN GROUP (ORDER BY ps.CreationDate) AS PostTitles,
        STRING_AGG(CAST(ps.Score AS VARCHAR(10)), ', ') WITHIN GROUP (ORDER BY ps.CreationDate) AS PostScores
    FROM UserMetrics um
    LEFT JOIN PostStats ps ON um.Id = ps.OwnerUserId
    WHERE ps.CreationDate >= '2020-01-01'
    GROUP BY um.Id, um.DisplayName, um.Reputation, um.UserTier
)
SELECT 
    TOP 100 
    upa.Id,
    upa.DisplayName,
    upa.Reputation,
    upa.UserTier,
    upa.TotalPosts,
    upa.TotalScore,
    upa.AvgPostScore,
    upa.LastPostDate,
    upa.PostTitles,
    upa.PostScores,
    COALESCE(ROUND(AVG(qta.Score) OVER (PARTITION BY upa.Id), 2), 0) AS AvgQuestionScore,
    COALESCE(ROUND(MAX(qta.Score) OVER (PARTITION BY upa.Id), 2), 0) AS MaxQuestionScore,
    COALESCE(ROUND(MIN(qta.Score) OVER (PARTITION BY upa.Id), 2), 0) AS MinQuestionScore,
    SUM(CASE WHEN qta.HasPopularTag = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY upa.Id) AS PopularTagQuestions,
    DENSE_RANK() OVER (ORDER BY upa.TotalScore DESC) AS ScoreRank,
    PERCENT_RANK() OVER (ORDER BY upa.TotalScore DESC) AS ScorePercentile,
    CASE 
        WHEN upa.TotalPosts > 0 AND upa.AvgPostScore > (SELECT AVG(AvgPostScore) FROM UserPostActivity) 
        THEN 'Above Average'
        ELSE 'Below Average'
    END AS PerformanceStatus,
    CASE 
        WHEN upa.Reputation >= 10000 AND upa.TotalPosts >= 10 THEN 'Expert'
        WHEN upa.Reputation >= 1000 AND upa.TotalPosts >= 5 THEN 'Experienced'
        WHEN upa.Reputation >= 100 AND upa.TotalPosts >= 2 THEN 'Competent'
        ELSE 'Novice'
    END AS ExpertiseLevel,
    IIF(upa.TotalPosts > 0, 
        'User has posted ' + CAST(upa.TotalPosts AS VARCHAR(10)) + ' times with average score of ' + 
        CAST(upa.AvgPostScore AS VARCHAR(10)) + ' and total score of ' + 
        CAST(upa.TotalScore AS VARCHAR(10)), 
        'No posts available') AS Summary,
    -- Complex window function calculation
    AVG(upa.AvgPostScore) OVER (
        ORDER BY upa.Reputation 
        ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING
    ) AS LocalAvgScore,
    -- Set operator usage with union
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = upa.Id AND PostTypeId = 1) AS QuestionCount,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = upa.Id AND PostTypeId = 2) AS AnswerCount,
    -- Correlated subquery with complex logic
    (SELECT TOP 1 COALESCE(AVG(ps.Score), 0) 
     FROM Posts ps 
     WHERE ps.OwnerUserId = upa.Id 
     AND ps.PostTypeId = 1 
     AND ps.CreationDate >= DATEADD(YEAR, -1, GETDATE())
    ) AS RecentAvgQuestionScore
FROM UserPostActivity upa
WHERE upa.TotalPosts >= 1
AND upa.Reputation > 100
ORDER BY upa.TotalScore DESC, upa.Reputation DESC
OFFSET 0 ROWS
FETCH NEXT 100 ROWS ONLY;
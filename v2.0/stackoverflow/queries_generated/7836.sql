-- {"query": "7836.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2075} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        COALESCE(AVG(p.ViewCount), 0) AS AvgViewCount,
        COUNT(DISTINCT b.Id) AS BadgesCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        COUNT(DISTINCT v.Id) AS VotesCount,
        STRING_AGG(DISTINCT p.Tags, '; ') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY QuestionScore DESC, AnswerScore DESC) AS RankByScore,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) AS RankByReputation,
        PERCENT_RANK() OVER (ORDER BY TotalPosts DESC) AS PostsPercentile
    FROM UserPostStats
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        COALESCE(p.Tags, '') AS Tags,
        STRING_AGG(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN u2.DisplayName END, '; ') AS Upvoters,
        STRING_AGG(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN u2.DisplayName END, '; ') AS Downvoters,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 1 THEN v.Id END) AS AcceptVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Users u2 ON v.UserId = u2.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.CreationDate, p.OwnerUserId, u.DisplayName, p.Tags
),
TopQuestions AS (
    SELECT 
        *,
        CASE 
            WHEN SCORE > 100 THEN 'Highly Voted'
            WHEN SCORE > 50 THEN 'Moderately Voted'
            ELSE 'Low Voted'
        END AS VoteCategory,
        CASE WHEN AnswerCount > 1 THEN 'Has Answers' ELSE 'No Answers' END AS HasAnswers,
        ROW_NUMBER() OVER (ORDER BY Score DESC, AnswerCount DESC) AS RankByVotes
    FROM QuestionStats
    WHERE Score > 0 AND CreationDate >= '2020-01-01'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END AS TagType,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'),
            0
        ) AS QuestionsWithTag,
        COALESCE(
            (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'),
            0
        ) AS AvgScoreForTag
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
CombinedAnalysis AS (
    SELECT 
        'User Analysis' AS AnalysisType,
        CAST(NULL AS VARCHAR) AS MetricName,
        CAST(COUNT(*) AS VARCHAR) AS MetricValue,
        CAST(NULL AS VARCHAR) AS Description
    FROM RankedUsers
    UNION ALL
    SELECT 
        'Question Analysis' AS AnalysisType,
        CAST(NULL AS VARCHAR) AS MetricName,
        CAST(COUNT(*) AS VARCHAR) AS MetricValue,
        CAST(NULL AS VARCHAR) AS Description
    FROM TopQuestions
    UNION ALL
    SELECT 
        'Tag Analysis' AS AnalysisType,
        CAST(NULL AS VARCHAR) AS MetricName,
        CAST(COUNT(*) AS VARCHAR) AS MetricValue,
        CAST(NULL AS VARCHAR) AS Description
    FROM TagAnalysis
    UNION ALL
    SELECT 
        'Post Types' AS AnalysisType,
        pt.Name AS MetricName,
        CAST(COUNT(*) AS VARCHAR) AS MetricValue,
        CAST(NULL AS VARCHAR) AS Description
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    GROUP BY pt.Name
),
ComplexMetrics AS (
    SELECT 
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.TotalPosts,
        r.Questions,
        r.Answers,
        r.QuestionScore,
        r.AnswerScore,
        r.LastPostDate,
        CASE 
            WHEN r.Questions > 0 AND r.Answers > 0 THEN 
                (CAST(r.AnswerScore AS FLOAT) / NULLIF(r.QuestionScore, 0)) * 100
            ELSE 0 
        END AS AnswerQualityRatio,
        CASE 
            WHEN r.QuestionScore > 0 THEN 
                (CAST(r.Answers AS FLOAT) / NULLIF(r.QuestionScore, 0)) * 100
            ELSE 0 
        END AS AnswerPerQuestionRatio,
        CASE 
            WHEN r.BadgesCount > 0 THEN 
                CASE 
                    WHEN r.BadgesCount >= 50 THEN 'Elite'
                    WHEN r.BadgesCount >= 25 THEN 'Veteran'
                    ELSE 'Regular'
                END
            ELSE 'Novice'
        END AS BadgeTier,
        CASE 
            WHEN r.PostsPercentile >= 0.9 THEN 'Top 10%'
            WHEN r.PostsPercentile >= 0.75 THEN 'Top 25%'
            WHEN r.PostsPercentile >= 0.5 THEN 'Top 50%'
            ELSE 'Below Average'
        END AS ActivityLevel,
        STRING_AGG(
            CASE 
                WHEN p.PostTypeId = 1 THEN 'Q' 
                WHEN p.PostTypeId = 2 THEN 'A'
                ELSE 'O'
            END, 
            '' ORDER BY p.CreationDate
        ) AS PostActivityPattern
    FROM RankedUsers r
    LEFT JOIN Posts p ON r.UserId = p.OwnerUserId
    WHERE r.TotalPosts > 0
    GROUP BY 
        r.UserId, 
        r.DisplayName, 
        r.Reputation, 
        r.TotalPosts, 
        r.Questions, 
        r.Answers, 
        r.QuestionScore, 
        r.AnswerScore, 
        r.LastPostDate, 
        r.PostsPercentile
)
SELECT 
    cm.UserId,
    cm.DisplayName,
    cm.Reputation,
    cm.TotalPosts,
    cm.Questions,
    cm.Answers,
    cm.QuestionScore,
    cm.AnswerScore,
    cm.LastPostDate,
    cm.AnswerQualityRatio,
    cm.AnswerPerQuestionRatio,
    cm.BadgeTier,
    cm.ActivityLevel,
    cm.PostActivityPattern,
    COALESCE(
        (SELECT STRING_AGG(t.TagName, ', ') 
         FROM Posts p 
         JOIN unnest(string_to_array(p.Tags, '<>')) AS t(TagName) ON t.TagName != '' 
         WHERE p.OwnerUserId = cm.UserId 
         GROUP BY p.OwnerUserId 
         HAVING COUNT(DISTINCT t.TagName) > 0
        ), 
        'No Tags'
    ) AS UserTagPreferences,
    CASE 
        WHEN cm.Reputation > 10000 THEN 'Expert'
        WHEN cm.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS ReputationLevel,
    CASE 
        WHEN cm.Answers > 0 THEN (cm.AnswerScore / cm.Answers)
        ELSE NULL 
    END AS AvgAnswerScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = cm.UserId AND v.VoteTypeId = 2) AS UpvotesGiven,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = cm.UserId AND v.VoteTypeId = 3) AS DownvotesGiven,
    COALESCE(ta.TagName, 'No Popular Tags') AS MostPopularTag,
    ta.TagCount,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = cm.UserId AND CreationDate >= DATEADD(DAY, -30, CURRENT_DATE)) AS RecentPostsCount
FROM ComplexMetrics cm
LEFT JOIN (
    SELECT 
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as rn
    FROM Tags t
    WHERE t.IsRequired = 0
) ta ON ta.rn = 1
WHERE cm.TotalPosts > 10
ORDER BY cm.QuestionScore DESC, cm.AnswerScore DESC, cm.Reputation DESC
LIMIT 100;
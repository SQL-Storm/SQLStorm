-- {"query": "7401.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2650} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation > 5000 THEN 'Advanced'
            WHEN u.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS ReputationLevel,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RankByReputation,
        RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) AS RankByTotalScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        LAG(DisplayName) OVER (ORDER BY RankByReputation) AS PreviousUser,
        LEAD(DisplayName) OVER (ORDER BY RankByReputation) AS NextUser,
        NTILE(10) OVER (ORDER BY Reputation) AS ReputationDecile,
        PERCENT_RANK() OVER (ORDER BY Reputation) AS ReputationPercentile,
        ROUND(AVG(Reputation) OVER (ORDER BY RankByReputation ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING), 2) AS ReputationMovingAvg
    FROM UserStats
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        COALESCE(p.AcceptedAnswerId, 0) AS HasAcceptedAnswer,
        COALESCE(p.ClosedDate, '1900-01-01') AS IsClosed,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosedFlag,
        CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END AS AnswerCountIfQuestion,
        CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END AS ScoreIfAnswer,
        COALESCE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '') AS CleanTags,
        STRING_TO_ARRAY(COALESCE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ''), '><') AS TagArray,
        CHAR_LENGTH(p.Body) AS BodyLength,
        ABS(p.Score) AS AbsoluteScore,
        CASE 
            WHEN p.PostTypeId = 1 AND p.Score > 50 THEN 'HighlyPopularQuestion'
            WHEN p.PostTypeId = 1 AND p.Score > 10 THEN 'PopularQuestion'
            WHEN p.PostTypeId = 2 AND p.Score > 20 THEN 'HighlyPopularAnswer'
            WHEN p.PostTypeId = 2 AND p.Score > 5 THEN 'PopularAnswer'
            ELSE 'Normal'
        END AS PopularityLevel
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostWithUserDetails AS (
    SELECT 
        pa.*,
        ru.DisplayName AS OwnerDisplayName,
        ru.Reputation AS OwnerReputation,
        ru.QuestionCount AS OwnerQuestionCount,
        ru.AnswerCount AS OwnerAnswerCount,
        ru.TotalScore AS OwnerTotalScore,
        CASE 
            WHEN pa.OwnerUserId = 0 THEN 'CommunityWiki'
            WHEN ru.DisplayName IS NOT NULL THEN ru.DisplayName
            ELSE ''
        END AS UserDisplayInfo,
        CASE 
            WHEN pa.OwnerReputation > 10000 THEN 'Expert'
            WHEN pa.OwnerReputation > 5000 THEN 'Advanced'
            WHEN pa.OwnerReputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS OwnerReputationLevel
    FROM PostAnalysis pa
    LEFT JOIN RankedUsers ru ON pa.OwnerUserId = ru.UserId
),
AggregatedResults AS (
    SELECT 
        COUNT(*) AS TotalPosts,
        COUNT(DISTINCT OwnerUserId) AS DistinctUsers,
        SUM(CASE WHEN IsClosedFlag = 1 THEN 1 ELSE 0 END) AS ClosedPosts,
        SUM(CASE WHEN HasAcceptedAnswer > 0 THEN 1 ELSE 0 END) AS PostsWithAcceptedAnswers,
        AVG(ABS(Score)) AS AverageAbsoluteScore,
        AVG(BodyLength) AS AverageBodyLength,
        SUM(ScoreIfAnswer) AS TotalAnswerScore,
        SUM(ScoreIfQuestion) AS TotalQuestionScore,
        AVG(AnswerCountIfQuestion) AS AverageAnswerCountPerQuestion,
        COUNT(*) OVER () AS GrandTotalPosts
    FROM PostWithUserDetails
),
ComplexPostAnalysis AS (
    SELECT 
        p.*,
        CASE 
            WHEN p.PostTypeId = 1 AND p.Score > (SELECT AVG(Score) + STDDEV(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAverageQuestion'
            WHEN p.PostTypeId = 1 THEN 'BelowAverageQuestion'
            WHEN p.PostTypeId = 2 AND p.Score > (SELECT AVG(Score) + STDDEV(Score) FROM Posts WHERE PostTypeId = 2) THEN 'AboveAverageAnswer'
            WHEN p.PostTypeId = 2 THEN 'BelowAverageAnswer'
            ELSE 'Other'
        END AS QualityLevel,
        CASE 
            WHEN p.BodyLength > 1000 THEN 'LongForm'
            WHEN p.BodyLength > 500 THEN 'MediumForm'
            ELSE 'ShortForm'
        END AS ContentLengthCategory,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.PostId),
            0
        ) AS CommentCountFromSubquery,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.PostId AND v.VoteTypeId = 2),
            0
        ) AS UpvotesFromSubquery,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.PostId AND v.VoteTypeId = 3),
            0
        ) AS DownvotesFromSubquery,
        CASE 
            WHEN LENGTH(p.Tags) > 1 THEN 
                (SELECT COUNT(*) FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS tag) 
            ELSE 0 
        END AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRankByType,
        RANK() OVER (ORDER BY p.Score DESC) AS OverallScoreRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS DenseScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.Score) AS PercentileRank
    FROM PostWithUserDetails p
),
FinalAnalysis AS (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY pa.Score DESC) AS RowNumber,
        pa.*,
        a.TotalPosts,
        a.DistinctUsers,
        a.ClosedPosts,
        a.WithAcceptedAnswers,
        a.AverageAbsoluteScore,
        a.AverageBodyLength,
        CASE 
            WHEN pa.OwnerUserId > 0 THEN
                (SELECT COUNT(DISTINCT h.Id) 
                 FROM PostHistory h 
                 WHERE h.PostId = pa.PostId 
                 AND h.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) 
                 AND h.UserId = pa.OwnerUserId)
            ELSE 0
        END AS UserEditsCount,
        CASE 
            WHEN pa.OwnerUserId > 0 THEN
                (SELECT COUNT(DISTINCT h.Id) 
                 FROM PostHistory h 
                 WHERE h.PostId = pa.PostId 
                 AND h.PostHistoryTypeId IN (10, 11, 12, 13)
                 AND h.UserId = pa.OwnerUserId)
            ELSE 0
        END AS UserActionCount,
        CASE 
            WHEN pa.Score > 0 THEN 
                COALESCE(SUM(pa.Score) OVER (ORDER BY pa.CreationDate), 0)
            ELSE NULL 
        END AS RunningScoreSum,
        CASE 
            WHEN pa.Score > 0 THEN 
                ROUND(LAG(pa.Score) OVER (ORDER BY pa.CreationDate), 2)
            ELSE NULL 
        END AS PreviousScore,
        CASE 
            WHEN pa.Score > 0 THEN 
                ROUND(LEAD(pa.Score) OVER (ORDER BY pa.CreationDate), 2)
            ELSE NULL 
        END AS NextScore,
        CASE 
            WHEN pa.OwnerUserId > 0 THEN
                (SELECT COUNT(*) 
                 FROM Posts p2 
                 WHERE p2.OwnerUserId = pa.OwnerUserId 
                 AND p2.CreationDate > pa.CreationDate
                 AND p2.PostTypeId = 1)
            ELSE 0
        END AS LaterQuestionsCount,
        CASE 
            WHEN pa.OwnerUserId > 0 THEN
                (SELECT COUNT(*) 
                 FROM Posts p2 
                 WHERE p2.OwnerUserId = pa.OwnerUserId 
                 AND p2.CreationDate < pa.CreationDate
                 AND p2.PostTypeId = 1)
            ELSE 0
        END AS EarlierQuestionsCount
    FROM ComplexPostAnalysis pa
    CROSS JOIN AggregatedResults a
    WHERE pa.CreationDate >= '2018-01-01'
)
SELECT 
    f.*,
    CASE 
        WHEN f.RunningScoreSum > 1000 THEN 'HighlyActive'
        WHEN f.RunningScoreSum > 500 THEN 'ModeratelyActive'
        WHEN f.RunningScoreSum > 100 THEN 'SlightlyActive'
        ELSE 'Inactive'
    END AS ActivityLevel,
    CASE 
        WHEN f.PreviousScore IS NOT NULL AND f.NextScore IS NOT NULL THEN
            (f.NextScore - f.PreviousScore) / NULLIF(f.PreviousScore, 0)
        ELSE NULL 
    END AS ScoreChangeRate,
    f.TotalPosts - f.RowNumber AS PostsRemaining,
    ROUND(
        (COALESCE(f.CommentCountFromSubquery, 0) + 
         COALESCE(f.UpvotesFromSubquery, 0) -
         COALESCE(f.DownvotesFromSubquery, 0)) / 
        NULLIF(
            (COALESCE(f.Score, 0) + COALESCE(f.AnswerCountIfQuestion, 0) + 1), 0
        ), 2
    ) AS EngagementRatio,
    CASE WHEN f.HasAcceptedAnswer > 0 THEN 'Has Accepted' ELSE 'No Accepted' END AS AnswerStatus,
    CASE WHEN f.IsClosed > '1900-01-01' THEN 'Closed' ELSE 'Open' END AS PostStatus,
    CASE 
        WHEN f.Score > (SELECT AVG(Score) FROM Posts) THEN 'AboveAverage'
        WHEN f.Score > (SELECT AVG(Score) - STDDEV(Score) FROM Posts) THEN 'Average'
        ELSE 'BelowAverage'
    END AS ScoreCategory,
    CASE 
        WHEN f.OwnerReputation > (SELECT AVG(Reputation) FROM Users) THEN 'AboveAverageReputation'
        WHEN f.OwnerReputation > (SELECT AVG(Reputation) - STDDEV(Reputation) FROM Users) THEN 'AverageReputation'
        ELSE 'BelowAverageReputation'
    END AS ReputationCategory
FROM FinalAnalysis f
WHERE f.Score IS NOT NULL
ORDER BY f.Score DESC, f.CreationDate DESC
LIMIT 1000;
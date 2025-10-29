-- {"query": "7338.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1982} 
WITH UserStats AS (
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
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(p.CreationDate) AS LatestPostDate,
        AVG(CAST(p.Score AS FLOAT)) AS AvgPostScore,
        STRING_AGG(DISTINCT LEFT(p.Tags, 50), '; ') AS TagList
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) AS ReputationRank,
        RANK() OVER (ORDER BY TotalQuestionScore DESC) AS QuestionScoreRank,
        DENSE_RANK() OVER (ORDER BY BadgeCount DESC) AS BadgeRank,
        PERCENT_RANK() OVER (ORDER BY Views DESC) AS ViewPercentile,
        NTILE(4) OVER (ORDER BY UpVotes - DownVotes DESC) AS EngagementQuartile
    FROM UserStats
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.PostTypeId,
        p.OwnerUserId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostTypeDescription,
        COALESCE(p.Title, 'No Title') AS SafeTitle,
        CASE 
            WHEN p.Body IS NULL THEN 0
            WHEN LENGTH(p.Body) < 100 THEN 1
            WHEN LENGTH(p.Body) BETWEEN 100 AND 1000 THEN 2
            ELSE 3
        END AS BodyLengthCategory,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1)
            ELSE 0
        END AS TagCount,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostDate
    FROM Posts p
),
ComplexFiltering AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.PostTypeDescription,
        pa.BodyLengthCategory,
        pa.TagCount,
        pa.OwnerUserId,
        pa.ParentId,
        pa.AcceptedAnswerId,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) 
                 AND pa.ViewCount > 100 THEN 'High Impact'
            WHEN pa.Score > 0 AND pa.ViewCount > 50 THEN 'Moderate Impact'
            ELSE 'Low Impact'
        END AS ImpactLevel,
        CASE 
            WHEN pa.CreationDate > '2023-01-01 00:00:00' THEN 'Recent'
            WHEN pa.CreationDate > '2022-01-01 00:00:00' THEN '2022'
            WHEN pa.CreationDate > '2021-01-01 00:00:00' THEN '2021'
            ELSE 'Older'
        END AS TimeCategory,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pa.PostId AND c.Score > 5),
            0
        ) AS HighScoreCommentCount
    FROM PostAnalysis pa
    WHERE pa.PostTypeDescription IN ('Question', 'Answer')
),
FinalAnalysis AS (
    SELECT 
        rf.UserId,
        rf.DisplayName,
        rf.Reputation,
        rf.PostCount,
        rf.QuestionCount,
        rf.AnswerCount,
        rf.TotalQuestionScore,
        rf.TotalAnswerScore,
        rf.BadgeCount,
        rf.ReputationRank,
        rf.QuestionScoreRank,
        rf.BadgeRank,
        rf.ViewPercentile,
        rf.EngagementQuartile,
        rf.LatestPostDate,
        rf.AvgPostScore,
        rf.TagList,
        cf.PostId,
        cf.Title,
        cf.Score,
        cf.ViewCount,
        cf.CreationDate,
        cf.PostTypeDescription,
        cf.BodyLengthCategory,
        cf.TagCount,
        cf.ImpactLevel,
        cf.TimeCategory,
        cf.HighScoreCommentCount,
        CASE 
            WHEN rf.Reputation > 10000 THEN 'Expert'
            WHEN rf.Reputation > 5000 THEN 'Advanced'
            WHEN rf.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS UserLevel,
        CASE 
            WHEN cf.TagCount > 5 THEN 'Tag Heavy'
            WHEN cf.TagCount > 2 THEN 'Tag Moderate'
            ELSE 'Tag Light'
        END AS TagDensity,
        ROW_NUMBER() OVER (
            PARTITION BY cf.TimeCategory 
            ORDER BY cf.Score DESC, cf.ViewCount DESC
        ) AS MonthlyRank,
        DENSE_RANK() OVER (
            ORDER BY cf.Score DESC, cf.ViewCount DESC
        ) AS GlobalRank
    FROM RankedUsers rf
    INNER JOIN ComplexFiltering cf ON rf.UserId = cf.OwnerUserId
    WHERE rf.PostCount > 0 AND cf.Score IS NOT NULL
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.PostCount,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.TotalQuestionScore,
    fa.TotalAnswerScore,
    fa.BadgeCount,
    fa.ReputationRank,
    fa.QuestionScoreRank,
    fa.BadgeRank,
    fa.ViewPercentile,
    fa.EngagementQuartile,
    fa.LatestPostDate,
    fa.AvgPostScore,
    fa.TagList,
    fa.PostId,
    fa.Title,
    fa.Score,
    fa.ViewCount,
    fa.CreationDate,
    fa.PostTypeDescription,
    fa.BodyLengthCategory,
    fa.TagCount,
    fa.ImpactLevel,
    fa.TimeCategory,
    fa.HighScoreCommentCount,
    fa.UserLevel,
    fa.TagDensity,
    fa.MonthlyRank,
    fa.GlobalRank,
    CASE 
        WHEN fa.PostTypeDescription = 'Question' AND fa.Score > 10 THEN 'Question Elite'
        WHEN fa.PostTypeDescription = 'Answer' AND fa.Score > 5 THEN 'Answer Elite'
        ELSE 'Standard'
    END AS PostEliteStatus,
    CASE 
        WHEN fa.ViewPercentile > 0.95 THEN 'Top Viewed'
        WHEN fa.ViewPercentile > 0.8 THEN 'High Viewed'
        ELSE 'Normal Viewed'
    END AS ViewRanking,
    CASE 
        WHEN fa.PostCount > 500 THEN 'Veteran'
        WHEN fa.PostCount > 100 THEN 'Experienced'
        WHEN fa.PostCount > 10 THEN 'Regular'
        ELSE 'Newbie'
    END AS PostingFrequency,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.PostTypeId = 1 AND p.Score > 0),
        0
    ) AS PositiveQuestions,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.PostTypeId = 2 AND p.Score > 0),
        0
    ) AS PositiveAnswers,
    CONCAT(
        fa.UserLevel, 
        ' - ', 
        fa.PostTypeDescription, 
        ' (', 
        fa.ImpactLevel, 
        ')'
    ) AS UserPostStatus
FROM FinalAnalysis fa
WHERE 
    fa.Reputation > 100 
    AND fa.PostCount > 5 
    AND fa.Score > 0
    AND fa.ViewCount > 10
    AND fa.CreationDate > '2021-01-01 00:00:00'
    AND fa.TimeCategory IN ('Recent', '2022', '2021')
ORDER BY 
    fa.Reputation DESC,
    fa.Score DESC,
    fa.ViewCount DESC
LIMIT 1000;
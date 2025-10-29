-- {"query": "7417.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2186} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT b.Id) as TotalBadges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                AVG(CAST(p.Score AS FLOAT)) 
            ELSE NULL 
        END as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTagsUsed
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
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPosts DESC) as RankByReputation,
        DENSE_RANK() OVER (ORDER BY TotalPosts DESC) as RankByPostCount
    FROM UserActivityStats
),
PostActivityAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                COALESCE(p.AnswerCount, 0) * 100.0 / NULLIF(p.ViewCount, 0)
            ELSE NULL 
        END as AnswerToViewRatio,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                CASE 
                    WHEN p.Score >= 10 THEN 'High'
                    WHEN p.Score >= 5 THEN 'Medium'
                    ELSE 'Low'
                END
            ELSE 'NotApplicable'
        END as ScoreCategory,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
        SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) as CleanTags
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
      AND p.PostTypeId IN (1, 2)
),
TagFrequencyAnalysis AS (
    SELECT 
        tag,
        COUNT(*) as Frequency,
        STRING_AGG(DISTINCT p.Id::VARCHAR, ', ') as PostIds
    FROM (
        SELECT 
            unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) as tag,
            p.Id
        FROM Posts p
        WHERE p.Tags IS NOT NULL 
          AND p.Tags != ''
          AND p.PostTypeId = 1
    ) x
    GROUP BY tag
    HAVING COUNT(*) >= 10
),
ComplexPostAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.PostTypeId,
        pa.AnswerToViewRatio,
        pa.ScoreCategory,
        pa.DaysSinceCreation,
        pa.CleanTags,
        RANK() OVER (PARTITION BY pa.PostTypeId ORDER BY pa.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY pa.ViewCount DESC) as ViewRank,
        NTH_VALUE(pa.Title, 1) OVER (
            PARTITION BY pa.PostTypeId 
            ORDER BY pa.CreationDate 
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) as RecentTitle,
        LAG(pa.Score, 1) OVER (ORDER BY pa.CreationDate) as PrevScore,
        LEAD(pa.Score, 1) OVER (ORDER BY pa.CreationDate) as NextScore,
        AVG(pa.Score) OVER (PARTITION BY pa.OwnerUserId) as AvgScorePerUser,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 1
            ELSE 0 
        END as IsAboveAverage,
        CASE 
            WHEN pa.CleanTags IS NOT NULL AND LENGTH(pa.CleanTags) > 0 THEN 
                (LENGTH(pa.CleanTags) - LENGTH(REPLACE(pa.CleanTags, '>', ''))) + 1
            ELSE 0 
        END as TagCount
    FROM PostActivityAnalysis pa
    WHERE pa.Score > 0
),
MainAnalysis AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.TotalPosts,
        ru.TotalComments,
        ru.TotalBadges,
        ru.LastPostDate,
        ru.LastCommentDate,
        ru.AvgPostScore,
        ru.AllTagsUsed,
        ru.RankByReputation,
        ru.RankByPostCount,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = ru.UserId 
              AND p.PostTypeId = 1
              AND p.Score >= 10
        ) as HighScoreQuestions,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = ru.UserId 
              AND p.PostTypeId = 2
              AND p.Score >= 5
        ) as HighScoreAnswers,
        (
            SELECT COUNT(*)
            FROM Votes v
            JOIN Posts p ON v.PostId = p.Id
            WHERE p.OwnerUserId = ru.UserId 
              AND v.VoteTypeId = 2
              AND v.CreationDate >= '2020-01-01'
        ) as RecentUpvotes,
        (
            SELECT STRING_AGG(b.Name, ', ')
            FROM Badges b
            WHERE b.UserId = ru.UserId
              AND b.Date >= '2020-01-01'
            GROUP BY b.UserId
        ) as RecentBadges,
        (
            SELECT COUNT(*)
            FROM PostHistory ph
            JOIN Posts p ON ph.PostId = p.Id
            WHERE p.OwnerUserId = ru.UserId 
              AND ph.PostHistoryTypeId IN (4, 5, 6)
              AND ph.CreationDate >= '2020-01-01'
        ) as RecentEdits
    FROM RankedUsers ru
    WHERE ru.Reputation > 1000
),
FilteredPosts AS (
    SELECT *
    FROM ComplexPostAnalysis
    WHERE ScoreCategory IN ('High', 'Medium')
      AND TagCount >= 1
      AND DaysSinceCreation <= 365
)
SELECT 
    'User Performance Report' as ReportType,
    COUNT(*) as TotalUsers,
    AVG(Reputation) as AvgReputation,
    MAX(Reputation) as MaxReputation,
    MIN(Reputation) as MinReputation,
    COUNT(DISTINCT UserId) as DistinctUsers,
    STRING_AGG(
        CONCAT(DisplayName, ' (', Reputation, ')'), 
        '; '
    ) as TopUsers,
    COUNT(*) OVER() as TotalReports,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        JOIN Users u ON p.OwnerUserId = u.Id
        WHERE u.Id IN (SELECT UserId FROM MainAnalysis)
          AND p.PostTypeId = 1
    ) as RelevantQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        JOIN Users u ON p.OwnerUserId = u.Id
        WHERE u.Id IN (SELECT UserId FROM MainAnalysis)
          AND p.PostTypeId = 2
    ) as RelevantAnswers,
    (
        SELECT STRING_AGG(
            CONCAT('Tag: ', tag, ' - Count: ', Frequency), 
            '; '
        )
        FROM TagFrequencyAnalysis
        WHERE Frequency >= 50
    ) as PopularTags,
    (
        SELECT AVG(Score) 
        FROM FilteredPosts
    ) as AvgFilteredPostScore
FROM MainAnalysis
WHERE TotalPosts > 10
  AND TotalComments > 5
  AND LastPostDate >= '2020-01-01'
  AND LastCommentDate >= '2020-01-01'
GROUP BY 
    ReportType,
    TotalUsers,
    AvgReputation,
    MaxReputation,
    MinReputation,
    DistinctUsers,
    TopUsers,
    TotalReports,
    RelevantQuestions,
    RelevantAnswers,
    PopularTags,
    AvgFilteredPostScore
HAVING 
    COUNT(*) > 0
EXCEPT
SELECT 
    'User Performance Report' as ReportType,
    COUNT(*) as TotalUsers,
    AVG(Reputation) as AvgReputation,
    MAX(Reputation) as MaxReputation,
    MIN(Reputation) as MinReputation,
    COUNT(DISTINCT UserId) as DistinctUsers,
    STRING_AGG(
        CONCAT(DisplayName, ' (', Reputation, ')'), 
        '; '
    ) as TopUsers,
    COUNT(*) OVER() as TotalReports,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        JOIN Users u ON p.OwnerUserId = u.Id
        WHERE u.Id IN (SELECT UserId FROM MainAnalysis)
          AND p.PostTypeId = 1
    ) as RelevantQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        JOIN Users u ON p.OwnerUserId = u.Id
        WHERE u.Id IN (SELECT UserId FROM MainAnalysis)
          AND p.PostTypeId = 2
    ) as RelevantAnswers,
    (
        SELECT STRING_AGG(
            CONCAT('Tag: ', tag, ' - Count: ', Frequency), 
            '; '
        )
        FROM TagFrequencyAnalysis
        WHERE Frequency >= 50
    ) as PopularTags,
    (
        SELECT AVG(Score) 
        FROM FilteredPosts
    ) as AvgFilteredPostScore
FROM MainAnalysis
WHERE TotalPosts < 5
   OR TotalComments < 2
   OR LastPostDate < '2019-01-01'
GROUP BY 
    ReportType,
    TotalUsers,
    AvgReputation,
    MaxReputation,
    MinReputation,
    DistinctUsers,
    TopUsers,
    TotalReports,
    RelevantQuestions,
    RelevantAnswers,
    PopularTags,
    AvgFilteredPostScore;
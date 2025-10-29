-- {"query": "7729.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1724} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(MAX(p.CreationDate), u.CreationDate) AS LastPostDate,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS CommentCount,
        COALESCE(COUNT(DISTINCT b.Id), 0) AS BadgeCount,
        RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) AS ScoreRank,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Veteran'
            WHEN u.Reputation >= 100 THEN 'Participant'
            ELSE 'Novice'
        END AS ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
TopUsers AS (
    SELECT 
        UserId,
        Reputation,
        DisplayName,
        QuestionCount,
        AnswerCount,
        TotalScore,
        LastPostDate,
        CommentCount,
        BadgeCount,
        ScoreRank,
        ReputationTier,
        DENSE_RANK() OVER (ORDER BY QuestionCount DESC) AS QuestionRank,
        DENSE_RANK() OVER (ORDER BY AnswerCount DESC) AS AnswerRank
    FROM UserActivityStats
    WHERE QuestionCount > 0 OR AnswerCount > 0
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        DATEDIFF(DAY, p.CreationDate, COALESCE(p.ClosedDate, GETDATE())) AS DaysOpen,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score >= 100 THEN 'Hot'
            WHEN p.Score >= 25 THEN 'Popular'
            WHEN p.Score >= 0 THEN 'Moderate'
            ELSE 'Low'
        END AS PopularityLevel,
        STRING_AGG(
            SUBSTRING(p.Tags, 
                CASE WHEN CHARINDEX('<', p.Tags) > 0 THEN CHARINDEX('<', p.Tags) + 1 ELSE 1 END,
                CASE 
                    WHEN CHARINDEX('>', p.Tags) > 0 THEN CHARINDEX('>', p.Tags) - CHARINDEX('<', p.Tags) - 1
                    ELSE LEN(p.Tags)
                END
            ), 
            ', '
        ) AS ExtractedTags
    FROM Posts p
    WHERE p.Score IS NOT NULL
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId, p.PostTypeId, p.AnswerCount, p.CommentCount, p.Tags, p.AcceptedAnswerId, p.ClosedDate
),
UserPostRelationships AS (
    SELECT 
        tu.UserId,
        tu.Reputation,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.ScoreRank,
        tu.QuestionRank,
        tu.AnswerRank,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.DaysOpen,
        pa.PopularityLevel,
        pa.ExtractedTags,
        ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY pa.Score DESC) AS UserPostRank,
        RANK() OVER (ORDER BY pa.Score DESC) AS GlobalPostRank
    FROM TopUsers tu
    INNER JOIN PostAnalysis pa ON tu.UserId = pa.OwnerUserId
),
ComplexCalculations AS (
    SELECT 
        upr.UserId,
        upr.Reputation,
        upr.QuestionCount,
        upr.AnswerCount,
        upr.ScoreRank,
        upr.QuestionRank,
        upr.AnswerRank,
        upr.PostId,
        upr.Title,
        upr.Score,
        upr.ViewCount,
        upr.DaysOpen,
        upr.PopularityLevel,
        upr.ExtractedTags,
        upr.UserPostRank,
        upr.GlobalPostRank,
        (upr.Score * 1.0 / NULLIF(COALESCE(upr.ViewCount, 1), 0)) AS ScorePerView,
        (upr.DaysOpen * 1.0 / NULLIF(upr.QuestionCount, 0)) AS AvgDaysPerQuestion,
        CASE 
            WHEN upr.Score > (SELECT AVG(Score) FROM PostAnalysis) THEN 'AboveAverage'
            WHEN upr.Score < (SELECT AVG(Score) FROM PostAnalysis) THEN 'BelowAverage'
            ELSE 'Average'
        END AS PerformanceCategory,
        COALESCE(
            (
                SELECT COUNT(DISTINCT ph.Id)
                FROM PostHistory ph
                WHERE ph.PostId = upr.PostId
                AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
            ), 0
        ) AS EditCount,
        COALESCE(
            (
                SELECT COUNT(DISTINCT v.Id)
                FROM Votes v
                WHERE v.PostId = upr.PostId
                AND v.VoteTypeId IN (2, 3)
            ), 0
        ) AS VoteCount,
        DENSE_RANK() OVER (ORDER BY upr.Score DESC) AS RankWithinScore,
        PERCENT_RANK() OVER (ORDER BY upr.Score) AS ScorePercentile
    FROM UserPostRelationships upr
)
SELECT 
    cc.UserId,
    cc.Reputation,
    cc.QuestionCount,
    cc.AnswerCount,
    cc.ScoreRank,
    cc.QuestionRank,
    cc.AnswerRank,
    cc.PostId,
    cc.Title,
    cc.Score,
    cc.ViewCount,
    cc.DaysOpen,
    cc.PopularityLevel,
    cc.ExtractedTags,
    cc.UserPostRank,
    cc.GlobalPostRank,
    cc.ScorePerView,
    cc.AvgDaysPerQuestion,
    cc.PerformanceCategory,
    cc.EditCount,
    cc.VoteCount,
    cc.RankWithinScore,
    cc.ScorePercentile,
    CASE 
        WHEN cc.ScorePercentile >= 0.9 THEN 'Top 10%'
        WHEN cc.ScorePercentile >= 0.75 THEN 'Top 25%'
        WHEN cc.ScorePercentile >= 0.5 THEN 'Top 50%'
        ELSE 'Below 50%'
    END AS PerformanceBracket,
    CONCAT(
        'User ', cc.UserId, ' (Rk: ', cc.ScoreRank, ') - ',
        IIF(cc.QuestionCount > 0, CONCAT('Q', cc.QuestionCount, ' '), ''),
        IIF(cc.AnswerCount > 0, CONCAT('A', cc.AnswerCount, ' '), ''),
        'Score: ', cc.Score
    ) AS UserPostSummary
FROM ComplexCalculations cc
WHERE cc.Score IS NOT NULL
    AND (cc.QuestionCount > 0 OR cc.AnswerCount > 0)
    AND cc.PostId > 0
    AND cc.DaysOpen IS NOT NULL
    AND cc.ScorePerView BETWEEN 0 AND 1000
    AND cc.EditCount BETWEEN 0 AND 100
ORDER BY cc.Score DESC, cc.ViewCount DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;
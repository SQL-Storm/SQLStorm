-- {"query": "49089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1301} 
WITH HighImpactQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.CreationDate
    FROM
        Posts p
    JOIN (
        SELECT PostId, COUNT(DISTINCT Id) as EditCount
        FROM PostHistory
        WHERE PostHistoryTypeId IN (
            4, -- Edit Title
            5, -- Edit Body
            6, -- Edit Tags
            7, -- Rollback Title
            8, -- Rollback Body
            9  -- Rollback Tags
        )
        GROUP BY PostId
        HAVING COUNT(DISTINCT Id) >= 3
    ) AS ph_edits ON p.Id = ph_edits.PostId
    WHERE
        p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
        AND p.CreationDate >= '2019-01-01'
        AND p.CreationDate < '2023-01-01'
        AND p.ViewCount > 5000
        AND p.Score > 100
        AND p.Tags LIKE '%<sql>%' -- Focus on questions related to SQL
),
UserAnswerPerformance AS (
    SELECT
        a.OwnerUserId,
        SUM(a.Score) AS TotalAnswerScore,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AverageAnswerScore,
        SUM(hi.QuestionScore) AS SumParentQuestionScore,
        COUNT(DISTINCT hi.QuestionId) AS DistinctParentQuestionCount,
        MIN(a.CreationDate) AS FirstAnswerDate,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM
        Posts a
    JOIN
        HighImpactQuestions hi ON a.ParentId = hi.QuestionId
    WHERE
        a.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
        AND a.OwnerUserId IS NOT NULL
        AND a.Score > 0 -- Only positive scoring answers
    GROUP BY
        a.OwnerUserId
),
UserEngagementMetrics AS (
    SELECT
        uap.OwnerUserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes AS UserTotalUpVotes,
        u.DownVotes AS UserTotalDownVotes,
        u.CreationDate AS UserCreationDate,
        uap.TotalAnswerScore,
        uap.AnswerCount,
        uap.AverageAnswerScore,
        uap.SumParentQuestionScore,
        uap.DistinctParentQuestionCount,
        uap.FirstAnswerDate,
        uap.LastAnswerDate,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT c.PostId) AS CommentedPostsCount,
        COUNT(v.Id) AS TotalVotesGivenByThisUser
    FROM
        UserAnswerPerformance uap
    JOIN
        Users u ON uap.OwnerUserId = u.Id
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    GROUP BY
        uap.OwnerUserId, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes,
        u.CreationDate, uap.TotalAnswerScore, uap.AnswerCount, uap.AverageAnswerScore,
        uap.SumParentQuestionScore, uap.DistinctParentQuestionCount,
        uap.FirstAnswerDate, uap.LastAnswerDate
)
SELECT
    uem.DisplayName,
    uem.OwnerUserId,
    uem.Reputation,
    uem.TotalAnswerScore,
    uem.AnswerCount,
    uem.AverageAnswerScore,
    uem.GoldBadges,
    uem.SilverBadges,
    uem.BronzeBadges,
    uem.TotalBadges,
    (CAST(uem.TotalAnswerScore AS NUMERIC) / NULLIF(uem.AnswerCount, 0)) AS AverageImpactPerAnswer,
    (CAST(uem.SumParentQuestionScore AS NUMERIC) / NULLIF(uem.DistinctParentQuestionCount, 0)) AS AvgScoreOfAnsweredQuestions,
    uem.CommentedPostsCount,
    uem.TotalVotesGivenByThisUser,
    EXTRACT(EPOCH FROM (uem.LastAnswerDate - uem.FirstAnswerDate)) / (60 * 60 * 24) AS ActiveAnswerDays, -- Duration in days
    RANK() OVER (
        ORDER BY
            uem.TotalAnswerScore DESC,
            uem.AverageAnswerScore DESC,
            uem.Reputation DESC,
            uem.GoldBadges DESC
    ) AS OverallImpactRank,
    NTILE(10) OVER (
        ORDER BY
            uem.TotalAnswerScore DESC,
            uem.Reputation DESC
    ) AS DecileRankByImpact
FROM
    UserEngagementMetrics uem
WHERE
    uem.AnswerCount >= 10 -- Only consider users with a significant number of answers to high-impact questions
    AND uem.DistinctParentQuestionCount >= 5 -- Only consider users who answered at least 5 different high-impact questions
    AND uem.Reputation > 1000 -- Only consider users with notable reputation
ORDER BY
    OverallImpactRank ASC, uem.OwnerUserId ASC
LIMIT 50;
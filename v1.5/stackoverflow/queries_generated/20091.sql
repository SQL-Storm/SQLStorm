-- {"query": "20091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1456} 

WITH UserContributionStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        MAX(p.LastActivityDate) AS LastContributionDate,
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = u.Id AND b.Class = 1
        ) AS GoldBadges,
        (
            SELECT MIN(b.Date)
            FROM Badges b
            WHERE b.UserId = u.Id AND b.Class = 1
        ) AS FirstGoldBadgeDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.Reputation > 10000 AND p.PostTypeId IN (1, 2)
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) > 50
),
AnswerDetails AS (
    SELECT
        p.Id AS AnswerId,
        p.OwnerUserId,
        p.ParentId AS QuestionId,
        p.Score,
        p.CreationDate,
        q.Tags,
        q.ClosedDate,
        q.AcceptedAnswerId,
        ROW_NUMBER() OVER(PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRankInQuestion,
        LAG(p.CreationDate, 1, p.CreationDate) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousAnswerDate,
        (
            SELECT
                STRING_AGG(DISTINCT crt.Name, ', ')
            FROM
                PostHistory ph
            JOIN
                CloseReasonTypes crt ON CAST(ph.Comment AS smallint) = crt.Id
            WHERE
                ph.PostId = p.ParentId AND ph.PostHistoryTypeId = 10 -- Post Closed
        ) AS CloseReasons
    FROM
        Posts p
    JOIN
        Posts q ON p.ParentId = q.Id
    WHERE
        p.PostTypeId = 2 -- Answer
        AND p.OwnerUserId IS NOT NULL
),
CombinedUserData AS (
    SELECT
        ucs.UserId,
        ucs.DisplayName,
        ucs.Reputation,
        ucs.UserCreationDate,
        ucs.TotalQuestions,
        ucs.TotalAnswers,
        ucs.TotalAnswerScore,
        ucs.AvgAnswerScore,
        ucs.GoldBadges,
        ucs.FirstGoldBadgeDate,
        ad.AnswerId,
        ad.QuestionId,
        ad.Score AS AnswerScore,
        ad.CreationDate AS AnswerCreationDate,
        ad.Tags AS QuestionTags,
        ad.CloseReasons,
        CASE WHEN ad.AnswerId = ad.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAcceptedAnswer,
        ad.AnswerRankInQuestion,
        EXTRACT(EPOCH FROM (ad.CreationDate - ad.PreviousAnswerDate)) / 3600 AS HoursBetweenAnswers
    FROM
        UserContributionStats ucs
    JOIN
        AnswerDetails ad ON ucs.UserId = ad.OwnerUserId
    WHERE
        ucs.TotalAnswerScore > 0 AND EXISTS (
            SELECT 1
            FROM Votes v
            WHERE v.PostId = ad.AnswerId
            AND v.VoteTypeId = 2 -- UpMod
            GROUP BY v.PostId
            HAVING COUNT(*) > 10
        )
)
SELECT
    c.DisplayName,
    c.Reputation,
    c.TotalQuestions,
    c.TotalAnswers,
    c.TotalAnswerScore,
    c.AvgAnswerScore,
    c.GoldBadges,
    c.FirstGoldBadgeDate,
    COUNT(c.AnswerId) AS AnalyzedAnswersCount,
    SUM(c.IsAcceptedAnswer) AS AcceptedAnswersCount,
    AVG(c.AnswerRankInQuestion) AS AvgAnswerRank,
    MAX(c.HoursBetweenAnswers) AS MaxHoursBetweenAnswers,
    STRING_AGG(DISTINCT SUBSTRING(c.QuestionTags FROM 2 FOR POSITION('>' IN c.QuestionTags) - 2), ' | ') AS TopTagsFromAnalyzedQuestions,
    SUM(CASE WHEN c.CloseReasons IS NOT NULL THEN 1 ELSE 0 END) AS AnswersOnClosedQuestions,
    DENSE_RANK() OVER(ORDER BY (c.Reputation / 1000) + (c.GoldBadges * 10) + (SUM(c.IsAcceptedAnswer) * 5) - AVG(c.AnswerRankInQuestion) DESC) AS UserPerformanceRank,
    (c.TotalAnswerScore::decimal / NULLIF(c.TotalQuestions + c.TotalAnswers, 0)) * LOG(c.Reputation) AS CalculatedImpactFactor
FROM
    CombinedUserData c
WHERE
    (c.QuestionTags LIKE '%<sql>%' OR c.QuestionTags LIKE '%<python>%' OR c.QuestionTags LIKE '%<java>%')
    AND c.AnswerCreationDate > c.UserCreationDate + INTERVAL '1 year'
GROUP BY
    c.UserId, c.DisplayName, c.Reputation, c.UserCreationDate, c.TotalQuestions, c.TotalAnswers, c.TotalAnswerScore, c.AvgAnswerScore, c.GoldBadges, c.FirstGoldBadgeDate
HAVING
    SUM(c.IsAcceptedAnswer) > 10 AND AVG(c.AnswerRankInQuestion) <= 2.5
ORDER BY
    UserPerformanceRank ASC, CalculatedImpactFactor DESC
LIMIT 100;

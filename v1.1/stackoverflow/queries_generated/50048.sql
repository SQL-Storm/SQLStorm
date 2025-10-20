-- {"query": "50048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1041} 

WITH UserContributionStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT q.Id) AS QuestionsAsked,
        COUNT(DISTINCT a.Id) AS AnswersGiven,
        SUM(CASE WHEN q.OwnerUserId = u.Id THEN q.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN a.OwnerUserId = u.Id THEN a.Score ELSE 0 END) AS TotalAnswerScore,
        SUM(CASE WHEN a.Id = q_parent.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswers,
        AVG(CASE WHEN q.OwnerUserId = u.Id THEN q.ViewCount ELSE NULL END) AS AvgQuestionViews,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Users u
    LEFT JOIN Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Posts q_parent ON a.ParentId = q_parent.Id
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Reputation > 10000 AND u.UpVotes > u.DownVotes
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT a.Id) > 50 AND COUNT(DISTINCT q.Id) > 10
),
RankedBadges AS (
    SELECT
        UserId,
        Name AS FirstGoldBadge,
        Date AS FirstGoldBadgeDate
    FROM (
        SELECT
            UserId,
            Name,
            Date,
            ROW_NUMBER() OVER(PARTITION BY UserId ORDER BY Date ASC) as rn
        FROM Badges
        WHERE Class = 1
    ) AS GoldBadges
    WHERE rn = 1
),
UserTagAnalysis AS (
    SELECT
        OwnerUserId,
        Tag,
        TagCount
    FROM (
        SELECT
            OwnerUserId,
            Tag,
            COUNT(*) AS TagCount,
            ROW_NUMBER() OVER(PARTITION BY OwnerUserId ORDER BY COUNT(*) DESC, Tag ASC) as rn
        FROM (
            SELECT
                OwnerUserId,
                unnest(string_to_array(substring(Tags, 2, length(Tags) - 2), '><')) AS Tag
            FROM Posts
            WHERE PostTypeId = 1 AND Tags IS NOT NULL AND OwnerUserId IS NOT NULL
        ) AS UnnestedTags
        GROUP BY OwnerUserId, Tag
    ) AS RankedTags
    WHERE rn = 1
),
TemporalAnalysis AS (
    SELECT
        OwnerUserId,
        AVG(EXTRACT(EPOCH FROM (q.CreationDate - a.CreationDate))) AS AvgAnswerTimeSeconds
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
)
SELECT
    ucs.DisplayName,
    ucs.Reputation,
    ucs.QuestionsAsked,
    ucs.AnswersGiven,
    ucs.AcceptedAnswers,
    CAST(ucs.AcceptedAnswers AS DECIMAL) / ucs.AnswersGiven AS AcceptedAnswerRatio,
    (ucs.TotalQuestionScore + ucs.TotalAnswerScore) / (ucs.QuestionsAsked + ucs.AnswersGiven) AS AvgPostScore,
    uta.Tag AS PrimaryTag,
    rb.FirstGoldBadge,
    ta.AvgAnswerTimeSeconds / 3600 AS AvgAnswerTimeHours,
    (
        LOG(ucs.Reputation) * 100 +
        (CAST(ucs.AcceptedAnswers AS DECIMAL) / ucs.AnswersGiven) * 500 +
        ucs.AvgQuestionViews * 0.1 -
        (ta.AvgAnswerTimeSeconds / 3600) * 2
    ) AS CalculatedUserRank
FROM
    UserContributionStats ucs
JOIN
    RankedBadges rb ON ucs.UserId = rb.UserId
JOIN
    UserTagAnalysis uta ON ucs.UserId = uta.OwnerUserId
LEFT JOIN
    TemporalAnalysis ta ON ucs.UserId = ta.OwnerUserId
WHERE
    ucs.LastCommentDate > (ucs.CreationDate + INTERVAL '1 year')
    AND rb.FirstGoldBadgeDate < (ucs.CreationDate + INTERVAL '5 year')
ORDER BY
    CalculatedUserRank DESC,
    ucs.Reputation DESC
LIMIT 200;

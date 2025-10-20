-- {"query": "20006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1416} 

WITH UserReputationRank AS (
    SELECT
        Id AS UserId,
        DisplayName,
        Reputation,
        AboutMe,
        CreationDate,
        NTILE(100) OVER (ORDER BY Reputation DESC) AS ReputationPercentile,
        RANK() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM
        Users
    WHERE
        AccountId IS NOT NULL AND Reputation > 1000
),
GoldBadgeHolders AS (
    SELECT DISTINCT
        UserId,
        MIN(Date) OVER (PARTITION BY UserId) as FirstGoldBadgeDate
    FROM
        Badges
    WHERE
        Class = 1
),
PowerUsers AS (
    SELECT
        urr.UserId,
        urr.DisplayName,
        urr.Reputation,
        urr.ReputationRank,
        urr.AboutMe,
        urr.CreationDate AS UserCreationDate,
        gbh.FirstGoldBadgeDate
    FROM
        UserReputationRank urr
    JOIN
        GoldBadgeHolders gbh ON urr.UserId = gbh.UserId
    WHERE
        urr.ReputationPercentile <= 5
),
UserPostActivity AS (
    SELECT
        OwnerUserId,
        MIN(CreationDate) AS FirstPostDate,
        MAX(CreationDate) AS LastPostDate,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COALESCE(AVG(CASE WHEN PostTypeId = 2 THEN Score END), 0) AS AvgAnswerScore,
        SUM(ViewCount) AS TotalViewCount
    FROM
        Posts
    WHERE
        OwnerUserId IS NOT NULL
    GROUP BY
        OwnerUserId
),
UserTopTag AS (
    WITH UserTagParticipation AS (
        SELECT
            p_ans.OwnerUserId,
            t.tag_name,
            COUNT(*) as TagAnswerCount,
            ROW_NUMBER() OVER(PARTITION BY p_ans.OwnerUserId ORDER BY COUNT(*) DESC, t.tag_name) as rn
        FROM
            Posts p_ans
        JOIN
            Posts p_ques ON p_ans.ParentId = p_ques.Id
        CROSS JOIN LATERAL
            unnest(string_to_array(substring(p_ques.Tags, 2, length(p_ques.Tags)-2), '><')) AS t(tag_name)
        WHERE
            p_ans.PostTypeId = 2
            AND p_ans.OwnerUserId IS NOT NULL
        GROUP BY
            p_ans.OwnerUserId, t.tag_name
    )
    SELECT
        OwnerUserId,
        tag_name AS TopTag
    FROM
        UserTagParticipation
    WHERE
        rn = 1
),
GlobalTagPerformance AS (
     SELECT
        t.tag_name,
        AVG(p_ans.Score) as GlobalAvgTagScore,
        COUNT(p_ans.Id) as GlobalTagAnswerCount
    FROM
        Posts p_ans
    JOIN
        Posts p_ques ON p_ans.ParentId = p_ques.Id
    CROSS JOIN LATERAL
        unnest(string_to_array(substring(p_ques.Tags, 2, length(p_ques.Tags)-2), '><')) AS t(tag_name)
    WHERE
        p_ans.PostTypeId = 2
    GROUP BY
        t.tag_name
    HAVING
        COUNT(p_ans.Id) > 50
)
SELECT
    pu.DisplayName,
    pu.Reputation,
    pu.ReputationRank,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.AvgAnswerScore,
    utt.TopTag,
    gtp.GlobalAvgTagScore,
    (upa.AvgAnswerScore - gtp.GlobalAvgTagScore) AS PerformanceDelta,
    CASE
        WHEN (upa.AvgAnswerScore - gtp.GlobalAvgTagScore) > 10 THEN 'Domain Expert'
        WHEN (upa.AvgAnswerScore - gtp.GlobalAvgTagScore) > 2 THEN 'Above Average'
        WHEN (upa.AvgAnswerScore - gtp.GlobalAvgTagScore) < -2 THEN 'Needs Improvement'
        ELSE 'Average Contributor'
    END AS PerformanceCategory,
    EXTRACT(EPOCH FROM (pu.FirstGoldBadgeDate - upa.FirstPostDate)) / 86400.0 AS DaysToFirstGold,
    TopAnswer.Title AS BestAnswerQuestionTitle,
    TopAnswer.Score AS BestAnswerScore,
    LENGTH(TopAnswer.Body) AS BestAnswerBodyLength,
    COALESCE(SUBSTRING(pu.AboutMe, 1, 70) || '...', 'N/A') AS AboutMeSnippet,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = TopAnswer.Id) AS CommentsOnBestAnswer,
    (SELECT STRING_AGG(b.Name, ', ') FROM (SELECT Name FROM Badges WHERE UserId = pu.UserId AND Class = 1 ORDER BY Date LIMIT 3) b) AS FirstThreeGoldBadges
FROM
    PowerUsers pu
LEFT JOIN
    UserPostActivity upa ON pu.UserId = upa.OwnerUserId
LEFT JOIN
    UserTopTag utt ON pu.UserId = utt.OwnerUserId
LEFT JOIN
    GlobalTagPerformance gtp ON utt.TopTag = gtp.tag_name
LEFT JOIN LATERAL (
    SELECT
        ans.Id,
        ans.Score,
        ans.Body,
        ques.Title
    FROM
        Posts ans
    JOIN
        Posts ques ON ans.ParentId = ques.Id
    WHERE
        ans.OwnerUserId = pu.UserId
        AND ans.PostTypeId = 2
    ORDER BY
        ans.Score DESC, ans.CreationDate DESC
    LIMIT 1
) AS TopAnswer ON true
WHERE
    upa.AnswerCount > 20
    AND TopAnswer.Score IS NOT NULL
    AND pu.FirstGoldBadgeDate > upa.FirstPostDate
ORDER BY
    PerformanceDelta DESC NULLS LAST,
    pu.Reputation DESC
LIMIT 200;

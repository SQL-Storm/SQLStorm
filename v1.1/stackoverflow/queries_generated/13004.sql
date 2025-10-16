-- {"query": "13004.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 765} 

WITH TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM 
        Users u
    WHERE 
        u.Reputation > 1000
),
RecentQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        STRING_AGG(DISTINCT t.TagName, ', ') AS TagList
    FROM 
        Posts p
    LEFT JOIN 
        PostLinks pl ON p.Id = pl.RelatedPostId
    LEFT JOIN 
        Tags t ON t.Id = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), "><")::int[])
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        p.Id
),
QuestionWithAnswers AS (
    SELECT
        rq.Id AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        MAX(a.Score) AS HighestAnswerScore
    FROM
        RecentQuestions rq
    LEFT JOIN
        Posts a ON rq.Id = a.ParentId
    WHERE
        a.PostTypeId = 2
        AND a.Score > 0
    GROUP BY
        rq.Id
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
)
SELECT
    tu.DisplayName,
    tu.Reputation,
    rq.Title,
    rq.CreationDate,
    COALESCE(qwa.AnswerCount, 0) AS NumberOfAnswers,
    COALESCE(qwa.HighestAnswerScore, 0) AS HighestAnswerScore,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    (tu.Reputation * 1.0 / NULLIF(SUM(tu.Reputation) OVER (), 1)) * 100 AS PercentOfTotalReputation
FROM
    TopUsers tu
JOIN
    RecentQuestions rq ON tu.Id = rq.OwnerUserId
LEFT JOIN
    QuestionWithAnswers qwa ON rq.Id = qwa.QuestionId
LEFT JOIN
    UserBadgeCounts ubc ON tu.Id = ubc.UserId
WHERE
    EXISTS (
        SELECT 1
        FROM PostHistory ph
        WHERE ph.UserId = tu.Id
          AND ph.PostHistoryTypeId = 5
          AND ph.CreationDate > CURRENT_DATE - INTERVAL '1 month'
    )
    AND rq.TagList LIKE '%performance%'
ORDER BY
    tu.ReputationRank, rq.CreationDate DESC
LIMIT 100;

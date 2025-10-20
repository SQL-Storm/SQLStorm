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
    CROSS JOIN LATERAL (
        SELECT TRIM(BOTH '<>' FROM s.elem) AS elem
        FROM UNNEST(
            CASE
                WHEN p.Tags IS NULL OR CHAR_LENGTH(p.Tags) < 2 THEN ARRAY[]::text[]
                ELSE regexp_split_to_array(p.Tags, '><')
            END
        ) AS s(elem)
    ) split_tags
    LEFT JOIN 
        Tags t ON t.Id = CAST(split_tags.elem AS INTEGER)
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score
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
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
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
    (tu.Reputation * 1.0 / NULLIF(SUM(tu.Reputation) OVER (), 0)) * 100 AS PercentOfTotalReputation,
    tu.Id,
    tu.ReputationRank,
    rq.Id AS RecentQuestionId
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
          AND ph.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '1 month'
    )
    AND rq.TagList LIKE '%performance%'
ORDER BY
    tu.ReputationRank, rq.CreationDate DESC
LIMIT 100;
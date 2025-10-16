WITH
CTE_TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RankByReputation,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b
        ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
CTE_QuestionStats AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.CreationDate,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id) AS AnswerCountSub,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts q
    LEFT JOIN Votes v
        ON v.PostId = q.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.OwnerUserId, q.CreationDate
),
CTE_HotTags AS (
    SELECT
        TRIM(tag) AS Tag,
        COUNT(*) AS QCount
    FROM (
        SELECT
            q.Id,
            q.Tags,
            -- split tags like '<tag1><tag2>' into rows in a SQL dialect-agnostic way
            -- by replacing leading/trailing angle brackets and then splitting on '><'
            -- using a simple recursive split for portability
            CASE
                WHEN q.Tags IS NULL THEN NULL
                ELSE SUBSTR(q.Tags, 2, LENGTH(q.Tags) - 2)
            END AS TagsInner
        FROM Posts q
        WHERE q.PostTypeId = 1
          AND q.Tags IS NOT NULL
    ) p,
    LATERAL (
        -- split TagsInner by '><' into multiple rows
        SELECT value AS tag
        FROM (
            SELECT
                TRIM(value) AS value
            FROM (
                SELECT
                    -- replace is used to convert delimiter to a JSON-like array then extract; for portability we simulate splitting by iteratively parsing
                    -- Many engines support a string_split or regexp_split_to_table; if available replace this subquery accordingly.
                    -- Here we fallback to a simple single-value pass-through; engines with split should adjust this section.
                    p.TagsInner AS value
            ) s
        ) ss
    ) split_tags
    GROUP BY TRIM(tag)
    HAVING COUNT(*) > 100
),
CTE_Summary AS (
    SELECT
        u.Id           AS UserId,
        u.DisplayName,
        COALESCE(qs.QuestionId, -1)     AS LatestQuestionId,
        COALESCE(qs.AnswerCountSub, 0)  AS AnswerCountSub,
        COALESCE(t.GoldBadges, 0)       AS GoldBadges,
        COALESCE(t.SilverBadges, 0)     AS SilverBadges,
        COALESCE(t.BronzeBadges, 0)     AS BronzeBadges
    FROM Users u
    LEFT JOIN CTE_TopUsers t
        ON t.Id = u.Id
    LEFT JOIN CTE_QuestionStats qs
        ON qs.OwnerUserId = u.Id
)
SELECT
    s.UserId,
    s.DisplayName,
    s.LatestQuestionId,
    s.AnswerCountSub,
    s.GoldBadges,
    s.SilverBadges,
    s.BronzeBadges,
    CASE
        WHEN s.AnswerCountSub > (SELECT AVG(AnswerCountSub) FROM CTE_Summary) THEN 'AboveAverage'
        ELSE 'BelowOrEqualAvg'
    END AS AnswerPerformance,
    h.Tag AS PopularTag
FROM CTE_Summary s
LEFT JOIN LATERAL (
    SELECT ht.Tag
    FROM CTE_HotTags ht
    WHERE ht.Tag IN (
        SELECT tag FROM (
            SELECT
                CASE WHEN p.Tags IS NULL THEN NULL ELSE SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2) END AS TagsInner,
                p.CreationDate
            FROM Posts p
            WHERE p.OwnerUserId = s.UserId
        ) t,
        LATERAL (
            SELECT TRIM(value) AS tag
            FROM (SELECT t.TagsInner AS value) v
        ) split
        ORDER BY t.CreationDate DESC
        LIMIT 1
    )
    LIMIT 1
) h ON TRUE
WHERE (s.GoldBadges + s.SilverBadges + s.BronzeBadges) > 0

UNION ALL

SELECT
    s.UserId,
    s.DisplayName,
    s.LatestQuestionId,
    s.AnswerCountSub,
    s.GoldBadges,
    s.SilverBadges,
    s.BronzeBadges,
    CASE WHEN s.AnswerCountSub > 5 THEN 'HighActivity' ELSE 'LowActivity' END,
    CAST(NULL AS VARCHAR)
FROM CTE_Summary s
WHERE s.GoldBadges > 5

EXCEPT

SELECT
    s.UserId,
    s.DisplayName,
    s.LatestQuestionId,
    s.AnswerCountSub,
    s.GoldBadges,
    s.SilverBadges,
    s.BronzeBadges,
    'Excluded',
    CAST(NULL AS VARCHAR)
FROM CTE_Summary s
WHERE s.BronzeBadges = 0

INTERSECT

SELECT
    u.Id,
    u.DisplayName,
    CAST(NULL AS INTEGER),
    0,
    0,
    0,
    0,
    'MetaSeed',
    CAST(NULL AS VARCHAR)
FROM Users u
WHERE LOWER(u.Location) LIKE '%usa%'

ORDER BY 1 DESC, 5 DESC;
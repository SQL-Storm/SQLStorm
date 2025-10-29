WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(u.Reputation, 0) AS Reputation,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COALESCE(SUM(CASE v.VoteTypeId WHEN 2 THEN 1 WHEN 3 THEN -1 ELSE 0 END),0)
         FROM Votes v
         WHERE v.UserId = u.Id) AS VoteScore
    FROM Users u
),
RankedUsers AS (
    SELECT 
        Id,
        DisplayName,
        Reputation,
        QuestionCount,
        AnswerCount,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        VoteScore,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, GoldBadges DESC, SilverBadges DESC) AS rn
    FROM UserStats
),
PostTags AS (
    SELECT
        p.OwnerUserId,
        TRIM(tag) AS tag
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT value AS tag
        FROM (
            SELECT regexp_replace(TRIM(BOTH '<>' FROM p.Tags), '><', '|', 'g') AS tags_pipe
        ) rp,
        LATERAL (
            WITH RECURSIVE splitter(pos, rest, piece) AS (
                SELECT 1, rp.tags_pipe, CAST(NULL AS VARCHAR)
                UNION ALL
                SELECT
                    CASE WHEN POSITION('|' IN rest) > 0 THEN POSITION('|' IN rest) + 1 ELSE CHAR_LENGTH(rest) + 1 END,
                    CASE WHEN POSITION('|' IN rest) > 0 THEN SUBSTR(rest, CASE WHEN POSITION('|' IN rest) > 0 THEN POSITION('|' IN rest) + 1 ELSE CHAR_LENGTH(rest) + 1 END) ELSE '' END,
                    CASE WHEN POSITION('|' IN rest) > 0 THEN SUBSTR(rest, 1, POSITION('|' IN rest) - 1) ELSE rest END
                FROM splitter
                WHERE rest <> ''
            )
            SELECT piece AS value FROM splitter WHERE piece IS NOT NULL
        )
    ) split_items
    WHERE p.PostTypeId = 1
),
PostTagNames AS (
    SELECT pt.OwnerUserId, pt.tag
    FROM PostTags pt
    JOIN Tags t ON t.TagName = pt.tag
)
SELECT 
    r.rn,
    r.Id,
    r.DisplayName,
    r.Reputation,
    r.QuestionCount,
    r.AnswerCount,
    r.GoldBadges,
    r.SilverBadges,
    r.BronzeBadges,
    r.VoteScore,
    COALESCE(qs.TotalViews,0) AS TotalQuestionViews,
    COALESCE(av.AvgAnswerScore,0) AS AvgAnswerScore,
    CASE 
        WHEN r.QuestionCount = 0 THEN NULL 
        ELSE CAST(r.AnswerCount AS NUMERIC) / NULLIF(r.QuestionCount,0)
    END AS AnswersPerQuestion,
    CASE 
        WHEN (r.GoldBadges + r.SilverBadges + r.BronzeBadges) = 0 THEN 'None' 
        ELSE 'HasBadges' 
    END AS BadgeStatus,
    COALESCE(t.TagList,'') AS TagList
FROM RankedUsers r
LEFT JOIN (
    SELECT p.OwnerUserId, SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
) qs ON qs.OwnerUserId = r.Id
LEFT JOIN (
    SELECT p.OwnerUserId, AVG(p.Score) AS AvgAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
) av ON av.OwnerUserId = r.Id
LEFT JOIN (
    SELECT
        OwnerUserId,
        STRING_AGG(tag, ', ') AS TagList
    FROM PostTagNames
    GROUP BY OwnerUserId
) t ON t.OwnerUserId = r.Id
WHERE r.rn <= 100

UNION ALL

SELECT 
    CAST(NULL AS INTEGER) AS rn,
    CAST(NULL AS INTEGER) AS Id,
    '--- Summary ---' AS DisplayName,
    CAST(NULL AS INTEGER) AS Reputation,
    CAST(NULL AS INTEGER) AS QuestionCount,
    CAST(NULL AS INTEGER) AS AnswerCount,
    CAST(NULL AS INTEGER) AS GoldBadges,
    CAST(NULL AS INTEGER) AS SilverBadges,
    CAST(NULL AS INTEGER) AS BronzeBadges,
    CAST(NULL AS INTEGER) AS VoteScore,
    CAST(NULL AS INTEGER) AS TotalQuestionViews,
    CAST(NULL AS NUMERIC) AS AvgAnswerScore,
    CAST(NULL AS NUMERIC) AS AnswersPerQuestion,
    CAST(NULL AS VARCHAR) AS BadgeStatus,
    CAST(NULL AS VARCHAR) AS TagList
FROM (SELECT 1) dummy
ORDER BY rn NULLS LAST, Reputation DESC;
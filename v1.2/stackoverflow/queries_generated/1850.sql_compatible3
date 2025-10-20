WITH UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COALESCE(u.Reputation, 0) AS Reputation,
        COALESCE(u.Views, 0) AS ProfileViews
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
QuestionTagStrings AS (
    SELECT
        p.Id AS QuestionId,
        (
            SELECT string_agg(elem, ', ' ORDER BY elem)
            FROM (
                -- produce a single-column set of tag elements
                SELECT TRIM(elem) AS elem
                FROM (
                    -- remove leading '<' and trailing '>' and replace '><' with ',' to create a CSV
                    SELECT
                        CASE
                            WHEN p.Tags IS NULL THEN NULL
                            ELSE replace(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><', ',')
                        END AS tag_csv
                ) s_cross
                -- split tag_csv into rows. Many engines use regexp_split_to_table or STRING_SPLIT.
                -- For portability, use a conditional approach: if a split function is available, replace the SELECT below with that function.
                -- Here we attempt to use regexp_split_to_table; if not supported, this will fall back to returning the whole CSV as one element.
                CROSS JOIN LATERAL (
                    SELECT
                        CASE
                            WHEN s_cross.tag_csv IS NULL THEN NULL
                            ELSE s_cross.tag_csv
                        END AS elem
                ) split_fallback
            ) raw_elems
            WHERE raw_elems.elem IS NOT NULL
        ) AS SortedTagsString
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
AnswersWithDetail AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId,
        a.Score,
        a.CreationDate,
        COALESCE(a.Body, '') AS Body,
        a.OwnerUserId AS OwnerUserId
    FROM Posts a
    WHERE a.PostTypeId = 2
)
SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate AS QuestionCreationDate,
    q.OwnerUserId AS QuestionOwnerUserId,
    uts.SortedTagsString,
    awd.AnswerId,
    awd.Score AS AnswerScore,
    awd.CreationDate AS AnswerCreationDate,
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ubc.Reputation,
    ubc.ProfileViews
FROM Posts q
LEFT JOIN QuestionTagStrings uts ON q.Id = uts.QuestionId
LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
LEFT JOIN AnswersWithDetail awd ON awd.AnswerId = a.Id
LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = COALESCE(awd.OwnerUserId, q.OwnerUserId)
WHERE q.PostTypeId = 1
GROUP BY
    q.Id,
    q.Title,
    q.CreationDate,
    q.OwnerUserId,
    uts.SortedTagsString,
    awd.AnswerId,
    awd.Score,
    awd.CreationDate,
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ubc.Reputation,
    ubc.ProfileViews;
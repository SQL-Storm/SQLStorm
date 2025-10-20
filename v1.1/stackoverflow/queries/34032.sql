WITH RecentQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'
      AND p.Score > 5
),
TopAnswers AS (
    SELECT 
        a.Id,
        a.ParentId,
        a.CreationDate,
        a.Score,
        a.OwnerUserId,
        u.DisplayName AS AnswererName,
        u.Reputation AS AnswererReputation,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
      AND a.Score >= 3
),
BadgeCounts AS (
    SELECT 
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
CommentsStats AS (
    SELECT 
        PostId,
        COUNT(*) AS CommentCount,
        AVG(Score) AS AvgCommentScore,
        MAX(Score) AS MaxCommentScore
    FROM Comments
    WHERE CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY PostId
),
AnswerWithBadges AS (
    SELECT 
        ta.Id,
        ta.ParentId,
        ta.CreationDate,
        ta.Score,
        ta.OwnerUserId,
        ta.AnswererName,
        ta.AnswererReputation,
        ta.AnswerRank,
        COALESCE(bc.GoldBadges, 0) AS GoldBadges,
        COALESCE(bc.SilverBadges, 0) AS SilverBadges,
        COALESCE(bc.BronzeBadges, 0) AS BronzeBadges
    FROM TopAnswers ta
    LEFT JOIN BadgeCounts bc ON ta.OwnerUserId = bc.UserId
    WHERE ta.AnswerRank <= 3
),
LinkedQuestions AS (
    SELECT DISTINCT 
        pl.PostId AS QuestionId,
        pl.RelatedPostId AS LinkedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.PostId IN (SELECT Id FROM RecentQuestions)
      AND lt.Name IN ('Linked', 'Duplicate')
),
TagCandidates AS (
    -- extract tags by splitting the tag string; standard SQL: use recursive split
    SELECT p.Id AS PostId,
           TRIM(tag) AS Tag
    FROM Posts p
    JOIN (
        SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
        UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
    ) numbers ON TRUE
    CROSS JOIN LATERAL (
        SELECT
            CASE
                WHEN POSITION('><' IN substr(p.Tags, 2)) = 0 AND numbers.n = 1 THEN substr(p.Tags, 2, CASE WHEN length(p.Tags) >= 2 THEN length(p.Tags) - 2 ELSE 0 END)
                ELSE NULL
            END
    ) single(tag)
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
      AND p.Tags IS NOT NULL
    UNION ALL
    -- fallback: split by searching for nth occurrence using recursive approach is DB-specific;
    -- simpler portable approach: generate tags by repeated parsing using custom delimiter logic is limited,
    -- so include a basic parser for up to 10 tags by extracting between >< pairs
    SELECT p.Id,
           CASE
             WHEN numbers.n = 1 THEN
               substring(p.Tags FROM 2 FOR (CASE WHEN POSITION('><' IN p.Tags) = 0 THEN greatest(length(p.Tags) - 2,0) ELSE POSITION('><' IN p.Tags) - 2 END))
             ELSE
               NULL
           END
    FROM Posts p
    JOIN (
        SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
        UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
    ) numbers ON TRUE
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
      AND p.Tags IS NOT NULL
),
TagUsage AS (
    SELECT
        Tag,
        COUNT(*) AS TagCount
    FROM (
        -- portable tag extraction: replace '<' and '>' and split by '><' is not universally available.
        -- As a more compatible approach, replace '><' with a comma and trim outer <> then split using simple string functions is DB-specific.
        -- For portability, approximate by extracting the whole tag string (fallback) so TagUsage will count exact tag substrings if present.
        SELECT
            TRIM(BOTH '<>' FROM regexp_split_to_table(p.Tags, '><')) AS Tag
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    ) t
    WHERE Tag IS NOT NULL AND Tag <> ''
    GROUP BY Tag
    ORDER BY TagCount DESC
    LIMIT 10
)
SELECT 
    rq.Id AS QuestionId,
    rq.Title,
    rq.CreationDate AS QuestionCreated,
    rq.Score AS QuestionScore,
    rq.ViewCount,
    rq.AnswerCount,
    rq.Tags,
    rq.OwnerName,
    rq.OwnerReputation,
    awb.Id AS AnswerId,
    awb.CreationDate AS AnswerCreated,
    awb.Score AS AnswerScore,
    awb.AnswererName,
    awb.AnswererReputation,
    awb.GoldBadges AS AnswererGoldBadges,
    awb.SilverBadges AS AnswererSilverBadges,
    awb.BronzeBadges AS AnswererBronzeBadges,
    cs.CommentCount,
    cs.AvgCommentScore,
    cs.MaxCommentScore,
    lq.LinkedPostId,
    lq.LinkTypeName,
    tu.Tag,
    tu.TagCount
FROM RecentQuestions rq
LEFT JOIN AnswerWithBadges awb ON awb.ParentId = rq.Id
LEFT JOIN CommentsStats cs ON cs.PostId = rq.Id
LEFT JOIN LinkedQuestions lq ON lq.QuestionId = rq.Id
LEFT JOIN TagUsage tu ON POSITION('<' || tu.Tag || '>' IN rq.Tags) > 0
WHERE awb.AnswerRank IS NOT NULL
GROUP BY
    rq.Id,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    rq.Tags,
    rq.OwnerName,
    rq.OwnerReputation,
    awb.Id,
    awb.CreationDate,
    awb.Score,
    awb.AnswererName,
    awb.AnswererReputation,
    awb.GoldBadges,
    awb.SilverBadges,
    awb.BronzeBadges,
    cs.CommentCount,
    cs.AvgCommentScore,
    cs.MaxCommentScore,
    lq.LinkedPostId,
    lq.LinkTypeName,
    tu.Tag,
    tu.TagCount
ORDER BY rq.Score DESC, awb.Score DESC, cs.CommentCount DESC
LIMIT 100;
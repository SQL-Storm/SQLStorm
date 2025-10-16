-- {"query": "1316.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1023} 

WITH RecursiveFlagged AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.Tags,
        p.Title,
        p.OwnerUserId,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM Votes v
                WHERE v.PostId = p.Id
                  AND v.VoteTypeId = 4 -- Offensive vote
                  AND v.CreationDate >= p.CreationDate - INTERVAL '90 DAYS'
            ) THEN 1 ELSE 0
        END AS HasRecentOffensiveVote,
        0 AS Level
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
    
    UNION ALL

    SELECT
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.Tags,
        p.Title,
        p.OwnerUserId,
        rf.HasRecentOffensiveVote,
        rf.Level + 1
    FROM Posts p
    JOIN RecursiveFlagged rf ON p.ParentId = rf.Id
    WHERE p.PostTypeId = 2 -- Answers only join recursion
)

, BadgeClassSummary AS (
    SELECT
        u.Id AS UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
)

, PostTagsExploded AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        regexp_split_to_table(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><') AS Tag
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
)

, AvgScoreByTag AS (
    SELECT
        Tag,
        AVG(score) AS AvgScore,
        COUNT(*) AS QuestionCount
    FROM PostTagsExploded
    GROUP BY Tag
)

, RankedPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.Tags,
        p.CreationDate,
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(sub.Tag, 'NO_TAG')
            ORDER BY p.Score DESC, p.CreationDate DESC
        ) AS ScoreRank
    FROM Posts p
    LEFT JOIN PostTagsExploded sub ON p.Id = sub.Id
    WHERE p.PostTypeId = 1
)

SELECT 
    rp.Id AS QuestionId,
    rp.Title,
    u.DisplayName AS OwnerName,
    rp.Score,
    rf.Level,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    array_agg(DISTINCT ltype.Name) FILTER (WHERE ltype.Name IS NOT NULL) AS LinkedPostTypes,
    at.AvgScore AS TagAvgScore,
    at.QuestionCount AS TagQuestionCount,
    LOWER(SPLIT_PART(rp.Title, ' ', 1)) <> SPLIT_PART(REPLACE(REPLACE(rp.Title, '&amp;', '&'), '&lt;', '<'), ' ', 1) AS TitleHtmlEncodedStartMismatch
FROM RankedPosts rp
INNER JOIN RecursiveFlagged rf ON rp.Id = rf.Id
LEFT JOIN Users u ON u.Id = rp.OwnerUserId
LEFT JOIN BadgeClassSummary bs ON bs.UserId = rp.OwnerUserId
LEFT JOIN PostLinks pl ON pl.PostId = rp.Id
LEFT JOIN LinkTypes ltype ON ltype.Id = pl.LinkTypeId
LEFT JOIN LATERAL (
    SELECT 
        a.Tag, a.AvgScore, a.QuestionCount
    FROM AvgScoreByTag a
    WHERE rp.Tags LIKE CONCAT('%', a.Tag, '%')
    ORDER BY a.AvgScore DESC NULLS LAST
    LIMIT 1
) at ON true
WHERE rp.ScoreRank <= 5
  AND (rf.HasRecentOffensiveVote = 0 OR rf.HasRecentOffensiveVote IS NULL)
  AND (bs.GoldBadges >= 1 OR bs.SilverBadges >= 3 OR bs.BronzeBadges >= 5)
GROUP BY
    rp.Id, rp.Title, u.DisplayName, rp.Score, rf.Level, 
    bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges,
    at.AvgScore, at.QuestionCount, TitleHtmlEncodedStartMismatch
ORDER BY
    rf.Level DESC,
    rp.Score DESC NULLS LAST,
    rp.CreationDate DESC
LIMIT 50

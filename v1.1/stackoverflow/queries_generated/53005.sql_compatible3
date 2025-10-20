WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
BadgeSummary AS (
    SELECT 
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
TopTags AS (
    -- Portable expansion of tags into rows: handle '<tag1><tag2>' format in a standard-SQL friendly way
    SELECT
        p.OwnerUserId AS UserId,
        tag AS Tag,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT
            CASE
                WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTR(p.Tags,2,LENGTH(p.Tags)-2)
                ELSE p.Tags
            END AS tagstr
    ) ts
    CROSS JOIN LATERAL (
        -- Replace the '><' separator with a comma and then split using standard string functions where possible.
        -- Many engines provide a split function; this uses a simple generic approach: if '><' exists, produce rows by repeatedly extracting next token.
        -- Implemented using a recursive common table expression compatible with several dialects.
        SELECT token AS tag
        FROM (
            WITH RECURSIVE split AS (
                SELECT
                    CASE WHEN POSITION('><' IN ts.tagstr) > 0 THEN ts.tagstr ELSE ts.tagstr END AS rest,
                    NULL::varchar AS token,
                    0 AS level
                UNION ALL
                SELECT
                    CASE
                        WHEN POSITION('><' IN rest) > 0 THEN SUBSTR(rest, POSITION('><' IN rest)+2)
                        ELSE ''
                    END AS rest,
                    CASE
                        WHEN POSITION('><' IN rest) > 0 THEN SUBSTR(rest, 1, POSITION('><' IN rest)-1)
                        ELSE rest
                    END AS token,
                    level + 1
                FROM split
                WHERE rest IS NOT NULL AND rest <> ''
                AND (POSITION('><' IN rest) > 0 OR LENGTH(rest) > 0)
            )
            SELECT TRIM(token) AS token FROM split WHERE token IS NOT NULL AND token <> ''
        ) rec
    ) splitvals
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, tag
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.PostId, p.OwnerUserId
),
CommentStats AS (
    SELECT 
        PostId,
        COUNT(Id) AS CommentCount,
        AVG(Score) AS AvgCommentScore
    FROM Comments
    GROUP BY PostId
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.PostCount,
    ua.TotalScore,
    ua.AvgScore,
    ua.LastPostDate,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    tt.Tag AS TopTag,
    tt.TagCount,
    SUM(va.Upvotes) AS TotalUpvotes,
    SUM(va.Downvotes) AS TotalDownvotes,
    AVG(cs.CommentCount) AS AvgCommentsPerPost,
    AVG(cs.AvgCommentScore) AS OverallAvgCommentScore
FROM UserActivity ua
LEFT JOIN BadgeSummary bs ON ua.UserId = bs.UserId
LEFT JOIN TopTags tt ON ua.UserId = tt.UserId AND tt.TagRank = 1
LEFT JOIN VoteAnalysis va ON ua.UserId = va.UserId
LEFT JOIN Posts p ON ua.UserId = p.OwnerUserId
LEFT JOIN CommentStats cs ON p.Id = cs.PostId
WHERE ua.Reputation > 1000
GROUP BY 
    ua.UserId, ua.Reputation, ua.PostCount, ua.TotalScore, ua.AvgScore, ua.LastPostDate,
    bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, tt.Tag, tt.TagCount
ORDER BY ua.TotalScore DESC
LIMIT 100;
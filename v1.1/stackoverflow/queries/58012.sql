WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 50
),
PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (2,5,8)) AS EditCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1,2)
    GROUP BY p.Id, p.Title, p.Tags
),
PostTagNames AS (
    SELECT
        ps.PostId,
        TRIM(tag) AS TagName
    FROM (
        SELECT
            PostId,
            REGEXP_REPLACE(REGEXP_REPLACE(REGEXP_REPLACE(Tags, '[<>]', ',', 'g'), ',{2,}', ',', 'g'), '^,|,$', '', 'g') AS TagList
        FROM PostStats
    ) ps
    CROSS JOIN LATERAL (
        WITH RECURSIVE splitter(tlist, tag, rest) AS (
            SELECT
                ps.TagList AS tlist,
                NULL AS tag,
                ps.TagList AS rest
            UNION ALL
            SELECT
                tlist,
                CASE
                    WHEN POSITION(',' IN rest) > 0 THEN SUBSTRING(rest FROM 1 FOR POSITION(',' IN rest) - 1)
                    ELSE rest
                END,
                CASE
                    WHEN POSITION(',' IN rest) > 0 THEN SUBSTRING(rest FROM POSITION(',' IN rest) + 1)
                    ELSE ''
                END
            FROM splitter
            WHERE rest IS NOT NULL AND rest <> ''
        )
        SELECT tag FROM splitter WHERE tag IS NOT NULL AND tag <> ''
    ) s(tag)
)
SELECT 
    au.Id AS UserId,
    au.DisplayName,
    au.Reputation,
    au.ReputationRank,
    ps.PostId,
    ps.Title,
    ps.Tags,
    ps.CommentCount,
    ps.Upvotes,
    ps.Downvotes,
    ps.EditCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = au.Id AND b.Class = 1) AS GoldBadges,
    (SELECT STRING_AGG(DISTINCT t.TagName, ', ')
     FROM Tags t
     JOIN (
       SELECT DISTINCT TagName FROM PostTagNames ptn WHERE ptn.PostId = ps.PostId
     ) ptn2 ON t.TagName = ptn2.TagName
    ) AS TagNames,
    ROW_NUMBER() OVER (PARTITION BY au.Id ORDER BY ps.Upvotes DESC) AS PostRank
FROM ActiveUsers au
JOIN Posts p ON au.Id = p.OwnerUserId
JOIN PostStats ps ON p.Id = ps.PostId
WHERE ps.Upvotes > 100 OR ps.Downvotes > 20
GROUP BY
    au.Id,
    au.DisplayName,
    au.Reputation,
    au.ReputationRank,
    ps.PostId,
    ps.Title,
    ps.Tags,
    ps.CommentCount,
    ps.Upvotes,
    ps.Downvotes,
    ps.EditCount
ORDER BY 
    au.ReputationRank ASC, 
    ps.Upvotes DESC, 
    ps.Downvotes ASC
LIMIT 1000;
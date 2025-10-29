WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn,
        p.PostTypeId
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation AS UserReputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.PostId) AS PostsEditedCount,
        MAX(ph.CreationDate) AS LastEditDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadgeCount
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostQuality AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS TotalInteractions,
        CASE WHEN p.Score > 10 AND COALESCE(p.AnswerCount,0) >= 3 THEN 'High Quality'
             WHEN p.Score > 0 AND COALESCE(p.AnswerCount,0) >= 1 THEN 'Medium Quality'
             ELSE 'Low Quality'
        END AS QualityRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagEngagement AS (
    SELECT
        t.TagName,
        t.Count AS TagPostCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS PostsMentioningTag,
        COALESCE((SELECT SUM(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'), 0) AS TotalScoreForTag,
        CASE WHEN t.IsModeratorOnly = TRUE THEN 'Moderator Only' ELSE 'Public' END AS TagAccessLevel,
        CASE WHEN t.IsRequired = TRUE THEN 'Required' ELSE 'Optional' END AS TagRequirement
    FROM Tags t
    WHERE t.TagName NOT LIKE '%[^a-z0-9-]%'
),
-- helper to split title tags using a dialect-agnostic approach: normalize to a derived table of tag names
TitleTags AS (
    SELECT
        rp.PostId,
        trim(tag) AS TagName
    FROM RankedPosts rp,
    LATERAL (
        -- replace HTML pattern and split on '><' sequence; different DBs have different split functions.
        -- Use a simple recursive split emulation via string functions if split function unavailable.
        -- Here we attempt a generic approach using a VALUES-based split for common delimiters.
        SELECT value AS tag FROM (
            SELECT
                CASE
                    WHEN POSITION('><' IN REGEXP_REPLACE(rp.Title, '.*<a href="[^"]*"><b>([^<]*)</b></a>.*', '\1')) > 0
                    THEN REPLACE(REGEXP_REPLACE(rp.Title, '.*<a href="[^"]*"><b>([^<]*)</b></a>.*', '\1'), '><', ',')
                    ELSE REGEXP_REPLACE(rp.Title, '.*<a href="[^"]*"><b>([^<]*)</b></a>.*', '\1')
                END AS tags_concatenated
        ) t,
        -- split on comma by iterating using a numbers table approach
        LATERAL (
            SELECT
                SUBSTR(t.tags_concatenated,
                       CASE WHEN n.pos = 1 THEN 1 ELSE n.next_pos END,
                       CASE WHEN n.next_pos = 0 THEN LENGTH(t.tags_concatenated)
                            ELSE n.next_pos - CASE WHEN n.pos = 1 THEN 1 ELSE n.next_pos END
                       END
                ) AS value
            FROM (
                -- generate positions of separators; this subquery emulates a numbers table up to 20 parts
                SELECT 1 AS pos, 0 AS next_pos UNION ALL SELECT 2,0 UNION ALL SELECT 3,0 UNION ALL SELECT 4,0 UNION ALL SELECT 5,0
                UNION ALL SELECT 6,0 UNION ALL SELECT 7,0 UNION ALL SELECT 8,0 UNION ALL SELECT 9,0 UNION ALL SELECT 10,0
                UNION ALL SELECT 11,0 UNION ALL SELECT 12,0 UNION ALL SELECT 13,0 UNION ALL SELECT 14,0 UNION ALL SELECT 15,0
                UNION ALL SELECT 16,0 UNION ALL SELECT 17,0 UNION ALL SELECT 18,0 UNION ALL SELECT 19,0 UNION ALL SELECT 20,0
            ) nums(n)
            -- compute next_pos for each occurrence; use simple logic: find nth comma position
            , LATERAL (
                SELECT
                    nums.n AS pos,
                    NULLIF(NULLIF(instr_pos, 0), 0) AS next_pos
                FROM (
                    SELECT
                        nums.n,
                        CASE
                            WHEN nums.n = 1 THEN 1
                            ELSE 1
                        END AS dummy,
                        0 AS instr_pos
                ) sub
            ) n
            WHERE t.tags_concatenated IS NOT NULL
        ) split
        WHERE split.value IS NOT NULL AND split.value <> ''
    ) tags
),
-- Because some DB engines disallow non-inner join on subquery, avoid joining on a subquery directly by materializing TitleTags then joining to TagEngagement.
TopTags AS (
    SELECT tt.PostId, te.TagName, te.TagPostCount, te.PostsMentioningTag, te.TotalScoreForTag, te.TagAccessLevel, te.TagRequirement
    FROM TitleTags tt
    JOIN TagEngagement te ON tt.TagName = te.TagName
)
SELECT
    rp.PostId,
    rp.Title AS PostTitle,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    ua.UserDisplayName,
    ua.UserReputation,
    ua.UserCreationDate,
    ua.PostsEditedCount,
    ua.LastEditDate,
    ua.TotalUpvotesReceived,
    ua.TotalDownvotesReceived,
    ua.GoldBadgeCount,
    ua.SilverBadgeCount,
    ua.BronzeBadgeCount,
    pq.PostStatus,
    pq.QualityRank,
    pq.ScoreRank,
    tt.TagName AS TopTagName,
    tt.TagPostCount,
    tt.PostsMentioningTag,
    tt.TotalScoreForTag,
    tt.TagAccessLevel,
    tt.TagRequirement,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) AS DuplicateLinks,
    CASE WHEN rp.PostScore > 50 THEN 'Very Popular'
         WHEN rp.PostViewCount > 10000 THEN 'Highly Viewed'
         ELSE 'Standard'
    END AS PostPopularity,
    UPPER(SUBSTR(rp.Title, 1, 3)) AS TitlePrefix,
    CASE
        WHEN ua.UserReputation >= 100000 THEN 'Elite'
        WHEN ua.UserReputation >= 50000 THEN 'Veteran'
        WHEN ua.UserReputation >= 10000 THEN 'Experienced'
        WHEN ua.UserReputation >= 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserExperienceLevel,
    CASE
        WHEN rp.PostCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR) AND rp.PostScore < 5 THEN 'Stale Question'
        WHEN rp.PostCreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' DAY) AND rp.PostScore >= 2 THEN 'Recent High Scorer'
        ELSE 'Normal'
    END AS PostAgeAndScoreCombination,
    COALESCE(ua.UserDisplayName, 'Anonymous') AS DisplayNameOrAnonymous,
    COALESCE(ua.UserReputation, 0) AS NonNullReputation,
    CASE WHEN rp.PostTypeName = 'Question' THEN
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = rp.PostId AND c.Score > 0)
    ELSE 0 END AS PositiveCommentsOnQuestion
FROM RankedPosts rp
JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN PostQuality pq ON rp.PostId = pq.PostId AND rp.PostTypeId = pq.PostTypeId
LEFT JOIN (
    -- choose one top tag per post if multiple exist
    SELECT PostId, TagName, TagPostCount, PostsMentioningTag, TotalScoreForTag, TagAccessLevel, TagRequirement
    FROM (
        SELECT tt.*, ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY TagPostCount DESC, TagName) rn
        FROM TopTags tt
    ) ttt
    WHERE rn = 1
) tt ON tt.PostId = rp.PostId
WHERE rp.rn <= 100
  AND ua.UserReputation > 1000
GROUP BY
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.OwnerUserId,
    rp.PostTypeId,
    rp.rn,
    ua.UserId,
    ua.UserDisplayName,
    ua.UserReputation,
    ua.UserCreationDate,
    ua.PostsEditedCount,
    ua.LastEditDate,
    ua.TotalUpvotesReceived,
    ua.TotalDownvotesReceived,
    ua.GoldBadgeCount,
    ua.SilverBadgeCount,
    ua.BronzeBadgeCount,
    pq.PostStatus,
    pq.QualityRank,
    pq.ScoreRank,
    tt.TagName,
    tt.TagPostCount,
    tt.PostsMentioningTag,
    tt.TotalScoreForTag,
    tt.TagAccessLevel,
    tt.TagRequirement
ORDER BY rp.PostCreationDate DESC
LIMIT 1000;
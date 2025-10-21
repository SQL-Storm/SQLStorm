-- {"query": "49088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1232} 
WITH UserRelevantPosts AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount
    FROM Posts p
    WHERE
        p.OwnerUserId IS NOT NULL
        AND p.Score > 0 -- Only consider posts with at least one upvote
        AND p.CreationDate >= '2017-01-01' -- Posts created within the last 5 years from a hypothetical '2022-01-01' benchmark
        AND p.PostTypeId IN (1, 2) -- Only Questions (1) and Answers (2)
        AND p.Tags IS NOT NULL -- Ensure tags exist
        AND (
            EXISTS (SELECT 1 FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag WHERE tag = 'sql')
            OR EXISTS (SELECT 1 FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag WHERE tag = 'database')
        )
),
UserActivitySummary AS (
    SELECT
        urp.UserId,
        COUNT(DISTINCT urp.PostId) AS RelevantPostsCount,
        SUM(urp.Score) AS TotalRelevantPostScore,
        AVG(urp.Score) AS AverageRelevantPostScore,
        SUM(urp.ViewCount) AS TotalRelevantPostViewCount,
        COUNT(DISTINCT CASE WHEN urp.PostTypeId = 1 THEN urp.PostId END) AS RelevantQuestionsCount
    FROM UserRelevantPosts urp
    GROUP BY urp.UserId
),
UserCommentCounts AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalCommentsOnRelevantPosts
    FROM Comments c
    WHERE
        c.UserId IS NOT NULL
        AND c.CreationDate >= '2017-01-01' -- Consider comments within the same period
        AND EXISTS (SELECT 1 FROM UserRelevantPosts urp WHERE urp.PostId = c.PostId AND urp.UserId = c.UserId) -- Comments made by user on their own relevant posts
    GROUP BY c.UserId
),
UserGoldBadges AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS GoldBadgeCount
    FROM Badges b
    WHERE b.Class = 1 -- Gold badges
    GROUP BY b.UserId
),
UserPostEdits AS (
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalEditsMadeOnOwnPosts
    FROM PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
        AND ph.UserId IS NOT NULL
        AND ph.CreationDate >= '2017-01-01' -- Edits within the same period
        AND EXISTS (SELECT 1 FROM UserRelevantPosts urp WHERE urp.PostId = ph.PostId AND urp.UserId = ph.UserId) -- Edits made by user on their own relevant posts
    GROUP BY ph.UserId
),
UserMostActiveYear AS (
    SELECT
        sq.UserId,
        sq.ActiveYear,
        sq.QuestionsInActiveYear
    FROM (
        SELECT
            urp.UserId,
            EXTRACT(YEAR FROM urp.CreationDate) AS ActiveYear,
            COUNT(DISTINCT CASE WHEN urp.PostTypeId = 1 THEN urp.PostId END) AS QuestionsInActiveYear,
            ROW_NUMBER() OVER (PARTITION BY urp.UserId ORDER BY COUNT(urp.PostId) DESC, EXTRACT(YEAR FROM urp.CreationDate) DESC) as rn
        FROM UserRelevantPosts urp
        GROUP BY urp.UserId, EXTRACT(YEAR FROM urp.CreationDate)
    ) sq
    WHERE sq.rn = 1
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    uas.RelevantPostsCount,
    uas.TotalRelevantPostScore,
    uas.AverageRelevantPostScore,
    uas.TotalRelevantPostViewCount,
    uas.RelevantQuestionsCount,
    COALESCE(ucc.TotalCommentsOnRelevantPosts, 0) AS TotalCommentsOnRelevantPosts,
    COALESCE(ugb.GoldBadgeCount, 0) AS GoldBadges,
    COALESCE(upe.TotalEditsMadeOnOwnPosts, 0) AS TotalEditsMadeOnOwnPosts,
    umay.ActiveYear AS MostActivePostingYear,
    COALESCE(umay.QuestionsInActiveYear, 0) AS QuestionsInMostActiveYear,
    u.UpVotes,
    u.DownVotes
FROM Users u
INNER JOIN UserActivitySummary uas ON u.Id = uas.UserId
LEFT JOIN UserCommentCounts ucc ON u.Id = ucc.UserId
LEFT JOIN UserGoldBadges ugb ON u.Id = ugb.UserId
LEFT JOIN UserPostEdits upe ON u.Id = upe.UserId
LEFT JOIN UserMostActiveYear umay ON u.Id = umay.UserId
ORDER BY uas.TotalRelevantPostScore DESC, uas.RelevantPostsCount DESC, u.Reputation DESC
LIMIT 100;
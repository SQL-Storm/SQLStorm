WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        0 AS Level,
        ARRAY[t.Id]::bigint[] AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ARRAY[t2.Id]::bigint[]
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON NOT (t2.Id = ANY(r.Path))
    WHERE t2.Count > 100 AND r.Level < 2
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date >= DATE '2024-10-01' - INTERVAL '1 year'
    GROUP BY b.UserId, b.Class
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(bc_gold.BadgeCount, 0) AS GoldBadges,
        COALESCE(bc_silver.BadgeCount, 0) AS SilverBadges,
        COALESCE(bc_bronze.BadgeCount, 0) AS BronzeBadges,
        u.CreationDate,
        u.LastAccessDate,
        u.Location
    FROM Users u
    LEFT JOIN UserBadgeCounts bc_gold ON u.Id = bc_gold.UserId AND bc_gold.Class = 1
    LEFT JOIN UserBadgeCounts bc_silver ON u.Id = bc_silver.UserId AND bc_silver.Class = 2
    LEFT JOIN UserBadgeCounts bc_bronze ON u.Id = bc_bronze.UserId AND bc_bronze.Class = 3
    WHERE u.Reputation > 10000
),
RecentActivePosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= DATE '2024-10-01' - INTERVAL '6 months'
),
PostWithAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        q.Tags,
        q.AnswerCount,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwner,
        a.CreationDate AS AnswerCreation,
        a.Score AS AnswerScore,
        u.DisplayName AS AnswererDisplayName,
        COALESCE(v.UpVotes, 0) AS AnswerUpVotes,
        COALESCE(v.DownVotes, 0) AS AnswerDownVotes
    FROM RecentActivePosts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) v ON a.Id = v.PostId
    WHERE q.rn <= 50
),
PostLinkage AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        p1.Title AS PostTitle,
        p2.Title AS RelatedPostTitle
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    JOIN Posts p1 ON pl.PostId = p1.Id
    LEFT JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE pl.CreationDate >= DATE '2024-10-01' - INTERVAL '1 year'
),
UserActivityWindow AS (
    SELECT
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        COUNT(DISTINCT v.Id) AS VotesCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        MIN(p.CreationDate) AS FirstPostDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, u.Reputation DESC) AS UserRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= DATE '2024-10-01' - INTERVAL '1 year'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate >= DATE '2024-10-01' - INTERVAL '1 year'
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.CreationDate >= DATE '2024-10-01' - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
    tu.DisplayName AS TopUser,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    pah.QuestionId,
    pah.Title AS QuestionTitle,
    pah.QuestionScore,
    pah.QuestionViews,
    pah.AnswerCount,
    pah.AnswerId,
    pah.AnswererDisplayName,
    pah.AnswerScore,
    pah.AnswerUpVotes,
    pah.AnswerDownVotes,
    pl.LinkTypeName,
    pl.PostTitle,
    pl.RelatedPostTitle,
    ua.PostsCount,
    ua.CommentsCount,
    ua.VotesCount,
    ua.AvgPostScore,
    ua.LastPostDate,
    ua.FirstPostDate,
    rh.Level AS TagHierarchyLevel,
    rh.TagName AS RelatedTag
FROM TopUsers tu
LEFT JOIN PostWithAnswerStats pah ON pah.AnswerOwner = tu.Id
LEFT JOIN PostLinkage pl ON pl.PostId = pah.AnswerId OR pl.RelatedPostId = pah.AnswerId
LEFT JOIN UserActivityWindow ua ON ua.Id = tu.Id
LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY(string_to_array(SUBSTRING(pah.Tags FROM 2 FOR CHAR_LENGTH(pah.Tags) - 2), '><'))
WHERE
    (
        (COALESCE(pah.QuestionScore, 0) > 5 OR COALESCE(pah.AnswerScore, 0) > 5)
        AND (COALESCE(pah.AnswerUpVotes, 0) - COALESCE(pah.AnswerDownVotes, 0)) > 3
    )
    AND (
        COALESCE(ua.PostsCount, 0) > 10 OR COALESCE(ua.CommentsCount, 0) > 20
    )
ORDER BY
    tu.Reputation DESC,
    pah.QuestionScore DESC,
    pah.AnswerScore DESC,
    ua.PostsCount DESC
LIMIT 100;
WITH UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        COUNT(p.Id) AS PostCount,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserTagParticipation AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT tag) AS DistinctTagsUsed,
        SUM(COALESCE(p.AnswerCount, 0)) AS TotalAnswersGiven,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAcceptedAnswer
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
    ) t
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
    GROUP BY u.Id
),
TopTaggedPosts AS (
    SELECT
        tag,
        COUNT(*) AS PostCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.ViewCount) AS MaxViewCount
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
    ) t
    WHERE p.PostTypeId = 1
    GROUP BY tag
    ORDER BY PostCount DESC
    LIMIT 10
),
UserVotesAgg AS (
    SELECT
        u.Id AS UserId,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 5) AS FavoritesGiven,
        COUNT(v.Id) AS TotalVotesGiven
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
),
PostLinkInfo AS (
    SELECT
        pl.PostId,
        pl.LinkTypeId,
        COUNT(pl.RelatedPostId) AS LinkCount,
        ARRAY_AGG(DISTINCT lp.Title) AS RelatedPostTitles
    FROM PostLinks pl
    JOIN Posts lp ON lp.Id = pl.RelatedPostId
    WHERE pl.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY pl.PostId, pl.LinkTypeId
)
SELECT
    ubs.UserId,
    ubs.DisplayName,
    ubs.Reputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    uts.DistinctTagsUsed,
    uts.TotalAnswersGiven,
    uts.QuestionsWithAcceptedAnswer,
    uvs.UpVotesGiven,
    uvs.DownVotesGiven,
    uvs.FavoritesGiven,
    ubs.TotalPostScore,
    ubs.PostCount,
    ubs.AvgPostScore,
    ubs.LastPostDate,
    array_agg(DISTINCT tt.tag) FILTER (WHERE tt.tag IS NOT NULL) AS TopTagsUsed,
    COUNT(DISTINCT pl.PostId) AS PostsWithLinksCount,
    SUM(pl.LinkCount) AS TotalLinksMade,
    MAX(pl.LinkCount) FILTER (WHERE pl.LinkTypeId = 1) AS MaxLinkedPosts,
    MAX(pl.LinkCount) FILTER (WHERE pl.LinkTypeId = 3) AS MaxDuplicatePosts
FROM UserBadgeStats ubs
LEFT JOIN UserTagParticipation uts ON uts.UserId = ubs.UserId
LEFT JOIN UserVotesAgg uvs ON uvs.UserId = ubs.UserId
LEFT JOIN Posts p ON p.OwnerUserId = ubs.UserId
LEFT JOIN PostLinkInfo pl ON pl.PostId = p.Id
LEFT JOIN LATERAL (
    SELECT tag
    FROM (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
    ) s
) tt ON TRUE
WHERE p.Tags IS NOT NULL OR tt.tag IS NOT NULL OR pl.PostId IS NOT NULL
GROUP BY
    ubs.UserId,
    ubs.DisplayName,
    ubs.Reputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    uts.DistinctTagsUsed,
    uts.TotalAnswersGiven,
    uts.QuestionsWithAcceptedAnswer,
    uvs.UpVotesGiven,
    uvs.DownVotesGiven,
    uvs.FavoritesGiven,
    ubs.TotalPostScore,
    ubs.PostCount,
    ubs.AvgPostScore,
    ubs.LastPostDate
ORDER BY ubs.Reputation DESC
LIMIT 50;
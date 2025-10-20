-- {"query": "3062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 946} 
WITH PostAnswerStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore
    FROM
        Posts p
        LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE
        p.PostTypeId = 1
        AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY
        p.OwnerUserId
),
UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM
        Users u
        LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id
),
PostHistoryTypesCount AS (
    SELECT
        pht.PostHistoryTypeId,
        COUNT(*) AS TypeCount
    FROM
        PostHistory p
        JOIN PostHistoryTypes pht ON p.PostHistoryTypeId = pht.Id
    GROUP BY
        pht.PostHistoryTypeId
),
RecentModifiedPosts AS (
    SELECT
        p.Id AS PostId,
        p.LastEditDate,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.LastEditDate DESC) AS rn
    FROM
        Posts p
    WHERE
        p.LastEditDate IS NOT NULL
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(b.GoldBadges, 0) AS GoldBadgesCount,
    COALESCE(b.SilverBadges, 0) AS SilverBadgesCount,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadgesCount,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesReceived,
    p.AnswerCount,
    p.AvgAnswerScore,
    SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS UpvoteComments,
    SUM(CASE WHEN c.Score < 0 THEN 1 ELSE 0 END) AS DownvoteComments,
    th.TypeCount AS PostHistoryTypeCounts,
    SUM(CASE WHEN p.LastEditDate >= NOW() - INTERVAL '30 days' THEN 1 ELSE 0 END) AS RecentEditsWithin30Days,
    RLE(STRING_AGG(DISTINCT l.Name, ', ')) OVER () AS AllLinkTypes,
    (SELECT COUNT(*) FROM Posts tmp WHERE tmp.OwnerUserId = u.Id AND tmp.PostTypeId = 1 AND tmp.CreationDate >= NOW() - INTERVAL '365 days') AS QuestionsLastYear,
    (SELECT COUNT(*) FROM Posts tmp WHERE tmp.OwnerUserId = u.Id AND tmp.PostTypeId = 2 AND tmp.CreationDate >= NOW() - INTERVAL '365 days') AS AnswersLastYear
FROM
    Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory h ON p.Id = h.PostId
    LEFT JOIN PostHistoryTypesCount th ON h.PostHistoryTypeId = th.PostHistoryTypeId
    LEFT JOIN PostLinks l ON p.Id = l.PostId AND l.LinkTypeId = 1
    LEFT JOIN RecentModifiedPosts rmp ON p.Id = rmp.PostId AND rmp.rn = 1
    LEFT JOIN LATERAL (
        SELECT
            STRING_AGG(t.TagName, ', ') AS Tags
        FROM
            unnest(split_part(p.Tags, '><', 1)) AS TagName
    ) tags_sub ON TRUE
GROUP BY
    u.Id, u.DisplayName, u.Reputation, b.GoldBadges, b.SilverBadges, b.BronzeBadges, p.AnswerCount, p.AvgAnswerScore, th.TypeCount, rmp.LastEditDate, rmp.Title, rmp.Tags;
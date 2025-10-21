WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS RecentPosts,
        COUNT(DISTINCT c.Id) AS RecentComments
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
    WHERE u.LastAccessDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
BadgeDistribution AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    WHERE b.Date > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days'
    GROUP BY b.UserId
),
TopTags AS (
    SELECT
        pt.OwnerUserId AS UserId,
        UNNEST(string_to_array(SUBSTRING(pt.Tags FROM 2 FOR char_length(pt.Tags) - 2), '><')) AS Tag,
        SUM(pt.Score) AS TagScore,
        COUNT(*) AS TagPosts
    FROM Posts pt
    WHERE pt.PostTypeId = 1 AND pt.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days'
    GROUP BY pt.OwnerUserId, Tag
),
UserTopTag AS (
    SELECT
        UserId,
        Tag,
        TagScore,
        TagPosts,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagScore DESC, TagPosts DESC) AS rn
    FROM TopTags
)
SELECT
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.UpVotes,
    rau.DownVotes,
    rau.CreationDate,
    rau.LastAccessDate,
    COALESCE(bd.GoldBadges, 0) AS GoldBadges,
    COALESCE(bd.SilverBadges, 0) AS SilverBadges,
    COALESCE(bd.BronzeBadges, 0) AS BronzeBadges,
    rau.RecentPosts,
    rau.RecentComments,
    utt.Tag AS TopTag,
    utt.TagScore AS TopTagScore,
    utt.TagPosts AS TopTagPosts,
    COALESCE(answers.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(questions.AvgQuestionView, 0) AS AvgQuestionView,
    CASE
        WHEN rau.RecentComments > 0 THEN ROUND(rau.RecentPosts::numeric / rau.RecentComments, 2)
        ELSE NULL
    END AS PostCommentRatio,
    CASE
        WHEN (rau.UpVotes + rau.DownVotes) > 0 THEN ROUND((COALESCE(rau.UpVotes, 0)::decimal / (rau.UpVotes + rau.DownVotes)) * 100, 2)
        ELSE NULL
    END AS UpvotePercentage
FROM RecentActiveUsers rau
LEFT JOIN BadgeDistribution bd ON bd.UserId = rau.UserId
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        AVG(p.Score) AS AvgAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90 days'
    GROUP BY p.OwnerUserId
) answers ON answers.OwnerUserId = rau.UserId
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        AVG(p.ViewCount) AS AvgQuestionView
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90 days'
    GROUP BY p.OwnerUserId
) questions ON questions.OwnerUserId = rau.UserId
LEFT JOIN (
    SELECT
        UserId,
        Tag,
        TagScore,
        TagPosts
    FROM UserTopTag
    WHERE rn = 1
) utt ON utt.UserId = rau.UserId
WHERE (rau.Reputation >= 500 OR bd.GoldBadges >= 1 OR answers.AvgAnswerScore > 5)
  AND (
    SELECT COUNT(*)
    FROM PostHistory ph
    WHERE ph.UserId = rau.UserId AND ph.PostHistoryTypeId = 5
      AND ph.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
  ) >= 2
ORDER BY rau.Reputation DESC, GoldBadges DESC, SilverBadges DESC, TopTagScore DESC
LIMIT 100;
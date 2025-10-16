WITH RECURSIVE TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM Users u
    WHERE u.Reputation IS NOT NULL
),
UserPosts AS (
    SELECT
        p.OwnerUserId            AS UserId,
        p.Id                     AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        COALESCE(p.Tags, '')     AS RawTags,
        CASE WHEN p.PostTypeId = 1 THEN p.Title ELSE NULL END AS QuestionTitle,
        CASE WHEN p.PostTypeId = 2 THEN p.ParentId ELSE NULL END AS ParentQuestionId
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
-- Split tags using standard SQL: replace leading/trailing '<' '>' then split on '><'
UserTagExploded AS (
    SELECT
        up.UserId,
        TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM up.RawTags)) AS StrippedTags
    FROM UserPosts up
    WHERE up.PostTypeId = 1
      AND up.RawTags <> ''
),
UserTagStats AS (
    SELECT
        ute.UserId,
        tag.value AS Tag,
        COUNT(*) AS TagUseCount
    FROM UserTagExploded ute,
    LATERAL (
        SELECT value
        FROM (SELECT regexp_split_to_table(ute.StrippedTags, '><') AS value) s
    ) tag
    GROUP BY ute.UserId, tag.value
),
UserTagAgg AS (
    SELECT
        uts.UserId,
        STRING_AGG(uts.Tag || ':' || CAST(uts.TagUseCount AS VARCHAR), ', ' ORDER BY uts.TagUseCount DESC) AS TopTags
    FROM (
        SELECT *
        FROM UserTagStats
        ORDER BY UserId, TagUseCount DESC
    ) uts
    GROUP BY uts.UserId
),
UserVoteStats AS (
    SELECT
        up.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        COUNT(v.Id)                                         AS TotalVotesGiven
    FROM UserPosts up
    LEFT JOIN Votes v ON v.UserId = up.UserId
    GROUP BY up.UserId
),
UserAnswerStats AS (
    SELECT
        up.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE up.PostTypeId = 2)            AS AnswerCount,
        AVG(up.Score) FILTER (WHERE up.PostTypeId = 2)       AS AvgAnswerScore,
        MAX(up.CreationDate) FILTER (WHERE up.PostTypeId = 2) AS LastAnswerDate
    FROM Posts up
    WHERE up.PostTypeId = 2
    GROUP BY up.OwnerUserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserHistoryEvents AS (
    SELECT
        ph.UserId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseEvents,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 12) AS DeleteEvents,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 24) AS SuggestedEditEvents
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
CombinedStats AS (
    SELECT
        tu.Id                                   AS UserId,
        tu.DisplayName,
        tu.Reputation,
        COALESCE(ua.AnswerCount,0)              AS AnswerCount,
        COALESCE(ua.AvgAnswerScore,0)           AS AvgAnswerScore,
        COALESCE(ub.GoldBadges,0)               AS GoldBadges,
        COALESCE(ub.SilverBadges,0)             AS SilverBadges,
        COALESCE(ub.BronzeBadges,0)             AS BronzeBadges,
        COALESCE(uv.UpVotesGiven,0)             AS UpVotesGiven,
        COALESCE(uv.DownVotesGiven,0)           AS DownVotesGiven,
        COALESCE(uh.CloseEvents,0)              AS CloseEvents,
        COALESCE(uh.DeleteEvents,0)             AS DeleteEvents,
        COALESCE(uh.SuggestedEditEvents,0)      AS SuggestedEditEvents,
        COALESCE(uta.TopTags, 'None')           AS TopTags
    FROM TopUsers tu
    LEFT JOIN UserAnswerStats ua      ON ua.UserId = tu.Id
    LEFT JOIN UserBadgeStats ub       ON ub.UserId = tu.Id
    LEFT JOIN UserVoteStats uv        ON uv.UserId = tu.Id
    LEFT JOIN UserHistoryEvents uh    ON uh.UserId = tu.Id
    LEFT JOIN UserTagAgg uta          ON uta.UserId = tu.Id
    WHERE tu.rn <= 100
)
SELECT *
FROM (
    SELECT *
    FROM CombinedStats

    UNION ALL

    SELECT
        u.Id                 AS UserId,
        u.DisplayName,
        u.Reputation,
        0                    AS AnswerCount,
        CAST(0 AS DOUBLE PRECISION)  AS AvgAnswerScore,
        0                    AS GoldBadges,
        0                    AS SilverBadges,
        0                    AS BronzeBadges,
        0                    AS UpVotesGiven,
        0                    AS DownVotesGiven,
        0                    AS CloseEvents,
        0                    AS DeleteEvents,
        0                    AS SuggestedEditEvents,
        'None'               AS TopTags
    FROM Users u
    WHERE u.Reputation > (SELECT COALESCE(MIN(Reputation), 0) FROM CombinedStats)
      AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
      AND NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id)
      AND NOT EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = u.Id)
      AND NOT EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.UserId = u.Id)
) AS combined_union
ORDER BY Reputation DESC, AnswerCount DESC
LIMIT 200;
WITH TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.Location, 'Unknown') AS UserLocation
    FROM Users u
    ORDER BY u.Reputation DESC
    FETCH FIRST 10 ROWS ONLY
), UserPostAgg AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.PostTypeId = 2) AS MedianAnswerScore,
        MAX(p.LastActivityDate) AS LastPostActivity,
        STRING_AGG(DISTINCT LOWER(TRIM(BOTH '><' FROM REPLACE(REPLACE(p.Tags, '<', ''), '>', ''))), ',') AS AllTags
    FROM Posts p
    GROUP BY p.OwnerUserId
), UserBadgeAgg AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount,
        COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS TagBasedBadgeCount
    FROM Badges b
    GROUP BY b.UserId
), UserVoteAgg AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteGiven,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoriteGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
), LastCloseReason AS (
    SELECT
        ph.PostId,
        ph.Comment AS CloseReason,
        ph.CreationDate AS ClosedOn,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
), UserClosedPosts AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) AS ClosedPostCount,
        MAX(c.ClosedOn) AS MostRecentCloseDate,
        STRING_AGG(DISTINCT c.CloseReason, '; ') AS DistinctCloseReasons
    FROM Posts p
    LEFT JOIN LastCloseReason c ON c.PostId = p.Id AND c.rn = 1
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
), CombinedStats AS (
    SELECT
        tu.Id,
        tu.DisplayName,
        tu.Reputation,
        tu.UserLocation,
        COALESCE(upa.QuestionCount,0) AS QuestionCount,
        COALESCE(upa.AnswerCount,0) AS AnswerCount,
        COALESCE(upa.AvgQuestionScore,0) AS AvgQuestionScore,
        COALESCE(upa.AvgAnswerScore,0) AS AvgAnswerScore,
        COALESCE(upa.MedianAnswerScore,0) AS MedianAnswerScore,
        COALESCE(upa.LastPostActivity, tu.CreationDate) AS LastActivity,
        COALESCE(uba.GoldBadgeCount,0) AS GoldBadgeCount,
        COALESCE(uba.SilverBadgeCount,0) AS SilverBadgeCount,
        COALESCE(uba.BronzeBadgeCount,0) AS BronzeBadgeCount,
        COALESCE(uba.TagBasedBadgeCount,0) AS TagBasedBadgeCount,
        COALESCE(uva.UpVoteGiven,0) AS UpVotesGiven,
        COALESCE(uva.DownVoteGiven,0) AS DownVotesGiven,
        COALESCE(uva.FavoriteGiven,0) AS FavoritesGiven,
        COALESCE(ucp.ClosedPostCount,0) AS ClosedPostCount,
        ucp.MostRecentCloseDate,
        ucp.DistinctCloseReasons,
        upa.AllTags
    FROM TopUsers tu
    LEFT JOIN UserPostAgg upa ON upa.UserId = tu.Id
    LEFT JOIN UserBadgeAgg uba ON uba.UserId = tu.Id
    LEFT JOIN UserVoteAgg uva ON uva.UserId = tu.Id
    LEFT JOIN UserClosedPosts ucp ON ucp.UserId = tu.Id
)
SELECT
    Id,
    DisplayName,
    Reputation,
    UserLocation,
    QuestionCount,
    AnswerCount,
    AvgQuestionScore,
    AvgAnswerScore,
    MedianAnswerScore,
    LastActivity,
    GoldBadgeCount,
    SilverBadgeCount,
    BronzeBadgeCount,
    TagBasedBadgeCount,
    UpVotesGiven,
    DownVotesGiven,
    FavoritesGiven,
    ClosedPostCount,
    MostRecentCloseDate,
    DistinctCloseReasons,
    AllTags
FROM CombinedStats
WHERE (GoldBadgeCount + SilverBadgeCount + BronzeBadgeCount) > 10
   OR ClosedPostCount > 0
GROUP BY
    Id,
    DisplayName,
    Reputation,
    UserLocation,
    QuestionCount,
    AnswerCount,
    AvgQuestionScore,
    AvgAnswerScore,
    MedianAnswerScore,
    LastActivity,
    GoldBadgeCount,
    SilverBadgeCount,
    BronzeBadgeCount,
    TagBasedBadgeCount,
    UpVotesGiven,
    DownVotesGiven,
    FavoritesGiven,
    ClosedPostCount,
    MostRecentCloseDate,
    DistinctCloseReasons,
    AllTags
ORDER BY Reputation DESC, GoldBadgeCount DESC, QuestionCount DESC;
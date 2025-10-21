WITH UserPostAggregates AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(CASE WHEN p.PostTypeId = 2 AND q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS TotalAcceptedAnswersReceived,
        SUM(p.ViewCount) AS TotalPostViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Posts q ON p.ParentId = q.Id AND p.PostTypeId = 2
    GROUP BY
        u.Id, u.Reputation
),
UserCommentAndEditAggregates AS (
    SELECT
        u.Id AS UserId,
        COUNT(c.Id) AS TotalCommentsMade,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS TotalEditsMade
    FROM
        Users u
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        PostHistory ph ON u.Id = ph.UserId
    GROUP BY
        u.Id
),
UserBadgeAggregates AS (
    SELECT
        u.Id AS UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 1 AND b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedGoldBadges
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id
),
UserTagContributions AS (
    SELECT
        a.OwnerUserId AS UserId,
        TRIM(UNNEST(string_to_array(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><'))) AS TagName,
        SUM(a.Score) AS TagAnswerScore,
        COUNT(a.Id) AS TagAnswerCount,
        SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS TagAcceptedAnswerCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS TagAnswerUpvotes
    FROM
        Posts a
    JOIN
        Posts q ON a.ParentId = q.Id AND q.PostTypeId = 1
    LEFT JOIN
        Votes v ON a.Id = v.PostId AND v.VoteTypeId = 2
    WHERE
        a.PostTypeId = 2
        AND a.OwnerUserId IS NOT NULL
        AND q.Tags IS NOT NULL
    GROUP BY
        a.OwnerUserId, TagName
    HAVING
        COUNT(a.Id) > 5
),
RankedUserTagContributions AS (
    SELECT
        UserId,
        TagName,
        TagAnswerScore,
        TagAnswerCount,
        TagAcceptedAnswerCount,
        TagAnswerUpvotes,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagAnswerScore DESC, TagAcceptedAnswerCount DESC) AS Rn
    FROM
        UserTagContributions
),
UserPostedTagsRaw AS (
    SELECT DISTINCT
        p.OwnerUserId AS UserId,
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
),
UserModeratorTagContribution AS (
    SELECT
        upr.UserId,
        COUNT(DISTINCT ti.Id) AS ModeratorOnlyTagsCount
    FROM
        UserPostedTagsRaw upr
    JOIN
        Tags ti ON upr.TagName = ti.TagName
    WHERE
        ti.IsModeratorOnly = TRUE
    GROUP BY
        upr.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    upa.TotalPosts,
    upa.TotalQuestions,
    upa.TotalAnswers,
    upa.TotalPostScore,
    upa.TotalAcceptedAnswersReceived,
    uca.TotalCommentsMade,
    uca.TotalEditsMade,
    uba.TotalBadges AS GoldBadges,
    uba.TagBasedGoldBadges,
    (SELECT ARRAY_AGG(TagName ORDER BY TagAnswerScore DESC) FROM RankedUserTagContributions rtc WHERE rtc.UserId = u.Id AND rtc.Rn <= 3) AS Top3TagsByAnswerScore,
    AVG(p_avg.Score) FILTER (WHERE p_avg.PostTypeId = 1) AS AvgQuestionScore,
    AVG(p_avg.Score) FILTER (WHERE p_avg.PostTypeId = 2) AS AvgAnswerScore,
    SUM(CASE WHEN v_given.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
    SUM(CASE WHEN v_given.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
    COALESCE(umtc.ModeratorOnlyTagsCount, 0) AS ModeratorOnlyTagsWrittenAbout,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate
FROM
    Users u
JOIN
    UserPostAggregates upa ON u.Id = upa.UserId
JOIN
    UserCommentAndEditAggregates uca ON u.Id = uca.UserId
JOIN
    UserBadgeAggregates uba ON u.Id = uba.UserId
LEFT JOIN
    Posts p_avg ON u.Id = p_avg.OwnerUserId
LEFT JOIN
    Votes v_given ON u.Id = v_given.UserId
LEFT JOIN
    UserModeratorTagContribution umtc ON u.Id = umtc.UserId
WHERE
    u.Reputation > 10000
    AND upa.TotalAnswers > 100
    AND uba.GoldBadges > 0
    AND EXISTS (SELECT 1 FROM RankedUserTagContributions rtc WHERE rtc.UserId = u.Id AND rtc.Rn <= 3)
GROUP BY
    u.Id, u.DisplayName, u.Reputation, upa.TotalPosts, upa.TotalQuestions, upa.TotalAnswers, upa.TotalPostScore, upa.TotalAcceptedAnswersReceived,
    uca.TotalCommentsMade, uca.TotalEditsMade, uba.TotalBadges, uba.TagBasedGoldBadges, umtc.ModeratorOnlyTagsCount, u.CreationDate, u.LastAccessDate
ORDER BY
    u.Reputation DESC, upa.TotalPostScore DESC, uba.TotalBadges DESC
LIMIT 1000;
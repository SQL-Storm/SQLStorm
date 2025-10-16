WITH RECURSIVE RecursiveBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        CAST(b.Class AS INTEGER) AS Class,
        COUNT(*) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, CAST(b.Class AS INTEGER)

    UNION ALL

    SELECT
        rbc.UserId,
        rbc.DisplayName,
        CASE WHEN rbc.Class IS NULL THEN 1 ELSE rbc.Class + 1 END AS Class,
        0 AS BadgeCount
    FROM RecursiveBadgeCounts rbc
    WHERE rbc.Class IS NULL OR rbc.Class < 3
),
TopUsersByBadge AS (
    SELECT
        UserId,
        DisplayName,
        MAX(CASE WHEN Class = 1 THEN BadgeCount END) AS GoldBadges,
        MAX(CASE WHEN Class = 2 THEN BadgeCount END) AS SilverBadges,
        MAX(CASE WHEN Class = 3 THEN BadgeCount END) AS BronzeBadges
    FROM RecursiveBadgeCounts
    GROUP BY UserId, DisplayName
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        MAX(p.Score) FILTER (WHERE p.PostTypeId = 2) AS MaxAnswerScore,
        SUM(CASE WHEN p.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS TimesAccepted
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
QuestionAnswerDetails AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreation,
        a.Id AS AnswerId,
        a.CreationDate AS AnswerCreation,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
FilteredTopAnswers AS (
    SELECT
        QuestionId,
        Title,
        OwnerUserId,
        AnswerId,
        AnswerCreation,
        AnswerScore,
        AnswerOwnerUserId
    FROM QuestionAnswerDetails
    WHERE AnswerRank = 1
),
UserAnswerAccepts AS (
    SELECT
        u.Id AS UserId,
        COUNT(*) AS AcceptedAnswerCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
    WHERE EXISTS (
        SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId = p.Id AND q.PostTypeId = 1
    )
    GROUP BY u.Id
),
ComplexPostTags AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        unnest(string_to_array(trim(both '<>' FROM COALESCE(p.Tags, '')), '><')) AS SingleTag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
TagCounts AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT cp.PostId) AS QuestionCount,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgScore
    FROM Tags t
    LEFT JOIN ComplexPostTags cp ON cp.SingleTag = t.TagName
    LEFT JOIN Posts p ON p.Id = cp.PostId
    GROUP BY t.TagName
),
UserRecentActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentDate,
        GREATEST(MAX(p.LastActivityDate), MAX(c.CreationDate)) AS LastActivityOverall
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
VotesSummary AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 5) AS Favorites,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id, p.PostTypeId
),
PostLinkSummary AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        COUNT(*) OVER (PARTITION BY pl.PostId, pl.LinkTypeId) AS LinkCountPerType
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
FinalResult AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        up.QuestionsAsked,
        up.AnswersGiven,
        up.AvgAnswerScore,
        up.MaxAnswerScore,
        COALESCE(uba.AcceptedAnswerCount, 0) AS AcceptedAnswers,
        tb.GoldBadges,
        tb.SilverBadges,
        tb.BronzeBadges,
        ua.LastActivityOverall,
        tc.TagName AS FavoriteTag,
        tc.QuestionCount AS TagQuestionCount,
        tc.TotalViews AS TagTotalViews,
        tc.AvgScore AS TagAvgScore,
        vsm.UpVotes AS LastPostUpVotes,
        vsm.DownVotes AS LastPostDownVotes,
        vsm.Favorites AS LastPostFavorites,
        vsm.TotalBounty AS LastPostBounty
    FROM Users u
    LEFT JOIN UserPostStats up ON up.UserId = u.Id
    LEFT JOIN UserAnswerAccepts uba ON uba.UserId = u.Id
    LEFT JOIN TopUsersByBadge tb ON tb.UserId = u.Id
    LEFT JOIN UserRecentActivity ua ON ua.UserId = u.Id
    LEFT JOIN LATERAL (
        SELECT t.TagName, t.QuestionCount, t.TotalViews, t.AvgScore
        FROM TagCounts t
        JOIN ComplexPostTags cpt ON cpt.SingleTag = t.TagName
        JOIN Posts p ON p.Id = cpt.PostId AND p.OwnerUserId = u.Id
        ORDER BY t.QuestionCount DESC
        LIMIT 1
    ) tc ON TRUE
    LEFT JOIN LATERAL (
        SELECT vsm.UpVotes, vsm.DownVotes, vsm.Favorites, vsm.TotalBounty
        FROM Posts p
        JOIN VotesSummary vsm ON vsm.PostId = p.Id
        WHERE p.OwnerUserId = u.Id
        ORDER BY p.LastActivityDate DESC
        LIMIT 1
    ) vsm ON TRUE
    WHERE u.Reputation > 1000
)
SELECT *
FROM FinalResult
ORDER BY AcceptedAnswers DESC, GoldBadges DESC, AnswersGiven DESC
LIMIT 100;
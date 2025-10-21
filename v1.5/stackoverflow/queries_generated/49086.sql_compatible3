WITH PostVoteSummary AS (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod') THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'DownMod') THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
),
UserPostMetrics AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN p.Id END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN p.ViewCount END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN p.Score END) AS AvgQuestionScore,
        COUNT(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') THEN p.Score END) AS AvgAnswerScore,
        SUM(COALESCE(pvs.UpVotes, 0)) AS TotalUpVotesReceived,
        SUM(COALESCE(pvs.DownVotes, 0)) AS TotalDownVotesReceived
    FROM Posts p
    LEFT JOIN PostVoteSummary pvs ON p.Id = pvs.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserRecentActivity AS (
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (SELECT Id FROM PostHistoryTypes WHERE Name IN ('Edit Title', 'Edit Body', 'Edit Tags')) AND ph.CreationDate >= DATE '2023-01-01' THEN ph.Id END) AS RecentEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed') AND ph.CreationDate >= DATE '2023-01-01' THEN ph.Id END) AS RecentClosedPosts
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL AND ph.CreationDate >= DATE '2022-01-01'
    GROUP BY ph.UserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        COUNT(CASE WHEN c.CreationDate >= DATE '2023-01-01' THEN c.Id END) AS RecentComments
    FROM Comments c
    WHERE c.UserId IS NOT NULL AND c.CreationDate >= DATE '2022-01-01'
    GROUP BY c.UserId
),
UserTopTags AS (
    SELECT
        UserId,
        STRING_AGG(TagName, ', ' ORDER BY TagRank) AS TopTagNames
    FROM (
        SELECT
            p.OwnerUserId AS UserId,
            TRIM(unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><'))) AS TagName,
            COUNT(*) AS TagCount,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC, TRIM(unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><'))) ASC) AS TagRank
        FROM Posts p
        WHERE p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
        GROUP BY p.OwnerUserId, TRIM(unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')))
    ) AS TaggedPosts
    WHERE TagRank <= 3
    GROUP BY UserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(upm.QuestionCount, 0) AS QuestionCount,
    COALESCE(upm.TotalQuestionViews, 0) AS TotalQuestionViews,
    COALESCE(upm.AvgQuestionScore, 0) AS AvgQuestionScore,
    COALESCE(upm.AnswerCount, 0) AS AnswerCount,
    COALESCE(upm.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(upm.TotalUpVotesReceived, 0) AS TotalUpVotesReceived,
    COALESCE(upm.TotalDownVotesReceived, 0) AS TotalDownVotesReceived,
    COALESCE(ura.RecentEdits, 0) AS RecentEdits,
    COALESCE(ura.RecentClosedPosts, 0) AS RecentClosedPosts,
    COALESCE(uca.TotalComments, 0) AS TotalComments,
    COALESCE(uca.RecentComments, 0) AS RecentComments,
    utt.TopTagNames,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    (u.Reputation * 0.4
     + COALESCE(upm.TotalUpVotesReceived, 0) * 0.2
     + COALESCE(upm.TotalQuestionViews, 0) * 0.005
     + COALESCE(upm.AvgQuestionScore, 0) * 0.05
     + COALESCE(upm.AvgAnswerScore, 0) * 0.05
     + COALESCE(ubs.GoldBadges, 0) * 50
     + COALESCE(ubs.SilverBadges, 0) * 20
     + COALESCE(ubs.BronzeBadges, 0) * 5
     + COALESCE(ura.RecentEdits, 0) * 2
     + COALESCE(uca.RecentComments, 0) * 1.5
    ) AS UserActivityScore
FROM Users u
LEFT JOIN UserPostMetrics upm ON u.Id = upm.UserId
LEFT JOIN UserRecentActivity ura ON u.Id = ura.UserId
LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
LEFT JOIN UserTopTags utt ON u.Id = utt.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
WHERE
    u.Reputation > 500 AND
    u.LastAccessDate >= DATE '2023-01-01' AND
    (COALESCE(upm.QuestionCount, 0) + COALESCE(upm.AnswerCount, 0) > 5) AND
    COALESCE(upm.TotalUpVotesReceived, 0) > 20
ORDER BY
    UserActivityScore DESC,
    u.Reputation DESC,
    u.LastAccessDate DESC
FETCH FIRST 50 ROWS ONLY;
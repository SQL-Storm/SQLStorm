-- {"query": "1705.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3611} 

WITH UserBaseStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / 86400 AS UserAgeDays, -- Age in days
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        NULLIF(TRIM(u.WebsiteUrl), '') AS CleanWebsiteUrl,
        u.Views AS ProfileViews,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        u.LastAccessDate,
        u.CreationDate
    FROM Users u
    WHERE u.Reputation >= 500 AND u.AccountId IS NOT NULL -- Filter for somewhat active users with an account
),
PostAggregates AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersPosted,
        SUM(p.Score) AS TotalPostScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS AvgQuestionViewCount,
        SUM(COALESCE(p.AnswerCount, 0)) AS TotalAnswersToUserQuestions,
        COUNT(CASE WHEN p.ClosedDate IS NOT NULL AND p.PostTypeId = 1 THEN 1 END) AS ClosedQuestionsCount,
        COUNT(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 END) AS CommunityOwnedPostsCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
AcceptedAnswersProvidedByUsers AS (
    SELECT
        A.OwnerUserId AS UserId,
        COUNT(DISTINCT A.Id) AS AcceptedAnswersCount
    FROM Posts Q -- Q for Question
    JOIN Posts A ON Q.AcceptedAnswerId = A.Id -- A for Answer
    WHERE Q.PostTypeId = 1
      AND A.PostTypeId = 2
      AND A.OwnerUserId IS NOT NULL
    GROUP BY A.OwnerUserId
),
CommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalCommentsMade,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(DISTINCT c.PostId) AS UniquePostsCommentedOn,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
PostEditHistorySummary AS (
    SELECT
        ph.UserId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS TotalEditsMade, -- Edit Title, Body, Tags
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.PostId END) AS UniquePostsEdited,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId = p.OwnerUserId THEN 1 ELSE 0 END) AS SelfEditsCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL THEN 1 ELSE 0 END) AS CloseVotesCast, -- Post Closed events
        MAX(ph.CreationDate) AS LastEditContributionDate,
        MIN(ph.CreationDate) AS FirstEditContributionDate,
        AVG(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate)) / 3600 END) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS AvgHoursFromPostCreationToAnyEdit
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id -- Needed to check OwnerUserId for self-edits
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
PostVoteAggregates AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesReceived,
        SUM(CASE WHEN v.VoteTypeId IN (4, 12) THEN 1 ELSE 0 END) AS OffensiveOrSpamVotesReceived
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
ControversialPostsSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS PostsWithHighDownvoteRatio,
        AVG(CAST(COALESCE(va.DownVotesReceived, 0) AS NUMERIC) / NULLIF(COALESCE(va.UpVotesReceived, 0) + COALESCE(va.DownVotesReceived, 0), 0)) AS AvgPostDownvoteRatio
    FROM Posts p
    JOIN (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
        FROM Votes v
        GROUP BY v.PostId
        HAVING SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) > 5 -- At least 5 downvotes
           AND CAST(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) + SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) > 0.3 -- Downvote ratio > 30%
    ) va ON p.Id = va.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TagPerformance AS (
    SELECT
        t.TagName,
        SUM(p.Score) AS TotalTagScore,
        COUNT(p.Id) AS TotalTagPosts,
        AVG(p.Score) AS AvgTagScore,
        NTILE(5) OVER (ORDER BY SUM(p.Score) DESC, COUNT(p.Id) DESC) AS TagScoreQuintile
    FROM Posts p
    JOIN LATERAL UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag_name ON TRUE -- Postgres specific tag parsing
    JOIN Tags t ON tag_name = t.TagName
    WHERE p.Tags IS NOT NULL AND p.Tags != ''
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 100 -- Only consider tags with substantial activity
),
UserTagInterest AS (
    SELECT
        ubs.UserId,
        STRING_AGG(DISTINCT tp.TagName, ', ' ORDER BY tp.TagName) AS TopTagsOfInterest,
        COUNT(DISTINCT tp.TagName) AS UniqueTagsEngagedInTopQuintiles
    FROM UserBaseStats ubs
    JOIN Posts p ON ubs.UserId = p.OwnerUserId
    JOIN LATERAL UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag_name ON TRUE
    JOIN TagPerformance tp ON tag_name = tp.TagName
    WHERE tp.TagScoreQuintile <= 2 -- Top 2 quintiles of tags by total score
    GROUP BY ubs.UserId
),
RecentActivityScores AS (
    SELECT
        ubs.UserId,
        SUM(CASE WHEN p.CreationDate >= (ubs.LastAccessDate - INTERVAL '90 days') THEN p.Score ELSE 0 END) AS RecentPostScore,
        SUM(CASE WHEN c.CreationDate >= (ubs.LastAccessDate - INTERVAL '90 days') THEN c.Score ELSE 0 END) AS RecentCommentScore,
        LAG(ubs.Reputation, 1, 0) OVER (PARTITION BY ubs.UserLocation ORDER BY ubs.Reputation DESC) AS PrevReputationInLocation,
        RANK() OVER (PARTITION BY ubs.UserLocation ORDER BY ubs.Reputation DESC) AS RankInLocationByReputation
    FROM UserBaseStats ubs
    LEFT JOIN Posts p ON ubs.UserId = p.OwnerUserId
    LEFT JOIN Comments c ON ubs.UserId = c.UserId
    GROUP BY ubs.UserId, ubs.LastAccessDate, ubs.Reputation, ubs.UserLocation
)
SELECT
    ubs.UserId,
    ubs.DisplayName,
    ubs.Reputation,
    ubs.UserAgeDays,
    ubs.UserLocation,
    ubs.CleanWebsiteUrl,
    COALESCE(pa.QuestionsAsked, 0) AS UserQuestionsAsked,
    COALESCE(pa.AnswersPosted, 0) AS UserAnswersPosted,
    COALESCE(pa.TotalPostScore, 0) AS UserTotalPostScore,
    COALESCE(aapb.AcceptedAnswersCount, 0) AS UserAcceptedAnswersCount,
    COALESCE(ca.TotalCommentsMade, 0) AS UserCommentsMade,
    COALESCE(pes.TotalEditsMade, 0) AS UserTotalEdits,
    COALESCE(pes.SelfEditsCount, 0) AS UserSelfEdits,
    COALESCE(pva.UpVotesReceived, 0) AS UserUpVotesReceived,
    COALESCE(pva.DownVotesReceived, 0) AS UserDownVotesReceived,
    COALESCE(pva.FavoritesReceived, 0) AS UserFavoritesReceived,
    COALESCE(pva.OffensiveOrSpamVotesReceived, 0) AS UserOffensiveOrSpamVotesReceived,
    CAST(COALESCE(pva.DownVotesReceived, 0) AS NUMERIC) / NULLIF(COALESCE(pva.UpVotesReceived, 0) + COALESCE(pva.DownVotesReceived, 0), 0) AS DownvoteRatioReceived,
    ubs.TotalUpVotesGiven,
    ubs.TotalDownVotesGiven,
    (
        SELECT COUNT(DISTINCT pl.PostId)
        FROM PostLinks pl
        WHERE pl.RelatedPostId IN (SELECT p_sub.Id FROM Posts p_sub WHERE p_sub.OwnerUserId = ubs.UserId AND p_sub.PostTypeId IN (1, 2))
          AND pl.LinkTypeId IN (1, 3) -- Linked or Duplicate
    ) AS TotalPostsLinkedToUserContent, -- Correlated Subquery for inbound links
    COALESCE(ubad.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubad.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubad.BronzeBadges, 0) AS BronzeBadges,
    (COALESCE(ubad.GoldBadges, 0) * 10 + COALESCE(ubad.SilverBadges, 0) * 5 + COALESCE(ubad.BronzeBadges, 0)) AS BadgeScore,
    COALESCE(cps.PostsWithHighDownvoteRatio, 0) AS ControversialPostsCount,
    uti.TopTagsOfInterest,
    COALESCE(uti.UniqueTagsEngagedInTopQuintiles, 0) AS UniqueTagsEngagedInTopQuintiles,
    COALESCE(ras.RecentPostScore, 0) AS Recent90DayPostScore,
    COALESCE(ras.RecentCommentScore, 0) AS Recent90DayCommentScore,
    ras.RankInLocationByReputation,
    COALESCE(pes.LastEditContributionDate, ca.LastCommentDate, ubs.CreationDate) AS LastContentContributionDate,
    CASE
        WHEN ubs.Reputation > 100000 AND COALESCE(aapb.AcceptedAnswersCount, 0) >= 100 AND COALESCE(ubad.GoldBadges, 0) >= 5 THEN 'GuruContributor'
        WHEN ubs.Reputation > 25000 AND COALESCE(pes.TotalEditsMade, 0) > 500 AND COALESCE(pa.QuestionsAsked, 0) + COALESCE(pa.AnswersPosted, 0) > 200 THEN 'ProlificEditorAndAuthor'
        WHEN COALESCE(pva.DownVotesReceived, 0) > 1000 AND (CAST(COALESCE(pva.DownVotesReceived, 0) AS NUMERIC) / NULLIF(COALESCE(pva.UpVotesReceived, 0) + COALESCE(pva.DownVotesReceived, 0), 0) > 0.4) THEN 'ControversialFigure'
        WHEN ubs.UserAgeDays > 1000 AND COALESCE(pa.TotalPostScore, 0) > 5000 THEN 'VeteranActive'
        ELSE 'ActiveUser'
    END AS UserCategory,
    'https://stackoverflow.com/users/' || ubs.UserId || '/' || REPLACE(LOWER(REPLACE(COALESCE(ubs.DisplayName, 'unknown'), ' ', '-')), '''', '') AS ProfileLink, -- String concatenation & manipulation, handling spaces and apostrophes
    NULLIF(CAST(COALESCE(pa.ClosedQuestionsCount, 0) AS NUMERIC) / NULLIF(COALESCE(pa.QuestionsAsked, 0), 0), 0) AS ClosedQuestionRatio -- NULL if no questions asked
FROM UserBaseStats ubs
LEFT JOIN PostAggregates pa ON ubs.UserId = pa.UserId
LEFT JOIN AcceptedAnswersProvidedByUsers aapb ON ubs.UserId = aapb.UserId
LEFT JOIN CommentActivity ca ON ubs.UserId = ca.UserId
LEFT JOIN PostEditHistorySummary pes ON ubs.UserId = pes.UserId
LEFT JOIN PostVoteAggregates pva ON ubs.UserId = pva.UserId
LEFT JOIN UserBadgeStats ubad ON ubs.UserId = ubad.UserId
LEFT JOIN ControversialPostsSummary cps ON ubs.UserId = cps.UserId
LEFT JOIN UserTagInterest uti ON ubs.UserId = uti.UserId
LEFT JOIN RecentActivityScores ras ON ubs.UserId = ras.UserId
WHERE ubs.DisplayName IS NOT NULL
  AND ubs.DisplayName !~ '^[0-9]+$' -- Exclude numeric display names (likely bots/test users)
  AND ubs.UserAgeDays > 180 -- Only users active for at least half a year
  AND (COALESCE(pa.QuestionsAsked, 0) > 0 OR COALESCE(pa.AnswersPosted, 0) > 0 OR COALESCE(ca.TotalCommentsMade, 0) > 0) -- Must have some content contribution
  AND ubs.Reputation > 1000 -- Further filter for more significant users
ORDER BY ubs.Reputation DESC, DownvoteRatioReceived DESC NULLS LAST, UserAcceptedAnswersCount DESC
LIMIT 500;

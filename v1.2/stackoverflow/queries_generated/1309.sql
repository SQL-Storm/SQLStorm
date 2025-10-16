-- {"query": "1309.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1866} 
WITH RecentActiveUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        COALESCE(u.AboutMe, '[No AboutMe]') as AboutSummary,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        RANK() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS ReputationRank
    FROM Users u
    WHERE u.LastAccessDate > now() - interval '90 day'
),
UserBadgesSummary AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class=1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class=2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class=3) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = 1 THEN b.Name ELSE NULL END) AS DistinctTagBasedBadges,
        MIN(b.Date) AS FirstBadgeDate,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserPostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.Score) AS MaxPostScore,
        SUM(p.FavoriteCount) AS TotalFavoritesReceived,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id ELSE NULL END) AS AnswerHasAcceptedCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentActivity AS (
    SELECT 
        c.UserId,
        COUNT(*) AS TotalComments,
        COUNT(DISTINCT c.PostId) AS DistinctPostsCommented,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.UserId
),
UserVotesGiven AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
        SUM(v.BountyAmount) AS TotalBountyGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
UserActivitySummary AS (
    -- Combine all user activity stats with outer joins and calculation of an activity score
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.AboutSummary,
        COALESCE(bs.GoldBadges,0) AS GoldBadges,
        COALESCE(bs.SilverBadges,0) AS SilverBadges,
        COALESCE(bs.BronzeBadges,0) AS BronzeBadges,
        COALESCE(ups.QuestionCount,0) AS Questions,
        COALESCE(ups.AnswerCount,0) AS Answers,
        COALESCE(ups.AvgPostScore,0) AS AvgScore,
        COALESCE(acs.TotalComments,0) AS CommentsPosted,
        COALESCE(uv.UpVotesGiven,0) AS UpVotesGiven,
        COALESCE(uv.DownVotesGiven,0) AS DownVotesGiven,
        u.Views,
        -- Complex expression mixing user stats for an 'engagement score'
        (COALESCE(bs.GoldBadges,0) * 10 + COALESCE(bs.SilverBadges,0) * 5 + COALESCE(bs.BronzeBadges,0) * 2
         + COALESCE(ups.QuestionCount,0) * 4 + COALESCE(ups.AnswerCount,0)*3 
         + COALESCE(acs.TotalComments,0) * 1.5 + COALESCE(uv.UpVotesGiven,0) * 0.1
         - COALESCE(uv.DownVotesGiven,0) * 0.3 + COALESCE(u.Views,0)*0.001) 
        AS EngagementScore
    FROM RecentActiveUsers u
    LEFT JOIN UserBadgesSummary bs ON bs.UserId = u.Id
    LEFT JOIN UserPostStats ups ON ups.OwnerUserId = u.Id
    LEFT JOIN UserCommentActivity acs ON acs.UserId = u.Id
    LEFT JOIN UserVotesGiven uv ON uv.UserId = u.Id
)
,
PostsWithOwnerInfo AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.AcceptedAnswerId,
        p.Tags,
        po.DisplayName as OwnerName,
        po.Reputation as OwnerReputation,
        po.UpVotes as OwnerUpVotes,
        po.DownVotes as OwnerDownVotes
    FROM Posts p
    LEFT JOIN Users po ON p.OwnerUserId = po.Id
    WHERE p.CreationDate > now() - interval '180 day'
),
RecentClosedDuplicates AS (
    SELECT
        ph.PostId,
        ph.Comment AS CloseReasonCode,
        cr.Name AS CloseReason,
        ph.CreationDate as CloseDate
    FROM PostHistory ph
    JOIN CloseReasonTypes cr ON cast(ph.Comment as smallint) = cr.Id
    WHERE ph.PostHistoryTypeId = 10 
        AND ph.CreationDate > now() - interval '90 day'
        AND cr.Name ILIKE '%duplicate%'
),
DuplicateLinkCounts AS (
    SELECT 
        pl.PostId, 
        COUNT(*) AS DuplicateLinksCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
),
TopTagsByCount AS (
    SELECT TagName, Count,
           ROW_NUMBER() OVER (ORDER BY Count DESC) AS Rnk
    FROM Tags
    WHERE TagName IS NOT NULL AND TagName <> ''
),
-- Select top 10 tags
SelectedTopTags AS (
    SELECT TagName FROM TopTagsByCount WHERE Rnk <= 10
),
-- Posts tagged with specific top tags in last 6 months with sentiment complexity
PostsTopTagsAnalysis AS (
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        (LENGTH(p.Body) - LENGTH(REPLACE(LOWER(p.Body), 'error', ''))) / NULLIF(LENGTH('error'), 0) AS ErrorCount,
        (LENGTH(p.Body) - LENGTH(REPLACE(LOWER(p.Body), 'exception', ''))) / NULLIF(LENGTH('exception'), 0) AS ExceptionCount,
        COALESCE(dlp.DuplicateLinksCount,0) AS DuplicateLinks,
        CASE WHEN EXISTS (
            SELECT 1 FROM RecentClosedDuplicates rcd WHERE rcd.PostId = p.Id
        )
        THEN TRUE ELSE FALSE END AS IsRecentlyClosedDuplicate
    FROM Posts p
    LEFT JOIN DuplicateLinkCounts dlp ON p.Id = dlp.PostId
    WHERE p.PostTypeId = 1
),
FinalAggregateView AS (
    SELECT
        ua.Id AS UserId,
        ua.DisplayName,
        ua.EngagementScore,
        COUNT(ptta.Id) FILTER (WHERE ptta.IsRecentlyClosedDuplicate = TRUE) AS UserRecentlyClosedDuplicateQuestions,
        AVG(ptta.ErrorCount + ptta.ExceptionCount) FILTER (WHERE ptta.Id IS NOT NULL) AS AvgErrorExceptionOccurrencesPerQuestion,
        SUM(ptta.DuplicateLinks) FILTER (WHERE ptta.Id IS NOT NULL) AS TotalDuplicateLinksInQuestions,
        MAX(ua.Reputation) AS MaxReputation,
        STRING_AGG(DISTINCT tt.TagName, ',' ORDER BY tt.Count DESC) AS TopUsedTagsForUserRecentlyClosedDuplicates
    FROM UserActivitySummary ua
    LEFT JOIN PostsTopTagsAnalysis ptta ON ptta.Id IN (
        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ua.Id
    )
    LEFT JOIN Tags tt ON tt.TagName = ANY(string_to_array(substr(ptta.Tags, 2, length(ptta.Tags) - 2), '>><<'))
    GROUP BY ua.Id, ua.DisplayName, ua.EngagementScore
)
SELECT 
    fa.UserId, 
    fa.DisplayName, 
    ROUND(fa.EngagementScore, 2) AS Engagement, 
    fa.UserRecentlyClosedDuplicateQuestions, 
    ROUND(fa.AvgErrorExceptionOccurrencesPerQuestion,3) AS Avg_error_exc_count, 
    fa.TotalDuplicateLinksInQuestions,
    fa.TopUsedTagsForUserRecentlyClosedDuplicates
FROM FinalAggregateView fa
WHERE fa.EngagementScore > 100 
AND fa.UserRecentlyClosedDuplicateQuestions > 0
ORDER BY fa.EngagementScore DESC, fa.UserRecentlyClosedDuplicateQuestions DESC
LIMIT 100;
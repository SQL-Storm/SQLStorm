-- {"query": "1392.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2453}
WITH UserCoreStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Location,
        u.WebsiteUrl,
        u.AboutMe,
        u.Views AS UserProfileViews,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        MAX(b.Date) AS LastBadgeAwardDate,
        (u.Reputation * 0.7 + u.UpVotes * 0.2 - u.DownVotes * 0.1 + COUNT(DISTINCT b.Id) * 10 +
         COALESCE(EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.LastAccessDate)), 365) * -0.01 +
         CASE WHEN u.WebsiteUrl IS NOT NULL THEN 50 ELSE 0 END
        ) AS EngagementScore,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.WebsiteUrl, u.AboutMe, u.Views, u.UpVotes, u.DownVotes
    HAVING u.Reputation > 500
),
PostTagParser AS (
    SELECT
        p.Id AS PostId,
        TRIM(value) AS TagName
    FROM Posts p,
         LATERAL (
           SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS value
         ) AS t
    WHERE p.Tags IS NOT NULL AND p.Tags LIKE '<%>%'
),
PostDetailsExtended AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastEditDate,
        p.LastActivityDate,
        p.ClosedDate,
        p.CommunityOwnedDate,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(COALESCE(p.Title, '')) AS TitleLength,
        COALESCE(CAST(p.Score AS NUMERIC) / NULLIF(p.ViewCount, 0), 0) AS ScorePerViewRatio,
        RANK() OVER (PARTITION BY p.PostTypeId, EXTRACT(QUARTER FROM p.CreationDate) ORDER BY p.Score DESC, p.ViewCount DESC) AS RankInQuarterByScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RollingAvgOwnerPostScore,
        (p.Body ILIKE '%sql%' OR p.Title ILIKE '%sql%') AS IsSQLRelated,
        (p.Body ILIKE '%database%' OR p.Title ILIKE '%database%') AS IsDatabaseRelated,
        EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.LastActivityDate)) AS DaysSinceLastActivity,
        (p.ClosedDate IS NOT NULL AND p.CommunityOwnedDate IS NOT NULL) AS IsClosedAndCommunityOwned
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2, 4)
),
PostHistoryTimeline AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryCreationDate,
        ph.UserId AS HistoryEditorUserId,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / 3600.0 AS HoursSincePreviousEvent,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) OVER (PARTITION BY ph.PostId) AS TotalMinorEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) OVER (PARTITION BY ph.PostId) AS EverClosed,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) OVER (PARTITION BY ph.PostId) AS EverReopened
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15)
),
AggregatedPostHistory AS (
    SELECT
        PostId,
        COUNT(DISTINCT HistoryCreationDate) AS TotalHistoryEvents,
        AVG(HoursSincePreviousEvent) FILTER (WHERE HoursSincePreviousEvent > 0) AS AvgHoursBetweenEdits,
        MAX(HistoryCreationDate) AS LastHistoryEventDate,
        MIN(HistoryCreationDate) AS FirstHistoryEventDate,
        MAX(TotalMinorEdits) AS PostTotalMinorEdits,
        MAX(EverClosed) AS PostEverClosed,
        MAX(EverReopened) AS PostEverReopened
    FROM PostHistoryTimeline
    GROUP BY PostId
),
UserQuestionPerformance AS (
    SELECT
        pde.OwnerUserId AS UserId,
        COUNT(DISTINCT pde.PostId) AS TotalQuestionsAsked,
        SUM(pde.PostScore) AS TotalQuestionScore,
        AVG(pde.ScorePerViewRatio) AS AvgQuestionScorePerView,
        SUM(CASE WHEN pde.IsSQLRelated THEN 1 ELSE 0 END) AS SQLRelatedQuestions,
        SUM(CASE WHEN pde.IsDatabaseRelated THEN 1 ELSE 0 END) AS DatabaseRelatedQuestions
    FROM PostDetailsExtended pde
    WHERE pde.PostTypeId = 1
    GROUP BY pde.OwnerUserId
),
UserAnswerPerformance AS (
    SELECT
        pde.OwnerUserId AS UserId,
        COUNT(DISTINCT pde.PostId) AS TotalAnswersProvided,
        SUM(pde.PostScore) AS TotalAnswerScore,
        AVG(pde.ScorePerViewRatio) AS AvgAnswerScorePerView,
        SUM(CASE WHEN pde.IsSQLRelated THEN 1 ELSE 0 END) AS SQLRelatedAnswers,
        SUM(CASE WHEN pde.IsDatabaseRelated THEN 1 ELSE 0 END) AS DatabaseRelatedAnswers,
        (CASE WHEN EXISTS (
            SELECT 1
            FROM Posts a_inner
            JOIN Posts q_parent ON a_inner.ParentId = q_parent.Id AND q_parent.AcceptedAnswerId = a_inner.Id
            JOIN Users u_q_owner ON q_parent.OwnerUserId = u_q_owner.Id
            WHERE a_inner.OwnerUserId = pde.OwnerUserId
              AND a_inner.PostTypeId = 2
              AND u_q_owner.Reputation > 15000
        ) THEN TRUE ELSE FALSE END) AS HasHighRepQuestionerAcceptedAnswer
    FROM PostDetailsExtended pde
    WHERE pde.PostTypeId = 2
    GROUP BY pde.OwnerUserId
),
UserCommentAndLinkAggregates AS (
    SELECT
        u.Id AS UserId,
        COALESCE(AVG(c_user.Score), 0) AS AvgCommentScoreOnUserPosts,
        COALESCE(MAX(c_user.Score), 0) AS MaxCommentScoreOnUserPosts,
        COUNT(DISTINCT c_user.Id) FILTER (WHERE c_user.Score < 0) AS ControversialCommentsCount,
        (SELECT COUNT(DISTINCT pl_inner.PostId)
         FROM PostLinks pl_inner
         JOIN Posts related_p ON pl_inner.RelatedPostId = related_p.Id
         WHERE pl_inner.PostId IN (SELECT p_own.Id FROM Posts p_own WHERE p_own.OwnerUserId = u.Id)
           AND pl_inner.LinkTypeId = 1
           AND related_p.ViewCount > 10000
           AND related_p.Score > 50
           AND related_p.ClosedDate IS NULL
        ) AS HighImpactLinkedPostsCount,
        MAX(c_user.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Posts p_user ON u.Id = p_user.OwnerUserId
    LEFT JOIN Comments c_user ON p_user.Id = c_user.PostId
    GROUP BY u.Id
)
SELECT
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.Location,
    ucs.EngagementScore,
    ucs.TotalBadgesEarned,
    ucs.GoldBadgeCount,
    COALESCE(uq.TotalQuestionsAsked, 0) AS TotalQuestionsAsked,
    COALESCE(uq.TotalQuestionScore, 0) AS TotalQuestionScore,
    COALESCE(uq.AvgQuestionScorePerView, 0) AS AvgQuestionScorePerView,
    COALESCE(ua.TotalAnswersProvided, 0) AS TotalAnswersProvided,
    COALESCE(ua.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(ua.AvgAnswerScorePerView, 0) AS AvgAnswerScorePerView,
    COALESCE(ua.SQLRelatedAnswers, 0) AS SQLRelatedAnswers,
    COALESCE(ua.DatabaseRelatedAnswers, 0) AS DatabaseRelatedAnswers,
    COALESCE(ua.HasHighRepQuestionerAcceptedAnswer, FALSE) AS HasHighRepQuestionerAcceptedAnswer,
    COALESCE(uqc.AvgCommentScoreOnUserPosts, 0) AS AvgCommentScoreOnUserPosts,
    COALESCE(uqc.MaxCommentScoreOnUserPosts, 0) AS MaxCommentScoreOnUserPosts,
    COALESCE(uqc.ControversialCommentsCount, 0) AS ControversialCommentsCount,
    COALESCE(uqc.HighImpactLinkedPostsCount, 0) AS HighImpactLinkedPostsCount,
    ucs.UserCreationDate,
    ucs.LastAccessDate,
    ucs.UserProfileViews,
    ucs.TotalUpVotesGiven,
    ucs.TotalDownVotesGiven,
    ucs.LastBadgeAwardDate,
    COALESCE(a.PhysicalTotalQuestions, 0) AS PhysicalTotalQuestions,
    COALESCE(ap.PostTotalMinorEdits, 0) AS PostTotalMinorEdits,
    COALESCE(ap.PostEverClosed, 0) AS PostEverClosed,
    COALESCE(ap.PostEverReopened, 0) AS PostEverReopened
FROM UserCoreStats ucs
LEFT JOIN UserQuestionPerformance uq ON ucs.UserId = uq.UserId
LEFT JOIN UserAnswerPerformance ua ON ucs.UserId = ua.UserId
LEFT JOIN UserCommentAndLinkAggregates uqc ON ucs.UserId = uqc.UserId
LEFT JOIN (
    SELECT OwnerUserId, COUNT(Id) AS PhysicalTotalQuestions
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
) a ON ucs.UserId = a.OwnerUserId
LEFT JOIN AggregatedPostHistory ap ON ap.PostId = (
    SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ucs.UserId LIMIT 1
)
GROUP BY
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.Location,
    ucs.EngagementScore,
    ucs.TotalBadgesEarned,
    ucs.GoldBadgeCount,
    uq.TotalQuestionsAsked,
    uq.TotalQuestionScore,
    uq.AvgQuestionScorePerView,
    ua.TotalAnswersProvided,
    ua.TotalAnswerScore,
    ua.AvgAnswerScorePerView,
    ua.SQLRelatedAnswers,
    ua.DatabaseRelatedAnswers,
    ua.HasHighRepQuestionerAcceptedAnswer,
    uqc.AvgCommentScoreOnUserPosts,
    uqc.MaxCommentScoreOnUserPosts,
    uqc.ControversialCommentsCount,
    uqc.HighImpactLinkedPostsCount,
    ucs.UserCreationDate,
    ucs.LastAccessDate,
    ucs.UserProfileViews,
    ucs.TotalUpVotesGiven,
    ucs.TotalDownVotesGiven,
    ucs.LastBadgeAwardDate,
    a.PhysicalTotalQuestions,
    ap.PostTotalMinorEdits,
    ap.PostEverClosed,
    ap.PostEverReopened;
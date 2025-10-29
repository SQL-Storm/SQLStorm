-- {"query": "2454.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1985}
WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        ARRAY[t.Id] AS TagPath
    FROM Tags t
    WHERE t.IsRequired = TRUE

    UNION ALL

    SELECT
        c.Id,
        c.TagName,
        c.Count,
        c.ExcerptPostId,
        c.WikiPostId,
        c.IsModeratorOnly,
        c.IsRequired,
        r.TagPath || c.Id
    FROM Tags c
    JOIN RecursiveTagHierarchy r ON c.IsRequired = TRUE AND NOT (c.Id = ANY (r.TagPath))
    WHERE cardinality(r.TagPath) < 3
),
PostScoresByUser AS (
    SELECT
        p.OwnerUserId,
        p.PostTypeId,
        count(*) AS PostCount,
        sum(coalesce(p.Score,0)) AS TotalScore,
        avg(coalesce(p.Score,0)) AS AvgScore,
        max(p.Score) AS MaxScore,
        min(p.Score) AS MinScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, p.PostTypeId
),
UserBadgeRanks AS (
    SELECT
        b.UserId,
        b.Class,
        count(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
UserAggregates AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        coalesce(pb.PostCount,0) AS QuestionCount,
        coalesce(pb.TotalScore,0) AS QuestionScore,
        coalesce(sum(case when ab.Class = 1 then ab.BadgeCount else 0 end),0) AS GoldBadges,
        coalesce(sum(case when ab.Class = 2 then ab.BadgeCount else 0 end),0) AS SilverBadges,
        coalesce(sum(case when ab.Class = 3 then ab.BadgeCount else 0 end),0) AS BronzeBadges,
        row_number() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        lead(u.Reputation) OVER (ORDER BY u.Reputation DESC) AS NextHighestReputation,
        lag(u.Reputation) OVER (ORDER BY u.Reputation DESC) AS PrevHighestReputation
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, PostCount, TotalScore, PostTypeId FROM PostScoresByUser
        WHERE PostTypeId = 1
    ) pb ON u.Id = pb.OwnerUserId
    LEFT JOIN UserBadgeRanks ab ON u.Id = ab.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, pb.PostCount, pb.TotalScore
),
PostsWithLatestCloseReason AS (
    SELECT
        p.Id,
        p.Title,
        p.Body,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        ph.Comment AS CloseReasonId,
        crt.Name AS CloseReasonName
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT phinner.Comment
        FROM PostHistory phinner
        WHERE phinner.PostId = p.Id AND phinner.PostHistoryTypeId = 10
        ORDER BY phinner.CreationDate DESC
        LIMIT 1
    ) ph ON TRUE
    LEFT JOIN CloseReasonTypes crt ON CAST(crt.Id AS varchar) = ph.Comment
),
UserRecentActivity AS (
    SELECT
        ph.UserId,
        ph.PostId,
        max(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    GROUP BY ph.UserId, ph.PostId
),
UserNetwork AS (
    SELECT DISTINCT
        p.OwnerUserId AS UserA,
        pl.RelatedPostId,
        p2.OwnerUserId AS UserB
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE p.OwnerUserId IS NOT NULL AND p2.OwnerUserId IS NOT NULL AND p.OwnerUserId != p2.OwnerUserId
),
MutualUserConnections AS (
    SELECT
        un1.UserA,
        un1.UserB
    FROM UserNetwork un1
    JOIN UserNetwork un2 ON un1.UserA = un2.UserB AND un1.UserB = un2.UserA
),
UserStatsWithConnections AS (
    SELECT
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        count(muc.UserB) AS MutualConnectionCount
    FROM UserAggregates ua
    LEFT JOIN MutualUserConnections muc ON ua.Id = muc.UserA
    GROUP BY ua.Id, ua.DisplayName, ua.Reputation, ua.QuestionCount, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges
),
AnswerScores AS (
    SELECT
        a.Id,
        a.ParentId,
        a.Score,
        u.Reputation AS OwnerReputation,
        row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
),
QuestionWithTopAnswer AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        a.Id AS TopAnswerId,
        a.Score AS TopAnswerScore,
        a.OwnerReputation AS TopAnswerOwnerReputation
    FROM Posts q
    LEFT JOIN AnswerScores a ON q.Id = a.ParentId AND a.AnswerRank = 1
    WHERE q.PostTypeId = 1
),
FilteredComments AS (
    SELECT 
        c.PostId,
        sum(case when c.Score > 2 then 1 else 0 end) AS HighScoreComments,
        sum(case when lower(c.Text) SIMILAR TO '%(performance)%' then 1 else 0 end) AS CommentsMentioningPerformance
    FROM Comments c
    GROUP BY c.PostId
),
CombinedPostData AS (
    SELECT
        q.Id,
        q.Title,
        q.Tags,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        coalesce(fc.HighScoreComments, 0) AS HighScoreComments,
        coalesce(fc.CommentsMentioningPerformance,0) AS CommentsMentioningPerformance,
        pwta.TopAnswerId,
        pwta.TopAnswerScore,
        pwta.TopAnswerOwnerReputation,
        p.CloseReasonName,
        q.OwnerUserId
    FROM Posts q
    LEFT JOIN FilteredComments fc ON q.Id = fc.PostId
    LEFT JOIN QuestionWithTopAnswer pwta ON q.Id = pwta.QuestionId
    LEFT JOIN PostsWithLatestCloseReason p ON q.Id = p.Id
    WHERE q.PostTypeId = 1
),
UnionsExample AS (
    SELECT Id, Title, 'Question' AS PostCategory, Score FROM Posts WHERE PostTypeId = 1 AND Score > 10
    UNION ALL
    SELECT Id, Title, 'Wiki' AS PostCategory, Score FROM Posts WHERE PostTypeId IN (3,5) AND Score > 10
),
FinalResults AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.QuestionCount,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        u.MutualConnectionCount,
        cpd.Title,
        cpd.Score AS QuestionScore,
        cpd.ViewCount,
        cpd.HighScoreComments,
        cpd.CommentsMentioningPerformance,
        cpd.TopAnswerId,
        cpd.TopAnswerScore,
        cpd.TopAnswerOwnerReputation,
        cpd.CloseReasonName,
        row_number() OVER (PARTITION BY u.Id ORDER BY cpd.Score DESC NULLS LAST) AS QuestionRank
    FROM UserStatsWithConnections u
    JOIN CombinedPostData cpd ON cpd.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
),
AggregatedUserStats AS (
    SELECT
        UserId,
        DisplayName,
        sum(QuestionCount) AS TotalQuestions,
        sum(HighScoreComments) AS TotalHighScoreComments,
        avg(CommentsMentioningPerformance) AS AvgCommentsMentioningPerformance,
        max(TopAnswerScore) AS MaxTopAnswerScore,
        count(distinct TopAnswerId) AS AnsweredQuestionsCount,
        max(MutualConnectionCount) AS MaxMutualConnections
    FROM FinalResults
    GROUP BY UserId, DisplayName
)
SELECT 
    aus.UserId,
    aus.DisplayName,
    aus.TotalQuestions,
    aus.TotalHighScoreComments,
    round(aus.AvgCommentsMentioningPerformance::numeric, 2) AS AvgCommentsMentioningPerformance,
    aus.MaxTopAnswerScore,
    aus.AnsweredQuestionsCount,
    aus.MaxMutualConnections,
    CASE 
        WHEN aus.MaxMutualConnections > 5 AND aus.TotalHighScoreComments > 10 THEN 'Highly Engaged & Connected'
        WHEN aus.MaxMutualConnections > 5 THEN 'Highly Connected'
        WHEN aus.TotalHighScoreComments > 10 THEN 'Highly Engaged'
        ELSE 'Normal'
    END AS UserEngagementCategory
FROM AggregatedUserStats aus
ORDER BY aus.TotalQuestions DESC, aus.TotalHighScoreComments DESC
LIMIT 50;
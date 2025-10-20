WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Level,
        ARRAY[t.Id] AS Path
    FROM Tags t
    WHERE t.IsRequired = TRUE

    UNION ALL

    SELECT 
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        child.IsModeratorOnly,
        child.IsRequired,
        p.Level + 1,
        p.Path || child.Id
    FROM Tags child
    JOIN RecursiveTagHierarchy p ON child.Id <> ALL(p.Path)
    WHERE child.IsRequired = TRUE
      AND child.Count < p.Count
),
UserActivityRanked AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        MAX(p.Score) AS MaxPostScore,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) AS RankByReputation
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostLinkAggregates AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Linked' THEN pl.RelatedPostId END) AS LinkedCount,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS DuplicateCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId
),
QuestionDetails AS (
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        ul.RankByReputation,
        pla.LinkedCount,
        pla.DuplicateCount,
        string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><') AS TagArray,
        (
            SELECT COALESCE(SUM(t.Count), 0)
            FROM Tags t
            WHERE t.TagName = ANY(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><'))
        ) AS TagPopularitySum
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN UserActivityRanked ul ON ul.UserId = p.OwnerUserId
    LEFT JOIN PostLinkAggregates pla ON pla.PostId = p.Id
    WHERE p.PostTypeId = 1
),
AnswerDetails AS (
    SELECT 
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        u.DisplayName AS OwnerName,
        ul.RankByReputation,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    LEFT JOIN UserActivityRanked ul ON ul.UserId = a.OwnerUserId
    WHERE a.PostTypeId = 2
),
AnswerWithAcceptedFlag AS (
    SELECT 
        a.*,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted
    FROM AnswerDetails a
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
),
TopAnswerers AS (
    SELECT 
        a.OwnerUserId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(a.IsAccepted) AS AcceptedCount,
        MAX(a.Score) AS MaxAnswerScore
    FROM AnswerWithAcceptedFlag a
    GROUP BY a.OwnerUserId
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS TotalEdits,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors,
        MAX(ph.CreationDate) AS LastEditDate,
        BOOL_OR(ph.PostHistoryTypeId IN (10, 12)) AS IsClosedOrDeleted,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEvents
    FROM PostHistory ph
    GROUP BY ph.PostId
),
UserCommentStats AS (
    SELECT 
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(length(c.Text)) AS AvgCommentLength,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
CombinedUserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(ua.TotalPosts, 0) AS TotalPosts,
        COALESCE(ua.Questions, 0) AS Questions,
        COALESCE(ua.Answers, 0) AS Answers,
        COALESCE(ua.BadgeCount, 0) AS BadgeCount,
        COALESCE(ua.GoldBadges, 0) AS GoldBadges,
        COALESCE(ua.SilverBadges, 0) AS SilverBadges,
        COALESCE(ua.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(tc.CommentCount, 0) AS CommentCount,
        COALESCE(tc.AvgCommentLength, 0) AS AvgCommentLength,
        COALESCE(tc.LastCommentDate, TIMESTAMP '1900-01-01') AS LastCommentDate,
        COALESCE(ta.AnswerCount, 0) AS AnswerCount,
        COALESCE(ta.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(ta.AcceptedCount, 0) AS AcceptedCount,
        COALESCE(ta.MaxAnswerScore, 0) AS MaxAnswerScore
    FROM Users u
    LEFT JOIN UserActivityRanked ua ON ua.UserId = u.Id
    LEFT JOIN UserCommentStats tc ON tc.UserId = u.Id
    LEFT JOIN TopAnswerers ta ON ta.OwnerUserId = u.Id
)
SELECT 
    q.Id AS QuestionId,
    q.Title,
    q.OwnerUserId,
    q.OwnerName,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.ClosedDate,
    q.RankByReputation AS OwnerReputationRank,
    q.TagPopularitySum,
    q.LinkedCount,
    q.DuplicateCount,
    phs.TotalEdits,
    phs.DistinctEditors,
    phs.IsClosedOrDeleted,
    phs.CloseEvents,
    phs.ReopenEvents,
    a.Id AS TopAnswerId,
    a.OwnerUserId AS TopAnswerOwnerId,
    a.OwnerName AS TopAnswerOwnerName,
    a.Score AS TopAnswerScore,
    a.IsAccepted,
    ucs.DisplayName AS TopAnswerOwnerDisplayName,
    ucs.Reputation AS TopAnswerOwnerReputation,
    ucs.BadgeCount AS TopAnswerOwnerBadgeCount,
    ucs.GoldBadges AS TopAnswerOwnerGoldBadges,
    ucs.SilverBadges AS TopAnswerOwnerSilverBadges,
    ucs.BronzeBadges AS TopAnswerOwnerBronzeBadges,
    ucs.CommentCount AS TopAnswerOwnerCommentCount,
    ucs.AvgCommentLength AS TopAnswerOwnerAvgCommentLength,
    ucs.AnswerCount AS TopAnswerOwnerAnswerCount,
    ucs.AvgAnswerScore AS TopAnswerOwnerAvgAnswerScore,
    ucs.AcceptedCount AS TopAnswerOwnerAcceptedCount,
    ucs.MaxAnswerScore AS TopAnswerOwnerMaxAnswerScore
FROM QuestionDetails q
LEFT JOIN LATERAL (
    SELECT a.*
    FROM AnswerWithAcceptedFlag a
    WHERE a.ParentId = q.Id
    ORDER BY a.IsAccepted DESC, a.Score DESC, a.CreationDate ASC
    LIMIT 1
) a ON TRUE
LEFT JOIN PostHistorySummary phs ON phs.PostId = q.Id
LEFT JOIN CombinedUserStats ucs ON ucs.Id = a.OwnerUserId
WHERE q.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
  AND (q.ClosedDate IS NULL OR q.ClosedDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
ORDER BY q.Score DESC, q.ViewCount DESC
LIMIT 100;
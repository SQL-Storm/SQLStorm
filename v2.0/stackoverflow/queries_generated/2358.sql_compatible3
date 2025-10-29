WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Level,
        ARRAY[t.Id] AS Path
    FROM Tags t
    WHERE NOT t.IsModeratorOnly

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.IsModeratorOnly,
        child.IsRequired,
        r.Level + 1,
        r.Path || child.Id
    FROM Tags child
    JOIN RecursiveTagHierarchy r ON NOT (child.Id = ANY(r.Path)) AND child.Count > r.Count * 0.5
    WHERE NOT child.IsModeratorOnly
),
UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
QuestionStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveCommentsCount,
        (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 12)) AS CloseOrDeleteEvents
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TopAnswersWindowed AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
PostsWithVotes AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS FavoriteVotes
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate
),
ComplexUserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.CreationDate,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId = 1) AS PostsCreated,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditsMade,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId IN (2,3) AND v.UserId = u.Id) AS VotesCast,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS UserQuestionScoreSum,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS UserAnswerScoreSum
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.CreationDate
),
UserRankings AS (
    SELECT
        cua.Id,
        cua.DisplayName,
        cua.CreationDate,
        cua.PostsCreated,
        cua.EditsMade,
        cua.VotesCast,
        cua.UserQuestionScoreSum,
        cua.UserAnswerScoreSum,
        RANK() OVER (ORDER BY cua.PostsCreated DESC, cua.EditsMade DESC, cua.VotesCast DESC) AS ActivityRank
    FROM ComplexUserActivity cua
),
FinalData AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        u.DisplayName AS OwnerName,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.HasAcceptedAnswer,
        q.PositiveCommentsCount,
        q.CloseOrDeleteEvents,
        pwv.UpVotes AS QuestionUpVotes,
        pwv.DownVotes AS QuestionDownVotes,
        pwv.FavoriteVotes AS QuestionFavorites,
        a.AnswerId,
        a.Score AS TopAnswerScore,
        a.CreationDate AS TopAnswerCreationDate,
        ua.DisplayName AS TopAnswerOwnerName,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        rs.Level AS TagHierarchyLevel,
        rs.TagName,
        ur.ActivityRank
    FROM QuestionStats q
    LEFT JOIN PostsWithVotes pwv ON pwv.PostId = q.QuestionId
    LEFT JOIN TopAnswersWindowed a ON a.QuestionId = q.QuestionId AND a.AnswerRank = 1
    LEFT JOIN Users ua ON ua.Id = a.OwnerUserId
    LEFT JOIN UserBadgeSummary ub ON ub.UserId = q.OwnerUserId
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN UserRankings ur ON ur.Id = q.OwnerUserId
    LEFT JOIN RecursiveTagHierarchy rs ON rs.TagName = ANY(string_to_array(SUBSTRING(q.Tags FROM 2 FOR CHAR_LENGTH(q.Tags) - 2), '><'))
    WHERE q.Score > 0 AND q.AnswerCount > 0
)
SELECT DISTINCT
    QuestionId,
    Title,
    OwnerUserId,
    OwnerName,
    CreationDate,
    Score,
    ViewCount,
    AnswerCount,
    HasAcceptedAnswer,
    PositiveCommentsCount,
    CloseOrDeleteEvents,
    QuestionUpVotes,
    QuestionDownVotes,
    QuestionFavorites,
    AnswerId,
    TopAnswerScore,
    TopAnswerCreationDate,
    TopAnswerOwnerName,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TagHierarchyLevel,
    TagName,
    ActivityRank,
    CASE 
        WHEN HasAcceptedAnswer = 1 THEN 'Accepted'
        WHEN Score > 50 THEN 'Hot'
        WHEN CloseOrDeleteEvents > 0 THEN 'Reviewed'
        ELSE 'Normal'
    END AS Status,
    ('Tags: ' || COALESCE(TagName, 'None') || '; Owner Activity Rank: ' || CAST(ActivityRank AS varchar)) AS Summary
FROM FinalData
WHERE TagHierarchyLevel IS NOT NULL AND ActivityRank <= 100
ORDER BY Score DESC, ViewCount DESC, AnswerCount DESC
LIMIT 50;
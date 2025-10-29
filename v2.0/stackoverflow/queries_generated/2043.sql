-- {"query": "2043.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1442} 
WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        COALESCE(p.ViewCount, 0) AS TagExcerptViewCount,
        1 AS Level
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        COALESCE(p2.ViewCount, 0) AS TagExcerptViewCount,
        r.Level + 1
    FROM Tags t2
    INNER JOIN RecursiveTagHierarchy r ON r.Id = t2.Id - 1 -- artificial hierarchy to generate recursion
    LEFT JOIN Posts p2 ON t2.ExcerptPostId = p2.Id
    WHERE r.Level < 3
), UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(badge_counts.GoldBadges, 0) AS GoldBadges,
        COALESCE(badge_counts.SilverBadges, 0) AS SilverBadges,
        COALESCE(badge_counts.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(posts_counts.QuestionCount, 0) AS QuestionCount,
        COALESCE(posts_counts.AnswerCount, 0) AS AnswerCount,
        COALESCE(comments_counts.CommentCount, 0) AS CommentCount
    FROM Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) badge_counts ON u.Id = badge_counts.UserId
    LEFT JOIN (
        SELECT
            OwnerUserId,
            SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
            SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
        FROM Posts
        WHERE OwnerUserId IS NOT NULL AND OwnerUserId != -1
        GROUP BY OwnerUserId
    ) posts_counts ON u.Id = posts_counts.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS CommentCount FROM Comments GROUP BY UserId
    ) comments_counts ON u.Id = comments_counts.UserId
), PopularQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS RN
    FROM Posts p
    WHERE p.PostTypeId = 1
), LatestAnswersWithCorrelatedInfo AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswerOwnerId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        q.Title AS QuestionTitle,
        q.Score AS QuestionScore,
        q.Tags AS QuestionTags,
        EXISTS (
            SELECT 1 FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2 AND v.CreationDate >= a.CreationDate - INTERVAL '30 days'
        ) AS HasRecentUpvote,
        (
            SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id
        ) AS AnswerCommentCount
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
), UserActivityRanked AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        QuestionCount,
        AnswerCount,
        CommentCount,
        RANK() OVER (ORDER BY Reputation DESC, GoldBadges DESC, SilverBadges DESC, BronzeBadges DESC) AS UserRank,
        NTILE(4) OVER (ORDER BY Reputation DESC) AS ReputationQuartile
    FROM UserStats
), FilteredUserActivity AS (
    SELECT *
    FROM UserActivityRanked
    WHERE Reputation >= 1000 AND (QuestionCount + AnswerCount) > 10
), CombinedUserHistory AS (
    SELECT u.UserId, u.DisplayName, ph.Id AS HistoryId, ph.PostHistoryTypeId, p.Title, ph.CreationDate, ph.Comment,
        ROW_NUMBER() OVER (PARTITION BY u.UserId ORDER BY ph.CreationDate DESC) AS HistoryRowNum
    FROM FilteredUserActivity u
    LEFT JOIN PostHistory ph ON ph.UserId = u.UserId
    LEFT JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4,5,6,10,11)
)
SELECT
    fua.UserId,
    fua.DisplayName,
    fua.Reputation,
    fua.GoldBadges,
    fua.SilverBadges,
    fua.BronzeBadges,
    fua.QuestionCount,
    fua.AnswerCount,
    fua.CommentCount,
    pq.Id AS TopQuestionId,
    pq.Title AS TopQuestionTitle,
    pq.Score AS TopQuestionScore,
    pq.ViewCount AS TopQuestionViews,
    COALESCE(ht.Level, 0) AS TagRecursionLevel,
    ht.TagName AS TagName,
    COALESCE(la.AnswerId, 0) AS LatestAnswerId,
    la.AnswerScore,
    la.AnswerCommentCount,
    la.HasRecentUpvote,
    cuh.HistoryId,
    cuh.PostHistoryTypeId,
    cuh.Title AS HistoryPostTitle,
    cuh.CreationDate AS HistoryDate,
    cuh.Comment AS HistoryComment
FROM FilteredUserActivity fua
LEFT JOIN PopularQuestions pq ON pq.OwnerUserId = fua.UserId AND pq.RN = 1
LEFT JOIN RecursiveTagHierarchy ht ON ht.TagName = ANY (string_to_array(replace(replace(pq.Tags, '<', ''), '>', ''), ' '))
LEFT JOIN LatestAnswersWithCorrelatedInfo la ON la.AnswerOwnerId = fua.UserId
LEFT JOIN CombinedUserHistory cuh ON cuh.UserId = fua.UserId AND cuh.HistoryRowNum = 1
WHERE (fua.QuestionCount > fua.AnswerCount OR pq.ViewCount > 1000)
ORDER BY fua.Reputation DESC, pq.Score DESC NULLS LAST, la.AnswerScore DESC NULLS LAST
LIMIT 100;
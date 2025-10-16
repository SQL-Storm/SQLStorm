-- {"query": "464.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1361} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        child.IsModeratorOnly,
        child.IsRequired,
        parent.TagPath || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy parent ON child.IsRequired = 1 AND child.Id <> ALL(parent.TagPath)
    WHERE array_length(parent.TagPath, 1) < 5
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(v.VoteTypeId = 2)::int, 0) AS TotalUpVotes,
        COALESCE(SUM(v.VoteTypeId = 3)::int, 0) AS TotalDownVotes,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopPostsWithComments AS (
    SELECT
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        COALESCE(c.CommentCount, 0) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
),
AcceptedAnswersWithDuplicates AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        dup.RelatedPostId AS DuplicateOfQuestionId,
        dup_link.PostId AS DuplicateLinkPostId,
        dup_link.RelatedPostId AS DuplicateLinkRelatedPostId
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
    LEFT JOIN PostLinks dup ON dup.PostId = q.Id AND dup.LinkTypeId = 3
    LEFT JOIN PostLinks dup_link ON dup_link.PostId = dup.RelatedPostId AND dup_link.LinkTypeId = 1
    WHERE q.PostTypeId = 1
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostsWithHistoryAndCloseReasons AS (
    SELECT
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        ph.PostHistoryTypeId,
        ph.Comment AS CloseReasonId,
        crt.Name AS CloseReasonName
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes crt ON crt.Id::varchar = ph.Comment
    WHERE p.PostTypeId = 1
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.ReputationRank,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.AvgPostScore,
    ua.LastPostDate,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    STRING_AGG(DISTINCT CASE WHEN pwh.CloseReasonName IS NOT NULL THEN pwh.CloseReasonName ELSE 'No Close Reason' END, ', ' ORDER BY pwh.CloseReasonName) AS CloseReasonsEncountered,
    COUNT(DISTINCT tp.Id) FILTER (WHERE tp.PostRank <= 3) AS Top3PostsCount,
    MAX(tp.Score) FILTER (WHERE tp.PostRank <= 3) AS MaxTop3PostScore,
    MIN(tp.CreationDate) FILTER (WHERE tp.PostRank <= 3) AS EarliestTop3PostDate,
    STRING_AGG(DISTINCT rh.TagName, ' > ' ORDER BY rh.TagName) AS RequiredTagHierarchy
FROM UserActivity ua
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = ua.UserId
LEFT JOIN TopPostsWithComments tp ON tp.OwnerUserId = ua.UserId
LEFT JOIN PostsWithHistoryAndCloseReasons pwh ON pwh.OwnerUserId = ua.UserId
LEFT JOIN RecursiveTagHierarchy rh ON rh.IsRequired = 1
WHERE ua.QuestionCount > 0
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.ReputationRank,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.AvgPostScore,
    ua.LastPostDate,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges
ORDER BY ua.ReputationRank
LIMIT 50;

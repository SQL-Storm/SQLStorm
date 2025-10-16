-- {"query": "414.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1739} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        0 AS Level,
        ARRAY[t.TagName] AS Ancestors
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        parent.Level + 1,
        parent.Ancestors || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy parent ON child.Id != parent.Id AND child.Count < parent.Count AND NOT child.TagName = ANY(parent.Ancestors)
    WHERE child.IsRequired = 0
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
UserReputationWindow AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(ubc_gold.BadgeCount, 0) AS GoldBadges,
        COALESCE(ubc_silver.BadgeCount, 0) AS SilverBadges,
        COALESCE(ubc_bronze.BadgeCount, 0) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) AS RankByRep
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc_gold ON u.Id = ubc_gold.UserId AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON u.Id = ubc_silver.UserId AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON u.Id = ubc_bronze.UserId AND ubc_bronze.Class = 3
),
TopQuestionsWithAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id AS AnswerId,
        a.CreationDate AS AnswerCreation,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwnerUserId,
        u.DisplayName AS AnswerOwnerDisplayName,
        u.Reputation AS AnswerOwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= NOW() - INTERVAL '1 year'
      AND q.Score >= 5
),
FilteredAnswers AS (
    SELECT *
    FROM TopQuestionsWithAnswers
    WHERE AnswerRank = 1
),
PostCommentsAggregated AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anonymous'), ', ' ORDER BY c.CreationDate DESC) AS RecentCommenters
    FROM Comments c
    GROUP BY c.PostId
),
PostCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        MAX(ph.CreationDate) AS LastCloseDate
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN CloseReasonTypes crt ON ph.Comment::int = crt.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserActivityWindows AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        plt.Name AS LinkTypeName,
        p1.Title AS PostTitle,
        p2.Title AS RelatedPostTitle
    FROM PostLinks pl
    JOIN LinkTypes plt ON pl.LinkTypeId = plt.Id
    JOIN Posts p1 ON pl.PostId = p1.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE plt.Name = 'Duplicate'
),
TopUsersWithActivity AS (
    SELECT
        urw.Id,
        urw.DisplayName,
        urw.Reputation,
        urw.GoldBadges,
        urw.SilverBadges,
        urw.BronzeBadges,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        ua.LastPostDate,
        ua.LastCommentDate,
        ua.LastVoteDate,
        CASE
            WHEN urw.Reputation > 100000 THEN 'Legendary'
            WHEN urw.Reputation > 10000 THEN 'Expert'
            WHEN urw.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS UserLevel
    FROM UserReputationWindow urw
    LEFT JOIN UserActivityWindows ua ON urw.Id = ua.UserId
    WHERE urw.RankByRep <= 100
)
SELECT
    tq.QuestionId,
    tq.Title AS QuestionTitle,
    tq.QuestionCreation,
    tq.QuestionScore,
    tq.ViewCount,
    tq.Tags,
    fa.AnswerId,
    fa.AnswerCreation,
    fa.AnswerScore,
    fa.AnswerOwnerUserId,
    fa.AnswerOwnerDisplayName,
    fa.AnswerOwnerReputation,
    pca.CommentCount,
    pca.AvgCommentScore,
    pca.RecentCommenters,
    COALESCE(pcr.CloseReasonName, 'Open') AS CloseReason,
    pcr.LastCloseDate,
    du.RelatedPostId AS DuplicateOfPostId,
    du.RelatedPostTitle AS DuplicateOfPostTitle,
    tuwa.DisplayName AS TopUserDisplayName,
    tuwa.Reputation AS TopUserReputation,
    tuwa.GoldBadges,
    tuwa.SilverBadges,
    tuwa.BronzeBadges,
    tuwa.QuestionsPosted,
    tuwa.AnswersPosted,
    tuwa.CommentsMade,
    tuwa.UpVotesGiven,
    tuwa.DownVotesGiven,
    tuwa.UserLevel
FROM FilteredAnswers fa
JOIN TopQuestionsWithAnswers tq ON fa.QuestionId = tq.QuestionId
LEFT JOIN PostCommentsAggregated pca ON tq.QuestionId = pca.PostId
LEFT JOIN PostCloseReasons pcr ON tq.QuestionId = pcr.PostId
LEFT JOIN DuplicateLinks du ON tq.QuestionId = du.PostId
LEFT JOIN TopUsersWithActivity tuwa ON fa.AnswerOwnerUserId = tuwa.Id
WHERE (tq.QuestionScore + COALESCE(fa.AnswerScore, 0)) > 10
  AND (pca.CommentCount IS NULL OR pca.CommentCount > 0)
ORDER BY tq.QuestionScore DESC, fa.AnswerScore DESC
LIMIT 50;

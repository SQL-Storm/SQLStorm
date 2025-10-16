-- {"query": "518.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1698} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        0 AS Level,
        ARRAY[t.TagName] AS AncestorTags
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
    UNION ALL
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.AncestorTags || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id <> r.Id AND t.Count < r.Count AND NOT t.TagName = ANY(r.AncestorTags)
    WHERE r.Level < 2
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
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        RANK() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocationRepRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc_gold ON u.Id = ubc_gold.UserId AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON u.Id = ubc_silver.UserId AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON u.Id = ubc_bronze.UserId AND ubc_bronze.Class = 3
),
TopQuestionsWithAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        a.ParentId,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
      AND q.Score > 10
      AND q.ViewCount > 1000
),
AnswerVotesSummary AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(*) AS TotalVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
),
RecentCommentsPerPost AS (
    SELECT
        c.PostId,
        c.Id AS CommentId,
        c.UserId,
        c.UserDisplayName,
        c.CreationDate,
        c.Score,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS CommentRank
    FROM Comments c
),
ClosedQuestionsWithReasons AS (
    SELECT
        ph.PostId,
        ph.Comment AS CloseReasonId,
        crt.Name AS CloseReasonName,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INT) = crt.Id
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Duplicate'
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
)
SELECT
    tq.QuestionId,
    tq.Title,
    tq.OwnerUserId,
    u.DisplayName AS QuestionOwner,
    tq.CreationDate AS QuestionCreationDate,
    tq.QuestionScore,
    tq.ViewCount,
    tq.Tags,
    qa.AnswerCount,
    qa.AvgAnswerScore,
    qa.MaxAnswerScore,
    avs_up.UpVotes AS AnswerUpVotes,
    avs_down.DownVotes AS AnswerDownVotes,
    avs_down.TotalVotes AS AnswerTotalVotes,
    dq.RelatedPostId AS DuplicateOf,
    cqwr.CloseReasonName,
    cqwr.CloseDate,
    STRING_AGG(DISTINCT rth.TagName, ', ') FILTER (WHERE rth.Level = 0) AS RootTags,
    STRING_AGG(DISTINCT rth.TagName, ', ') FILTER (WHERE rth.Level = 1) AS SubTags,
    STRING_AGG(DISTINCT rth.TagName, ', ') FILTER (WHERE rth.Level = 2) AS SubSubTags,
    rc.CommentId AS RecentCommentId,
    rc.UserDisplayName AS RecentCommentUser,
    rc.CreationDate AS RecentCommentDate,
    urw.Reputation,
    urw.GoldBadges,
    urw.SilverBadges,
    urw.BronzeBadges,
    urw.Location,
    urw.LocationRepRank,
    CASE
        WHEN urw.Reputation > 10000 THEN 'Expert'
        WHEN urw.Reputation BETWEEN 5000 AND 10000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS ReputationLevel,
    CASE
        WHEN tq.QuestionScore > 50 THEN 'Hot'
        WHEN tq.QuestionScore BETWEEN 20 AND 50 THEN 'Trending'
        ELSE 'Normal'
    END AS QuestionPopularity,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.QuestionId AND v.VoteTypeId = 2) AS QuestionUpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.QuestionId AND v.VoteTypeId = 3) AS QuestionDownVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tq.QuestionId) AS QuestionCommentCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = tq.QuestionId AND a.Score > 0) AS PositiveAnswersCount
FROM TopQuestionsWithAnswers tq
LEFT JOIN Users u ON tq.OwnerUserId = u.Id
LEFT JOIN QuestionAnswerStats qa ON qa.QuestionId = tq.QuestionId
LEFT JOIN AnswerVotesSummary avs_up ON avs_up.PostId = tq.AnswerId
LEFT JOIN AnswerVotesSummary avs_down ON avs_down.PostId = tq.AnswerId
LEFT JOIN DuplicateLinks dq ON dq.PostId = tq.QuestionId
LEFT JOIN ClosedQuestionsWithReasons cqwr ON cqwr.PostId = tq.QuestionId
LEFT JOIN RecursiveTagHierarchy rth ON POSITION(rth.TagName IN COALESCE(tq.Tags, '')) > 0
LEFT JOIN RecentCommentsPerPost rc ON rc.PostId = tq.QuestionId AND rc.CommentRank = 1
LEFT JOIN UserReputationWindow urw ON urw.Id = tq.OwnerUserId
WHERE tq.AnswerRank = 1
  AND (tq.Tags IS NOT NULL AND tq.Tags <> '')
ORDER BY tq.QuestionScore DESC, qa.AnswerCount DESC
LIMIT 50;

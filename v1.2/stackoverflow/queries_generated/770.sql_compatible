WITH RECURSIVE RecursiveTagCounts AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(p.Score, 0) AS Score,
        1 AS Level
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId AND p.PostTypeId = 1

    UNION ALL

    SELECT
        rtc.TagId,
        rtc.TagName,
        rtc.AnswerCount + COALESCE(p.AnswerCount, 0) AS AnswerCount,
        rtc.ViewCount + COALESCE(p.ViewCount, 0) AS ViewCount,
        rtc.Score + COALESCE(p.Score, 0) AS Score,
        rtc.Level + 1 AS Level
    FROM RecursiveTagCounts rtc
    JOIN Tags t ON t.Id = rtc.TagId
    JOIN Posts p ON p.Id = t.WikiPostId AND p.PostTypeId = 1
    WHERE rtc.Level < 3
),
UserBadgeRanks AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, b.Class
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.CreationDate,
        p.Score,
        row_number() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS RecentPostRank,
        count(*) OVER (PARTITION BY u.Id) AS TotalPosts
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
),
TopQuestionsWithAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionDate,
        q.Score AS QuestionScore,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        u.DisplayName AS AnswerOwner,
        COALESCE(voteCounts.UpVotes, 0) AS AnswerUpVotes,
        COALESCE(voteCounts.DownVotes, 0) AS AnswerDownVotes
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    LEFT JOIN (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ) voteCounts ON voteCounts.PostId = a.Id
    WHERE q.PostTypeId = 1 AND q.Score > 10
),
ClosedQuestionsWithReasons AS (
    SELECT
        ph.PostId,
        p.Title,
        p.CreationDate,
        crt.Name AS CloseReason,
        ph.CreationDate AS CloseDate,
        ph.UserDisplayName AS ClosedBy
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    JOIN Posts p ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId = 10
),
UserCommentStats AS (
    SELECT
        c.UserId,
        u.DisplayName,
        COUNT(c.Id) AS CommentCount,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        SUM(CASE WHEN c.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY) THEN 1 ELSE 0 END) AS RecentComments
    FROM Comments c
    JOIN Users u ON u.Id = c.UserId
    GROUP BY c.UserId, u.DisplayName
),
QuestionAnswerRatio AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
        CASE WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) = 0 THEN NULL
             ELSE 1.0 * COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) / COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)
        END AS AnswerToQuestionRatio
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT DISTINCT
    t.TagName,
    rtc.AnswerCount AS TotalAnswersByTag,
    rtc.ViewCount AS TotalViewsByTag,
    rtc.Score AS TotalScoreByTag,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate AS UserSince,
    ubr.Class AS BadgeClass,
    ubr.BadgeCount,
    ua.RecentPostRank,
    ua.TotalPosts,
    tq.Title AS PopularQuestion,
    tq.QuestionScore,
    tq.AnswerId,
    tq.AnswerScore,
    tq.AnswerOwner,
    tq.AnswerUpVotes,
    tq.AnswerDownVotes,
    cq.CloseReason,
    cq.CloseDate,
    cq.ClosedBy,
    ucs.CommentCount,
    ucs.AvgCommentLength,
    ucs.RecentComments,
    qar.AnswerToQuestionRatio,
    CASE
        WHEN u.WebsiteUrl IS NULL OR LENGTH(u.WebsiteUrl) = 0 THEN 'No Website'
        ELSE LOWER(SUBSTRING(u.WebsiteUrl FROM 'https?://([^/]+)'))
    END AS WebsiteDomain,
    CASE
        WHEN LENGTH(t.TagName) > 5 THEN CONCAT(SUBSTR(t.TagName, 1, 3), '...', SUBSTR(t.TagName, -2))
        ELSE t.TagName
    END AS ShortTagName
FROM RecursiveTagCounts rtc
JOIN Tags t ON t.Id = rtc.TagId
JOIN Users u ON u.Id = (
    SELECT p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1 AND POSITION('<' || t.TagName || '>' IN COALESCE(p.Tags, '')) > 0
    ORDER BY p.Score DESC
    LIMIT 1
)
LEFT JOIN UserBadgeRanks ubr ON ubr.UserId = u.Id AND ubr.Class = 1
LEFT JOIN UserActivityWindow ua ON ua.UserId = u.Id AND ua.RecentPostRank = 1
LEFT JOIN TopQuestionsWithAnswers tq ON tq.QuestionId = (
    SELECT p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1 AND POSITION('<' || t.TagName || '>' IN COALESCE(p.Tags, '')) > 0
    ORDER BY p.Score DESC
    LIMIT 1
)
LEFT JOIN ClosedQuestionsWithReasons cq ON cq.PostId = tq.QuestionId
LEFT JOIN UserCommentStats ucs ON ucs.UserId = u.Id
LEFT JOIN QuestionAnswerRatio qar ON qar.UserId = u.Id
WHERE rtc.Level = 3
ORDER BY rtc.Score DESC, u.Reputation DESC
LIMIT 100;
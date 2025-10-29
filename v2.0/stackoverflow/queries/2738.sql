WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        ARRAY[t.Id] AS Path,
        1 AS Depth
    FROM Tags t
    WHERE NOT t.IsModeratorOnly

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        r.Path || t.Id,
        r.Depth + 1
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.ExcerptPostId = r.Id
    WHERE t.Id <> ALL(r.Path)
),
UserBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Name AS BadgeName,
        b.Class,
        row_number() OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS rn
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE b.Class IN (1,2,3)
),
TopUserBadges AS (
    SELECT UserId, BadgeName, Class
    FROM UserBadges
    WHERE rn <= 5
),
PostVotesSummary AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        count(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        count(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        count(CASE WHEN v.VoteTypeId = 1 THEN 1 END) AS AcceptedVotes,
        coalesce(sum(v.BountyAmount),0) AS TotalBounty,
        max(v.CreationDate) AS LastVoteDate
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId
),
PostWithAnswers AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        count(a.Id) AS AnswerCount,
        max(a.Score) AS MaxAnswerScore,
        avg(CASE WHEN a.Score > 0 THEN a.Score END) AS AvgAnswerScorePositive,
        sum(CASE WHEN a.Score > 10 THEN 1 ELSE 0 END) AS HighlyScoredAnswers,
        max(a.CreationDate) AS LastAnswerDate
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate
),
QuestionsClosedReason AS (
    SELECT 
        ph.PostId,
        crt.Name AS CloseReasonName,
        ph.CreationDate AS ClosedAt
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS integer) = crt.Id
    WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL
),
QuestionsWithCloseFlag AS (
    SELECT q.Id, q.Title, qc.CloseReasonName, qc.ClosedAt
    FROM Posts q
    LEFT JOIN QuestionsClosedReason qc ON q.Id = qc.PostId
    WHERE q.PostTypeId = 1
),
RankedPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        count(DISTINCT p.Id) AS TotalPosts,
        count(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsCount,
        count(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
        coalesce(sum(p.Score),0) AS TotalScore,
        avg(p.Score) AS AvgScore,
        max(p.Score) AS MaxScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopContributors AS (
    SELECT *
    FROM UserPostStats
    WHERE TotalPosts > 50
    ORDER BY TotalScore DESC
    LIMIT 100
)
SELECT
    tc.UserId,
    tc.DisplayName,
    tc.TotalPosts,
    tc.QuestionsCount,
    tc.AnswersCount,
    tc.TotalScore,
    tc.AvgScore,
    tb.BadgeName,
    tb.Class AS BadgeClass,
    pws.QuestionId,
    pws.Title AS QuestionTitle,
    pws.AnswerCount,
    pvs.UpVotes,
    pvs.DownVotes,
    pvs.TotalBounty,
    qc.CloseReasonName,
    qc.ClosedAt,
    r.Id AS TopPostId,
    r.Score AS TopPostScore,
    r.ViewCount AS TopPostViews
FROM TopContributors tc
LEFT JOIN TopUserBadges tb ON tb.UserId = tc.UserId
LEFT JOIN LATERAL (
    SELECT p.Id AS QuestionId, p.Title, p.CreationDate, pws_sub.AnswerCount
    FROM Posts p
    LEFT JOIN (
        SELECT q.Id AS QId, count(a.Id) AS AnswerCount
        FROM Posts q
        LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
        WHERE q.PostTypeId = 1
        GROUP BY q.Id
    ) pws_sub ON p.Id = pws_sub.QId
    WHERE p.OwnerUserId = tc.UserId AND p.PostTypeId = 1
    LIMIT 1
) pws ON TRUE
LEFT JOIN PostVotesSummary pvs ON pvs.PostId = pws.QuestionId
LEFT JOIN QuestionsWithCloseFlag qc ON qc.Id = pws.QuestionId
LEFT JOIN RankedPosts r ON r.OwnerUserId = tc.UserId AND r.rn = 1
WHERE (tb.BadgeName IS NOT NULL OR tc.TotalPosts > 100)
GROUP BY
    tc.UserId,
    tc.DisplayName,
    tc.TotalPosts,
    tc.QuestionsCount,
    tc.AnswersCount,
    tc.TotalScore,
    tc.AvgScore,
    tb.BadgeName,
    tb.Class,
    pws.QuestionId,
    pws.Title,
    pws.AnswerCount,
    pvs.UpVotes,
    pvs.DownVotes,
    pvs.TotalBounty,
    qc.CloseReasonName,
    qc.ClosedAt,
    r.Id,
    r.Score,
    r.ViewCount
ORDER BY tc.TotalScore DESC, tc.TotalPosts DESC
LIMIT 500;
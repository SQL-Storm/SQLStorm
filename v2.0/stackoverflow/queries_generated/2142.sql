-- {"query": "2142.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1821} 
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName AS OwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS RankByScoreView,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsByType
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1,2) /* Questions and Answers */
),
FilteredBadges AS (
    SELECT
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS RecentBadgeRank
    FROM Badges b
    WHERE b.Class IN (1,2) /* Gold or Silver badges */
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        COALESCE(SUM(vp.Score), 0) AS TotalPostScore,
        COALESCE(SUM(vu.TotalUpVotes - vu.TotalDownVotes),0) AS VoteNet,
        MAX(fb.Date) FILTER (WHERE fb.RecentBadgeRank = 1) AS LatestBadgeDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 -- questions
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2 -- answers
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId = 2 -- UpMod votes cast by user
    LEFT JOIN (
        SELECT
            vp.PostId,
            SUM(vp.Score) AS Score
        FROM Posts vp
        GROUP BY vp.PostId
    ) vp ON vp.PostId = p.Id OR vp.PostId = a.Id
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ) vu ON vu.OwnerUserId = u.Id
    LEFT JOIN FilteredBadges fb ON fb.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5 AND (COALESCE(SUM(vp.Score), 0) > 50 OR COALESCE(SUM(vu.TotalUpVotes - vu.TotalDownVotes),0) > 20)
),
QuestionStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.AcceptedAnswerId,
        u.DisplayName AS OwnerName,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        MAX(COALESCE(a.Score,0)) AS MaxAnswerScore,
        AVG(COALESCE(a.Score,0)) AS AvgAnswerScore,
        SUM(COALESCE(vp.VoteTypeId = 2::smallint::int, 0)) FILTER (WHERE vp.PostId = q.Id) AS QuestionUpVotes,
        EXISTS (
            SELECT 1 FROM PostHistory ph
            WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId = 10
        ) AS IsClosed,
        CASE
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END AS HasAcceptedAnswer,
        ROW_NUMBER() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS QuestionRank
    FROM Posts q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = q.Id
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Votes vp ON vp.PostId = q.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, q.AcceptedAnswerId, u.DisplayName
    HAVING COUNT(DISTINCT a.Id) > 0
),
ClosedQuestions AS (
    SELECT q.QuestionId, q.Title, q.IsClosed, cr.Name AS CloseReason
    FROM QuestionStats q
    LEFT JOIN PostHistory ph ON ph.PostId = q.QuestionId AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes cr ON ph.Comment::int = cr.Id
    WHERE q.IsClosed = TRUE
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        DATE_TRUNC('month', p.CreationDate) AS Month,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId IN (2,3)) AS VotesMade
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, DATE_TRUNC('month', p.CreationDate)
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        COALESCE(pq.AnswersCount, 0) AS AnswersCount,
        COALESCE(AVG(p.Score), 0) AS AvgScore,
        MAX(p.Score) AS MaxScore
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS AnswersCount 
        FROM Posts p
        WHERE p.PostTypeId = 2
          AND p.Tags LIKE '%' || t.TagName || '%'
    ) pq ON TRUE
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    GROUP BY t.TagName, t.Count, pq.AnswersCount
    ORDER BY t.Count DESC
    LIMIT 50
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    upa.Month,
    upa.QuestionsPosted,
    upa.AnswersPosted,
    upa.CommentsMade,
    upa.VotesMade,
    q.QuestionRank,
    q.Title AS PopularQuestionTitle,
    q.Score AS PopularQuestionScore,
    q.ViewCount AS PopularQuestionViews,
    q.AnswerCount,
    q.MaxAnswerScore,
    q.AvgAnswerScore,
    q.HasAcceptedAnswer,
    COALESCE(cb.CloseReason, 'Not Closed') AS CloseStatus,
    t.TagName AS TopTagName,
    t.Count AS TopTagUseCount,
    t.AnswersCount AS TagAnswersCount,
    t.AvgScore AS TagAvgScore,
    t.MaxScore AS TagMaxScore,
    fb.Name AS LatestBadgeName,
    fb.Class AS LatestBadgeClass,
    fb.Date AS LatestBadgeDate
FROM TopUsers u
LEFT JOIN UserPostActivity upa ON upa.UserId = u.Id
LEFT JOIN QuestionStats q ON q.OwnerName = u.DisplayName
LEFT JOIN ClosedQuestions cb ON cb.QuestionId = q.QuestionId
LEFT JOIN (
    SELECT DISTINCT ON (UserId) UserId, Name, Class, Date FROM FilteredBadges ORDER BY UserId, Date DESC
) fb ON fb.UserId = u.Id
LEFT JOIN TopTags t ON t.TagName = (
    SELECT unnest(string_to_array(coalesce(q.Tags, ''), '><')) ORDER BY 1 LIMIT 1
)
WHERE upa.Month >= CURRENT_DATE - INTERVAL '12 months'
ORDER BY u.Reputation DESC, q.QuestionRank
LIMIT 100;
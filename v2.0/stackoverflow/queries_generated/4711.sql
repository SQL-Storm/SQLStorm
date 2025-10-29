-- {"query": "4711.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1156} 
WITH QuestionStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.AnswerCount,
        p.FavoriteCount,
        p.ViewCount AS QuestionViewCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.AnswerCount DESC) AS ScoreRank,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount,
        AVG(CAST(p.AnswerCount AS DECIMAL(10, 2))) OVER () AS AvgAnswerCountAcrossAllQuestions
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.AnswerCount, p.FavoriteCount, p.ViewCount, u.DisplayName, u.Reputation
),
AnswerQuality AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        SUM(CASE WHEN a.Id = p_q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswerFlag,
        AVG(CAST(a.Score AS DECIMAL(10, 2))) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LatestAnswerDate
    FROM Posts a
    JOIN Posts p_q ON a.ParentId = p_q.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
UserContribution AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(b.Date) AS LastBadgeDate,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (2, 5)) AS PostEditCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
HighReputationUsers AS (
    SELECT *
    FROM UserContribution
    WHERE Reputation > 10000
),
TopQuestions AS (
    SELECT
        qs.QuestionId,
        qs.Title,
        qs.OwnerDisplayName,
        qs.QuestionScore,
        qs.AnswerCount AS QuestionAnswerCount,
        qs.FavoriteCount,
        qs.CommentCount,
        qs.AvgAnswerCountAcrossAllQuestions,
        aq.AnswerCount AS ActualAnswerCount,
        aq.AcceptedAnswerFlag,
        aq.AvgAnswerScore,
        aq.LatestAnswerDate
    FROM QuestionStats qs
    LEFT JOIN AnswerQuality aq ON qs.QuestionId = aq.QuestionId
    WHERE qs.ScoreRank <= 50
),
FrequentTags AS (
    SELECT
        t.TagName,
        t.Count AS TagCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE
)
SELECT
    tq.Title AS QuestionTitle,
    tq.OwnerDisplayName,
    tq.QuestionScore,
    tq.FavoriteCount,
    tq.CommentCount,
    tq.ActualAnswerCount,
    tq.AcceptedAnswerFlag,
    tq.AvgAnswerScore,
    tq.LatestAnswerDate,
    ft.TagName AS TopTagName,
    ft.TagRank AS TopTagRank,
    hr.DisplayName AS HighRepUserDisplayName,
    hr.Reputation AS HighRepUserReputation,
    hr.BadgeCount AS HighRepUserBadgeCount,
    hr.PostEditCount AS HighRepUserPostEditCount,
    CASE
        WHEN tq.QuestionScore > 1000 AND tq.ActualAnswerCount > 10 THEN 'Highly Engaged'
        WHEN tq.QuestionScore < 0 AND tq.ActualAnswerCount = 0 THEN 'Neglected'
        WHEN tq.FavoriteCount > 50 AND tq.AcceptedAnswerFlag = 1 THEN 'Popular & Accepted'
        ELSE 'Standard'
    END AS QuestionEngagementCategory,
    COALESCE(u.Views, 0) AS OwnerTotalViews,
    CASE WHEN hr.UserId IS NULL THEN 'No' ELSE 'Yes' END AS IsHighReputationUser
FROM TopQuestions tq
LEFT JOIN FrequentTags ft ON ft.TagRank = 1
LEFT JOIN HighReputationUsers hr ON hr.UserId = tq.OwnerUserId
LEFT JOIN Users u ON tq.OwnerUserId = u.Id
WHERE tq.QuestionScore > 0 OR tq.ActualAnswerCount > 0
ORDER BY tq.QuestionScore DESC, tq.FavoriteCount DESC;
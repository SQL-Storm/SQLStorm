-- {"query": "39053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 3350} 
WITH
RecentAnswers AS (
    SELECT
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS AnswerRank
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
TopAnswers AS (
    SELECT * 
    FROM RecentAnswers 
    WHERE AnswerRank <= 3
),
UserStats AS (
    SELECT
        u.Id                         AS UserId,
        COUNT(DISTINCT q.Id) FILTER (WHERE q.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswersPosted,
        AVG(a.Score)                 AS AvgAnswerScore,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)   AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)   AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)   AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts q ON q.OwnerUserId = u.Id
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id
),
TagActivity AS (
    SELECT
        t.TagName,
        COUNT(p.Id)          AS QCount,
        SUM(p.ViewCount)     AS TotalViews,
        AVG(p.Score)         AS AvgScore
    FROM Tags t
    JOIN Posts p
      ON p.PostTypeId = 1
     AND POSITION('<' || t.TagName || '>' IN p.Tags) > 0
    GROUP BY t.TagName
    HAVING COUNT(*) > 100
),
Edits AS (
    SELECT
        ph.PostId,
        COUNT(*)                AS TotalEdits,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors,
        MAX(ph.CreationDate)    AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY ph.PostId
),
CommentsAgg AS (
    SELECT
        c.PostId,
        COUNT(*)                                    AS TotalComments,
        MAX(c.Score)                                AS TopCommentScore,
        STRING_AGG(c.Text, ' || ' ORDER BY c.Score DESC)
            FILTER (WHERE c.Score >= 5)            AS HighScoreComments
    FROM Comments c
    GROUP BY c.PostId
),
VoteTrends AS (
    SELECT
        p.Id                                  AS PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END)
            FILTER (WHERE v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days') 
                                             AS UpvotesLast30Days,
        MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END)
                                             AS LastUpvoteDate
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    WHERE v.VoteTypeId = 2
      AND v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '60 days'
    GROUP BY p.Id
)
SELECT
    us.UserId,
    us.QuestionsAsked,
    us.AnswersPosted,
    ROUND(us.AvgAnswerScore,2)     AS AvgAnswerScore,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    ta.TagName,
    ta.QCount,
    ta.TotalViews,
    ROUND(ta.AvgScore,2)           AS AvgTagScore,
    ta2.PostId                      AS TopQuestionId,
    ta2.Title                       AS TopQuestionTitle,
    ta2.Score                       AS TopQuestionScore,
    ed.TotalEdits,
    ed.DistinctEditors,
    ed.LastEditDate,
    ca.TotalComments,
    ca.TopCommentScore,
    ca.HighScoreComments,
    vt.UpvotesLast30Days,
    vt.LastUpvoteDate
FROM UserStats us
JOIN TagActivity ta
  ON ta.QCount > us.QuestionsAsked
JOIN LATERAL (
    SELECT
        p.Id    AS PostId,
        p.Title,
        p.Score
    FROM Posts p
    WHERE p.OwnerUserId = us.UserId
      AND p.PostTypeId = 1
    ORDER BY p.ViewCount DESC
    LIMIT 1
) ta2 ON TRUE
LEFT JOIN Edits ed       ON ed.PostId = ta2.PostId
LEFT JOIN CommentsAgg ca ON ca.PostId = ta2.PostId
LEFT JOIN VoteTrends vt  ON vt.PostId = ta2.PostId
ORDER BY us.AvgAnswerScore DESC, ta.QCount DESC
LIMIT 50;
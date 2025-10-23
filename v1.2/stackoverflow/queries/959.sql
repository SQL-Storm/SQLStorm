-- {"query": "959.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1097} 
WITH RecursiveAcceptedAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwner,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreation,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
UserBadgesSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopCommenters AS (
    SELECT
        c.UserId,
        u.DisplayName,
        COUNT(c.Id) AS CommentCount,
        AVG(LENGTH(c.Text) - LENGTH(REPLACE(c.Text, ' ', '')) + 1) AS AvgCommentWordCount
    FROM Comments c
    JOIN Users u ON u.Id = c.UserId
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId, u.DisplayName
    HAVING COUNT(c.Id) > 50
),
QuestionTagExplode AS (
    SELECT
        p.Id AS PostId,
        LOWER(TRIM(tag)) AS Tag
    FROM Posts p
    CROSS JOIN LATERAL regexp_split_to_table(
        substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2),
        '><'
    ) AS tag
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TagPopularity AS (
    SELECT
        t.Tag,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.ViewCount) AS AvgViewCount,
        SUM(COALESCE(p.Score,0)) AS TotalScore
    FROM QuestionTagExplode t
    JOIN Posts p ON p.Id = t.PostId
    GROUP BY t.Tag
    ORDER BY QuestionCount DESC
    LIMIT 10
)
SELECT
    q.QuestionId,
    q.Title,
    q.QuestionCreation,
    q.AnswerId,
    q.AnswerOwner,
    u.DisplayName AS AnswerOwnerName,
    q.AnswerScore,
    q.AnswerCreation,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.LastBadgeDate,
    tc.CommentCount AS AnswerOwnerCommentCount,
    tc.AvgCommentWordCount AS AnswerOwnerAvgCommentWords,
    tp.Tag,
    tp.QuestionCount,
    tp.AvgViewCount,
    tp.TotalScore,
    ROW_NUMBER() OVER (PARTITION BY q.QuestionId ORDER BY q.AnswerScore DESC) AS AnswerScoreRank,
    CASE
        WHEN q.AnswerCreation > q.QuestionCreation THEN
            EXTRACT(EPOCH FROM (q.AnswerCreation - q.QuestionCreation)) / 3600.0
        ELSE NULL
    END AS HoursToAnswer,
    COALESCE(pv.UpVotes, 0) - COALESCE(pv.DownVotes, 0) AS NetVotes,
    CASE
        WHEN q.AnswerScore > 0 AND bs.GoldBadges > 0 THEN 'High Impact'
        WHEN q.AnswerScore <= 0 AND (bs.BronzeBadges + bs.SilverBadges) > 5 THEN 'Active User'
        ELSE 'Regular'
    END AS UserCategory,
    CONCAT(
        'Q: ', LEFT(q.Title, 50),
        ' | Tag: ', tp.Tag,
        ' | Owner Badges (G/S/B): ', bs.GoldBadges, '/', bs.SilverBadges, '/', bs.BronzeBadges
    ) AS SummaryString
FROM RecursiveAcceptedAnswers q
LEFT JOIN Users u ON u.Id = q.AnswerOwner
LEFT JOIN UserBadgesSummary bs ON bs.UserId = q.AnswerOwner
LEFT JOIN TopCommenters tc ON tc.UserId = q.AnswerOwner
LEFT JOIN QuestionTagExplode qe ON qe.PostId = q.QuestionId
LEFT JOIN TagPopularity tp ON tp.Tag = qe.Tag
LEFT JOIN (
    SELECT
        PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY PostId
) pv ON pv.PostId = q.AnswerId
WHERE q.AnswerRank <= 3
  AND q.AnswerOwner IS NOT NULL
ORDER BY q.QuestionCreation DESC, q.AnswerScore DESC
LIMIT 100;
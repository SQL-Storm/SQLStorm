-- {"query": "34054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 909} 

WITH RankedAnswers AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.CreationDate,
        a.Score,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TopAnswers AS (
    SELECT *
    FROM RankedAnswers
    WHERE AnswerRank <= 3
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(COALESCE(p.Score,0)) AS TotalPostScore,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionTagStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        STRING_TO_ARRAY(SUBSTRING(q.Tags, 2, LENGTH(q.Tags)-2), '><') AS TagList
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount
),
TagAggregate AS (
    SELECT 
        UNNEST(TagList) AS Tag,
        COUNT(DISTINCT QuestionId) AS QuestionCount,
        AVG(Score) AS AvgQuestionScore,
        AVG(ViewCount) AS AvgQuestionViews,
        AVG(AnswerCount) AS AvgAnswerCount
    FROM QuestionTagStats
    GROUP BY Tag
),
CloseReasonCounts AS (
    SELECT 
        cht.Name AS CloseReason,
        COUNT(ph.Id) AS CloseCount
    FROM PostHistory ph
    JOIN CloseReasonTypes cht ON CAST(ph.Comment AS INT) = cht.Id AND ph.PostHistoryTypeId = 10
    GROUP BY cht.Name
)
SELECT 
    qts.QuestionId,
    qts.Title,
    qts.CreationDate,
    qts.Score AS QuestionScore,
    qts.ViewCount,
    qts.AnswerCount,
    ta.AnswerId,
    ta.Score AS AnswerScore,
    u.DisplayName AS Answerer,
    u.Reputation AS AnswererReputation,
    us.TotalPosts AS AnswererTotalPosts,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    ta.CreationDate AS AnswerCreationDate,
    ARRAY_AGG(DISTINCT t.Tag ORDER BY t.QuestionCount DESC) FILTER (WHERE t.Tag IS NOT NULL) AS TopTags,
    crc.CloseReason,
    crc.CloseCount
FROM QuestionTagStats qts
LEFT JOIN TopAnswers ta ON ta.QuestionId = qts.QuestionId
LEFT JOIN Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = ta.AnswerId)
LEFT JOIN UserStats us ON us.UserId = u.Id
LEFT JOIN TagAggregate t ON t.Tag = ANY(qts.TagList)
LEFT JOIN CloseReasonCounts crc ON TRUE
WHERE qts.Score >= 5
GROUP BY 
    qts.QuestionId, qts.Title, qts.CreationDate, qts.Score, qts.ViewCount, qts.AnswerCount,
    ta.AnswerId, ta.Score, u.DisplayName, u.Reputation, us.TotalPosts, us.GoldBadges, us.SilverBadges, us.BronzeBadges, ta.CreationDate,
    crc.CloseReason, crc.CloseCount
ORDER BY qts.Score DESC, ta.Score DESC NULLS LAST, qts.ViewCount DESC
LIMIT 100;
